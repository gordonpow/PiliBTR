# 規格：英文介面、字幕與彈幕翻譯（english-ui）

需求：[1-requirements.md](1-requirements.md)　探索：[explore-ui.md](explore-ui.md)、[explore-media.md](explore-media.md)

## A. 語言包產生（開發時）

### A1. 擷取腳本 `lib/scripts/extract_i18n.py`（T-1）

- 沿用 `lib/scripts/dartlex.py` 剖析 Dart 字面量（**需擴充**：目前只辨識 `${`（`dartlex.py:62`），要加上 `$name` 簡寫插值 `\$[A-Za-z_]\w*`），掃描 `lib/`（排除 `lib/grpc/`、`lib/scripts/`、`*.g.dart`）所有含中文的字串字面量。
- 跳過：`to_traditional.py` 的 `PROTECT` 清單、`num_utils.dart` 的單位字串與正規式、`chat_item.dart` 的 `'直播'`、語言選項標籤（`'简体中文'`、`'繁體中文'`）、出現在 `RegExp(...)` 或 `==`／`contains(`／`startsWith(` 比對中的字面量（無法確定時列入 `i18n/review.txt` 由人工判斷，不放進語言包）。
- 靜態字串：key 為字面量本身（繁體）。
- 含插值的字串：把每個 `${...}`／`$name` 換成依序的佔位 `{0}`、`{1}`…，產生樣板 key（例如 `'$diffInMins分鐘前'` → `{0}分鐘前`）。只收錄「中文部分至少 2 個字」的樣板；只有一個中文字或佔位相鄰而無法比對的列入 `review.txt`。
- 另外輸出 `i18n/fragments.txt`：同一個 widget 樹中被拆成多段 `Text`／`TextSpan` 的中文片段（只能逐段翻譯，作為人工檢查清單；片段本身仍以靜態字串收錄）。
- 輸出 `i18n/source.json`：`{"strings": {"中文": ""}, "templates": {"{0}分鐘前": ""}}`，依 key 排序，可重複執行（保留 `i18n/en.json` 已有的翻譯，只列出新增的待翻譯項目到 `i18n/todo.json`）。

### A2. 翻譯（T-2，Opus 用 agy 批次執行）

- `i18n/todo.json` 切成每批約 250 筆，用 `run-agy.sh` 平行翻譯（`--mode plan`，只輸出 JSON）。提示要求：保留 `{0}` 佔位、按鈕／選單用簡短的標題式英文、bilibili 專有名詞的固定譯法（彈幕 = Danmaku、投幣 = Coin、充電 = Charge、番劇 = Anime、UP 主 = Uploader、大會員 = Premium…，表格放在提示中）。
- 合併腳本 `lib/scripts/merge_i18n.py`：驗證每筆 JSON、佔位數量與順序一致、非空；不合格的列出重翻。產生 `i18n/en.json`：`{"version": "<yyyyMMddHHmm>", "strings": {...}, "templates": {...}}`。

## B. App 端介面翻譯（T-3）

- 語言設定：`Pref.appLanguage` 新增值 `3` = English（`style_settings.dart:918-943` 的選項與標籤）。`ZhConvert`（`lib/utils/zh_convert.dart:8,31-48`）新增 `ZhScript.english`；英文模式下中文轉換維持繁體作為後備。
- 語言包服務 `lib/utils/i18n_pack.dart`：
  - `download()`：GET 語言包 URL（獨立 Dio，不帶 B 站 cookie），驗證 JSON 後存到 App 文件目錄 `i18n/en.json`，並記錄 `version` 與檢查時間。
  - `load()`：啟動時（英文模式）同步讀入記憶體：`Map<String,String> strings`；樣板轉成 `RegExp` 清單（中文部分 `RegExp.escape`，`{n}` → `(.+?)`，整句錨定 `^...$`），依中文部分長度由長到短排序。
  - `translate(String s)`：先查 `strings`；再試樣板（命中時把擷取群組代入英文樣板的 `{n}`；擷取到的片段若本身是中文固定字串也再查一次 `strings`，處理 `${anonymity ? '退出' : '進入'}` 這類組合）；都沒有則回傳原字串。結果用現有的 LRU 快取（`zh_convert.dart:25-28` 的作法）。
  - 載入時機：`I18nPack.load()` 在 `ZhConvert.init()` 內、`runApp` 之前 await（`main.dart:127-133` 附近），讀檔失敗就退回繁體中文，不阻擋啟動。
- 背景更新：英文模式啟動時，上次檢查超過 7 天就背景下載比對 `version`，有新版存檔，下次啟動生效。
- 轉換層：`zh_text.dart`、`zh_material_widgets.dart` 中呼叫 `ZhConvert` 的地方，在英文模式改呼叫 `I18nPack.translate`（保持單一入口，例如 `ZhConvert.convert` 內部判斷）。新增匯出的 `Tooltip` 與 `IconButton` 包裝（`zh_material_widgets.dart` 加上，`zh_material.dart` 匯出時 `hide` 原版），翻譯 `message`／`tooltip`。
- 切換流程：選 English → 對話框顯示下載語言包與 ML Kit 模型的進度（模型見 D）→ 語言包成功才存設定並沿用現有的重新啟動流程；語言包失敗則提示並不切換；模型失敗不阻擋（字幕／彈幕維持原文）。
- Locale：`main.dart:112-114` 的 `_appLocale`／`fallbackLocale` 在英文模式回傳 `Locale('en','US')`。
- 設定：外觀頁加「更新語言包」（僅英文模式顯示），顯示目前語言包版本。

## C. 翻譯服務（T-4）

新檔 `lib/services/translate/translator.dart`：

- `Translator.translateBatch(List<String> texts, {bool online = false}) → Future<List<String>>`；失敗的項目回傳原文。
- 離線：模型下載失敗（例如裝置沒有 Google 服務、網路不通）時，回報明確錯誤；切換英文的對話框與「離線翻譯模型」設定顯示「離線模型無法使用，可在 播放 › 字幕 › 翻譯服務 填入 DeepL 或 Google Cloud 金鑰」，此時字幕改用線上服務（有金鑰時），彈幕維持原文。
- 離線：`google_mlkit_translation`（`TranslateLanguage.chinese` → `english`），`OnDeviceTranslatorModelManager` 下載／檢查／刪除模型。僅 Android；其他平台回傳原文。
- 線上（只給字幕用）：DeepL（`https://api-free.deepl.com/v2/translate` 或付費版，依金鑰尾碼 `:fx` 判斷）與 Google Cloud Translation v2（`https://translation.googleapis.com/language/translate/v2?key=`）；一次送一批（DeepL 最多 50 筆、Google 最多 128 筆）；獨立 Dio，不帶 B 站 cookie；失敗改用離線。
- 快取：記憶體 LRU（最多 5000 筆），key 為原文。
- 設定：`play_settings.dart`（播放 › 字幕，`setting_tree.dart:221-226`）加「翻譯服務」（離線模型／DeepL／Google Cloud）與金鑰輸入。金鑰存在獨立的 Hive box（例如 `translate_secrets`），**不加入設定匯出**（`lib/utils/storage.dart:22,47` 的 `exportSettings` 不得包含）；介面上以遮罩顯示；`dm_settings.dart` 加「翻譯彈幕」（預設開，僅英文模式顯示）；外觀或字幕頁加「離線翻譯模型」：狀態、下載、刪除。

## D. 字幕（T-5）

- 選擇：`Subtitle.compareTo`（`lib/models_new/video/video_play_info/subtitle.dart:24-30`）與 `_setSubtitle`（`lib/pages/video/controller.dart:1328-1342`）：英文模式時 `lan` 以 `en` 開頭或為 `ai-en` 者優先（使用者手動選的不覆蓋）。
- 翻譯放在 `VideoDetailController.setSubtitle`（`controller.dart:1175-1208`），不放在靜態的 `VideoHttp.getSubtitles`：取得原文 JSON 後先照原樣轉 VTT 顯示；英文模式且是中文軌時，把所有 `content` 交給 `Translator.translateBatch(online: 依設定)`。發出前記錄請求版本號（cid、軌道索引、遞增 token）；完成時只有在 `!isClosed`、cid 與目前選的軌道都沒變、token 是最新的情況下，才產生英文 VTT 並替換。譯文依「cid + lan」快取在記憶體。
- 字幕選單（`header_control.dart:1141-1367`）：翻譯過的軌道名稱加「 (Translated)」。
- 單元測試：`Subtitle.compareTo` 在英文模式的排序。

## E. 彈幕（T-6）

- 影片：`PlDanmakuController.handleDanmaku`（`lib/pages/danmaku/controller.dart:82-90`）在過濾、去重之後，把該段彈幕原文送入背景翻譯佇列（一律離線；依播放位置優先：先翻接下來 30 秒內的，再往後）；`DanmakuContentItem` 建立時（`lib/pages/danmaku/view.dart:138-157`）若快取已有譯文就用譯文，否則用原文。
- 直播：`_danmakuListener`（`lib/pages/live_room/controller.dart:580-641`）**不等待翻譯**：快取有譯文就顯示譯文，沒有就立即顯示原文，同時把原文送入低優先權背景翻譯（佇列上限 200，超過丟最舊的），供之後重複出現的彈幕命中快取。
- 封鎖、去重、彈幕詳情（長按檢舉、複製）使用原文。

## 任務

| 任務 | 內容 | 執行 | 相依 |
|---|---|---|---|
| T-1 | A1 擷取腳本、`i18n/source.json`、`todo.json`、`review.txt` | Sonnet | 無 |
| T-2 | A2 agy 批次翻譯、`merge_i18n.py`、`i18n/en.json` | Opus 派 agy；合併腳本由 T-1 的 Sonnet 一併寫 | T-1 |
| T-3 | B App 端介面翻譯 | Sonnet | 無（用一個小的假 `en.json` 開發） |
| T-4 | C 翻譯服務與設定 | Sonnet | 無 |
| T-5 | D 字幕 | Sonnet（與 T-4 同一個） | T-4 |
| T-6 | E 彈幕 | Sonnet（與 T-4 同一個） | T-4 |

平行：代理 1 做 T-1（含 merge 腳本）；代理 2 做 T-3；代理 3 做 T-4→T-5→T-6。T-2 在 T-1 完成後由 Opus 執行。

## AC 驗證方式

| AC | 方式 |
|---|---|
| AC-1～AC-8 | 單元測試：樣板 RegExp 產生與代入（`I18nPack.translate`）；diff 審查；`en.json` 合併腳本驗證；模擬器切換英文截圖（使用者要求時） |
| AC-9～AC-17 | diff 審查；功能待使用者實機測試 |
| AC-18 | `flutter analyze`、release 建置 |

## 邊界情況與風險

- 樣板誤配：中文部分太短的樣板可能誤譯伺服器內容（例如標題剛好符合 `{0}分鐘前`）。只收錄中文部分 ≥ 2 字的樣板，並全句錨定。
- 伺服器內容剛好與 UI 字串完全相同（例如標題就是「設定」）會被翻譯：可接受。
- 效能：英文模式查表是 O(1)；樣板比對只在查表未命中且含中文時進行，並有 LRU 快取。
- ML Kit 模型下載需要 Google 服務連線；失敗時字幕／彈幕維持原文。
- 彈幕量大：只做離線、依播放位置優先；手機效能不足時譯文可能晚到（先顯示原文）。
- 回退：語言設定改回中文即停用全部翻譯；語言包與模型可刪除。

## 審查紀錄

agy（gemini-3.8-flash-high）2026-11-08，7 條：

1. 採用：字幕翻譯移到 `setSubtitle`，加版本號防切換競態。
2. 採用：直播彈幕不等待翻譯，先顯示原文（原規格違反 AC-12）。
3. 採用：`dartlex.py` 需支援 `$name` 插值。
4. 部分採用：拆成多段的片段另列 `fragments.txt` 供人工檢查；不改寫原始碼。
5. 部分採用：不另外偵測 GMS，改為模型下載失敗時明確提示改用線上金鑰。
6. 部分採用：金鑰存獨立 box、不匯出、遮罩顯示；不另外加密（只存在本機）。
7. 採用：`I18nPack.load()` 在 `runApp` 前於 `ZhConvert.init()` 內完成；補樣板與字幕排序的單元測試。

## 實作偏差

- T-4：`google_mlkit_translation` 1.0.1；外掛 minSdk 21，Flutter 預設 24，相容。ML Kit 外掛沒有下載進度 API，`Translator.ensureModel()` 只回傳最後結果（`ok` / `error`），設定頁的對話框以不確定進度條顯示。
- T-4：`lib/utils/i18n_pack.dart` 尚不存在，未接線；切換 English 的對話框需呼叫 `Translator.ensureModel()`（失敗不阻擋切換，顯示 `result.error`）。
- T-4：模型檢查同時下載 `zh` 與 `en`；`isOfflineReady()` 對「未下載」的結果快取 30 秒，避免彈幕佇列反覆查詢。
- T-4：「翻譯彈幕」開關僅在英文模式且 Android 顯示（其他平台沒有離線模型）。金鑰 box 為 `translate_secrets`，不在 `exportAllSettings`，但 `GStorage.clear()` 會清除。
- T-4：新增 `lib/services/translate/translate_queue.dart`（背景佇列，影片與直播共用）、`lib/pages/setting/widgets/translate_dialogs.dart`。
- T-5：`Subtitle.compareTo` 改由 `compareWith(other, englishFirst:)` 實作以便測試；`_setSubtitle` 未改（清單已用 `sort()` 排序，`first` 即英文優先）。新增 `VideoHttp.getSubtitleBody` 供取得原始 JSON；`getSubtitles` 行為不變。
- T-5：`test/models/subtitle_compare_test.dart` 已寫，但本機沒有 MSVC，`flutter test` 因 native assets 建置失敗而無法執行（既有測試同樣受影響）。
- T-6：`DanmakuExtra` 新增 `original`（譯文顯示時為原文）；彈幕長按複製與時間跳轉使用原文。直播聊天室列表本來就顯示原文，未改。檢舉只用 id，不受影響。
- T-3：`flutter test` 在本機無法執行（`cnativeapi` 原生資產需要 Visual Studio C++ 編譯器），單元測試改用去除 Flutter 依賴的暫存副本以 `dart test` 驗證（10 項通過）。
- T-3：語言包版本與「上次檢查時間」存在 `i18n/meta.json`／`i18n/en.json`（App 文件目錄），不放 Hive，避免被設定匯出。
- T-3：`translate()` 的 LRU 快取在 `I18nPack`（樣板結果）與 `ZhConvert.convert`（最終結果）各一份；英文模式下語言包未命中才退回繁體轉換。
- T-3：切換對話框直接呼叫 `Translator.ensureModel()`（檔案已存在），未使用靜態 hook；模型失敗只提示、不阻擋切換。
- T-3：「更新語言包」下載後版本比對對象是啟動時載入的版本，重複按會再次顯示「已更新」，重新啟動後才生效。
- T-3：`IconButton` 包裝另補上 `styleFrom` 靜態轉發（靜態方法不會被繼承，現有 10 處使用）。

### 審查修正（T-3）

1. 進度對話框的 `ValueNotifier` 改為等對話框 route 結束（`await dialog`）後才 dispose。
2. `I18nPack.download` 在 `rename` 前先刪除既有的 `en.json`（Windows 不能覆蓋）。
3. 切換英文時先用 `I18nPack.loadValid()` 載入本機有效語言包，只有缺少或無效才下載，離線也能切回英文。
4. `IconButton` 包裝補上 `filled`、`filledTonal` 建構子；lib 內其餘用到的 `IconButton`／`Tooltip` 建構子與靜態成員（`styleFrom`、`outlined`）皆可編譯。
5. `ZhConvert.convert` 與 `span` 在英文模式不再因 `_table` 為空而提早返回，語言包翻譯先行，只有繁體後備依賴對照表。

### 審查修正（T-4～T-6）

- 1：Google 金鑰改放 `X-goog-api-key` 標頭，不再放 URL；翻譯用的獨立 Dio 沒有任何記錄攔截器，DeepL `Authorization` 不會被印出。
- 2：模型狀態／就緒判斷改為 zh 與 en 兩個都已下載；下載兩個；刪除 zh 後再嘗試刪 en，忽略內建模型無法刪除的錯誤。
- 3：`TranslateQueue` 影片版上限 500、一次線性挑出最近的 12 筆（不再整體排序）、已播放的丟棄；改由 `PlDanmakuController` 每 10 秒（或跳轉後）把已過濾去重的「接下來 2 分鐘」彈幕送入佇列，滿了就忽略新項目，不再翻整支影片。
- 4：字幕翻譯以 cid+lan 記錄進行中的 Future，重複選同一軌道會共用，不重複送線上請求。
- 5：離線模型未就緒時佇列只暫停、保留工作；下次加入項目時重新檢查。
- 6：非 Android 不顯示「離線模型」選項；預設為離線但沒有離線時，自動改用有金鑰的線上服務（DeepL 優先）。
