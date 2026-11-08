# 需求與規格：英文模式翻譯影片內容（content-translate）

日期：2026-11-08　探索：[explore.md](explore.md)

## 需求

使用者回報：切換成英文後，影片卡片仍是中文（標題、播放數「15萬」、推薦理由等是伺服器內容或中文數字單位，語言包翻不到）。

使用者決定（2026-11-08）：英文模式下翻譯影片卡標題、影片頁標題與簡介、評論、動態與分區名稱；加開關「翻譯影片內容」，預設開啟。

### 驗收條件

- **AC-1**：英文模式且開關開啟時，所有影片卡（首頁推薦、搜尋、歷史、稍後再看、收藏、直播、番劇／PGC 卡）的標題顯示英文譯文；尚未翻好時先顯示原文，翻好後自動替換。
- **AC-2**：英文模式下，`NumUtils.numFormat` 的顯示改為英文單位：≥10 億 → `B`、≥100 萬 → `M`、≥1000 → `K`（例如 `150000` → `150K`、`120000000` → `120M`，保留一位小數、去掉 `.0`）；傳入的字串若含 `万／萬／亿／億／千`，先用 `parseNum` 解析再格式化。中文模式行為不變；`parseNum` 不變。
- **AC-3**：推薦理由徽章（`rcmdReason`）、直播分類（`cateName`）、影片標籤（`tagName`）、直播分區名稱翻成英文（直接替換）。
- **AC-4**：影片頁標題（UGC、PGC）直接替換為譯文。簡介、評論、動態文字**保留原文**（不破壞表情、@、連結、時間戳），在原文下方以較小的灰色字顯示英文譯文；原文為空或已是英文（不含中日韓字元）時不顯示。
- **AC-5**：設定 外觀 › 字型與縮放 新增「翻譯影片內容」（僅英文模式顯示，預設開啟）；關閉後全部顯示原文。設定搜尋找得到。
- **AC-6**：內容翻譯一律使用離線模型（不消耗線上金鑰額度）；模型未就緒或非 Android 時顯示原文、不報錯。
- **AC-7**：全域翻譯佇列：同時只送一批給 ML Kit；100 ms 內的請求合併成一批（最多 16 句）；後請求的先翻（畫面上最新出現的優先）；佇列上限 300，超過丟最舊的；已翻譯的走快取（與現有 `Translator` LRU 共用），同一句不重複翻。
- **AC-8**：元件 dispose 後不再更新（不呼叫已卸載元件的 setState）。
- **AC-9**：不含中文的字串（純英文、數字）不送翻。
- **AC-10**：`flutter analyze` 無新增錯誤或警告。

### 不做

- UP 主名稱、使用者名稱（人名維持原樣）。
- 私訊、專欄全文、彈幕以外的直播聊天室。

## 設計

- 新檔 `lib/services/translate/content_translator.dart`：`ContentTranslator`（全域佇列、去重、合併、LIFO、上限、`ChangeNotifier` 或每句的 `ValueNotifier`），對外：
  - `String? cached(String text)`：快取有譯文就回傳。
  - `void request(String text)`：排入佇列。
  - `ValueListenable<String?> listen(String text)`：**每句獨立**的通知（以原文為 key，元件 dispose 時取消訂閱，沒有訂閱者的 notifier 可回收），避免一批翻完喚醒所有元件。
  - `ValueListenable<bool> enabled`：英文模式 && 開關開啟 && 離線模型可用（Android）；設定切換時通知，已顯示的元件即時切回原文或譯文。
  - 兩種優先順序：`priority: high`（標題、徽章、標籤、影片頁）與 `low`（評論、動態、簡介）；高優先的佇列先處理；上限分開（高 300、低 150），各自超過丟最舊。
- 新元件 `lib/common/widgets/content_text.dart`：
  - `ContentText(text, {style, maxLines, overflow, ...})`：與 `Text` 相同參數的替代品；enabled 時顯示 `cached ?? text`，沒有快取就 `request` 並監聽，拿到譯文後重建。`didUpdateWidget` 若 `text` 變了（列表回收）要換訂閱並重設，不得殘留上一筆的譯文。顯示譯文時用 Flutter 原生 `Text`（不經 `zh_text` 的 `ZhConvert`）。
  - `ContentTranslator.textOf(String text) → String`：給只能收字串的地方（`PBadge(text:)`、`TextSpan`），回傳快取或原文並觸發 request；這些地方外層用 `ValueListenableBuilder` 監聽該句。
  - `ContentTranslationLine(text, {style})`：enabled 且有中文時，在原文下方顯示譯文（翻好前不佔空間或顯示細小的省略號）。
- 替換點（依探索結果）：
  - 卡片標題：`video_card_v.dart:199`、`video_card_h.dart:121,139,283,307`（搜尋高亮的 rich title：英文模式且有譯文時改顯示純文字譯文）、`history/widgets/item.dart:198`、`later/widgets/video_card_h_later.dart:134,161`、`fav_detail/widget/fav_video_card.dart:114,311`、`live/widgets/live_item_app.dart:173`、`search_panel/live/widgets/item.dart:82`、`pgc/widgets/pgc_card_v.dart:88`、`pgc_card_v_timeline.dart:82`、`pgc_index/widgets/pgc_card_v_pgc_index.dart:84`、`search_panel/pgc/widgets/item.dart:64`。其他使用相同模式的卡片（grep `title` 的 Text）一併處理。
  - 徽章與分類：`video_card_v.dart:219`（rcmdReason；`PBadge` 只收 `String? text`（`badge.dart:7`），用 `textOf` + `ValueListenableBuilder`）、`ugc/view.dart:1029`（tagName）、`search_panel/live/widgets/item.dart:58`（cateName）、`live_area/view.dart:36`。
  - 影片頁：`ugc/view.dart:415` 標題（是 `TextSpan`，用 `textOf` + 外層監聽）、`pgc/view.dart:270` 標題；簡介 `ugc/view.dart:295`（buildDesc 下方加 `ContentTranslationLine`；純文字取 `desc` 非空時用 `desc`，否則用 `descV2` 各段 `rawText` 串接（`ugc/view.dart:293`、`data.dart:101`））、`pgc/view.dart:324`。
  - 評論：主樓 `reply_item_grpc.dart:370` 與子評論 `:656` 的內容下方加 `ContentTranslationLine(replyItem.content.message, priority: low)`。檔案中已有 `_buildTranslateBtn`（手動翻譯）：英文模式自動翻譯時隱藏或保留皆可，避免重複顯示兩份譯文。
  - 動態：`dynamics/widgets/content_panel.dart:104` 加 `ContentTranslationLine(desc.text ?? opus.summary.text)`。
- 數字：`lib/utils/num_utils.dart` 的 `numFormat` 依英文模式改單位（AC-2）。`parseNum` 的正規式同時接受 `K/M/B`（大小寫不拘），避免有呼叫端把格式化後的字串再解析時算錯。
- 設定：`style_settings.dart:74-87` 附近加開關；`storage_key.dart`、`storage_pref.dart` 加 key（預設 true）；`setting_tree.dart:337` 對應節點登錄標題。

## 任務

| 任務 | 內容 | 執行 |
|---|---|---|
| T-1 | 全部 | 一個 Sonnet 子代理 |

## 驗證

`flutter analyze`；功能待使用者實機測試。

## 風險

- 大量卡片同時出現：佇列合併、LIFO、上限 300；離線模型逐批翻譯，捲動很快時舊的會被丟掉。
- 搜尋高亮標題換成譯文後失去高亮：可接受。
- 機器翻譯品質有限。

## 審查紀錄

agy（gemini-3.8-flash-high）2026-11-08，7 條：

1. 採用：全域 Listenable 會引發重繪風暴 → 每句獨立的 ValueListenable。
2. 部分採用：評論維持自動翻譯（使用者選擇），但改為低優先、獨立上限，並涵蓋子評論（`:656`）；處理既有的手動翻譯按鈕避免重複。
3. 採用：列表回收殘留譯文 → `didUpdateWidget` 重設；譯文用原生 `Text`。
4. 採用：開關即時生效 → `enabled` 改 `ValueListenable<bool>`。
5. 採用：`PBadge`、`TextSpan` 不能直接放元件 → `textOf` + 外層監聽。
6. 採用：`parseNum` 也接受 K/M/B。
7. 採用：簡介純文字改從 `desc` 或 `descV2` 取。

## 實作偏差

- `parseNum` 的正規式除了 K/M/B，另外加入繁體單位 `萬／億`（`numFormat` 在英文模式收到含繁體單位的字串時也能解析）；K/M/B 後面不可緊接英文字母，避免把 `15 min` 之類誤判。
- `live_area/view.dart:36` 是固定標題「全部標籤」，實際的分區名稱在 `:90`（Tab）、`:259`、`:321`，改譯這三處；`SearchText` 新增 `translate` 參數（預設 false）。
- 另外處理的卡片：`live_item_follow.dart`、`live_search_room.dart`、`music_video_card_h.dart`、`video_card_h_member_video.dart`、`pgc_rank_item.dart`。
- 評論：主樓與評論串頁共用 `reply_item_grpc.dart:370` 的譯文行；樓中樓預覽（`:656`）為每則子評論加兩行上限的譯文行。伺服器翻譯（手動按鈕）顯示中時不產生自動譯文，避免重複。
- PGC 簡介的譯文行放在 `SingleChildScrollView`（不可捲動）內，避免固定高度時溢位。
- 內容翻譯與彈幕翻譯（`TranslateQueue`）各自有佇列，兩者可能同時各送一批給 ML Kit。
- 翻譯失敗（模型未就緒等）的句子 60 秒內不重試，開關切換時清除。
- 為了格式化順便跑了 `dart format lib/common/widgets/video_card/*.dart`（目錄內其他檔案可能有格式變動）。
