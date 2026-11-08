### 1. 影片卡片標題 (Video Card Titles)
* **共用性**：目前**無**共用 title 元件。[`VerticalVideoCardFrame`](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/common/widgets/video_card/vertical_video_card_frame.dart#L93) 僅為外框容器，title 由各卡片傳入。
* **各卡片渲染位置**：
  * 首頁推薦卡片：[video_card_v.dart:199](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/common/widgets/video_card/video_card_v.dart#L199)
  * 水平卡片（含搜尋關鍵字與垂直模式）：[video_card_h.dart:121](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/common/widgets/video_card/video_card_h.dart#L121), [:139](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/common/widgets/video_card/video_card_h.dart#L139), [:283](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/common/widgets/video_card/video_card_h.dart#L283), [:307](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/common/widgets/video_card/video_card_h.dart#L307)
  * 歷史紀錄：[item.dart:198](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/history/widgets/item.dart#L198)
  * 稍後再看：[video_card_h_later.dart:134](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/later/widgets/video_card_h_later.dart#L134) (PGC), [:161](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/later/widgets/video_card_h_later.dart#L161) (一般)
  * 收藏清單：[fav_video_card.dart:114](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/fav_detail/widget/fav_video_card.dart#L114) (垂直), [:311](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/fav_detail/widget/fav_video_card.dart#L311) (水平)
  * 直播卡片：[live_item_app.dart:173](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/live/widgets/live_item_app.dart#L173)、[item.dart:82](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/search_panel/live/widgets/item.dart#L82)
  * PGC/番劇：[pgc_card_v.dart:88](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/pgc/widgets/pgc_card_v.dart#L88)、[pgc_card_v_timeline.dart:82](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/pgc/widgets/pgc_card_v_timeline.dart#L82)、[pgc_card_v_pgc_index.dart:84](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/pgc_index/widgets/pgc_card_v_pgc_index.dart#L84)、[item.dart:64](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/search_panel/pgc/widgets/item.dart#L64)
* **最佳截流點 (Choke point)**：在 UI 層封裝統一的 `CardTitleText` Widget 替換上述渲染點；或於 Controller/Model 接收列表時批次翻譯替換 `title` 欄位。

---

### 2. 影片詳情頁 (Video Page)
* **UGC 標題**：[ugc/view.dart:415](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/video/introduction/ugc/view.dart#L415) (`TextSpan(text: videoDetail.title)`)。
* **UGC 簡介**：[ugc/view.dart:295](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/video/introduction/ugc/view.dart#L295) 透過 [`buildDesc`](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/video/introduction/ugc/view.dart#L580) 渲染富文本。依 `DescV2` 解析：type 1 普通文字透過正則抓取 URL/av/bv/時間戳跳轉，其餘文字為 TextSpan；type 2 為點擊 `@用戶`。
* **PGC 標題與簡介**：[pgc/view.dart:270](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/video/introduction/pgc/view.dart#L270) (標題 `Text`)、[:324](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/video/introduction/pgc/view.dart#L324) (簡介 `Text('簡介：${item.evaluate}')`)。

---

### 3. 評論區 (Comments)
* **元件與富文本建構**：[reply_item_grpc.dart:64](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/video/reply/widgets/reply_item_grpc.dart#L64)，在 `_buildMessage` ([:708](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/video/reply/widgets/reply_item_grpc.dart#L708)) 針對表情、話題、@用戶、超連結、投票和時間戳進行正則匹配。
* **純文字位置**：`replyItem.content.message`（[:812](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/video/reply/widgets/reply_item_grpc.dart#L812)）。
* **譯文展示點**：在 `_buildContent` 的 `TextMore.rich` 區塊下方（[:370](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/video/reply/widgets/reply_item_grpc.dart#L370)），新增獨立的譯文 Text 區塊，完全不需更動原訊息的 InlineSpan 結構。

---

### 4. 動態 (Dynamics)
* **富文本渲染**：[rich_node_panel.dart:24](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/dynamics/widgets/rich_node_panel.dart#L24) (`richNode`) 解析 `richTextNodes` 轉為 TextSpan，於 [content_panel.dart:83](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/dynamics/widgets/content_panel.dart#L83) (`SelectionText.rich`) 與 [:96](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/dynamics/widgets/content_panel.dart#L96) (`TextMore.rich`) 渲染。
* **純文字與插入點**：純文字可直接取 `moduleDynamic.desc.text ?? opus.summary.text`（[content_panel.dart:36-37](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/dynamics/widgets/content_panel.dart#L36-L37)）。譯文可直接插入於 [content_panel.dart:104](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/dynamics/widgets/content_panel.dart#L104)（`TextMore.rich` 與圖片九宮格之間）。

---

### 5. 分區/標籤/類別 (Zone/Tag/Category)
* **推薦原因 Badge**：[video_card_v.dart:219](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/common/widgets/video_card/video_card_v.dart#L219) (`videoItem.rcmdReason`)。
* **影片標籤**：[ugc/view.dart:1029](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/video/introduction/ugc/view.dart#L1029) (`_buildTags`, `item.tagName`)。
* **搜尋排序/過濾條件**：[view.dart:74](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/search_panel/video/view.dart#L74) (`ArchiveFilterType.desc`)。
* **分區 Tab**：全站分區為本地列舉 [rank_type.dart:25](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/models/common/rank_type.dart#L25) (`RankType.label`)；直播類別與標籤為 [item.dart:58](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/search_panel/live/widgets/item.dart#L58) (`liveItem.cateName`) 與 [live_area/view.dart:36](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/live_area/view.dart#L36)。

---

### 6. 設定頁面入口 (Settings Page)
* **語言相關設定**：[style_settings.dart:74-87](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/setting/models/style_settings.dart#L74-L87)（對應 [setting_tree.dart:337](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/setting/models/setting_tree.dart#L337)「外觀 › 字型與縮放」），建議在此放置「翻譯內容」開關（僅在 `Pref.appLanguage == 3` 顯示）。
* **現有翻譯引擎設定**：[play_settings.dart:268-300](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/setting/models/play_settings.dart#L268-L300)（對應 [setting_tree.dart:225](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/setting/models/setting_tree.dart#L225)「播放 › 字幕」的 `翻譯服務`、`金鑰` 與 `離線模型`）。

---

### 7. Translator 併發與隊列評估
* **現況**：[`Translator`](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/services/translate/translator.dart#L118) **完全沒有**併發限制或排隊隊列機制。單次批次內部為順序執行，但多個 Widget 同時調用會引發併發衝擊。
* **ML Kit 與線上 API 併發安全性**：**不安全**。ML Kit 透過 Platform Channel 調用 native 模型，高併發會導致 Channel 阻塞與 CPU 暴增；線上服務（DeepL / Google）若未排隊更會迅速觸發 HTTP 429 限流。實作時**必須建立全域任務佇列（Queue/Debounce）**進行流量整形。
