### 1. 字幕架構職責錯置與切換競態
* **規格章節**：D. 字幕
* **問題**：規格要求在 `VideoHttp.getSubtitles` 中先回傳原 VTT，待翻譯完成後重新呼叫 `setSubtitle`。但該方法為純靜態 HTTP 解析函式，無播放器與控制器上下文；且未處理非同步翻譯期間使用者切換字幕軌道、換集（`cid` 變更）或關閉播放器的 Race Condition。
* **代碼依據**：[video.dart:1081-1097](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/http/video.dart#L1081-L1097)、[controller.dart:1175-1208](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/pages/video/controller.dart#L1175-L1208)
* **具體修正**：翻譯邏輯移至 `VideoController.setSubtitle`。引入請求版本號（Token），非同步完成時驗證 `cid`、軌道索引一致且 `!isClosed` 才替換軌道。

### 2. 直播彈幕延遲緩衝違反驗收條件
* **規格章節**：E. 彈幕
* **問題**：規格要求直播彈幕「累積 300ms 送翻、最多等 1.5 秒」才送出，直接違反 AC-12（未翻譯完成先顯示原文）。行動端離線模型推論單執行緒排隊，高流量直播會造成佇列無上限膨脹與音畫嚴重不同步。
* **代碼依據**：AC-12、[controller.dart:617-641](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/pages/live_room/controller.dart#L617-L641)
* **具體修正**：直播彈幕收到後立即以原文（或快取命中譯文）上屏，不等待翻譯；新訊息僅非同步送入低優先權快取預熱，不得阻塞顯示串流。

### 3. dartlex 腳本漏判無大括號插值
* **規格章節**：A1. 擷取腳本
* **問題**：規格聲明沿用 `dartlex.py` 處理 `$name` 樣板，但現有實作僅比對 `${`，無法辨識 `$diffInMins分鐘前`、`$columns 排` 等常見簡寫，導致整句被誤判為靜態字面量或切碎。
* **代碼依據**：[dartlex.py:62](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/scripts/dartlex.py#L62)
* **具體修正**：擴充 `dartlex.py` 的正則與狀態機，納入 `\$[a-zA-Z_]\w*` 辨識，並將含插值的完整字面量作為單一表達式提取至樣板庫。

### 4. RichText 與拆分字串無法命中樣板
* **規格章節**：B. App 端介面翻譯
* **問題**：`ZhConvert.span` 對每個 `TextSpan` 個別翻譯；UI 中亦有以 `Row` 串接多個 `Text` 之寫法。破碎片段（如「第」、「頁」）無法匹配 `^{0}...$` 全句錨定樣板，導致譯文殘缺或語序顛倒。
* **代碼依據**：[zh_convert.dart:146-162](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/utils/zh_convert.dart#L146-L162)
* **具體修正**：A1 擷取時產出跨元件拆分待審清單，將原始碼片段改組為單一插值字串；無法合併處於 `i18n/en.json` 的 `strings` 補入單詞對照。

### 5. 無 GMS 裝置之離線翻譯不可用
* **規格章節**：C. 翻譯服務、AC-15
* **問題**：規格假設 Android 皆可用 ML Kit，但無 Google Play 服務（GMS）之機型無法下載模型，導致無付費金鑰之使用者完全無法翻譯且未有明確降級引導。
* **代碼依據**：[2-spec.md:38](file:///C:/presonal_project/bilibili_bata/PiliPlus/docs/work/english-ui/2-spec.md#L38)、AC-15
* **具體修正**：下載模型前檢查 GMS 可用性；若缺失則停用離線選項並彈窗提示需填寫 DeepL/Google 線上金鑰。

### 6. API 金鑰明文存儲與匯出風險
* **規格章節**：C. 翻譯服務
* **問題**：規格將翻譯 API 金鑰置於一般 `Hive`，設定檔為未加密明文，且會被 `GStorage.exportSettings` 匯出外洩。
* **代碼依據**：[storage.dart:22,47](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/utils/storage.dart#L22-L47)
* **具體修正**：使用加密 Hive Box 獨立存儲金鑰，並於設定匯出黑名單中排除翻譯金鑰鍵值。

### 7. 啟動載入時機與不可驗證 AC
* **規格章節**：B. App 端介面翻譯、AC 驗證方式
* **問題**：規格未明定 `I18nPack.load()` 於 `main.dart` 的位置，若未在 `runApp` 前 await 完成，首屏 `Text` 將以繁中渲染；AC-9～AC-17 全部標記「待使用者實機測試」，缺乏 CI 自動化驗證。
* **代碼依據**：[main.dart:127-133](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/main.dart#L127-L133)、[2-spec.md:73](file:///C:/presonal_project/bilibili_bata/PiliPlus/docs/work/english-ui/2-spec.md#L73)
* **具體修正**：將 `I18nPack.load()` 納入 `ZhConvert.init()`，載入失敗自動 fallback 繁中；替 `Subtitle.compareTo` 與樣板正則補寫單元測試以利自動化驗證。
