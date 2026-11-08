### 1. 設計（佇列與通知）：全域 Listenable 引發重繪風暴
* **問題**：規格定 `Listenable listenable` 於有新譯文時通知，單批（16句）翻完將喚醒畫面上所有 `ContentText` 重繪比對，列表卡片多時引發嚴重重繪風暴。
* **證據**：[2-spec.md:34](file:///c:/presonal_project/bilibili_bata/PiliPlus/docs/work/content-translate/2-spec.md#L34)。
* **修復**：改以單句提供 `ValueListenable<String?>` 獨立訂閱，或以原文字串為 Key 精準通知對應元件。

### 2. 驗收條件 AC-4 / AC-7：評論區百則灌爆佇列且遺漏子評論
* **問題**：ML Kit 為單執行緒逐句調用（[translator.dart:269](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/services/translate/translator.dart#L269)）。自動載入數百則評論將迅速塞滿上限 300 佇列，擠掉卡片標題並造成 CPU 高耗；且規格僅替換主樓（[reply_item_grpc.dart:370](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/video/reply/widgets/reply_item_grpc.dart#L370)），遺漏子評論（[reply_item_grpc.dart:656](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/video/reply/widgets/reply_item_grpc.dart#L656)）。
* **證據**：[reply_item_grpc.dart:370, 656](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/video/reply/widgets/reply_item_grpc.dart#L370)；[translator.dart:269](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/services/translate/translator.dart#L269)。
* **修復**：更簡化的設計為評論區不自動入列，維持點擊手動翻譯（整合既有 `_buildTranslateBtn`）。

### 3. 設計（ContentText）：列表回收殘留舊譯文與 zh_text 冗餘轉換
* **問題**：`ListView` 元件複用時若未於 `didUpdateWidget` 檢查文字變更，會短暫殘留上一筆項目的譯文；且專案中 `Text` 預設經由 [zh_text.dart:108](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/common/widgets/zh_text.dart#L108) 走 `ZhConvert.convert`，已翻為英文之文字會做無謂的 OpenCC/I18nPack 檢查。
* **證據**：[zh_text.dart:108](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/common/widgets/zh_text.dart#L108)；[zh_convert.dart:118](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/utils/zh_convert.dart#L118)。
* **修復**：在 `didUpdateWidget` 比對 `oldWidget.text` 並重設狀態；顯示譯文時直接使用底層 `flutter.Text`。

### 4. 驗收條件 AC-5：設定即時開關無響應
* **問題**：`enabled` 僅為 static getter，使用者於設定頁切換開關時，已渲染元件無法接收變更即時切回原文。
* **證據**：[2-spec.md:35, 46](file:///c:/presonal_project/bilibili_bata/PiliPlus/docs/work/content-translate/2-spec.md#L35)。
* **修復**：`enabled` 提供 `ValueListenable<bool>`，變更時廣播通知重繪。

### 5. 設計（替換點）：PBadge 與 TextSpan 假定錯誤
* **問題**：[video_card_v.dart:219](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/common/widgets/video_card/video_card_v.dart#L219) 的 `PBadge` 參數為 `String? text` 非 Widget；[ugc/view.dart:415](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/video/introduction/ugc/view.dart#L415) 為 `TextSpan`，無法直接替換為 `ContentText` Widget。
* **證據**：[badge.dart:7](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/common/widgets/badge.dart#L7)；[ugc/view.dart:415](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/video/introduction/ugc/view.dart#L415)。
* **修復**：`PBadge` 內部改用 `ContentText`，或改於 Model/Controller 接收資料時截流替換。

### 6. 驗收條件 AC-2：numFormat 與 parseNum 不對稱
* **問題**：AC-2 規定 `parseNum` 不變，但若呼叫端傳入已格式化的英文字串（如 `150K`、`1.2M`），`_numRegExp` 僅比對 `[千万亿]`，導致單位遺失回傳錯誤整數（`150K` 誤轉為 `150`）。
* **證據**：[num_utils.dart:5, 23](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/utils/num_utils.dart#L5)。
* **修復**：`parseNum` 正規式同步加入 `K/M/B` 解析單位。

### 7. 設計（影片簡介）：純文字取值不健全
* **問題**：UGC 詳情常僅有 `descV2` 而 `desc` 為 null，直接取 `desc` 純文字會得空值導致不翻譯。
* **證據**：[ugc/view.dart:293](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/video/introduction/ugc/view.dart#L293)；[data.dart:101](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/models_new/video/video_detail/data.dart#L101)。
* **修復**：改為 `videoDetail.desc?.isNotEmpty == true ? videoDetail.desc! : (videoDetail.descV2?.map((e) => e.rawText ?? '').join() ?? '')`。
