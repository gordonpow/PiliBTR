# 規格審查：豎屏模式換片速度與畫質

審查對象：`docs/work/reels-speed-quality/2-spec.md`（對照 `1-requirements.md` 與程式碼）

## 問題（依嚴重度排序）

### 1. 規格 T-1.4／AC-4：1080P 門檻與「以使用者設定畫質播放」衝突

- 位置：spec T-1.4（`min(_maxQa, 80)`）、AC-4。
- 問題：使用者上限設為 4K（`_maxQa` > 80）時，story feed 給的 1080P `player_preload` 仍會被接受，因為 `min(116, 80) = 80`，`80 < 80` 為假。結果是 4K 使用者被靜默降到 1080P，與需求目標「以使用者設定的畫質播放」相反。
- 證據：`lib/pages/reels/controller.dart:503-510`（`_preloadSource` 目前沒有任何畫質門檻，spec 新增的門檻即是這裡）。
- 修正：請使用者確認。若要以設定為準，門檻改為 `id < _maxQa` 即改走 `videoUrl`（代價：4K 使用者每部多一次 API）；若保留 1080P 門檻，spec 須明寫這個取捨與理由。

### 2. 規格 T-1.3：跨編碼選擇沒有解碼能力的退路，錯誤重試會再選同一編碼

- 位置：spec T-1.3（候選不分編碼，取最高 id）。
- 問題：原程式只選 AVC，註解寫明「所有裝置都能解碼」。改後可能選到 AV1/HEVC 的高畫質，低階裝置若無硬解會播放失敗。`_onSlotError` 的重試會呼叫 `videoUrl`，再經 `_pickVideo` 選到同一個 AV1，於是 `_fail`，沒有任何降級。
- 證據：`lib/pages/reels/controller.dart:576-585`（原 AVC 限定與註解）、`:549`（一般路徑呼叫 `_pickVideo`）、`:464-482`（`_onSlotError` 重試）。
- 修正：`_pickVideo` 增加參數（例如 `avcOnly`）。`_onSlotError` 重試時在該 aid 上設為 `avcOnly`，記錄方式比照 `_noPreload`。spec 須列出此重試規則與測試方式。

### 3. 規格 AC-2／T-2.4：預取的播放網址沒有過期機制

- 位置：spec AC-2、T-2.4（對 `items[i+4..i+6]` 呼叫 `_source`）。
- 問題：`_preloadSource` 的 60 秒剩餘時間檢查只在取得網址當下執行。`_source` 的快取不會重新驗證。目前網址只快取數秒，AC-2 把存活時間拉長到數分鐘以上，使用者滑到 i+4 時網址可能已過期，`_startItem` 直接 `_fail`。
- 證據：`lib/pages/reels/controller.dart:517-526`（過期檢查只在取得時）、`:488-491`（`_source` 快取永不失效）、`:685-690`（`source` 為 null 時 `_fail`）。
- 修正：`_sources` 的值保存 `expire`（或 `deadline`）。`_source` 取用時若剩餘不足 60 秒，就丟棄快取並重新 `_fetchSource`。spec 須列出此規則。

### 4. 規格 T-1.1：`storyFeed` 的 `qn` 改動影響另一個呼叫者，規格未列

- 位置：spec T-1.1（`VideoHttp.storyFeed` 的 `qn` 由 32 改為 80）。
- 問題：`storyFeed` 還被 `lib/pages/reels/feed.dart:50` 呼叫。該檔不在「只改兩個檔」的範圍內，但行為會被改變。規格也沒有說明這個影響。
- 證據：`lib/http/video.dart:207`（`'qn': 32`）、`lib/pages/reels/feed.dart:50`（另一呼叫者）。
- 修正：`storyFeed` 增加 `int qn = 32` 參數，只有 `ReelsController.loadMore`（`controller.dart:277`）傳 80。或者 spec 明確說明 feed.dart 也可接受 80，並更新需求的限制段。

### 5. 規格 T-1.2：畫質判斷缺平台閘門、缺 import，且 `_qaReady` 失敗未處理

- 位置：spec T-1.2（「同 `lib/pages/video/controller.dart:933-942`」）。
- 問題 a：影片頁只在 `PlatformUtils.isMobile || Platform.isLinux` 時才做 Wi-Fi／行動網路判斷（`lib/pages/video/controller.dart:933`）。spec 沒有列出這個閘門，所以「和一般影片頁相同判斷」（AC-3）不成立。
- 問題 b：`controller.dart` 的 import 區（第 1-23 行）沒有 `ConnectivityUtils`（定義於 `lib/utils/connectivity_utils.dart`），spec 未提及。
- 問題 c：`_qaReady` 的 `await` 位於 `_fetchSource` 第 536 行，在 `try` 之外。若 `ConnectivityUtils.isWiFi` 拋出例外，`_source` 會失敗，`_startItem` 進入 `_fail('播放失敗')`。
- 修正：spec 寫明平台閘門，並與影片頁保持一致。補上 import。`_qaReady` 包 try/catch，失敗時保留 `Pref.defaultVideoQa`。若要簡化，可在 `_startItem` 開頭 `await _qaReady` 一次，不必放在 `_fetchSource`。另需說明網路切換後 `_maxQa` 不會重新判斷。

### 6. 規格 T-2.3／T-2.4：`reset()` 不會停止播放器或取消進行中的 `open`

- 位置：spec T-2.3（swap 路徑）、T-2.4（`_preloadAhead` 的「`pause` + `reset()`」）、`_onSlotError` 的丟棄路徑。
- 問題：`_Slot.reset()` 只 `token++` 並清欄位，沒有 `stop()`，也不會中斷正在執行的 `player.open`。被丟棄的預載槽位會繼續持有解碼器與約 32MiB 的 demuxer 快取，直到被重新指派。若重新指派時前一個 `open` 尚未結束，兩個 `open` 會重疊。目前只有 `_startItem` 一般路徑會呼叫 `stop()`（`controller.dart:682-684`）。
- 證據：`lib/pages/reels/controller.dart:848-855`（`reset`）、`:678-684`（一般路徑的 `stop()`）、`:721-725`（`_preloadNext` 的 reset）。
- 修正：spec 規定所有丟棄槽位的路徑都必須 `pause()` + `stop()` + `reset()`。重新指派前應等待舊的 `opening` 結束或確認 token 失效後才開新檔。

### 7. 規格 T-2.4／邊界情況：目前這部失敗時不會預載，網路失敗的行為未定義

- 位置：spec T-2.4、邊界情況段（未提網路失敗）。
- 問題：`_preloadAhead` 只在 `_startItem` 開啟成功後（`controller.dart:667`、`:706`）或 `loadMore`（`:291`，需 `_opened`）呼叫。目前這部走 `_fail` 時不會預載，`_fail` 1.5 秒後自動跳下一部，下一部可能沒有預載槽位而冷啟。預取失敗（`_fetchSource` 回傳 null）是靜默的，spec 也沒有說明應否重試。
- 修正：spec 規定 `_fail` 路徑也要呼叫 `_preloadAhead(i)`（不依賴 `_opened`，但目標仍以 `items` 為準）。並寫明：預取失敗靜默、不影響目前播放、下次取用時再取網址，且不覆寫 `_sourceErrors`。

### 8. 規格 T-2.5／風險段：4 個播放器的啟動延遲與解碼器數量未處理

- 位置：spec T-2.5（`_createPlayers` 改為 `_poolSize`）、風險段（只寫記憶體）。
- 問題 a：`_createPlayers` 目前循序 `await` 建立槽位（`controller.dart:379-389`）。改為 4 個後，第一部要等 4 次 `Player.create` + `VideoController.create` 才能開始播放，因為 `_startItem` 第 637 行會 `await _ensurePlayers()`。
- 問題 b：4 個 `open` 各自會初始化 video track（mpv 開檔即建立解碼器），同時佔用多個硬體解碼器。低階裝置可能超過上限。風險段只提記憶體，漏掉這點。
- 修正：spec 規定先建立並開始播放第 0 槽，其餘在背景建立（或 `Future.wait` 平行建立，並處理部分失敗）。風險段加入解碼器數量，並寫明實機驗證方式（例如記錄 `open` 失敗次數）。

### 9. 規格 AC 驗證方式：AC-1、AC-2 只靠讀程式碼，無法證明「不需重新取得網址與開啟」

- 位置：spec「AC 驗證方式」表。
- 問題：AC-1 要求連續下滑三部時「每一部都不需要重新取得網址與開啟」。目前只寫「讀程式碼 + diff 審查」，沒有可重現的判定方式。AC-6 的「diff 審查逐項確認」也沒有列出逐項的檢查點。
- 修正：spec 規定在 `_startItem`、`_openPreload`、`_fetchSource` 加入 `kDebugMode` 計數日誌（`open` 次數、`_sources` 命中次數、swap 次數）。驗收方式改為實機連續下滑三部，檢查日誌中第 i+1..i+3 部沒有新的 `open` 與 `videoUrl` 請求。AC-6 則列出逐項檢查的行號（例如 `setActive` 的 pause 迴圈、`onClose` 的 dispose 迴圈）。

### 10. 規格 T-2.3／T-2.4：跳頁或往回滑時，非目標的預載槽位要等到新頁成功開啟才處理

- 位置：spec T-2.3 的「沒有時」分支（「不再 reset 其他預載槽位，除非它們載的不是 i+1 到 i+3」）。
- 問題：跳到不相鄰的 j 時，舊的 i+1..i+3 槽位仍保持開啟，直到 `_startItem(j)` 成功才由 `_preloadAhead` 清理。期間仍佔用記憶體與解碼器。往回滑時（i → i-1），目標是 i-1 的 i、i+1、i+2，i+3 應被丟棄，但 spec 只寫「i+1 到 i+3」，沒有說明相對於哪個索引。
- 證據：`lib/pages/reels/controller.dart:671-676`（現有 `other` 的 reset 只針對單一槽位）、`:642`（只有相鄰時才 swap）。
- 修正：`_startItem(i)` 開始時（gen 更新後）就 `stop()` + `reset()` 所有非目前、且 aid 不屬於 `items[i+1..i+3]` 的槽位，目標則以新的 i 為準。spec 須以索引明確寫出。
