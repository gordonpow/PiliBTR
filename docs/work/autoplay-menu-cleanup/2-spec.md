# 規格：快取與下載捷徑、影片頁推薦排數、自動連播倒數、選單精簡、載入相關預設值、下載進度條

對應需求：[1-requirements.md](1-requirements.md)

## 設計

1. **AC-1**：`lib/pages/video/introduction/ugc/view.dart:534-545` 與 `pgc/view.dart:454-465` 的「快取」「下載」ActionItem 加上 `onLongPress`，開啟 `Get.toNamed('/download', arguments: {'tab': 0 或 1})`。
   - `DownloadPage`（`lib/pages/download/download/view.dart`）讀取 `Get.arguments?['tab']`，設定 `TabController.initialIndex`。
   - 先確認 ActionItem 原本有沒有長按行為（例如「快取」長按是否已有功能），有的話改為新行為並記錄。
2. **AC-2**：
   - 新增 `SettingBoxKey.videoPageRelatedColumns`（int，0 為自動），`Pref` getter clamp 在 0～4。
   - 設定項放在 `style_settings.dart`，接在「影片卡片排數」之後，標題「影片頁推薦排數（橫向）」。`setting_tree.dart` 不需要改：外觀的預設節點會收進它。之後跑 `python lib/scripts/check_setting_tree.py`。
   - `RelatedVideoPanel` 新增參數 `bool sidePane = false`。`lib/pages/video/view.dart` 橫向分欄版面（`childWhenDisabledLandscape` 系列）建立 RelatedVideoPanel 時傳入 true。
   - sidePane 為 true 時，grid delegate 改用：
     - 固定排數（設定值大於 0）：`fixedCrossAxisCount` 等於設定值。
     - 自動：`maxCrossAxisExtent = Pref.recommendCardWidth`，不使用 `VideoCardStyle.fixedColumns`。
     - 其餘參數同 `VideoCardStyle.gridDelegate`。
     - 在 `VideoCardStyle` 加 `gridDelegate(context, {int? fixedColumns})` 這類參數化版本，避免複製程式碼。
3. **AC-3**：
   - 預設值：`Pref.playRepeat` 的 defaultValue 改為 `PlayRepeat.autoPlayRelated`。
   - 先讀 `lib/pages/video/view.dart` 約 270-300 行，了解播完時 `PlayRepeat` 的處理與 `introController.nextPlay()`。另外找出 autoPlayRelated 選下一部的邏輯（`nextPlay` 或相關函式），倒數只是在既有的「播下一部」動作之前延遲 5 秒。
   - 新增 `lib/pages/video/widgets/up_next_overlay.dart`：
     - 卡片放在播放器右下角（全螢幕與一般模式都要），顯示「接下來播放」、下一部的封面與標題、圓形倒數（5 秒），以及「取消」「立即播放」按鈕。
     - 下一部影片的資訊從 RelatedController 的第一筆取得（或從既有的 nextPlay 選取邏輯取得）。分 P、合集等有「下一集」的情況沿用原本邏輯，只加倒數。取不到下一部時不顯示卡片，行為不變。
   - 倒數狀態放在 `VideoDetailController`：`RxnInt upNextSeconds`（null 表示沒有倒數）和 `Timer`。
     - 播完時開始倒數。
     - 歸零時執行原本的播下一部。
     - 「取消」：清除倒數。
     - 「立即播放」：直接播下一部。
     - 使用者重新播放或拖動進度條：清除倒數。
     - 頁面 dispose：取消 Timer。
   - 捲動取消：在相關影片清單外層包 `NotificationListener<ScrollNotification>`，收到使用者拖動造成的 `ScrollUpdateNotification`（`dragDetails != null`）時呼叫 `videoDetailController.cancelUpNext()`。範圍包括：簡介頁直向的相關影片（同一個 CustomScrollView）、橫向右欄、全螢幕推薦面板。
   - 小視窗或子母畫面中播完：直接播下一部，不顯示卡片；子母畫面中看不到卡片，不能讓使用者等不到。
4. **AC-4**：`lib/pages/video/widgets/header_control.dart` 的「⋮」選單移除下列項目，並刪除因此不再使用的 import 與私有方法（analyze 不能有 unused 警告）：
   - 「過載影片」（約 468 行）
   - 「播放器音量」（約 500 行）
   - 「選擇畫質」（約 627 行；只刪選單項，不刪播放器底部的畫質按鈕，954 行那個是畫質對話框本身，要確認仍有入口）
   - 「彈幕列表」（約 685 行）
   - 「彈幕設定」（約 694 行）
5. **AC-5、AC-6**：
   - `storage_pref.dart`：`preInitPlayer` 與 `enableHttp2` 的 defaultValue 改為 true。
   - `play_settings.dart`、`extra_settings.dart` 中對應的 `SwitchModel.defaultVal` 改為 true。
   - 確認 `enableHttp2` 在 `lib/http/init.dart` 的讀取方式（是否在啟動時讀取、是否有其他預設值）。
6. **AC-7**：
   - 新增共用元件 `lib/common/widgets/thin_progress_bar.dart`：`ThinProgressBar(value)`，用 `ClipRRect` 加 `LinearProgressIndicator(minHeight: 3, value:)`，關閉 M3 的結尾圓點（`stopIndicatorRadius: 0`、`stopIndicatorColor: Colors.transparent`，或依 Flutter 版本的對應參數）。背景色為 `colorScheme.primary.withValues(alpha: 0.15)`。
   - 套用位置：
     - `video_export.dart` 的 `ExportTaskTile`。
     - `lib/pages/download/detail/widgets/item.dart` 的 `progressWidget`。

### 審查後修訂（優先於上方設計）

- **R-1**：`didPushNext`（開新頁）、`onChangeEpisode`（手動切集），以及開啟全螢幕推薦面板時，都要呼叫 `cancelUpNext()`。
- **R-2**：`NotificationListener<ScrollNotification>` 包在外層的 `CustomScrollView`，不要包在 sliver 上。位置：`video/view.dart` 約 1021、1734 行，以及 `fullscreen_recommend_panel.dart` 約 102 行。直向時，捲動簡介也會取消倒數（因為簡介和相關影片在同一個 scroll view）。
- **R-3**：在 ugc 與 pgc 的 IntroController 加 `peekNext()`，回傳下一部的標題與封面，不能有副作用；邏輯與 `nextPlay` 相同（分 P、播放清單、合集、相關影片，PGC 則是下一集）。卡片顯示 `peekNext()` 的結果，倒數結束時呼叫原本的 `nextPlay()`。
- **R-4**：
  - `video/view.dart` 約 281-284 行，把 `autoPlayRelated` 拆成獨立的分支：開始倒數，並把 `exitFlag` 設為 false。
  - 按「取消」時，如果開啟了 `autoExitFullscreen`，就退出全螢幕。
- **R-5**：
  - 小視窗：維持現狀，播完就停止。
  - 子母畫面（`isPipMode`）：播完直接 `nextPlay()`，不倒數。
- **R-6**：取消倒數的時機：
  - `positionListener` 中，`duration - position > 1s` 時（使用者重播或拖動進度條）。
  - `playerListener` 收到播放狀態時。
  - `setPlayRepeat` 改變播放順序時。
- **R-7**：相關影片還沒載入完成時，`playRelated` 走非同步路徑，維持現狀（不倒數），記錄為已知限制。
- **R-8（AC-2）**：
  - delegate 依 `widget.sidePane` 在 build 中取得（不要用 `late final`），因為直向和橫向共用同一個 GlobalKey。
  - `fixedCrossAxisCount` 傳 getter（`ValueGetter<int>`）。
  - 直式影片的分欄（`childSplit`、`enableVerticalExpand`）也傳 `sidePane: true`。
- **R-9**：卡片放在播放器右下角；開啟全螢幕推薦面板時取消倒數（R-1）。

## 任務

| ID | 任務 | 執行 | 檔案 |
|---|---|---|---|
| T-1 | AC-1、AC-4、AC-5、AC-6、AC-7 | Sonnet | ugc/pgc intro view、download/view.dart、header_control.dart、storage_pref、play/extra_settings、thin_progress_bar、video_export.dart（只改 ExportTaskTile 的進度條）、download item.dart |
| T-2 | AC-2 | Sonnet | storage_key/pref、style_settings、video_card_style、related/view.dart、video/view.dart（只改橫向 RelatedVideoPanel 的建立） |
| T-3 | AC-3 | Sonnet | play_repeat 預設、video/controller.dart、video/view.dart（播完處理）、up_next_overlay.dart、related 清單的 NotificationListener、fullscreen_recommend_panel.dart |
| T-4 | 建置與模擬器驗證 | Sonnet | — |

T-2 和 T-3 都會改 `video/view.dart` 與 `related/view.dart`，所以 T-3 在 T-2 完成後才開始；T-1 可以和 T-2 平行。`storage_key.dart`、`storage_pref.dart` 同時被 T-1、T-2 修改，兩者改的位置不同，提示中要求各自只加自己的行。

## 邊界情況

- 自動連播倒數時切到背景：Timer 照常倒數，歸零後播下一部（和 YouTube 相同）。
- 相關影片尚未載入完成：沒有下一部，就不顯示卡片。
- 「單個迴圈」「列表迴圈」等其他播放順序不受影響。

## 審查紀錄

| 來源 | 意見 | 處理 |
|---|---|---|
| 審查子代理 | 1～9（開新頁不會取消倒數、捲動通知位置錯誤、下一部的來源不一致、分支共用、小視窗與子母畫面、重播偵測、非同步路徑、GlobalKey 與 late delegate、推薦面板擋住卡片） | 全部採用，見 R-1～R-9 |

## 實作偏差

- **AC-4：** 移除選單項目後，「彈幕列表」（`showDanmakuPool`）在 App 內已經沒有任何入口。方法保留。2026-11-07 使用者決定補入口：播放器「彈幕設定」面板（`showSetDanmaku`，`header_mixin.dart`）最上方新增「彈幕列表」項目，點擊後關閉設定面板並呼叫 `showDanmakuPool()`（直播不顯示）。畫質與彈幕設定仍可從播放器的按鈕開啟。
- **AC-2：** `RelatedVideoPanel` 不再使用 `VideoGridMixin`，delegate 改在 build 中計算。`videoIntro()` 新增 `sidePane` 參數；「近正方形」版面（約 1115 行）維持原樣。
