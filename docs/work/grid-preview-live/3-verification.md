# 驗證：卡片排數同步、全部影片卡片可預覽、直播預覽與小視窗

對應規格：[2-spec.md](2-spec.md)　日期：2026-11-07

本次為「程式碼驗證」：未啟動模擬器，功能由使用者實機測試。

## 自動檢查

| 檢查 | 指令 | 結果 |
|---|---|---|
| 靜態分析 | `flutter analyze --no-pub lib` | 通過：38 個既有 info，0 error、0 warning |
| 測試 | — | 未執行（專案沒有涵蓋此功能的自動化測試） |
| 建置 | `flutter build apk --debug --target-platform android-x64` | 通過（`build\app\outputs\flutter-apk\app-debug.apk`） |
| diff 備份 | `git diff HEAD > docs/work/grid-preview-live/diff.patch` | 已產生（約 3120 行；新檔 `card_preview.dart`、`live_preview.dart` 為未追蹤，不在 patch 內） |

## 驗收條件

| AC | 結果 | 證據（程式碼涵蓋範圍） |
|---|---|---|
| AC-1 排數同步 | 待使用者測試 | 直播（`live/view.dart`、`live_follow`、`live_area_detail/child`、`search_panel/live`）與番劇／影視（`pgc/view.dart`）的 grid delegate 皆加 `fixedCrossAxisCount: VideoCardStyle.fixedColumns`（ValueGetter，旋轉後重新取值）。自動時回傳 null，維持原寬度算法。 |
| AC-2 全卡片預覽 | 待使用者測試 | `CardPreview` 已套用在 `VideoCardV`、`VideoCardH`（橫、直）、`FavVideoCardH`、`SubVideoCardH`、`MusicVideoCardH`、`VideoCardHLater`、`HistoryItem`、`VideoCardHMemberVideo`。第一次長按預覽、第二次長按原行為；點選用 `take()` 或 `VideoPreview.takeProgress` 把 cid 與進度帶入影片頁（`pushVideoH`、`onViewFav`、`onPushHistory`、`onPushLater`、`PageUtils.toVideoPage`）。相關影片（直向、橫向、全螢幕面板）依 R-10 暫停主播放器、預覽結束後恢復。 |
| AC-3 滑動時預覽 | 待使用者測試 | `SwipePreviewDetector` 加在：熱門、排行分區、搜尋結果、收藏夾、稍後再看、觀看紀錄、UP 主影片（`member_video`、`member_video_web`）、直播各清單。Target 改登記到最近的 Detector（R-1），並檢查 `ModalRoute.isCurrent` 與 `TickerMode`。未加：`fav_search`、`later_search`、`history_search`、`popular_series`、`popular_precious`、`subscription_detail`、`music`（這些只有長按預覽）。 |
| AC-4 直播預覽 | 待使用者測試 | `LiveCardPreview` + `LiveInlinePreview`：用 `LiveHttp.liveRoomInfo` 取網址、優先 avc、不經 `BtrProxy`、靜音可切換；`liveStatus != 1` 顯示「直播已結束」；與影片預覽共用同一個播放器。已套用在 `LiveCardVApp`、`LiveCardVFollow`、`LiveCardVSearch`、`LiveItem`（搜尋直播）。點選時 `stop()` 後進直播間。首幀偵測依 `position > 0`，尚未實測。 |
| AC-5 直播小視窗 | 待使用者測試 | 直播間 `PopScope` 改用 `_onPopInvokedWithResult`（先記下 wasPlaying 與 toMini）；dispose 走 `MiniPlayer.show(isLive: true)`，略過 `onVideoDetailDispose`、清掉 `danmakuController`、不呼叫 `makeHeartBeat`。`expand()` 依類型走 `PageUtils.toLiveRoom(roomId)`；`handOver` 對直播不設 `reuseNextSource`；小視窗隱藏快退／快進；`_canSwipeToMini` 改為排除「直播且全螢幕」。 |

## 實作審查

審查範圍：全部 39 個修改檔與 2 個新檔，對照 spec 與 R-1～R-10。沒有找到可確認會崩潰或洩漏的錯誤。

| 發現 | 查證結果 | 處理 |
|---|---|---|
| `live_preview.dart` 首幀偵測只看 `position > Duration.zero`。若某些 FLV 串流 position 長時間為 0，封面會一直顯示轉圈、看不到畫面。 | 待查（SUSPECTED，需實機） | 不處理。實測若不出畫，改為再監聽 `player.stream.width` 或 `videoParams`。 |
| 直播小視窗：`poppingPlayerPages` 期間直播間 `didPopNext` 提早 return（沿用原行為）。從「影片頁 → 直播間」堆疊斜滑時，下方的頁面不會重新載入。 | 待查（SUSPECTED，堆疊很少見） | 不處理，只列為風險。 |
| 直播間 dispose 先呼叫 `PlPlayerController.setPlayCallBack(null)` 再轉小視窗。影片頁不會清這個 callback，直播小視窗期間媒體通知的播放回呼可能被清掉。 | 待查（SUSPECTED，影響小） | 不處理，請在實機看通知列控制。 |
| `search/all/widgets/user.dart` 的 `pushVideoH` 沒有預覽參數。 | 成立（已列入實作偏差） | 不處理：該卡片為搜尋「全部」中的 UP 主影片入口，不屬於 AC-2 清單。 |
| 搜尋頁（`fav_search`、`later_search`、`history_search`）、`popular_series`、`popular_precious`、`subscription_detail`、`music` 沒有 `SwipePreviewDetector`，只能長按預覽。 | 成立（AC-3 範圍為「上述有捲動清單的頁面」，這些在需求清單外或為次要頁面） | 不處理，已列入已知限制。 |
| 自訂 `VideoCardH.onTap` 的呼叫端必須自己呼叫 `takeProgress`，否則預覽不會停止。 | 成立：現有 3 個呼叫端（`related`、`popular_series`、`popular_precious`）都已處理，沒有遺漏 | 不處理。 |
| `dart format` 造成無關重排；多處 `SwipePreviewDetector(child: CustomScrollView(` 寫成同一行、import 順序未整理；`mini_player.dart` 的 `if (!MiniPlayer._isLive)` 縮排未對齊。 | 成立，僅風格，analyze 不報 | 不處理（避免擴大 diff）；commit 前可再統一格式。 |
| 預覽管線（`CardPreview.take/longPress`、`VideoPreview` 共用播放器的 `_acquire`/`_release` 擁有權、直播卡片 dispose 釋放）。 | 不成立：已逐項追蹤，擁有者檢查與 `stop(item)` 可防止互相覆蓋；`LiveInlinePreview.dispose` 取消訂閱並釋放；`VideoPreview` 影片預覽開始時固定 `setVolume(0)`，直播取消靜音不會殘留。 | 無 |
| 小視窗生命週期：直播間→小視窗→放大／再進其他播放頁／關閉。 | 不成立：`handOver` 暫停、`getInstance` 重設 `isLive`，`close()` → `updatePlayCount` 釋放；直播間 `_toMini` 有 `isCloseAll` 保護。 | 無 |

## 修正

沒有程式碼修正：沒有找到「可確認」且範圍明確的小錯誤。因此未重跑 analyze（結果同上）。

## 已知限制

- 直播的滑動預取為空操作；直播清單的滑動預覽是直接開始載入串流。
- 直播預覽首幀偵測尚未實測。
- 上列搜尋頁與少數清單頁沒有滑動預覽，只有長按預覽。
- 直播小視窗放大時一律重新連線，不沿用緩衝。
- 部分檔案有無關的格式重排。

## 需要使用者做的事

實機測試：

1. 設定「影片卡片排數」為固定 N（直向、橫向各一）與「自動」，檢查首頁直播、番劇、影視、直播分區、關注直播、搜尋直播的排數；旋轉螢幕後立即換排。
2. 各類清單（熱門、排行、搜尋、收藏夾、稍後再看、觀看紀錄、UP 主影片、合集、音樂）：長按預覽、第二次長按原選單（擁有者的收藏夾／歷史／稍後再看為多選）、預覽中點卡片從預覽位置接著播、多選模式不預覽。
3. 影片頁相關影片（直向、橫向、全螢幕面板）：預覽時主播放器暫停，結束後恢復；預覽中點開另一支影片時舊頁保持暫停。
4. 滑動時預覽：開關開啟時手指停在卡片約 0.25 秒開始預覽；關閉時無；切換分頁或蓋上新頁面時不誤觸。
5. 直播預覽：長按出畫面（靜音、可開聲）、已下播顯示「直播已結束」、點選進直播間；若一直轉圈（無首幀）請回報。
6. 直播小視窗：返回與斜下滑縮小、拖曳／吸附／雙指縮放、點視窗回同一直播間、X 關閉；設定關閉時不縮小；全螢幕直播不可斜滑；直式直播的斜滑與亮度／音量手勢是否衝突。
7. 通知列的播放控制在直播小視窗期間是否正常。

## 審查後修正（主導者）

- 審查第 1 點（直播預覽只靠 `position > 0` 判斷第一幀）：改為也監聽 `player.stream.size`，影片寬度大於 0 就視為第一幀已出現（`live_preview.dart`）。analyze 通過；實際效果待使用者測試。
