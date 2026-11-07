# 規格：豎屏模式換片速度與畫質

需求：`docs/work/reels-speed-quality/1-requirements.md`

## 設計

### T-1 畫質（`lib/pages/reels/controller.dart`、`lib/http/video.dart`）

1. `VideoHttp.storyFeed` 的 `qn` 由 32 改為 80。
2. 控制器新增 `int _maxQa`，在 `onInit` 先設為 `Pref.defaultVideoQa`，再非同步依 `ConnectivityUtils.isWiFi` 改為 Wi-Fi 或行動網路的設定值（同 `lib/pages/video/controller.dart:933-942`）。`_fetchSource` 開頭 `await` 這個判斷（用 `Future<void> _qaReady`）。
3. `_pickVideo(Dash dash)` 改為回傳選到的 `VideoItem`（或含 `id` 與 `baseUrl` 的 record）：
   - 候選：`id <= _maxQa` 的全部影片；沒有時取 id 最小的。
   - 取最高 `id`；同 `id` 依 codecid 7（AVC）→ 12（HEVC）→ 13（AV1）→ 其他；同 codec 取 `bandWidth` 最高。
4. `_preloadSource`：選到的 `id < min(_maxQa, 80)` 時回傳 null（改走 `videoUrl`）。
5. `videoUrl` 呼叫的 `qn` 改用 `_maxQa`。

### T-2 預載更多（`lib/pages/reels/controller.dart`）

1. 播放器數量由 2 改為 4（常數 `_poolSize = 4`）。所有 `_slots.length == 2` / `!= 2` 改為 `_poolSize`。
2. 移除 `_otherSlot`。新增 `_Slot? _slotFor(int aid)`：在非目前槽位中找 `aid` 相同者。
3. `_startItem(i)`：
   - 有 `_slotFor(item.aid)` 時：把該槽位設為目前（`_cur` 改為它的索引），舊目前槽位 `pause`、`setVolume(0)`、`reset()`。其餘流程同現在的交換路徑。
   - 沒有時：不再 reset 其他預載槽位，除非它們載的不是 i+1 到 i+3（交給 `_preloadAhead` 處理）。在目前槽位走一般開啟。
4. `_preloadNext(i)` 改為 `_preloadAhead(i)`：
   - 目標：`items[i+1]`、`items[i+2]`、`items[i+3]`（存在者）。
   - 先保留已載目標的槽位；把其他非目前槽位（載的不是目標）`pause` + `reset()`，再依序指派給尚未載入的目標，呼叫 `_openPreload`。
   - 另外對 `items[i+4]` 到 `items[i+6]` 呼叫 `_source(item)`（只取網址，不開播放器）。
5. `_onSlotError`、`setActive`、`onClose`、`_createPlayers` 中針對兩個槽位的寫法，改為迴圈處理所有槽位。新建的非目前槽位 `setVolume(0)`。
6. `loadMore` 補預載處（`if (_opened) _preloadNext(_playingIndex);`）改呼叫 `_preloadAhead`。


### 審查後補充（必須實作）

- R-2 解碼退路：新增 `Set<int> _avcOnly`。`_pickVideo(dash, {bool avcOnly = false})`：`avcOnly` 時只選 codecid 7（沒有 AVC 才退回全部）。`_onSlotError` 改為：
  - `slot.fromPreload` 時：照舊加入 `_noPreload`、清 `_sources`、重試（F-1 位置保留）。
  - 否則若 `_avcOnly.add(aid)` 成功：清 `_sources[aid]`、同樣從原位置重試（只用 AVC）。
  - 都已試過時：不再重試。
- R-3 網址過期：`ReelsSource` record 加 `int expire`（毫秒 epoch；0 表示未知）。`player_preload` 用現有 `expire_time`；`videoUrl` 取影片網址的 `deadline` 查詢參數（秒）。`_source(item)` 取快取時，若 `expire > 0` 且剩不到 60 秒，移除快取並重新 `_fetchSource`。
- R-4 `storyFeed` 的 `qn` 直接改為 80；`lib/pages/reels/feed.dart:50`（豎屏分頁卡片）也使用同一個函式，可接受（卡片的 `player_preload` 會被豎屏模式沿用，畫質更高是預期）。
- R-5 網路判斷：`_maxQa` 只在 `PlatformUtils.isMobile || Platform.isLinux` 時依 `ConnectivityUtils.isWiFi` 決定（同影片頁）；其他平台用 `Pref.defaultVideoQa`。補 import。`isWiFi` 例外時保留 `Pref.defaultVideoQa`。`_qaReady` 在 `onInit` 啟動，`_fetchSource` 開頭 `await`（已包 try/catch，不會丟例外）。
- R-6 丟棄槽位：所有「丟棄預載槽位」的路徑都要 `player.pause()`、`player.stop()`、`reset()`，釋放解碼器與快取。`token` 機制確保舊的 `open` 完成後被丟棄。
- R-7 目前這部失敗（`_fail`）時也呼叫 `_preloadAhead(i)`，避免自動跳下一部時冷啟。預取網址失敗時靜默（不寫 `_sourceErrors` 以外的狀態），下次取用時自然重試（`_source` 失敗會移除快取，現有行為）。
- R-8 建立播放器：`_createPlayers` 改為 `Future.wait` 平行建立 4 個；任何一個失敗或頁面已關閉時釋放全部已建立者（現有清理邏輯改為等全部完成後處理）。
- R-9 除錯紀錄：`kDebugMode` 時 `debugPrint`：`[reels] open aid=… slot=… preload|play`、`[reels] swap aid=…`、`[reels] source hit|fetch aid=…`，方便實機確認 AC-1、AC-2。
- R-10 `_startItem(i)` 在 `gen` 更新後、`await _ensurePlayers()` 之後立即：把「非目前、且 aid 不屬於 `items[i+1..i+3]` 也不是 `items[i]`」的槽位依 R-6 丟棄。往回滑與跳頁都以新的 i 為準。

## 任務

| ID | 內容 | 相依 |
|---|---|---|
| T-1 | 畫質（上方 T-1） | — |
| T-2 | 預載 3 部 + 預取 3 部網址（上方 T-2） | — |

兩個任務改同一個檔案，由同一個子代理依序完成。

## AC 驗證方式

| AC | 方式 |
|---|---|
| AC-1、AC-2 | 讀程式碼 + diff 審查；實機手感待使用者測試 |
| AC-3、AC-4、AC-5 | 讀程式碼 + diff 審查；實際畫質待使用者測試 |
| AC-6 | diff 審查逐項確認 |

## 邊界情況與風險

- 列表剩不到 3 部：只預載存在的；`loadMore` 補上後再呼叫 `_preloadAhead`。
- 預載中途使用者跳頁：靠 `token` 丟棄過時的開啟（現有機制）。
- 記憶體：4 個 mpv，最多約 128MiB demuxer 快取。
- 硬體解碼器數量：4 個播放器同時開啟可能超過低階裝置上限；失敗時走 `_onSlotError`／`_fail`，實機待使用者測試。
- 行動網路流量增加：預載 3 部（使用者選擇）。
- 帳號未登入時伺服器可能只給 480P：`player_preload` 與 `videoUrl` 都低，結果仍是 480P（無法改善），只多一次 API 請求。

## 回退

還原這兩個檔案即可，沒有資料格式變更。

## 審查紀錄

agy 審查逾時（4 分 40 秒，只有部分輸出），改由 Haiku 審查：`review-spec.md`。

| # | 意見 | 處理 |
|---|---|---|
| 1 | 4K 設定時 1080P 的 `player_preload` 仍被接受 | 不採用：豎屏影片極少有 1080P 以上，為了 4K 讓每部多一次 API 請求不划算；上限 1080P 是刻意取捨 |
| 2 | 改選 HEVC/AV1 後無解碼退路 | 採用：R-2 |
| 3 | 預取網址可能過期 | 採用：R-3 |
| 4 | `storyFeed` 另有呼叫者 | 採用：R-4（說明可接受） |
| 5 | 平台閘門、import、例外 | 採用：R-5 |
| 6 | `reset()` 不停止播放器 | 採用：R-6 |
| 7 | 失敗時不預載 | 採用：R-7 |
| 8 | 4 個播放器循序建立較慢、解碼器數量 | 採用：R-8，風險段補充 |
| 9 | AC-1、AC-2 無法觀察 | 採用：R-9 |
| 10 | 非目標槽位清理時機 | 採用：R-10 |

## 實作偏差

- `onPageChanged` 的 loadMore 門檻由 `items.length - i <= 3` 改為 `<= 6`，讓 i+4..i+6 的網址預取有項目可用。
- `_createPlayers` 失敗時用 `Future<void>.error(err, st)` 重新丟出（`Error` 被 loading_state 的 `Error` 遮蔽，無法用 `Error.throwWithStackTrace`）。
- `_onSlotError` 另加 `slot.media == null` 時忽略（槽位已 reset 或尚未開啟的過時錯誤事件），避免非預載來源誤觸發 AVC 重試。
- `_source` 改為 async：先 await 快取的 Future 才能檢查 `expire`；過期則移除快取並重新取得。
- `_preloadAhead` 空槽位來自「非目前、未載目標」的槽位（先 `_discard`）；指派以級聯呼叫確保 `reset()` 後才取 token。
- `_startItem` 的 R-10 清理對 `aid == null` 的槽位不再重複 `_discard`。
