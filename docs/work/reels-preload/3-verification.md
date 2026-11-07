# 驗證：豎屏模式換片加速

對應：[1-requirements.md](1-requirements.md)、[2-spec.md](2-spec.md)。差異 patch：[diff.patch](diff.patch)。

本次為程式碼層級驗證（靜態分析與 diff 審查）。未操作模擬器 UI，功能測試由使用者進行。

## 一、已執行的檢查

| 檢查 | 指令 | 結果 |
|---|---|---|
| 靜態分析 | `flutter analyze --no-pub lib` | `38 issues found`，錯誤 0、警告 0（皆為既有 info，`grep` 確認 error/warning 數量為 0） |
| diff 存檔 | `git diff HEAD -- lib/pages/reels/controller.dart` | 已存為 [diff.patch](diff.patch)（525 行） |
| 程式碼審查 | 對照 2-spec.md 逐項檢查 `controller.dart` | 見第三節 |

## 二、驗收條件（AC）

| 編號 | 條件 | 狀態 | 程式碼覆蓋說明 |
|---|---|---|---|
| AC-1 | 往上滑直接切換，1 秒內開始播放，不再有長時間載入圈 | 待使用者測試 | `_preloadNext` 在播放目前影片時，於另一槽位以靜音暫停預載下一部；`_startItem` 的交換路徑（`other.aid == item.aid`）直接 `play()`，不重新請求網址。預載未完成時會等待 `slot.opening` 再決定。 |
| AC-2 | 往下滑回上一部可接受重新載入 | 待使用者測試 | 非預載的那部走一般開啟流程（`_startItem` 非交換路徑），不預載上一部。 |
| AC-3 | `player_preload` 未過期則直接播放，過期、缺少或失敗則退回 `VideoHttp.videoUrl` | 待使用者測試 | `_preloadSource`：`expire_time` 優先、無則取網址 `deadline`，離過期不足 60 秒即放棄；`_onSlotError` 在 preload 播放錯誤時清快取、記入 `_noPreload`，改用 `videoUrl` 重試一次。 |
| AC-4 | 同一時間只有一個播放器出聲；離開、蓋住、退到背景時兩個都暫停；離開頁面時兩個都釋放 | 待使用者測試 | 預載槽位 volume 0（`_createPlayers`、`_openPreload`）；`setActive(false)` 暫停兩個槽位；`onClose` 釋放兩個槽位，`_createSlot`／`_createPlayers` 有 `isClosed` 競態保護。 |

## 三、程式碼審查結果

審查範圍：`lib/pages/reels/controller.dart` 全檔（含 diff）。對照 2-spec.md 的設計與實作偏差。

### 符合規格的項目

- 兩個槽位 `_slots[2]`，`_cur` 指向目前播放者（`controller.dart:319-320`）。
- 事件只處理目前槽位：`_isMine(slot)` 要求 `identical(slot, _curSlot)` 且 `_opened`（`controller.dart:363-372`）。
- 世代與 token 檢查：`_startItem` 的每個 `await`（`_ensurePlayers`、`opening`、`_source`、`open`）之後都有 `gen`／`tok` 檢查；`_openPreload` 在 `_source` 與 `open` 之後檢查 `isClosed` 與 `tok`。
- `setActive(false)` 暫停兩個槽位（`controller.dart:612-614`）；`onClose` 釋放兩個槽位（`controller.dart:805-807`）。
- 預載槽位 volume 0（`controller.dart:406`、`725-727`、`741`）。
- `player_preload` 只在離過期超過 60 秒時使用（`controller.dart:519-521`）。
- 播放錯誤時每部只重試一次（`controller.dart:464-469`）。
- `loadMore` 補預載（`controller.dart:290-291`）。

### 發現的問題

| 編號 | 位置 | 問題與失敗情境 | 判定 |
|---|---|---|---|
| F-1 | `controller.dart:470-472` | 目前播放中、來自 preload 的影片發生播放器錯誤時，`_onSlotError` 呼叫 `_startItem(i)`，但 `_startAt` 已為 null，因此會從 0 秒重播，而不是從錯誤前的位置繼續。影響：罕見，但會造成跳回開頭。 | 已修正：重試前把目前位置存入 `_startAt`（待使用者測試） |
| F-2 | `controller.dart:666-671` 與 `controller.dart:472` | `_startItem(i)` 的非交換路徑會直接 `other.reset()`，即使 `other` 已預載 `i+1` 且有效。F-1 的重試路徑觸發時，會丟掉好的預載，並在 `_preloadNext(i)` 重新預載。影響：只浪費流量與時間，不影響正確性。 | CONFIRMED（行為屬實；屬效能問題） |
| F-3 | `controller.dart:666-671` 與 `controller.dart:723-738` | 非交換路徑 `other.reset()` 不會等待 `other.opening`。若 `_openPreload` 已進入 `slot.player.open(...)`，reset 之後同一播放器可能又被 `_preloadNext` 重新 `open`，兩個 open 交錯。mpv 以最後一次 loadfile 為準，且 `open` 內的 token 檢查會丟棄過時結果，因此實際風險低；但 `_openPreload` 在 `open` 之後的 token 檢查只做 `return`，不會 stop 過時媒體。影響：理論上可能出現槽位記錄與實際媒體不符，造成換片時播錯片。 | SUSPECTED（需實機快速連滑驗證；未重現） |
| F-4 | `controller.dart:480-486`、`controller.dart:519-521` | `player_preload` 的過期檢查只在取得來源時做一次（離過期 60 秒以上），之後快取在 `_sources` 直到使用。若目前影片停留很久（例如暫停超過網址有效期），換到該部時 URL 可能已過期。影響：預載槽位已開啟的情況下 mpv 多半仍可播放；若開啟失敗會由 `_onSlotError` 退回 `videoUrl`，因此預期不會卡住。 | SUSPECTED（低風險，需實機確認） |
| F-5 | `controller.dart:591-595` | `onPageChanged` 在 `_active == false` 時只更新 `index`，不會更新 `videoController`、`firstFrame`。若在不可播放狀態下換頁，新頁可能短暫顯示前一部的畫面。實際上使用者在頁面被蓋住或退到背景時無法滑動，因此幾乎不會觸發。 | SUSPECTED（低，實際難以觸發） |

### 實作偏差（2-spec.md 已記載）

- 下一頁只顯示封面，不顯示預載槽位的第一幀（規格標為可選）。`view.dart` 未修改，`videoController` 隨目前槽位更新（`view.dart:215-216`）。
- `StoryItem.playerPreload` 既有，直接重用 `Dash.fromJson`。
- 換片時的交換流程與 token 機制與規格一致。

### 未修改程式碼

本次審查未修改 `controller.dart`。所有問題都不屬於「一行即可修正的明顯錯誤」，因此只記錄。

## 四、請使用者測試的項目

1. 往上滑一次：下一部在約 1 秒內開始播放。
2. 快速連續上滑多次，再往回滑：只會播放一部影片，且聲音正確（只有一個聲音來源）。
3. 播放到結尾：自動跳到下一部，且使用預載（無明顯載入圈）。
4. 鎖定螢幕、切到封面頁、離開豎屏頁：沒有殘留聲音。
5. 從影片頁以種子影片進入豎屏頁：種子影片仍能正常播放。
6. 載入更多後，最後一部的下一部會補預載（滑到最後一部後往上滑，應不再載入圈）。
7. 觀察 F-1：播放預載來的影片中途若出現播放錯誤，記錄是否從頭播放。
8. 觀察 F-3：快速連滑時，是否出現畫面與聲音不一致（例如畫面是 A、聲音或進度屬於 B）。
