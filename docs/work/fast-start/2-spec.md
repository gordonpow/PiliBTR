# 規格：點開影片快速開播（fast-start）

需求：[1-requirements.md](1-requirements.md)

## 設計

### A. BTR 代理（`lib/services/download/btr_proxy.dart`、`lib/services/download/btr_cdn.dart`）

1. **平行試連（AC-3）**：`_probe` 改為對最多 3 個候選節點同時發 `bytes=0-0`，用第一個回 206 且有 `content-range` 的結果；其他請求取消。單一試連逾時：connect 3 秒、receive 3 秒。全部失敗 → `_total = null`，直通原始網址（沿用 `_passthrough`）。試連失敗的節點記一次失敗到全域統計（見 4）。
   - `_probed` 失敗的黏性（`:160-162`）：失敗後 30 秒內直通，之後的新請求可以再試一次。
2. **標頭時機（AC-1）**：取得 `_total` 後先設定好 206、`content-range`、`content-length`、`accept-ranges` 等標頭，但**不立即 flush**；收到開頭片段第一個 chunk 時連同資料一起送出。`dart:io` 送出標頭後不能再改，所以標頭送出前失敗才可改走 `_passthrough`；標頭送出後的失敗只能用 `pipeRemaining` 在同一個回應繼續寫 body。
3. **開頭片段串流（AC-1、AC-2）**：`_Pump.run` 的第一個片段不再走「整塊下載後 `res.add`」。改為：
   - 對選定節點（優先：全域統計中最快且未封鎖者；沒有統計時用原始網址）開一個 range 請求 `start..start+128KB-1`，收到的 chunk 直接 `res.add` 並 `flush`。
   - 首 byte 計時：2 秒內沒收到任何 byte → 取消，換下一個節點重來（最多 2 次），再失敗就 `pipeRemaining` 直通原始網址。
   - 中途斷線：已寫出的 byte 數記在 `position`，從 `position` 起改由其他節點補完開頭片段剩餘部分（可用一般片段下載後寫出）。
   - 其他片段（512 KB）照舊平行下載並依序寫出；開頭片段串流期間就開始下載後續片段。
4. **全域節點統計（AC-4）**：新增程序層級的 `BtrHostStats`（static map，key 為 host）：失敗次數、封鎖到期時間、速度 EMA。
   - `BtrNodePool` 建立時與 `pick` 時參考全域統計：跳過封鎖中的 host；有速度資料的 host 不再當作「未測試」優先嘗試。
   - 片段成功更新速度；DNS 失敗、連線錯誤、非 206 記失敗；同一 host 連續 2 次失敗封鎖 10 分鐘。
   - 所有節點都封鎖時，不丟例外，改用原始網址。
5. **一定關閉回應（AC-5）**：`_Pump.run` 最外層加 `finally { try { await res.close(); } catch (_) {} }`，`pipeRemaining` 失敗也會關閉。檢查 `btr_proxy.dart` 中所有回應寫出路徑（`_passthrough`、404 等）都有關閉。
6. **重試期間不影響已有行為**：片段重試次數、hedge 邏輯保留，但開頭片段使用 3 的新流程。

### B. 播放器（`lib/plugin/pl_player/controller.dart`）

1. **重試條件（AC-6）**：`:1282-1286` 的錯誤判斷加入 `Failed to open http://127.0.0.1`、`Can not open external file http://127.0.0.1`、`Failed to open edl://`（DASH 用 EDL 包裝，`:1063-1070`；目前 `:1309-1314` 會吞掉這些錯誤）。觸發重試時，若這次播放使用 BTR，重試必須用 `dataSource` 中原始的 CDN 網址重新組 EDL 開檔（不經 `BtrProxy.wrap`），不能重播已包裝過的字串。實作方式：在 PlPlayerController 加一個「這部影片停用 BTR」旗標（以 cid 判斷，換影片時重設），`setDataSource`／`refreshPlayer`（`:1302`）依旗標決定是否 wrap。
2. **network-timeout（AC-7）**：播放器建立時（`_createVideoController` 或設定 mpv 屬性的位置）設定 `network-timeout` 為 `15`。若 media_kit 在 `open` 時覆寫，改在 open 前設定；確認實際生效的位置。

### C. 影片頁 playurl（`lib/pages/video/controller.dart`、`lib/common/widgets/video_card/video_preview.dart`）

0. **首播用目標畫質請求（AC-8、AC-10）**：`_queryVideoUrl` 目前固定以最高畫質 `qn=129`（`:956`）請求，回應常缺少較低畫質才需要補齊。改為首播以目標畫質（`cacheVideoQa`，預設 1080P）請求；目標畫質高於 1080P 或使用者手動切到回應中沒有的更高畫質時，才發請求取得。
1. **補齊畫質不阻擋（AC-8）**：`_queryVideoUrl` 中 `_supplementVideoQualities`（`:906-913`、`:960`）改為不 await：先用第一次結果選串流並 `initPlayerIfNeeded`，補齊結果回來後只更新畫質清單（不重新開檔、不改目前畫質）。注意：如果目前畫質依賴補齊結果才選得到，就維持第一次結果中最接近的畫質。
2. **重用 prefetch（AC-9）**：
   - tap-down prefetch 不受影片預覽開關影響（目前 `video_preview.dart:163-165` 有 `if (enabled)`）：預覽關閉時仍預取 playurl（不建立預覽播放器）。卡片沒有 cid 時不預取 playurl（不為此多打 ab2c）。
   - `VideoPreview.prefetch`（`video_preview.dart:163-226`）改為用影片頁相同的 playurl 參數（`qn`、`fnval`、`fourk` 等，與 `VideoHttp.videoUrl` 在影片頁的呼叫一致）請求，完整的回應模型存入一個共用快取（例如 `PlayUrlCache`，key 為 `bvid + cid + mid`（mid 為目前主帳號，未登入為 0），有效 60 秒，最多 6 筆）。
   - 預覽從同一個回應中挑最低畫質影片與最低音訊作為 `PreviewSource`（保持現有預覽行為）。
   - 影片頁 `_queryVideoUrl` 呼叫 `VideoHttp.videoUrl` 前先查快取，命中且未過期就直接用；未命中照舊請求。進行中的 prefetch（Future 尚未完成）也可以等待同一個 Future，避免重複請求。
   - 只處理 UGC（非番劇、非課程、無 epid）。
   - 帳號切換或登出時清空快取（key 已含 mid，清空為額外保險）。
   - 影片頁使用快取前確認請求參數（qn、fnval 等）與快取時相同，不同就不用快取。

### D. 預設畫質（AC-10，`lib/utils/storage_pref.dart`）

- `defaultVideoQa`（Wi-Fi，`:254-257`）與行動網路的預設值：未設定時改為 1080P（qn 80）。桌面平台維持原預設。
- 使用者已存的值不變（Hive 有值就用該值）。
- 設定頁顯示的預設值同步（若設定頁有獨立的 defaultVal，一起改）。

## 任務

| 任務 | 內容 | 檔案 | 相依 |
|---|---|---|---|
| T-1 | A（BTR 代理全部） | `btr_proxy.dart`、`btr_cdn.dart` | 無 |
| T-2 | B（重試、network-timeout、停用 BTR 旗標） | `lib/plugin/pl_player/controller.dart` | 無 |
| T-3 | C（補齊畫質不阻擋、prefetch 重用） | `lib/pages/video/controller.dart`、`video_preview.dart`、可能 `lib/http/video.dart`、新檔 `lib/utils/play_url_cache.dart` | 無 |
| T-4 | D（預設畫質） | `lib/utils/storage_pref.dart`、設定頁 model | 無 |

分派：T-1 + T-2 一個 Sonnet 子代理（同屬播放管線）；T-3 + T-4 一個 Sonnet 子代理。兩者檔案不重疊。

## AC 驗證方式

| AC | 方式 |
|---|---|
| AC-1～AC-5 | diff 審查；模擬器 debug 版 log（`BTR:` 開頭）觀察首 byte 時間與 fallback |
| AC-6、AC-7 | diff 審查 |
| AC-8、AC-9 | diff 審查；debug log 確認影片頁沒有重打 playurl（Dio log） |
| AC-10 | diff 審查 |
| AC-11 | diff 審查：BTR 關閉時的分支 |
| AC-12 | `flutter analyze`、release 建置 |
| 整體開播時間 | 待使用者實機測試 |

## 邊界情況與風險

- 開頭片段串流與 hedge／重試交錯：要確保不會重複寫出同一段 byte，`position` 必須精確。
- 播放器 seek 時關閉舊連線：`res.done` 觸發 `_stop`，串流中的請求要取消。
- 全域統計誤封鎖：只在連續失敗時封鎖，且有 10 分鐘時效。
- prefetch 改用高畫質參數：回應大小相同（playurl 是 JSON），不增加流量；但 tap-down 不一定點開，請求數不變（原本就會打）。
- playurl 網址有效期約 120 分鐘，快取只保留 60 秒，無過期風險。
- 回退：每個任務獨立，可分別還原。

## 審查紀錄

agy（gemini-3.8-flash-high）2026-11-08，4 條採用：

1. 首播固定 `qn=129` 會缺 1080P 而需補齊：改為首播以目標畫質請求（部分採用：仍保留背景補齊作為高畫質清單來源）。
2. prefetch 受預覽開關限制、cid 缺失、key 未含 mid：預取脫離預覽開關、無 cid 不預取、key 改 `bvid + cid + mid`。
3. 重試漏抓 `edl://` 錯誤、`refreshPlayer` 會重播已包裝網址：加入 `edl://`，重試用原始網址重組。
4. 標頭提早 flush 後無法 fallback 到 `_passthrough`：標頭延到首個 chunk 才送；`run` 加 `finally` 關閉回應。

## 實作偏差

- T-1：開頭片段失敗且已換滿節點（初始加 2 次切換）時，一律用 `pipeRemaining` 從 `position` 直通原始網址（不論標頭是否已送出，標頭在送出前已依請求範圍設好）；只有 `pipeRemaining` 本身在「尚未寫出任何 byte」時失敗，才改走 `_passthrough`。
- T-1：節點首 byte 逾時計為該節點一次失敗（寫入全域統計）；被 seek／停止取消則不計。
- T-1：`BtrNodePool` 移除「全部封鎖超過 maxResets 就丟例外」，改回傳原始網址節點；單檔封鎖仍最多重置 3 次，全域封鎖只等到期。
- T-1：`_handle` 加 `finally` 再關一次回應（重複關閉無害），涵蓋所有 serve 路徑。
- T-2：`network-timeout` 在 `_initPlayer` 中 `Player.create` 之後用 `setProperty` 設為 15（media_kit 的 `_create` 會在套用 `PlayerConfiguration.options` 之後把它覆寫成 5，所以不能放在 options）。
- T-2：停用 BTR 旗標僅在 `Failed to open http://127.0.0.1`、`Can not open external file http://127.0.0.1`、`Failed to open edl://` 觸發時設定，且沿用原本節流與「isBuffering 且 buffered==0」的重試條件。


- T-3：背景補齊（缺少的低於最高畫質）只在目標畫質高於 1080P 時執行；一般情況首播不再多打 playurl。更高或缺少的畫質改為使用者手動選取時才延遲請求（`ensureVideoQuality`），畫質選單改用 `canSelectVideoQuality`（回應已有，或在 accept_quality 內）判斷可選，需動到 `lib/plugin/pl_player/view/view.dart` 畫質選單；請求失敗時提示並維持目前畫質。
- T-3：影片頁只有首次查詢（非 fromReset、未切換語言、無 epId、UGC）才走 `PlayUrlCache`；重新查詢一律直接請求。
- T-3：預取與影片頁的 qn 都來自 `PlayUrlCache.defaultParams()`（`PlPlayerController.instance?.cacheVideoQa`，否則依 Wi-Fi/行動網路取預設畫質）；若使用者本次已手動改畫質導致 qn 不同，參數不符就不使用快取。
- T-3：快取參數比對含 qn、tryLook、voiceBalance；快取清空掛在 `Accounts.set(main)`、`Accounts.clear`、`Accounts.deleteAll`。預覽啟用時，tap-down 仍走 `source()`（內含同一份快取請求，可處理無 cid 的 ab2c）。
- T-4：設定頁沒有獨立 defaultVal，直接讀 `Pref`，無需另改；行動網路預設本來就是 1080P，未改。

### 審查修正

- T-1 全域封鎖：`recordFailure` 同 host 1 秒內最多算一次；原始網址的 host 不會被封鎖（`canBan: false`）；首 byte 逾時改為只降速度（`slow`），不計失敗。
- T-1 中途斷線：連線中斷或提早結束但已收到部分 byte 時，`report(failed: true)` 仍記 strike 與全域失敗，不重設失敗計數（速度照樣更新）。
- T-1 取消：`pipeRemaining` 由 `_Pump._fallbackToken` 控制，`_stop` 時取消；`_passthrough` 監聽 `res.done` 取消上游請求。
- T-1 `BtrNodePool._build` 保留所有節點，只排序；封鎖在使用時由 `_isUsable` 動態過濾，封鎖到期後節點自動回來。
- T-1 開頭片段與一般片段檢查 206 回應 `content-range` 的起點必須等於請求起點，不符視為失敗（沒有該標頭則接受）。
- T-1 `_probe` 等待加 4 秒上限，逾時視為試連失敗（直通）。
- T-2 重試：`btrFailed` 錯誤首次出現時設定停用旗標並直接 `refreshPlayer()`，不經 `isBuffering` 判斷與節流；每部影片只觸發一次（旗標已設則走原本流程）。`Media.copyWith(uri:, start:)` 在 media_kit 解析版本（git `73771ec`）中存在，`Player.open(Media, play:)` 簽名相符。
- T-2 旗標重設：`setDataSource` 每次都重設 `_btrDisabledCid`；`refreshPlayer` 不經過此處，重試期間旗標保留。

### 審查修正

- T-3：移除每次開啟都多打一次 playurl 的背景補齊，改為高畫質延遲請求（見上）。
- T-3：快取 key 改為 bvid + cid + 主帳號 mid + 影片帳號 mid；`Accounts.set`（任何類型）、`clear`、`deleteAll` 都清空快取。
- T-3：影片頁取得回應後用 `PlayUrlModel.copyForPage()`（新增於 `lib/models/video/play/url.dart`，dash 影片清單為新 List）作為自己的副本，合併畫質不再改到共用快取的物件。
