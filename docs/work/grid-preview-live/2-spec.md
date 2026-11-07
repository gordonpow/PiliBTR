# 規格：卡片排數同步、全部影片卡片可預覽、直播預覽與小視窗

對應需求：[1-requirements.md](1-requirements.md)

## 現況（探索結果，路徑相對於 lib/）

- 推薦的格線用 `VideoCardStyle.gridDelegate(context)`（`common/widgets/video_card/video_card_style.dart`），`fixedCrossAxisCount: fixedColumns` 依視窗長寬選擇 `Pref.videoCardColumnsPortrait/Landscape`。
- 直播格線：`pages/live/view.dart:185-191`，`SliverGridDelegateWithExtentAndRatio(maxCrossAxisExtent: Grid.smallCardWidth)`，沒有固定排數。相同寫法也在 `live_follow/view.dart:56`、`live_area_detail/child/view.dart:75`、`search_panel/live/view.dart:48`。
- 番劇與影視：`pages/pgc/view.dart:303-309`，海報比例 0.75，寬度 `smallCardWidth*0.6`。
- 預覽目前只在 `VideoCardV`（`common/widgets/video_card/video_card_v.dart`）：
  - `canPreview`：:94。
  - 長按 `VideoPreview.start`，第二次長按開選單：:99-104。
  - `onTapDown` 預取：:124。
  - 疊加 `InlineVideoPreview`：:162-183。
  - 外層包 `SwipePreviewTarget`：:209。
  - 滑動預覽需要祖先有 `SwipePreviewDetector`（`swipe_preview.dart:57`，目前只有 `rcmd/view.dart:38`）。
  - 點選時用 `VideoPreview.progressOf(bvid)` 接續播放：`video_card_v.dart:37-69,105-114`。
- `VideoPreview` 只支援 UGC：`video_preview.dart:176-208`，用 bvid 取 cid 與 DASH。
- 直播間離開時直接 dispose 播放器（`live_room/view.dart:204-220`）。小視窗：
  - 排除直播的地方：`_canSwipeToMini`（`pl_player/view/view.dart:1188`）。
  - `MiniPlayer.expand()` 寫死 `/videoV`（`mini_player.dart:280-287`）。
  - 只有影片頁 dispose 時會呼叫 `MiniPlayer.show`（`pages/video/view.dart:443-468`）。

## 設計

1. **排數同步（AC-1）**：
   - `VideoCardStyle` 新增 `static int? fixedColumnsOrNull()`，自動時回傳 null。
   - 直播的 4 個格線改用 `VideoCardStyle.gridDelegate(context)`。直播卡片也是 16:10 封面加文字，和推薦一致。
   - 番劇與影視：保留海報比例與自動寬度，`fixedCrossAxisCount` 傳 `VideoCardStyle.fixedColumns`（ValueGetter，旋轉後重新取值）。
   - 不能使用 `late final` 的 delegate，避免旋轉後沿用舊值；排數一律透過 getter 取得。
2. **全卡片預覽（AC-2、AC-3）**：
   - 把 `VideoCardV` 的預覽邏輯抽成共用元件 `PreviewCard`（新檔 `common/widgets/video_card/preview_card.dart`），參數包括：`bvid`、`cid?`、`canPreview`、`child`、`onOpen(progress)`、`onSecondLongPress`（原本的長按行為）。
   - `PreviewCard` 處理長按開始預覽、`onTapDown` 預取、疊加 `InlineVideoPreview`、`SwipePreviewTarget`，以及點選時把預覽位置傳給 `onOpen`。
   - `VideoCardV` 改用 `PreviewCard`，行為不變。
   - 套用到：
     - `VideoCardH`（直式與橫式兩種版面）
     - `FavVideoCardH`
     - `SubVideoCardH`
     - 觀看紀錄與稍後再看的卡片
     - `MusicVideoCardH`（可選，若結構允許）
   - 只對有 bvid 的一般影片（av）啟用；番劇、課程、直播、專欄維持原樣。
   - `SwipePreviewDetector` 加在下列頁面的捲動清單外層：熱門、排行、搜尋結果、收藏夾、稍後再看、觀看紀錄、UP 主影片、影片頁相關影片（直向、橫向、全螢幕面板）。
3. **直播預覽（AC-4）**：
   - `VideoPreview` 新增直播來源：`startLive(roomId)`，用直播播放網址 API（找 `lib/http/live.dart` 中直播間使用的 playurl 方法，取最低畫質）。
   - 開啟 HLS 或 FLV 串流，靜音，沒有進度條。
   - 共用同一個預覽播放器，所以同一時間只會有一個預覽。
   - 在 `LiveCardVApp`、`LiveCardVFollow` 與直播分區、搜尋直播的卡片包上預覽：長按開始預覽，第二次長按維持原本行為（存圖），點選進入直播間。
4. **直播小視窗（AC-5）**：
   - `MiniPlayer.show` 新增參數 `isLive` 與 `roomId`。`expand()` 依類型開啟 `/videoV` 或 `PageUtils.toLiveRoom(roomId)`（直播重新連線，不需要沿用進度）。
   - 直播間的返回與 dispose 比照影片頁的 `_onPopInvokedWithResult` 與 `dispose`：條件成立（設定開啟、沒有其他播放頁、播放器存在）時，呼叫 `MiniPlayer.show`，而不是 dispose 播放器。
   - 直播間的 `dispose` 不能釋放小視窗正在用的播放器，處理方式同影片頁的 `makeHeartBeat` 與 `sharedByOtherPage`。
   - 重新進入直播間時，`PlPlayerController.getInstance(isLive: true)` 會呼叫 `MiniPlayer.handOver()`，關閉小視窗並把播放器交給頁面。需確認直播頁的初始化流程會重新開啟串流。
   - 斜下滑：`_canSwipeToMini` 允許直播（非全螢幕時）。`popPlayerPages` 已經把 `/liveRoom` 當成播放頁。
   - 小視窗的控制列：直播沒有快退與快進，隱藏這兩個按鈕。
   - 子母畫面：沿用 `MiniPlayer.active` 的處理。

### 審查後修訂（優先於上方設計）

- **R-1**：`SwipePreviewTarget` 改為登記到最近的 `SwipePreviewDetector`（InheritedWidget 或 `findAncestorStateOfType`），不再全域登記。命中前檢查 `ModalRoute.of(context)?.isCurrent` 與 `TickerMode` 是否啟用，避免命中被蓋住的下層頁面。
- **R-2**：不做通用的 `PreviewCard(child)`。改為：
  - 預覽參數加在 `VerticalVideoCardFrame`：由它處理 onTapDown 預取、長按、封面疊加與 Target。
  - `VideoCardH` 橫式版面在 `_buildCover` 疊加。
  - `VideoCardV` 盡量改為共用同一套 helper（mixin 或函式），行為不變。
- **R-3**：預覽進度要傳到開啟動作：
  - `pushVideoH` 與 `onViewFav` 加上預覽參數（cid 與 progress）。
  - `VideoCardH.onTap` 的自訂回呼改為可以拿到預覽資訊，例如 `ValueChanged<PreviewProgress?>`，或提供 `VideoPreview.takeProgress(bvid)`。需更新 `related/view.dart:91`、`popular_series/view.dart:78`、`popular_precious/view.dart:62` 的呼叫端。
- **R-4**：觀看紀錄、稍後再看、收藏夾（擁有者）的長按：第一次預覽，第二次進入多選。多選中或 `isSort` 時停用長按預覽與滑動預覽；進入多選時呼叫 `VideoPreview.stop()`。`fav_sort` 不加預覽。
- **R-5**：`canPreview` 的條件：
  - VideoCardH 排除 isPugv、isLive、redirectUrl 為番劇的項目。
  - Fav 排除 type 12、24，以及 attr 1、9（已失效）。
  - 觀看紀錄只限 archive。開啟時，預覽進度優先於觀看紀錄的進度。
- **R-6**：AC-2 範圍加入 `VideoCardHMemberVideo`（`member_video/view.dart:229`、`video/member/view.dart:244`）。設計 3 的範圍加入 `LiveCardVSearch`（`live_search/child/view.dart:105`）。
- **R-7（直播預覽）**：
  - 新增 `LiveInlinePreview`，只共用 `VideoPreview` 的 `_acquire` 與 `_release`（同一個預覽播放器）。
  - 播放網址：`LiveHttp.liveRoomInfo`（`live.dart:80`）加上 `VideoUtils.getLiveCdnUrl`，流程比照 `live_room/controller.dart:246-338`。
  - **不要呼叫 `BtrProxy.wrap`**：BTR 會用分段請求代理無限長的直播串流，結果會播不出來。
  - `liveStatus != 1` 時顯示「直播已結束」。
- **R-8（直播小視窗）**：
  - 直播間的 PopScope 包一層，先記下 wasPlaying 與 toMini，再呼叫 `onPopInvokedWithResult`（原本會 pause）。
  - 走小視窗時略過 `onVideoDetailDispose`。
  - 播放器的 `danmakuController` 設為 null。
  - 不使用 `makeHeartBeat`，它對直播無效。
  - 直播間的 arguments 是 int：`MiniPlayer.show` 改為接受 `Object args` 加上 `isLive`，或傳入 `{'roomId': id}`。
- **R-9**：`_canSwipeToMini` 加上 `!(isLive && isFullScreen)`。直式直播（`_buildPP`）要確認斜滑和亮度、音量手勢不衝突，需要時只在影片區域啟用。
- **R-10**：影片頁的相關影片（直向、橫向、全螢幕面板）只支援長按預覽，不加 SwipePreviewDetector。長按預覽開始時暫停主播放器，預覽停止後若原本在播就恢復。

## 任務

| ID | 任務 | 執行 | 相依 |
|---|---|---|---|
| T-1 | 排數同步（設計 1） | Sonnet | — |
| T-2 | PreviewCard 與全卡片預覽（設計 2） | Sonnet | — |
| T-3 | 直播預覽（設計 3） | Sonnet | T-2（同一個 video_preview.dart） |
| T-4 | 直播小視窗（設計 4） | Sonnet | — |
| T-5 | 程式碼驗證：analyze、建置、diff 審查 | Sonnet | 全部 |

T-1、T-2、T-4 修改的檔案沒有重疊，可以平行；T-3 在 T-2 之後做。功能測試由使用者進行。

## 邊界情況

- 預覽中進入影片頁、App 退到背景：沿用既有的停止邏輯。
- 直播已下播：預覽顯示「直播已結束」。小視窗：播放器錯誤時顯示錯誤並可關閉。
- 直播小視窗放大時，若直播間已經關閉（下播），直播間頁面會顯示既有的狀態。

## 審查紀錄

| 來源 | 意見 | 處理 |
|---|---|---|
| 審查子代理 | 1～10 | 全部採用，見 R-1～R-10。取捨：R-4（第一次長按預覽、第二次進入多選）、R-10（相關影片只長按預覽，並暫停主播放器） |

## 實作偏差

- **T-1**：直播、番劇、影視的格線保留各自的 extent 與比例，只加上 `fixedCrossAxisCount: VideoCardStyle.fixedColumns`，沒有改用 `VideoCardStyle.gridDelegate`（設計 1 原本寫直播改用它）。
- **T-2**：
  - 用 `CardPreview` helper（`card_preview.dart`）取代 `PreviewCard` widget。
  - 自訂 `VideoCardH.onTap` 的呼叫端自行呼叫 `VideoPreview.takeProgress`。
  - 數個動到的檔案跑過 `dart format`，含無關的重排。
  - `fav_search` 沒有 SwipePreviewDetector。
  - `search/all/widgets/user.dart` 的 `pushVideoH` 沒有預覽。
  - `popular_series`、`popular_precious` 沒有 SwipePreviewDetector。
- **T-3**：
  - 沒有 `VideoPreview.startLive`；直播卡片直接用 `VideoPreview.start(item)` 當 key，由 `LiveInlinePreview` 載入串流。
  - 直播的滑動預取為空操作。
  - 直播首幀偵測依 `position > 0`（尚未實測）。
- **T-4**：
  - `MiniPlayer.show` 改為接受 `Object args` 加 `isLive`。
  - `handOver` 只在非直播時設定 `reuseNextSource`。
  - 風險：`poppingPlayerPages` 期間直播間 `didPopNext` 的提早 return 維持不變。
