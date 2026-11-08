# 需求與規格：快速開播第二階段（fast-start-2）

日期：2026-11-08
前一階段：[../fast-start/](../fast-start/)（模擬器中位數 999 ms；已有快取命中時 219～470 ms）

## 需求

目標：讓多數從首頁推薦點開的影片在點擊前就準備好播放網址與開頭資料，接近 0.5 秒開播。

使用者決定（2026-11-08）：預取可見卡片的播放網址、點擊時就開始下載開頭、預先建立 CDN 連線、更快切換慢節點。

### 驗收條件

- **AC-1**：首頁推薦（App 端與 web 端推薦清單）停止捲動約 300 ms 後，畫面上可見且有 bvid、cid 的影片卡片（最多前 6 張）若沒有快取，就預取 playurl；同時進行的預取最多 2 個。
- **AC-2**：playurl 快取有效期改為 10 分鐘，最多 30 筆；同 key 不重複請求。
- **AC-3**：預取收到 HTTP 412 或 code `-412`／`-352` 時，暫停所有可見卡片預取 5 分鐘（tap-down 預取不受影響）。
- **AC-4**：按下卡片（tap-down）時，若該影片的 playurl 已在快取中，立即讓 BTR 開始下載影片頁將會選用的影片與音訊串流開頭（各約 512 KB，存在記憶體）；影片頁開檔時，同一網址的開頭資料直接從記憶體送給播放器。選到的串流與影片頁不同時，預熱資料閒置 30 秒後丟棄。
- **AC-5**：預取 playurl 成功時，對該 CDN host 預先建立連線（例如對影片網址發 `bytes=0-0` 請求）；BTR 使用的連線閒置逾時延長到 60 秒，讓預先建立的連線在點擊時仍可重用。
- **AC-6**：開頭片段 0.8 秒內沒收到第一個 byte 時，同時向下一個節點請求同一範圍（不取消第一個），先收到資料者勝出，另一個取消；取代目前 2 秒才換節點。0.8 秒的 hedge 不計為節點失敗。
- **AC-7**：BTR 關閉時：AC-1、AC-2、AC-3 仍有效（playurl 預取不依賴 BTR）；AC-4、AC-6 不適用；AC-5 只做 playurl 預取部分，不發 CDN 預連線。
- **AC-8**：離開首頁或 App 進背景時停止排程新的預取。
- **AC-9**：`flutter analyze` 無新增錯誤或警告。

### 不做

- 預先下載整部影片或預先建立播放器。
- 推薦以外的頁面（搜尋、動態、相關影片）的可見卡片預取。

## 設計

### A. 可見卡片預取（AC-1～AC-3、AC-8）

- `lib/utils/play_url_cache.dart`：`_ttl` 改 10 分鐘、`_maxEntries` 改 30；新增 `prefetchVisible(List<(String bvid, int cid)>)`：佇列、併發 2、去重、412 退避 5 分鐘（`_backoffUntil`）；`isPaused` 旗標（AC-8）。`prefetch`（tap-down）不檢查退避。
- `lib/pages/rcmd/view.dart`：在推薦清單外層用 `NotificationListener<ScrollNotification>`，`ScrollEndNotification` 後 debounce 300 ms，取得可見卡片：最簡單的做法是每張卡片用 `VisibilityDetector`（若專案已有該套件）或依 `SliverGrid` 的可見索引（由 `ScrollController` 位置與卡片高度估算，或用 `itemBuilder` 被建立時登記、dispose 時移除的「已建立卡片」集合，取視窗內的前 6 張）。實作選專案現有工具中最簡單、不新增套件的方式。
- 首次載入清單完成後也觸發一次（不用等捲動）。
- `ScrollStartNotification` 時清空尚未發出的預取佇列（已發出的請求不取消），避免連續捲動時積壓舊卡片。
- 頁面不可見（切到其他分頁、進影片頁）或 App 進背景時 `PlayUrlCache.isPaused = true`，回來時恢復。

### B. 點擊時預熱開頭（AC-4）

- 抽出影片頁「從 PlayUrlModel 選出影片串流與音訊串流網址」的邏輯成純函式（例如 `lib/utils/play_url_select.dart` 的 `selectStreams(PlayUrlModel, {qn, codec 偏好, audio 偏好, BTR 時的 getCdnUrl})`），影片頁 `_queryVideoUrl` 改用它，確保預熱與實際開檔選到同一個網址。
- `BtrProxy.warm(String url, {int bytes = 512 * 1024})`：建立或取得該網址的 `_BtrSource`（與 `wrap` 相同的 key），probe 後下載 `0..bytes-1` 到 source 的預熱緩衝區；**邊下載邊可讀**（例如記錄已收到的 byte 數並在新資料到達時通知等待者）。同一網址只預熱一次。30 秒未被使用只釋放預熱的位元組，**不移除** `_BtrSource` 與 id 對應（否則播放器會拿到 404，`btr_proxy.dart:110-114`）。
- `_Pump`／serve：請求起點落在預熱範圍內時，先寫出已收到的部分；預熱仍在下載中就等待後續資料（不另向 CDN 重複請求同一範圍），直到預熱範圍寫完或預熱失敗（失敗則從目前 `_position` 走原本流程）；之後再走原本的串流／片段流程。
- tap-down（`card_preview.dart` 的 `onTapDown` → `VideoPreview.prefetch`）：快取已有完成的 playurl 時，`selectStreams` 後對影片與音訊網址呼叫 `BtrProxy.warm`。快取未完成時不等待。

### C. 預先建立 CDN 連線（AC-5）

- `btr_cdn.dart`：`btrDio`、`btrProbeDio` 改用 BTR 自己的 `IOHttpClientAdapter(createHttpClient: ...)`，HttpClient `idleTimeout` 60 秒；`clone()` 會共用原本的 adapter，不能直接改它，否則影響全 App 的連線（`btr_cdn.dart:8-13`）。
- `BtrProxy.preconnect(String url)`：對該網址（或同 host）發 `bytes=0-0`，不記失敗統計；同 host 60 秒內只做一次。
- 呼叫時機：playurl 預取成功後，對選出的影片網址 host 呼叫一次（冷啟動沒有網址可用，不做啟動預連）。

### D. 0.8 秒 hedge（AC-6）

- `btr_proxy.dart` 的開頭串流：首 byte 0.8 秒未到 → 啟動第二個節點的同範圍請求，兩者競速：先收到第一個 chunk 者成為寫出來源，另一個取消。兩者都在 2 秒內沒資料 → 依原本流程換節點／fallback。hedge 落敗或被取消不計失敗；勝者記速度。
- 注意 `_position` 與寫出來源只能有一個；競速期間不得寫出任何 byte，直到選定勝者。

## 任務

| 任務 | 內容 | 檔案 |
|---|---|---|
| T-1 | A 可見卡片預取 | `play_url_cache.dart`、`lib/pages/rcmd/view.dart`、可能 `lib/pages/main/` 生命週期 |
| T-2 | B 抽出選串流函式、warm、tap-down 呼叫 | `lib/utils/play_url_select.dart`（新）、`lib/pages/video/controller.dart`、`btr_proxy.dart`、`video_preview.dart` 或 `card_preview.dart` |
| T-3 | C 預連線、D hedge | `btr_cdn.dart`、`btr_proxy.dart` |

分派：T-1 一個 Sonnet；T-2 + T-3 一個 Sonnet（都改 `btr_proxy.dart`）。

## 驗證

模擬器 debug 版重跑 fast-start 的量測方式（至少 10 次開啟，含停止捲動後等 2 秒再點、捲動後立即點），比較中位數；log 加 `PlayUrlCache visible prefetch`、`BTR: warm hit N bytes`、`BTR: preconnect host`、`BTR: hedge win host`。

## 風險

- 可見卡片預取增加 API 請求數（每次停下捲動最多 6 個）：有 412 退避；只在首頁推薦。
- 預熱選錯串流：浪費約 1 MB 流量，30 秒後釋放。
- 記憶體：預熱最多保留最近 4 個網址（約 2 MB），超過時釋放最舊的。

## 審查紀錄

agy（gemini-3.8-flash-high，`--print-timeout 600s`）2026-11-08，5 條全部採用：

1. 預熱未完成時播放器就來請求，會重複向 CDN 要同一段：預熱改為邊下載邊可讀，serve 等待預熱資料。
2. 連續捲動積壓預取：`ScrollStartNotification` 清空未發出的佇列。
3. 冷啟動沒有網址可預連：移除啟動預連，只在 playurl 預取成功後預連。
4. `clone()` 共用 adapter，改 idleTimeout 會影響全 App：BTR 用自己的 adapter。
5. 預熱逾時若移除 source 會 404：只釋放位元組，保留 source。

## 實作偏差

- T-1：可見卡片用 render tree 走訪 `RenderSliverGrid` 的子節點（layoutOffset 對照 `constraints.scrollOffset` 與 `remainingPaintExtent`）取得，未新增套件，也未動 `MainApp`。
- T-1：暫停條件由推薦頁自己判斷（App 生命週期、`MainController.selectedIndex` 是否為首頁、`HomeController.tabController` 是否為推薦），不處理「進影片頁」的 route 事件；進影片頁後，已排入佇列的項目最多再發 6 個請求，之後因無新捲動事件不再排程。
- T-1：清單每次載入成功（含重新整理、載入更多）都會在 300 ms debounce 後觸發預取，不只第一次。
- T-1：風控判斷（412／-412／-352）因 `VideoHttp.videoUrl` 把錯誤轉成文字，用 `errMsg` 字串比對（`(-412)`、`(-352)`、`status code of 412`）。

- T-2：`selectStreams` 回傳 record（含 video、audio、videoUrl、audioUrl）；影片頁只改用它取代原本的選畫質／音訊／getCdnUrl（影片清單為空時以 `!` 保持原本會例外的行為）。音訊畫質與編碼偏好另由 `defaultSelectParams()` 依影片頁同一規則（PlPlayerController.instance 的 cacheAudioQa，否則依 Wi-Fi 預設）取得。
- T-2：`PlayUrlCache` 新增 `completedOf(...)`（用 `Expando` 記錄已成功的回應，快取未完成回傳 null）。tap-down 預熱在 `VideoPreview.prefetch` 開頭執行（有 cid 且 BTR 開啟才做），預覽啟用與否都會預熱。
- T-2：`warm` 只釋放位元組（`_Warm.buffer = null`），`_BtrSource` 與 id 保留；同一網址只預熱一次（釋放後不再重熱）；預熱最多保留 4 個網址，超過時釋放最舊的。預熱緩衝區一開始就配置 512 KB（`Uint8List`）。serve 讀取中（`users > 0`）時計時器不會釋放，結束後才重新計 30 秒。
- T-2：`_Pump` 在 head 之前先 `_serveWarm()`；head 的結尾改由寫完預熱後的 `_position` 計算，後續片段從該位置接續。預熱下載使用 `pickHead`、至多 2 個節點、首 byte 2 秒限制，失敗計節點失敗（與 head 相同）。
- T-3：`btrDio` 與 `btrProbeDio` 共用同一個 `IOHttpClientAdapter`（同一個連線池，探測連線可被 head 重用），系統 proxy 設定複製自 `Request._createPool`。
- T-3：`PlayUrlCache.get` 成功時（含影片頁請求）呼叫 `preconnectStreams`（只加兩行）；`preconnect` 用 `btrProbeDio` 發 `bytes=0-0`，每個 host 60 秒一次，不記失敗統計。
- T-3：hedge 實作為 `_HeadReq` + `_raceHead`：0.8 秒後以 `pickHead(exclude: tried)` 啟動第二節點，首個 chunk 勝出，競速期間不寫任何 byte；輸家若為單純被取消不計失敗；primary 輸給 hedge 也只取消（不降速）；兩者都 2 秒無資料才各自 `slow` 並換下一組節點（`_headSwitches` 不變）；競速前就出錯的節點照常計失敗。

### 審查修正（fast-start-2 T-2/T-3）

- hedge 勝出時，輸掉的節點只記為取消，不再降速（有勝者時一律不標 slow）。
- 兩者都無資料時，只有自己已等滿 head 逾時（約 2 秒）的請求才標 slow；0.8 秒才啟動的 hedge 只記取消。
- 預熱 LRU 淘汰時若仍有 serve 在讀，只先移出 LRU、標記 `evicted`，等最後一個讀取者結束才釋放位元組。
- `CardPreview.onTapDown` 不再受 `VideoPreview.enabled` 限制（改為 `canPreview && !suspended`），預覽關閉時仍會預取 playurl 與預熱；`VideoPreview.prefetch` 預覽關閉時不建立預覽播放器。

### 審查修正

- T-1：移除 `rcmd/view.dart` 中只能在 debug 使用的 `grid.debugNeedsLayout`（release 會丟例外），只靠 `geometry != null`。
- T-1：`_RcmdPageState.dispose()` 增加 `PlayUrlCache.clearPending()`。
- T-1：`prefetchVisible` 改為 async，先取 `defaultParams()`，只有快取未過期且 params 相同才略過；網路切換造成 params 不同時會重新預取。

### 使用者回報後修正（2026-11-08）

- 預熱常被取消：agy 調查（`warm-cancel.md`）確認 11 次 `warm failed ... request cancelled` 皆為預熱共用開頭片段的 2 秒首 byte 逾時；預熱改用獨立的 `_warmTimeout` 5 秒（`btr_proxy.dart`）。
