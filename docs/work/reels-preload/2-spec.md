# 規格：豎屏模式換片加速

對應需求：[1-requirements.md](1-requirements.md)。程式：`lib/pages/reels/controller.dart`（`ReelsController`，約 620 行）、`view.dart`、`lib/models_new/story/story_item.dart`。

## 設計

1. **雙播放器**：
   - `ReelsController` 改成管理兩個槽位 `_slots[2]`，每個槽位有：
     - `Player` 與 `VideoController`
     - `aid`（目前載入哪一部）
     - `ready`（是否已開啟）
   - `current` 指向正在播放的槽位，另一個是 `preload`。
   - 播放目前影片時，在另一個槽位對下一部（index + 1）做這些事：
     - `open(media, play: false)`，音量 0。
     - 讓它緩衝前幾秒。mpv 開啟後暫停時，demuxer 仍會預讀，`demuxer-readahead-secs` 維持現值。
   - 換片（onPageChanged）時：
     - **往下一部，且 preload 槽位的 aid 相符**：交換兩個槽位，新的 current 設音量並 `play()`，seek 到 0（如果已經前進）。舊的 current 暫停，然後拿來預載再下一部。
     - **其他情況**（跳頁、往回、預載不符）：用 current 槽位正常開啟，再用 preload 槽位預載下一部。
   - 各頁的畫面要綁定「這一頁對應的槽位的 VideoController」：
     - 目前頁顯示 current 槽位的 Video。
     - 下一頁在預載完成前顯示封面；預載完成後可以先顯示第一幀（可選）。
   - 事件過濾：position、duration、completed、playing 都只處理 current 槽位的事件。preload 槽位的事件一律忽略（`_isMine` 改為比對槽位）。
   - 世代計數 `_gen` 同時套用到兩個槽位的非同步開啟：換片後過時的開啟要丟棄，避免錯片或兩部同時播。
   - `setActive(false)`（背景、被蓋住）：兩個槽位都暫停。`onClose`：兩個都 dispose，`_createPlayer` 的競態保護兩個都要有（`isClosed` 檢查）。
   - 播完自動下一部，走相同的換片流程，可以用到預載。
2. **使用 `player_preload`**：
   - `StoryItem` 解析 `uri` 中的 `player_preload`（URL 解碼後的 JSON）：
     - 取 `dash.video[]`、`dash.audio[]` 的 `base_url`、`backup_url`、`bandwidth`、`codecid`、`id`（畫質）。
     - 取 `expire_time`，或網址中的 `deadline`。
   - `_fetchSource` 開頭：如果 preload 存在且還沒過期（離過期超過 60 秒），就用它挑影音，規則同 `_pickVideo`：不高於設定畫質的最高 H.264；沒有 H.264 就用其他編碼。然後經 `BtrProxy.wrap`（維持現有行為）組成 EDL。
   - 用 preload 開啟失敗（播放器錯誤）時，清掉這部的快取，改用 `VideoHttp.videoUrl` 再試一次（每部只重試一次）。
   - 種子影片（從影片頁進入，沒有 preload）照舊用 `videoUrl`。

## 任務

| ID | 任務 | 執行 |
|---|---|---|
| T-1 | 實作設計 1、2 | Sonnet |
| T-2 | 程式碼驗證（analyze、diff 審查、建置 release x64、安裝到模擬器並保留資料），寫 3-verification.md | Sonnet |

## 邊界情況

- 快速連滑多頁：預載會被新的換片取代，舊的開啟依世代計數丟棄。
- 下一部的播放網址取得失敗：不預載，換到該頁時照舊顯示錯誤並自動跳過。
- 最後一部（還沒載入更多）：沒有下一部可以預載，載入更多後再預載。

## 實作偏差

-
- 預載頁（下一頁）只顯示封面，不顯示預載槽位的第一幀（規格標為可選）；`view.dart` 不需修改，`videoController` 改成隨目前槽位更新。
- `StoryItem` 原本就已解析 `player_preload` 原始 JSON（`playerPreload`），不需改檔；在 `_preloadSource` 以 `Dash.fromJson` 重用既有的 dash 解析。過期時間先看 `expire_time`，沒有才看網址 `deadline`。
- 預載槽位用 `_Slot.token`（每次重新指派加一）丟棄過時的預載開啟；目前槽位的開啟用 `_gen` 加 token。換片時若預載還在開啟中，先交換槽位再等它完成，失敗則在該槽位一般開啟。
- 播放器錯誤事件（`player.stream.error`）觸發 `player_preload` 重試：清掉 `_sources` 快取、記入 `_noPreload`，用 `videoUrl` 再開一次。
- `loadMore` 加入新影片後，若目前已開啟，會補預載下一部。
- 依使用者變更，T-2 驗證（3-verification.md、建置、安裝）改由其他模型執行，本次僅跑一次 `flutter analyze`。
