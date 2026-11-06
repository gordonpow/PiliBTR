# 規格：全螢幕三區手勢、子母畫面、小視窗縮放、背景播放、橫向頁面與旋轉偵測

對應需求：[1-requirements.md](1-requirements.md)

## 設計

### 已查證的現況

- 方向鎖定都經過 `lib/plugin/pl_player/utils/fullscreen.dart` 的 `_setPreferredOrientations`。`fullMode()` 傳 4 個方向，Flutter 對應 `SCREEN_ORIENTATION_FULL_USER`（13）。這個值已在 `flutter_embedding_release` 的 `PlatformChannel.decodeOrientations` 反組譯確認；它**會遵守系統自動旋轉鎖定**。所以 AC-14 不需要原生程式碼，只要開啟橫屏適配。
- `Pref.horizontalScreen`（`storage_pref.dart:647`）和 `Pref.fullScreenMode`（`:213`）第一次讀取時會把預設值**寫入** Hive。所以舊使用者已經存了 `false`／`auto`，只改預設值無效，需要一次性遷移。
- 方向感測：`native_device_orientation`（Android 用加速度計 `OrientationEventListener`）。它只在**方向改變**時通知。監聽器建立在單例 `PlPlayerController._()`（`controller.dart:662`），單例在預覽播放器、小視窗之間共用。手機已經是橫向時開影片頁，不會再收到事件，所以不會進入全螢幕（需求第 6 項的原因）。
- 影片頁版面：`horizontalScreen == false` 時用 `childWhenDisabled`，橫向時只靠全螢幕（`video/view.dart:1304`）。`horizontalScreen == true` 時，橫向顯示左右分欄（平板版面）。
- 全螢幕中間區塊：`view.dart:1006` 用 `maxWidth / 3` 分區。中間上下滑會進入或退出全螢幕。
- 斜滑縮小：`_canSwipeToMini`（`view.dart:1158`）排除全螢幕。
- 小視窗：`mini_player.dart` 有 3 種尺寸（`_widthFactor`、`_maxWidth`），用 `GestureDetector` 處理拖曳。
- 子母畫面：`autoPiP`。只在 `_isCurrVideoPage` 時進入子母畫面（`controller.dart:352, 692, 1102`），小視窗不會進入。

### 決策

1. **手機上的影片頁維持「非橫屏適配」行為**：新增 `PlPlayerController.videoPageHorizontal = horizontalScreen && DeviceUtils.isTablet`。下列地方原本讀 `horizontalScreen`，改讀它：影片頁版面、`VideoDetailController.horizontalScreen`、`_onOrientationChanged`、離開全螢幕時的 `resetScreenRotation`。效果如下：
   - 首頁等頁面隨手機旋轉（`fullMode`）。
   - 進入影片頁時鎖直向。
   - 轉成橫向時進入全螢幕，轉回直向時退出。

   平板的行為不變。
   - 不採用的做法：讓手機也用平板分欄版面。手機橫向分欄太擠，也不符合「橫向就全螢幕」的需求。
2. **進入影片頁時套用目前方向**：控制器記住最後一次感測結果 `_lastOrientationParams`。新增 `syncOrientation()`，在下列時機呼叫，用最後一次結果重跑 `_onOrientationChanged`：
   - 影片頁 `initState` 的 post frame。
   - 從小視窗放大後。
   - 影片頁回到前景（`didPopNext`）。

   如果這時還沒有感測結果，就等第一個事件。這個事件本來就會走到 `_onOrientationChanged`。
3. **一次性遷移**：在 `main.dart` 啟動時檢查 `btrDefaultsV1`。沒有這個 key 時：
   - `horizontalScreen` 設為 `true`。
   - `fullScreenMode` 設為 `none`。
   - 寫入 `btrDefaultsV1=true`。

   新安裝的使用者由 getter 的預設值處理：`horizontalScreen` 預設 `true`，`fullScreenMode` 預設 `none`。

   `continuePlayInBackground` 沒有在讀取時寫入，所以只改預設值為 `true`。
4. **全螢幕手勢**：只在 `isFullScreen && PlatformUtils.isMobile && !isLive` 時套用新規則。
   - 分區：中間寬度 = `maxWidth * Pref.fullscreenCenterRatio`，左右各 `(maxWidth - center) / 2`。
   - 斜下滑（現有的 `_miniMinSlope` 判斷）在任何位置都開始縮小手勢。中間區塊直直往下滑也開始縮小手勢，方向用手指的水平位移決定，沒有位移時縮到右下角。
   - 中間區塊上滑：開啟推薦面板，不再切換全螢幕。
   - 縮小手勢確定後，先 `triggerFullScreen(status: false)`，再走原本的 `MiniPlayer.endSwipe` 和 `popPlayerPages` 流程。縮小手勢的起點（`from`）是全螢幕播放器的 rect。
   - 非全螢幕時，`_canSwipeToMini` 和中間區塊進入全螢幕的行為都不變（AC-6）。
5. **推薦面板**：新增 `lib/pages/video/widgets/fullscreen_recommend_panel.dart`。它是一個從底部滑出的半透明 route（高度為畫面的 60%），沿用 `PublishRoute` 寫法，和 `PageUtils.showVideoBottomSheet` 類似，但改為由底部滑出、寬度填滿。
   - 一般影片：`CustomScrollView` 包 `RelatedVideoPanel(heroTag)`。
   - 番劇：`EpisodePanel`（沿用 `showEpisodes` 的參數）。
   - 點推薦影片前，設定 `PlPlayerController.enterFullScreenOnNextPage = true`。新影片頁的播放器載入完成（`controller.dart` 中 `autoEnterFullScreen` 的位置）時，如果旗標為 `true`，就清除旗標並 `triggerFullScreen(status: true)`。
   - 番劇切換選集是在同一頁換 cid，全螢幕狀態不變，不需要旗標。
6. **子母畫面涵蓋小視窗**：小視窗播放中也啟用自動子母畫面：
   - SDK 31 以上：播放時呼叫 `enterPip(autoEnter: true)`，暫停或關閉時呼叫 `_disableAutoEnterPip`。
   - SDK 30 以下：`_onUserLeaveHint` 判斷 `_isCurrVideoPage || MiniPlayer.isShowing`。

   進入子母畫面時，`_MiniPlayerView` 偵測到 `AndroidHelper.isPipMode`，改成填滿整個視窗、只顯示影片（不顯示控制列）。首頁的其他內容用黑底蓋住。
7. **小視窗縮放**：`GestureDetector` 的 pan 改為 `onScaleStart/Update/End`。單指時沿用拖曳；雙指時以 focal point 為中心縮放 `_rect`。
   - 限制：寬度在 `shortestSide * 0.30` 到 `min(shortestSide * 0.95, 可用寬度)` 之間，高度 = `width * 9/16 + barHeight`。
   - 放開時寫入 `miniPlayerCustomWidth`（寬度的 dp 值），`miniPlayerSize` 設為 3（自訂），然後吸附角落。
   - `sizeLabels` 加上「自訂」；選自訂時用記住的寬度，沒有記錄時用「中」的尺寸。
8. **中間寬度設定與即時預覽**：外觀設定新增「全螢幕中間區塊寬度」，點選後開對話框：
   - 上方是 16:9 的橫向播放器示意圖，分成三塊：左「亮度」、中「推薦／縮小」、右「音量」，並標示百分比。
   - 下方是 Slider（20–60，步進 1）。
   - 用 `StatefulBuilder`，拖動時即時重畫示意圖；按確定才寫入。
9. **「屏」改「螢幕」**：
   - 用腳本 `lib/scripts/screen_wording.py` 依需求 AC-18 的對照表，只替換 Dart **字串字面值**中的字。範圍是 `lib/` 中 `lib/grpc`、`lib/scripts` 以外的檔案。
   - 跳過 `to_traditional.py` 的 PROTECT 清單（伺服器比對字串）。
   - 程式碼註解不在範圍內。
   - 同時把對照表加進 `to_traditional.py` 的後處理步驟，之後重跑轉換時會保留新用詞。

### 審查後修訂（與上方決策衝突時，以本節為準）

- **R-1 方向重設分兩種情況**（取代決策 1 中 `resetScreenRotation` 的部分）：
  - 新增 `exitFullScreenRotation()`：用於離開全螢幕但仍在影片頁時。`videoPageHorizontal` 為 true 時呼叫 `fullMode()`，否則呼叫 `portraitUpMode()`。
  - 新增 `restoreAppRotation()`：用於離開影片頁時，包括 `dispose`、`_toMini` 和縮小手勢。`Pref.horizontalScreen` 為 true 時呼叫 `fullMode()`，否則呼叫 `portraitUpMode()`。
  - `dispose()` 改為呼叫 `restoreAppRotation()`。`MiniPlayer.show` 前也要呼叫 `restoreAppRotation()`。
  - 手機影片頁在 `initState` 的 post frame 先處理 R-2。不需要進入全螢幕時，明確呼叫 `portraitUpMode()`。
- **R-2 進入影片頁時的方向**（取代決策 2）：
  - 新增 `syncOrientation(BuildContext)`，在影片頁 post frame 時呼叫，播放器載入完成後再呼叫一次。
  - 先看 `MediaQuery.orientationOf(context)`。首頁是 `fullMode`，所以這個值已經反映系統自動旋轉鎖定。如果是橫向，就呼叫 `triggerFullScreen(orientation: landscapeLeft/Right, isManualFS: false)`。左右方向取自 `View.of(context).display`，取不到時用 landscapeLeft。
  - 如果是直向，但實例的 `_orientation` 是橫向，而且最後一次 `isAutoRotate == true`（`horizontalScreen` 關閉的舊使用者），就用 `_orientation` 進入全螢幕。
  - 不用跨實例的快取，也不用 `didPopNext`。
  - 實作時先加 debug log 重現原本的 bug，並把原因記在「實作偏差」。
- **R-3 縮小手勢與 PopScope**：全螢幕縮小手勢確定後，流程如下：
  1. `await triggerFullScreen(status: false)`
  2. `restoreAppRotation()`
  3. `await WidgetsBinding.instance.endOfFrame`
  4. 才呼叫 `popPlayerPages`

  `MiniPlayer.endSwipe` 要支援這個非同步前置步驟。
- **R-4 退出全螢幕時一定還原方向**：新增 `_fsChangedOrientation`，在進入全螢幕且實際改過方向時設為 true，包括由感測器帶入方向的情況。退出時，只要 `_fsChangedOrientation` 為 true，就算 `mode == none` 也要呼叫 `exitFullScreenRotation()`。
- **R-5** `_onOrientationChanged` 開頭：不在影片頁時（`!_isCurrVideoPage`，或小視窗顯示中），只記錄 `_orientation`，不做其他處理。
- **R-6 遷移條件**：
  - 只在 `Platform.isAndroid && !DeviceUtils.isTablet` 時執行。
  - `horizontalScreen` 設為 true。
  - `fullScreenMode` 只在存的值是 `auto` 時改成 `none`。
  - 遷移放在 `main.dart` 第一次讀取 `Pref.horizontalScreen`（約第 140 行）之前。

  AC-17 補充：所有手機都會補一次，因為無法分辨「已改過」和「自動寫入的 auto」。存的值不是 auto 的使用者沿用原設定。
- **R-7** `videoPageHorizontal = horizontalScreen && !(Platform.isAndroid && !DeviceUtils.isTablet)`：桌面和 iOS 維持原值。這個值在控制器建立時算一次（`late final`），和 `horizontalScreen` 一樣。
- **R-8 背景暫停**：小視窗也要遵守 `continuePlayInBackground`。`_MiniPlayerView` 加入 `WidgetsBindingObserver`：`paused` 時，如果設定關閉且不在子母畫面，就暫停並記住；`resumed` 時恢復播放。
- **R-9 全螢幕新規則和既有設定的互動**：
  - `MiniPlayer.swipeEnabled` 關閉時，全螢幕不能縮小，中間下滑沒有作用。
  - `enableSlideFS` 關閉時，中間區塊沒有作用。
  - `enableSlideVolumeBrightness` 控制左右區塊，和原本相同。
  - 全螢幕時忽略 `fullScreenGestureReverse`。
- **R-10 推薦面板**：
  - 點選項目時，先 `pop` 面板再導航。
  - 新頁面因為共用單例，`isFullScreen` 可能已經是 true。保留 `enterFullScreenOnNextPage` 旗標，作法如下：
    1. 新頁面載入後，如果旗標為 true 且 `isFullScreen` 為 false，才呼叫 `triggerFullScreen`。
    2. 如果 `isFullScreen` 已經是 true，只確保系統列隱藏、方向正確，然後清除旗標。
  - `_isCurrVideoPage` 改為「最上層的 `GetPageRoute` 是影片頁」，讓 PopupRoute 開著時仍算在影片頁。
- **R-11 自訂尺寸**：所有尺寸都由 `_windowSize(media)` 計算，包括 `_SwipePreview`。`i == 3` 時使用 `miniPlayerCustomWidth`；沒有值時用「中」的尺寸。每次計算都 clamp 到 R-7 的寬度範圍，旋轉後也會重新 clamp。`_widthFactor` 和 `_maxWidth` 不加第 4 個元素。
- **R-12「屏」與繁簡切換**：「屏」改「螢幕」後，確認 `lib/scripts/gen_zh_dict.py` 和 `assets/zh/` 的簡體轉換仍正確，例如「全螢幕」要轉成「全屏幕」或「全屏」；必要時重新產生字典。

### 要改的檔案

| 檔案 | 改什麼 |
|---|---|
| `lib/utils/storage_key.dart` | 新增 `fullscreenCenterRatio`、`miniPlayerCustomWidth`、`btrDefaultsV1` |
| `lib/utils/storage_pref.dart` | `horizontalScreen` 未設定時寫 `true`；`fullScreenMode` 未設定時寫 `none`；`continuePlayInBackground` 預設 `true`；新增 `fullscreenCenterRatio` getter（預設 0.34，clamp 0.2–0.6） |
| `lib/main.dart` | 一次性遷移 `btrDefaultsV1` |
| `lib/plugin/pl_player/controller.dart` | `videoPageHorizontal`、`_lastOrientationParams`、`syncOrientation()`、`enterFullScreenOnNextPage`；`_onOrientationChanged` 與 `resetScreenRotation` 改用 `videoPageHorizontal`；子母畫面條件涵蓋小視窗 |
| `lib/pages/video/controller.dart` | `horizontalScreen` getter 改回傳 `videoPageHorizontal` |
| `lib/pages/video/view.dart` | 呼叫 `syncOrientation()`；版面判斷改用 `videoPageHorizontal`；傳入推薦面板的 callback |
| `lib/plugin/pl_player/view/view.dart` | 全螢幕分區比例、中間上滑開推薦、全螢幕縮小手勢 |
| `lib/plugin/pl_player/mini_player.dart` | 雙指縮放、自訂尺寸、子母畫面填滿、`isShowing` |
| `lib/pages/video/widgets/fullscreen_recommend_panel.dart` | 新檔：推薦面板 route |
| `lib/pages/setting/models/play_settings.dart` | 「背景畫中畫」改名「子母畫面」；`continuePlayInBackground` 的 `defaultVal` 改為 `true`；小視窗大小加「自訂」 |
| `lib/pages/setting/models/style_settings.dart` | 新增「全螢幕中間區塊寬度」與預覽對話框；`horizontalScreen` 開關的 `defaultVal` 改為 `true` |
| `lib/scripts/screen_wording.py`、`lib/scripts/to_traditional.py` | 新用詞腳本與後處理 |
| `lib/**/*.dart`（字串） | 「屏」改「螢幕」 |
| `docs/PROJECT_LOG.md` | 紀錄 |

### 介面與設定

| Key | 型別 | 預設 | 說明 |
|---|---|---|---|
| `fullscreenCenterRatio` | double | 0.34 | 全螢幕中間區塊寬度比例 |
| `miniPlayerCustomWidth` | double? | null | 自訂小視窗寬度（dp） |
| `miniPlayerSize` | int | 1 | 0 小、1 中、2 大、3 自訂 |
| `btrDefaultsV1` | bool | — | 遷移旗標 |
| `horizontalScreen` | bool | true（遷移後） | |
| `fullScreenMode` | int | `none`（遷移後） | |
| `continuePlayInBackground` | bool | true | |
| `autoPiP` | bool | false | 標題改為「子母畫面」 |

## 任務

| ID | 任務 | 相依 | 執行 | 完成條件 |
|---|---|---|---|---|
| T-1 | 設定 key、預設值、遷移、改名（決策 3、AC-7、AC-12、AC-13、AC-17） | — | Opus | analyze 無新錯誤 |
| T-2 | 中間寬度設定與預覽對話框（決策 8） | T-1 | Sonnet | analyze 通過，對話框可拖動 |
| T-3 | 全螢幕分區與手勢（決策 4） | T-1 | Opus | analyze 通過 |
| T-4 | 推薦面板與保持全螢幕旗標（決策 5） | T-3 | Sonnet | analyze 通過 |
| T-5 | 小視窗雙指縮放與自訂尺寸（決策 7） | T-1 | Sonnet | analyze 通過 |
| T-6 | 子母畫面涵蓋小視窗（決策 6） | T-5 | Opus | analyze 通過 |
| T-7 | 旋轉：`videoPageHorizontal`、`syncOrientation`（決策 1、2） | T-1 | Opus | analyze 通過 |
| T-8 | 「屏」改「螢幕」（決策 9） | T-1～T-7 | Sonnet | 介面字串 grep 不到「屏」（PROTECT 除外），analyze 通過 |
| T-9 | 建置 debug APK、更新 PROJECT_LOG | 全部 | Opus | 建置成功 |

T-8 放在最後，避免和其他任務同時修改設定檔而產生衝突。

## 驗證計畫

使用者要求時才做模擬器驗證（`Medium_Phone_API_37.0`）。預設只跑 `flutter analyze` 和建置。

| AC | 驗證方式 |
|---|---|
| AC-1, 3 | 全螢幕時在 1/6、1/2、5/6 寬度處上下滑，確認是亮度、推薦、音量 |
| AC-2 | 開設定對話框，拖動滑桿並截圖 |
| AC-4 | 全螢幕中間上滑，截圖面板；點一部影片，確認新頁仍是全螢幕 |
| AC-5 | 全螢幕中間下滑、左下滑，確認跟手動畫並變成小視窗；短距離放開會彈回 |
| AC-6 | 直向時重跑原有手勢 |
| AC-7, 8 | 開啟子母畫面，在影片頁和小視窗時各按一次 Home，用 `adb shell dumpsys activity` 確認進入 PiP 模式並截圖 |
| AC-9–11 | 模擬器雙指（Ctrl+拖曳）縮放，重開小視窗，確認尺寸被記住，設定顯示「自訂」 |
| AC-12 | 全新安裝後切到背景，確認音訊繼續 |
| AC-13, 14 | 全新安裝，用 `adb shell settings put system accelerometer_rotation 1/0` 加上旋轉模擬器，確認首頁轉向，鎖定時不轉 |
| AC-15, 16 | 先把模擬器轉成橫向再開影片，確認直接全螢幕；連續開 2 部、從小視窗放大後再測 |
| AC-17 | 全新安裝後，直向按全螢幕維持直向 |
| AC-18 | `grep` 字串字面值中的「屏」 |

## 邊界情況與風險

- 遷移會覆蓋舊使用者原本刻意設定的 `horizontalScreen=false`。無法分辨是預設寫入還是使用者設定，比照先前「觀看紀錄列」的做法補一次，回報時說明。
- `horizontalScreen` 也是 `horizontalSeasonPanel`、`horizontalMemberPage`、`dynamicsWaterfallFlow` 的預設值來源。手機開啟後，這些頁面在橫向時會改用分欄或瀑布流。這是預期結果，不另外處理。
- 平板（`DeviceUtils.isTablet`）的影片頁行為完全不變。
- `fullScreenMode=none` 時，直向按全螢幕不會旋轉；手機轉橫時，感測器會以方向參數呼叫 `triggerFullScreen`（有 orientation，不受 none 影響），會進入橫向全螢幕。
- 系統自動旋轉關閉時，`_onOrientationChanged` 在非全螢幕時直接 return（現有邏輯），符合 AC-14。
- 推薦面板在直播頁不開啟（`isLive` 時中間上滑沒有作用）。
- 子母畫面需要 Android 8 以上（`isPipAvailable`），低版本隱藏設定（現有）。
- 縮放手勢與單指拖曳同時存在：`pointerCount >= 2` 時才縮放，避免誤觸。
- 回退：每個任務的改動都獨立，可以用 `git checkout -- <file>` 還原；遷移 key 改名即可重新觸發或停用。

## 審查紀錄

| 來源 | 意見 | 處理 |
|---|---|---|
| 審查子代理 | 1 `resetScreenRotation` 也在 `dispose` 呼叫，改了會讓首頁鎖直向；小視窗路徑沒有重設方向 | 採用：R-1（已查證 controller.dart:1737） |
| 審查子代理 | 2 監聽器會送出第一次讀值；單例在 dispose 時清空，快取無效 | 採用：R-2 改讀 MediaQuery（已查證 SensorOrientationListener.java:43、controller.dart:1792） |
| 審查子代理 | 3 `triggerFullScreen` 是 async，`popPlayerPages` 會被 PopScope 擋下 | 採用：R-3 |
| 審查子代理 | 4 `mode=none` 時退出全螢幕不還原方向 | 採用：R-4 |
| 審查子代理 | 5 小視窗在首頁時，旋轉會觸發全螢幕 | 採用：R-5 |
| 審查子代理 | 6 遷移無條件覆寫 | 採用：R-6（只改手機、只改 auto） |
| 審查子代理 | 7 `isTablet` 依視窗大小判斷，會影響桌面 | 採用：R-7 |
| 審查子代理 | 8 小視窗不受背景暫停設定控制 | 採用：R-8 |
| 審查子代理 | 9 和既有手勢設定的互動未定義 | 採用：R-9 |
| 審查子代理 | 10 推薦面板與共用單例、`_isCurrVideoPage` | 採用：R-10 |
| 審查子代理 | 11 自訂尺寸索引越界 | 採用：R-11 |
| 主導者 | 繁簡切換字典可能受用詞替換影響 | 新增 R-12 |

## 實作偏差

- **R-10 推薦面板：** 點選影片時先關閉面板（`RelatedVideoPanel.beforeOpen`，模擬器測試後補上）。沒有實作 `enterFullScreenOnNextPage` 旗標，因為共用單例的 `isFullScreen` 已經讓新頁維持全螢幕（模擬器已確認）。
- **dispose：** 回到的影片頁已經是全螢幕時，不重設方向（模擬器測試發現的問題）。
- **R-2：** 沒有加 debug log 重現原 bug（使用者未要求驗證）。原因推測為感測器的第一次事件早於影片頁成為目前 route，或在 `_fsProcessing` 期間被略過，改用 `syncOrientation` 在 post frame 主動套用。
- **番劇上滑：** 呼叫既有的 `showEpisodes(type: .pgc)`。橫向時沿用 `showVideoBottomSheet` 從右側滑出，不是從底部滑出。
- **縮小手勢：** 判斷是否在影片頁時，不再直接檢查 `MiniPlayer.active`，改由 `_isCurrVideoPage` 處理；`_isCurrVideoPage` 也允許 PopupRoute 疊在影片頁上（已查證 GetX 的 `didPush` 對非 PageRoute 不更新 `current`）。
- **T-8 額外修正：**
  - `to_traditional.py` 加入 FIXUP `許可權→權限`。
  - `gen_zh_dict.py` 讓簡體模式顯示「全屏、横屏、竖屏、小屏」。
  - 重跑 `to_traditional.py` 時，順便轉換了 4 個前一批（lang-cdn-speed）尚未轉換的檔案：`login/view.dart`、`cdn_settings_dialog.dart`、`video_export.dart`、`cdn_choice.dart`。
- **保留的「屏」：** `rcmd/result.dart` 的 `'竖屏'` 與 `whisper_settings/view.dart` 的 `'消息屏蔽词'` 是伺服器比對字串，保留原文並加註解。
