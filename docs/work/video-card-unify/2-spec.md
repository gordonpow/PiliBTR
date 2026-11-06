# 規格：影片卡片統一與滑動預覽卡頓

對應需求：[1-requirements.md](1-requirements.md)

## 設計

### A. 卡片統一

現況：首頁用 `VideoCardV`（直式），網格為 `SliverGridDelegateWithExtentAndRatio(maxCrossAxisExtent: Pref.recommendCardWidth, childAspectRatio: Style.aspectRatio, mainAxisExtent: textScaler.scale(90), spacing: Style.cardSpace)`，外層左右各留 `Style.safeSpace`（12）。其他頁用 `VideoCardH`（橫式），網格為 `Grid.videoCardHDelegate()`（`maxCrossAxisExtent: smallCardWidth * 2`，固定高 110）。

做法：

1. 新增 `VideoCardStyle`（`lib/common/widgets/video_card/video_card_style.dart`），集中首頁的網格參數：
   - `static SliverGridDelegate gridDelegate(BuildContext context)`：回傳與首頁完全相同的 delegate。
   - `static const EdgeInsets sidePadding = EdgeInsets.symmetric(horizontal: Style.safeSpace)`。
   - `mixin VideoGridMixin<T extends StatefulWidget> on State<T>`：`late final videoGridDelegate = VideoCardStyle.gridDelegate(context);` 與 `videoGridSkeleton`（用 `VideoCardVSkeleton`，10 個）。
   - 首頁 `RcmdPage` 改用 `VideoCardStyle.gridDelegate`，確保 AC-5 兩邊參數來源相同。
2. 不改 `GridMixin`：它也被文章、下載、歷史等非影片列表使用。
3. 新增共用外框 `VerticalVideoCardFrame`（`lib/common/widgets/video_card/vertical_video_card_frame.dart`，已完成）：`Card` + `InkWell`，16:10 封面（上方圓角 12）、標題區、統計列、底列，右下角可放 29×29 的動作按鈕（位置與 `VideoCardV` 的 ⋮ 相同：`right: -5, bottom: -2`）。四張卡片的直式版都用它，避免四份重複版面。`VideoCardV`（首頁）不改，避免影響長按／滑動預覽。
4. 卡片各自加 `vertical` 參數（預設 `false`，維持既有行為），範圍內的頁面明確傳 `vertical: true`：
   - `VideoCardH`：封面沿用目前的 Stack（角標、時長、進度條）；標題最多兩行（支援搜尋關鍵字高亮 `titleList`）；統計列為播放／彈幕數＋日期，直播項目（`isLive`）沒有播放數時統計列仍保留同樣高度；底列為 UP 主名稱；動作為 `VideoPopupMenu`。點擊、長按、右鍵行為不變。
   - `FavVideoCardH`：保留 `selectMask` 蓋滿封面的多選樣式；擁有者的「取消收藏」X 按鈕放在底列右側；番劇（`type == 24`）的兩行簡介在直式版省略；收藏夾排序頁不傳 `vertical`。
   - `SubVideoCardH`、`MusicVideoCardH`：直式版面，功能不變。
5. 範圍內頁面的影片 sliver：改用 `videoGridDelegate`、`vertical: true`，只在影片網格外包 `SliverPadding(padding: VideoCardStyle.sidePadding)`（頁面已有的安全區 left/right padding 要相加，不是取代；`SliverMainAxisGroup` 裡的 header、tags 不包）；骨架改用 `videoGridSkeleton`。
   - 分區排行：同一個網格混有番劇排行 `PgcRankItem`。依資料型別選 delegate：影片排行用直式，番劇排行維持原 `gridDelegate`。
   - 搜尋：`SearchVideoPanelMixin` 的 `on` 由 `GridMixin` 改為 `VideoGridMixin`，「綜合」（`search_panel/all/view.dart`）與「影片」分頁一起改；綜合分頁中非影片項目（使用者、直播等）不變。
   - 收藏夾內容：清單尾端的「載入中／沒有更多了」不再佔網格一格，改成網格後面獨立的 `SliverToBoxAdapter`。
6. 設定：「卡片寬度」對話框（`style_settings.dart`）標題改為「列表最大列寬度」（拿掉錯誤的「預設240dp」），兩個值改名為「影片卡片（首頁與影片列表，預設 300dp）」（`recommendCardWidth`）與「其他列表（直播、番劇、歷史、稍後再看等，預設 240dp）」（`smallCardWidth`）。不新增設定鍵（AC-7）。

### B. 滑動預覽卡頓

推測原因（待驗證階段量測）：

1. 手指一直移動時，只要手指下的卡片 0.25 秒內沒變就開始預覽；直向滑動時手指跟著內容移動，所以滑動中幾乎一定會開始預覽。
2. 每次預覽都 `Player.create` + `VideoController.create`（建立 mpv 與貼圖），換卡片時再 `dispose`，這些原生操作在滑動中造成掉格。
3. 播放位置每次更新都 `setState` 整個預覽 widget。

做法：

1. **只在手指停住時開始**（AC-8、AC-9）：`SwipePreviewDetector` 改成以「錨點」計時：手指移動距離相對錨點超過 12dp 就重設錨點並重新計時；手指在錨點附近停留 250ms 才開始預覽手指下的卡片。起手方向以水平為主時（左右切換分頁）整個手勢都不觸發預覽。
2. **共用預覽播放器**（AC-10）：`VideoPreview` 持有一組共用的 `Player`／`VideoController`。`InlineVideoPreview` 取得時記錄擁有者；釋放時只有目前擁有者才 `stop()`（新卡片的 `initState` 會早於舊卡片的 `dispose`）。沒有擁有者 30 秒後才真正 `dispose`。訂閱 `player.stream` 的 listener 隨各自 widget 取消。每張卡片記下自己開啟的媒體 uri，只有 `player.state.playlist` 目前的媒體是自己的時才處理 position／playing／duration 事件，並以「自己的媒體 position > 0」作為第一格畫面，避免閃出前一張卡片的畫面。
3. **縮小重繪範圍**：播放位置、字幕文字改存在 `ValueNotifier`，只有進度條與字幕區塊重繪。

### 要改的檔案

| 檔案 | 改什麼 |
|---|---|
| `lib/common/widgets/video_card/video_card_style.dart` | 新增：`VideoCardStyle`、`VideoGridMixin` |
| `lib/common/widgets/video_card/vertical_video_card_frame.dart` | 新增：共用直式外框 |
| `lib/pages/search_panel/all/view.dart` | 「綜合」分頁的影片網格改直式 |
| `lib/pages/rcmd/view.dart` | 網格改用 `VideoCardStyle.gridDelegate` |
| `lib/common/widgets/video_card/video_card_h.dart` | 新增 `vertical` 直式版面 |
| `lib/pages/search_panel/video/view.dart` | 影片網格改直式 |
| `lib/pages/hot/view.dart`、`lib/pages/rank/zone/view.dart`、`lib/pages/popular_precious/view.dart`、`lib/pages/popular_series/view.dart`、`lib/pages/member_video_web/base/view.dart` | 影片網格改直式 |
| `lib/pages/fav_detail/widget/fav_video_card.dart`、`lib/pages/fav_detail/view.dart`、`lib/pages/fav_search/view.dart` | 收藏卡片直式與網格 |
| `lib/pages/subscription_detail/widget/sub_video_card.dart`、`lib/pages/subscription_detail/view.dart` | 訂閱卡片直式與網格 |
| `lib/pages/music/widget/music_video_card_h.dart`、`lib/pages/music/video/view.dart` | 音樂相關影片直式與網格 |
| `lib/pages/setting/models/style_settings.dart` | 卡片寬度對話框文字 |
| `lib/common/widgets/video_card/swipe_preview.dart` | 停住才開始預覽 |
| `lib/common/widgets/video_card/video_preview.dart` | 共用播放器、縮小重繪 |

### 介面與設定

- `VideoCardH({..., bool vertical = false})`，`FavVideoCardH`、`SubVideoCardH`、`MusicVideoCardH` 同。
- 設定鍵不變：`recommendCardWidth`（預設 300）、`smallCardWidth`（預設 240）。

## 任務

| ID | 任務 | 相依 | 執行 | 完成條件 |
|---|---|---|---|---|
| T-1 | `VideoCardStyle`、`VideoGridMixin`，首頁改用 | — | Opus（完成） | analyze 通過，首頁外觀不變 |
| T-1b | `VerticalVideoCardFrame` 共用外框 | T-1 | Opus（完成） | analyze 通過 |
| T-2 | `VideoCardH` 直式 + 搜尋（綜合、影片）、熱門、分區排行（只限影片項）、每週必看、入站必刷、UP 主影片頁 | T-1b | Sonnet | analyze 通過；相關影片仍橫式 |
| T-3 | `FavVideoCardH` 直式 + 收藏夾內容、收藏夾搜尋；尾端文字移出網格；排序頁不變 | T-1b | Sonnet | analyze 通過 |
| T-4 | `SubVideoCardH`、`MusicVideoCardH` 直式 + 頁面；卡片寬度對話框文字 | T-1b | Sonnet | analyze 通過 |
| T-5 | 滑動預覽：停住才開始、水平手勢不觸發 | — | Opus（完成） | analyze 通過 |
| T-6 | 共用預覽播放器、媒體歸屬判斷、縮小重繪 | T-5 | Opus（完成） | analyze 通過；預覽各功能正常 |

T-2、T-3、T-4 修改不同檔案，平行執行。

## 驗證計畫

| AC | 驗證方式 | 證據 |
|---|---|---|
| AC-1、AC-2 | 模擬器逐頁開啟截圖 | 截圖路徑 |
| AC-3 | 開影片頁相關影片、收藏夾排序頁截圖 | 截圖 |
| AC-4 | 模擬器點擊、長按、⋮ 選單；收藏多選需登入（未登入則讀程式碼確認並標未驗證） | 截圖／說明 |
| AC-5 | 同裝置首頁與搜尋截圖量測卡片寬 | 兩張截圖與像素數 |
| AC-6、AC-7 | 改寬度設定後重開，首頁與搜尋欄數同步變化；未改設定時首頁欄寬與修改前相同 | 截圖 |
| AC-8、AC-9 | `adb input swipe` 連續滑動不開始預覽；`adb input motionevent` 按住停 0.3 秒開始預覽 | 截圖 |
| AC-10 | profile 版 + 暫時加入 `addTimingsCallback` 記錄 >32ms 影格（不 commit），預覽開始前後量測 | logcat 片段 |
| AC-11 | 長按預覽、CC、靜音、進度條、點擊延續位置 | 截圖 |

## 邊界情況與風險

- 搜尋「綜合」分頁同時有使用者、直播等其他項目：只改影片網格。
- 直式卡片高度固定（`mainAxisExtent` 90 × 字級），標題超長要省略不溢位；大字級時以 textScaler 放大。
- 桌面寬螢幕：欄數由寬度設定決定，不需特別處理。
- 共用播放器：快速換卡時舊 widget 晚於新 widget dispose，必須以擁有者判斷，否則會停掉新預覽。
- App 進入背景、頁面被覆蓋：沿用既有 stop 機制；共用播放器 30 秒閒置後釋放。
- 回退：各卡片 `vertical` 預設 `false`，頁面改回不傳即可恢復；共用播放器問題可回到每次建立。

## 審查紀錄

| 來源 | 意見 | 處理 |
|---|---|---|
| 審查子代理 | 分區排行混有番劇卡，整個網格換 delegate 會變形 | 採用：依型別選 delegate |
| 審查子代理 | 搜尋「綜合」分頁（`all/view.dart`）未列入，mixin 綁 `GridMixin` | 採用：加入檔案表，mixin 改綁 `VideoGridMixin` |
| 審查子代理 | 收藏夾尾端「載入中／沒有更多」會佔一格 | 採用：移到網格後的 `SliverToBoxAdapter` |
| 審查子代理 | AC-1 寫 16:9，實際首頁為 16:10 | 採用：AC-1 改 16:10 |
| 審查子代理 | 收藏卡為 `selectMask` 非勾選框；有取消收藏 X；番劇簡介放不下 | 採用：寫入設計與 AC-4 |
| 審查子代理 | UP 主影片頁的 `SliverMainAxisGroup`、音樂頁既有 padding | 採用：只包網格、padding 相加 |
| 審查子代理 | 橫向時首頁有導覽列，AC-5 不成立 | 採用：AC-5 限手機直向 |
| 審查子代理 | `smallCardWidth` 影響範圍不只直播番劇；標題「預設240dp」錯誤 | 採用：改文字 |
| 審查子代理 | ⋮ 位置依賴橫式內距；直播項無播放數 | 採用：外框統一 ⋮ 位置；統計列保留高度 |
| 審查子代理 | 水平切換分頁、下拉重新整理時停住手指會觸發預覽 | 部分採用：水平手勢不觸發；下拉重新整理時手指停在卡片上仍可能預覽，影響小，不處理 |
| 審查子代理 | 共用播放器可能顯示前一張卡片殘留畫面 | 採用：以媒體 uri 判斷事件歸屬 |
| 審查子代理 | 四張卡片各自寫直式版面太重複 | 採用：新增 `VerticalVideoCardFrame` |

## 實作偏差

- （實作時填寫）

### 實作紀錄

- T-2：直式統計列日期用 `VideoCardV` 的短格式；分區排行以 `seasonType == null` 判斷影片排行（已查證 controller）；載入骨架也加左右留白。
- T-3：取消收藏 X 放在外框右下角（`action`），不在底列；收藏夾搜尋頁沒有骨架（載入中由共用頁面顯示）。
- T-4：訂閱合集資料沒有 UP 名稱，底列改顯示發布日期；音樂卡直式版省略標籤與跑馬燈。
- 統計列在窄卡片會和日期重疊（分區頁實測發現），改為數字列縮放、日期固定寬度。
- 依使用者指示停止驗證（token 用量），未寫 `3-verification.md`。已知結果：AC-8、AC-9 在模擬器確認；AC-10 模擬器影格數據雜訊大，無法判定。
