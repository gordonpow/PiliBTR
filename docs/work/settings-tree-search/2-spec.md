# 規格：設定介面樹狀分類與設定搜尋紀錄

對應需求：[1-requirements.md](1-requirements.md)

## 設計

### 現況（已查證）

- 設定首頁：`lib/pages/setting/view.dart`。內容是 `SettingType`（`lib/models/common/setting_type.dart`）的 9 個平面分類，加上 WebDAV、關於、更新、切換帳號、退出登入。
  - 直向時：點選後 `Get.to(CommonSetting)`。
  - 橫向時：左右雙欄，左欄是分類，右欄是 `CommonSetting(showAppBar: false)`。
- 每個分類的設定項是一個 `List<SettingsModel>`，定義在 `lib/pages/setting/models/*_settings.dart`。設定項用 `.widget` 產生元件。
- 搜尋頁：`lib/pages/settings_search/view.dart`。它把 9 個清單合併後，用 `effectiveTitle` 或 `effectiveSubtitle` 過濾，結果直接顯示 `.widget`，所以開關本來就能在結果中直接操作。
  - 目前沒有搜尋紀錄。
  - 沒有輸入時顯示 `HttpError()`（空白）。
- 同一個清單中，有些設定項會依平台出現兩個同名版本（`if/else`），例如影片設定的「預設畫質」。

### 決策

1. **不搬動設定項的程式碼**。原有的 9 個清單照舊（key、預設值、行為都不變，符合 AC-4）。新增 `lib/pages/setting/models/setting_tree.dart`，在執行時把原清單的項目分配到樹狀節點：
   - `SettingNode`：`id`、`title`、`subtitle`、`icon`，以及 `children`（子節點）或 `items`（設定項）二擇一。
   - 每個葉節點有 `titles`：一組 `effectiveTitle`，列出要收進這個節點的設定項。
   - 每個原清單（`SettingType`）有一個**預設葉節點**。沒有列在任何 `titles` 的項目，依來源清單放進該預設節點。這樣每個設定項都**恰好出現一次**，不會遺漏（AC-2）。
   - 分配時保留原清單的順序。來源清單的順序依 `SettingType` 列舉順序。
   - 同名的平台版本只有一個會存在（`if/else`），用標題比對不會重複。
   - 不採用的做法：把 200 多個設定項搬到新檔案。改動太大、和上游合併時會衝突，而且容易漏改。
2. **節點與分配**（標題比對；沒有列出的項目落入預設節點）：

| 節點 | 預設來源 | 額外收進的標題 |
|---|---|---|
| 播放 › 畫質與音質 | videoSetting | 超解析度、音量均衡 |
| 播放 › 播放行為 | playSetting | 番劇片頭/片尾跳過型別、空降助手 |
| 播放 › 手勢與操作 | — | 雙擊快退/快進、左右側滑動調節亮度/音量、滾輪調節音量、調節系統亮度、中間滑動進入/退出全螢幕、啟用雙指縮小影片、雙擊快進/快退時長、滑動快進/快退使用相對時長、滑動快進/快退時長、全螢幕手勢反向、全螢幕中間區塊寬度、啟用鍵盤控制 |
| 播放 › 全螢幕與旋轉 | — | 預設全螢幕方向、傾斜角度閾值、自動全螢幕、自動退出全螢幕、全螢幕顯示鎖定按鈕、全螢幕顯示截圖按鈕、全螢幕顯示電池電量、全螢幕展示點贊/投幣/收藏等操作按鈕、全螢幕 SuperChat 設定、直向螢幕擴大展示、橫向螢幕適配、橫向螢幕自動展開影片簡介、橫向螢幕分P/合集列表顯示在Tab欄、橫向螢幕播放頁在側欄開啟UP主頁、橫向螢幕在側欄開啟圖片預覽、播放頁移除安全邊距 |
| 播放 › 小視窗與子母畫面 | — | 返回時縮小為小視窗、斜下滑縮小為小視窗、小視窗大小、子母畫面、畫中畫不載入彈幕、背景播放、背景音訊服務、最小化時暫停/還原時播放 |
| 播放 › 彈幕 | dmSetting | — |
| 播放 › 字幕 | — | 自動啟用字幕、字幕選擇偏好、啟用拖拽字幕調整底部邊距 |
| 網路與加速 | — | CDN 設定、直播 CDN 設定、CDN 測速、音訊不跟隨 CDN 設定、B站定向流量支援、免登入1080P、緩衝大小、緩衝時長、直播緩衝大小、直播緩衝時長、啟用HTTP/2、連線重試次數、連線重試間隔、停用 SSL 證書驗證、設定代理 |
| 內容 › 首頁推薦 | recommendSetting | 顯示熱門推薦、展示追番時間表 |
| 內容 › 評論 | replySetting | — |
| 內容 › 動態 | dynSetting | 動態頁啟用瀑布流、動態頁UP主顯示位置、動態頁顯示所有已關注UP主、動態頁展開正在直播UP列表、動態未讀標記、檢查未讀動態 |
| 內容 › 搜尋 | — | 搜尋建議、記錄搜尋歷史、大家都在搜、搜尋發現、搜尋預設詞 |
| 外觀 › 主題與顏色 | — | 主題模式、純黑主題、應用主題、影片播放頁使用深色主題、深色下圖片顏色疊加、氣泡提示不透明度 |
| 外觀 › 版面與導覽 | styleSetting | — |
| 外觀 › 字型與縮放 | — | 語言、App字型設定、介面縮放 |
| 外觀 › 圖片 | — | 圖片質量、檢視大圖質量、預覽 Live Photo、靜默下載圖片、長按/右鍵顯示圖片選單 |
| 外觀 › 動畫 | — | 首頁切換頁面動畫、頁面過渡動畫、滑動動畫彈簧引數、螢幕幀率、側滑關閉二級頁面、橫向滑動閾值、重新整理指示器高度 |
| 帳號與隱私 | privacySetting | 另加兩個動作項：切換帳號、退出登入（從首頁移入） |
| 下載與儲存 | — | 下載路徑、快取路徑、允許三方APP訪問私有儲存、最大快取大小 |
| 其他 | extraSetting | — |
| 更新、WebDAV、關於 | 沿用原頁面 | — |

   實作時，若發現實際的 `effectiveTitle` 和上表不同（例如動態標題），以實際標題為準，並記在「實作偏差」。

3. **頁面**：
   - 新增 `lib/pages/setting/setting_node_page.dart`。
     - 節點有 `children` 時，顯示子節點清單（標題、說明、圖示）。
     - 節點有 `items` 時，用 `ListView` 顯示 `item.widget`，和 `CommonSetting` 相同。
   - `SettingPage`（首頁）：
     - 第一層顯示樹的根節點，順序是：播放、網路與加速、內容、外觀、帳號與隱私、下載與儲存、其他、更新、WebDAV、關於。
     - 「更新」保留紅點（`Update.available`，AC-6）。
     - 切換帳號、退出登入移到「帳號與隱私」。
   - 直向：點節點後 `Get.to(SettingNodePage(node))`。
   - 橫向（AC-5）：左欄是根節點，右欄是選中節點的 `SettingNodePage(showAppBar: false)`。右欄使用巢狀 `Navigator`，點子節點時在右欄內推入，右欄頂部有返回列。
   - `CommonSetting` 只有設定首頁使用（已 grep 確認）。保留檔案但首頁不再使用，避免動到其他功能。
4. **搜尋紀錄**：
   - 存放：`GStorage.setting` 的 key `settingsSearchHistory`（`List<String>`），最多 20 筆，最新的在前，重複的移到最前（AC-9）。
   - 寫入時機：
     - 鍵盤送出（`onSubmitted`）時。
     - 點選某個結果時：用 `Listener(onPointerUp)` 包住結果項，不攔截原本的點擊。
   - 輸入框為空時，顯示紀錄清單（AC-7）：
     - 每筆有刪除按鈕（AC-8）。
     - 頂部有「清除全部」。
     - 點紀錄會把文字填入輸入框並搜尋。
     - 沒有紀錄時顯示提示文字「輸入關鍵字搜尋設定」。
   - 結果標示路徑（AC-10）：每個結果上方顯示小字路徑，例如「播放 › 小視窗與子母畫面」，用 `setting_tree.dart` 提供的 `pathOf(item)`。
   - 比對：關鍵字小寫後，比對 `effectiveTitle`、`effectiveSubtitle`，以及兩者經過 `ZhConvert.convert` 的結果。
   - 搜尋的資料來源改為「樹中所有的設定項」。這和原本 9 個清單的內容相同，但加入了帳號動作項。
5. **AC-2 檢查**：`setting_tree.dart` 提供 `debugCheckTree()`，在 debug 模式進入設定頁時執行：
   - 每個原清單的項目都恰好被分配一次。
   - 每個 `titles` 都至少比對到一個項目。沒比對到的印出 `debugPrint`，表示標題打錯或該平台沒有這個項目。

#### 審查後修訂

- **R-1 橫向版面（AC-5）**：不用巢狀 Navigator。
  - 狀態是 `_path`（從根節點到目前節點的串列）。
  - 左欄顯示目前層級的節點清單：根層級時顯示根節點；選了有子節點的節點後，左欄改為顯示它的子節點，頂部有返回列。
  - 右欄顯示選中葉節點的設定項。
  - Android 返回鍵：用 `PopScope`。左欄不在根層級時，先回上一層，不離開設定頁。
  - AppBar 標題顯示目前路徑。
- **R-2 帳號動作**：
  - 把 `_logoutDialog` 與相關邏輯抽成 top-level 函式，放在 `lib/pages/setting/account_actions.dart`。
  - 提供 `List<SettingsModel> accountActionItems()`：兩個 `NormalModel`，標題「切換帳號」「退出登入」。
  - 「退出登入」沒有帳號時隱藏：自訂 `SettingsModel` 子類，或 `NormalModel` 外包 `Obx`。由於 `SettingsModel` 是 sealed，若無法擴充，就在帳號節點頁的建構處另外處理。
- **R-3 搜尋細節**：
  - 關鍵字先 `trim`，空字串不記錄。
  - 清除鈕清空輸入後，回到紀錄清單。
  - 點紀錄時設定 `text`、把游標移到最後，並呼叫 `ctr!.add`。
  - 比對前，原文與 `ZhConvert.convert` 的結果都先 `toLowerCase`。

## 要改的檔案

| 檔案 | 改什麼 |
|---|---|
| `lib/pages/setting/models/setting_tree.dart` | 新增：節點定義、分配、`pathOf`、`allItems`、`debugCheckTree` |
| `lib/pages/setting/setting_node_page.dart` | 新增：節點頁 |
| `lib/pages/setting/view.dart` | 首頁改用樹；橫向巢狀導覽；帳號動作移出 |
| `lib/pages/settings_search/view.dart` | 搜尋紀錄、路徑標示、資料來源 |
| `lib/utils/storage_key.dart` | `settingsSearchHistory`（存在 `localCache`） |
| `lib/pages/setting/account_actions.dart` | 新增：切換帳號、退出登入 |
| `lib/scripts/check_setting_tree.py` | 新增：AC-2 靜態檢查 |

## 任務

| ID | 任務 | 相依 | 執行 | 完成條件 |
|---|---|---|---|---|
| T-1 | `setting_tree.dart`（決策 1、2、5） | — | Opus | analyze 通過 |
| T-2 | 節點頁與首頁、橫向（決策 3） | T-1 | Sonnet | analyze 通過 |
| T-3 | 搜尋紀錄與路徑（決策 4） | T-1 | Sonnet | analyze 通過 |
| T-4 | 建置並在模擬器檢查 | T-2、T-3 | Opus | 截圖 |

## 驗證計畫

| AC | 方式 |
|---|---|
| AC-1、3 | 模擬器截圖：首頁、播放分類、葉節點 |
| AC-2 | debug log：`debugCheckTree` 沒有錯誤 |
| AC-4 | 在新位置切換一個開關，回到搜尋確認值相同 |
| AC-5 | 模擬器橫向截圖 |
| AC-6 | 首頁更新項目顯示紅點（有新版本時，用 `--dart-define=btr.version` 舊版號測試，可選） |
| AC-7～9 | 搜尋兩次，回到空白輸入框，截圖紀錄；刪除一筆 |
| AC-10 | 結果中直接切換開關並截圖路徑 |

## 邊界情況與風險

- 標題依語言轉換：已查證，轉換是在 `Text` 元件顯示時才做（`lib/common/widgets/zh_text.dart:109`），`effectiveTitle` 一定是繁體原文，所以用標題分配不受語言影響。不過簡體模式下，使用者會輸入簡體字，因此搜尋時要同時比對原文與 `ZhConvert.convert(原文)`。
- 有些設定項的標題是動態的（`getTitle`），比對不到時會落入預設節點，不會遺失。
- 上游新增的設定項會自動落入預設節點。
- 回退：還原 `view.dart` 與 `settings_search/view.dart`，刪除兩個新檔即可。

## 審查紀錄

| 來源 | 意見 | 處理 |
|---|---|---|
| 審查子代理 | 1 `setting` box 會被 WebDAV 匯出、匯入時清空 | 採用：搜尋紀錄改存 `GStorage.localCache` |
| 審查子代理 | 2「字幕選擇偏好」不是設定項 | 採用：移除 |
| 審查子代理 | 3 執行時檢查分不出打錯字和平台限定項目 | 採用：改用 `lib/scripts/check_setting_tree.py` 靜態比對標題、檢查重複；移除執行時檢查 |
| 審查子代理 | 4 橫向巢狀 Navigator 不符 AC-5、沒處理返回鍵 | 採用：見 R-1 |
| 審查子代理 | 5 帳號動作的寫法不明 | 採用：見 R-2 |
| 審查子代理 | 6 `onPointerUp` 捲動時也會觸發 | 採用：位移小於 `kTouchSlop` 才記錄 |
| 審查子代理 | 7 樹不可做成 static 快取 | 採用：每次開頁面時 `SettingTree.build()`；`pathOf` 用同一棵樹 |
| 審查子代理 | 8 空白關鍵字、清除鈕、點紀錄、`toLowerCase` | 採用：見 R-3 |
| 審查子代理 | 9「橫向螢幕適配」「橫向滑動閾值」放錯位置 | 採用：前者回到「外觀 › 版面與導覽」，後者回到「其他」 |
| 審查子代理 | 10 節點說明沒寫 | 採用：說明寫在 `setting_tree.dart` 每個節點的 `subtitle` |

## 實作偏差

- **帳號動作：** 在 `model.dart` 新增 `CustomModel`（sealed 類別只能在同一個 library 擴充）。「退出登入」用 `Obx` 依 `Accounts.account.isEmpty` 隱藏。
- **橫向狀態：** 除了 `_path`，另外有 `_category` 和 `_special`（WebDAV、關於）。預設選「帳號與隱私」，和原本預設 privacySetting 相同。點有子節點的根節點時，自動選第一個子節點。
- **子頁導覽：** `SettingNodePage` 推入子頁時使用 `Get.to(preventDuplicates: false)`，模擬器測試時發現需要這樣做。
- **執行時檢查：** 不做執行時檢查，改用 `lib/scripts/check_setting_tree.py`（審查意見 3）。
