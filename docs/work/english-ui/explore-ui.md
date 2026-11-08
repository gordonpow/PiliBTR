### 1. 轉換層涵蓋與運作機制
* **涵蓋 Widget**：
  * `Text` / `Text.rich`（含遞迴 `TextSpan` 與 `semanticsLabel`）：[zh_text.dart:28,54,104,146](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/common/widgets/zh_text.dart#L28-L146)
  * `Tab.text`：[zh_material_widgets.dart:14-27](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/common/widgets/zh_material_widgets.dart#L14-L27)
  * `TextField`（涵蓋 hint/label/helper/error 等 7 項裝飾）：[zh_material_widgets.dart:29-123](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/common/widgets/zh_material_widgets.dart#L29-L123)
  * `AppBar(title)`：若傳入 `Text` 即被涵蓋。
  * **未涵蓋**：`Tooltip.message`、`IconButton.tooltip`、`TextFormField`、由 [zh_flutter_material.dart:1-4](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/common/widgets/zh_flutter_material.dart#L1-L4) 引用的 `Tab`。
* **語系判定**：
  * `Pref.appLanguage`（0跟隨系統、1繁體、2簡體）：[style_settings.dart:918-924](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/pages/setting/models/style_settings.dart#L918-L924)；由 `ZhConvert.resolve` 根據系統 `Hans/CN/SG` 決定：[zh_convert.dart:31-48](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/utils/zh_convert.dart#L31-L48)，需重啟生效：[style_settings.dart:941-943](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/pages/setting/models/style_settings.dart#L941-L943)。
* **快取與效能**：
  * 字串 $\le 200$ 字元走 4096 筆 LinkedHashMap LRU 快取：[zh_convert.dart:25-28,95-107](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/utils/zh_convert.dart#L25-L107)。
  * UI 字串優先走 `_exact` 精確匹配：[zh_convert.dart:103](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/utils/zh_convert.dart#L103)；未命中則按首字 UTF-16 索引 `_maxLenByFirst` 執行最長匹配，無替換不分配記憶體：[zh_convert.dart:112-141](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/utils/zh_convert.dart#L112-L141)。

---

### 2. 未經轉換層 Text 之字串與單一攔截點
* `SmartDialog.showToast / showNotify`：底層 `CustomToast` 與 `NotifyWarning` 已使用 `zh_material.dart` 的 `Text`：[custom_toast.dart:24,91](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/common/widgets/custom_toast.dart#L24-L91)；全域攔截點在 [custom_toast.dart:24](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/common/widgets/custom_toast.dart#L24)（~350+ 處呼叫）。
* `Get.snackbar`：專案未使用（0 處）。
* `Tooltip.message` / `IconButton.tooltip`：未轉換（~180+ 處）。單一攔截點：在 [zh_material_widgets.dart:12](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/common/widgets/zh_material_widgets.dart#L12) 封裝自訂 `Tooltip` 與 `IconButton` 並由 [zh_material.dart:3](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/common/widgets/zh_material.dart#L3) 匯出。
* `InputDecoration hintText/labelText`：已在 `zhDecoration` 攔截：[zh_material_widgets.dart:112-123](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/common/widgets/zh_material_widgets.dart#L112-L123)；裸用處少（~15 處）。
* `Semantics`：`Text.semanticsLabel` 已轉換：[zh_text.dart:104](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/common/widgets/zh_text.dart#L104)；獨立元件極少（<10 處）。
* `通知頻道`：單一攔截點 [audio_handler.dart:48-54](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/services/audio_handler.dart#L48-L54)（1 處，代碼現已為英文）。
* `分享文字`：單一攔截點 [share_utils.dart:28](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/utils/share_utils.dart#L28)（~8 處）。
* `AlertDialog / PopupMenu`：普遍傳入 `Text(...)` 作為 child，已自動涵蓋，如 [select_dialog.dart:38](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/pages/setting/widgets/select_dialog.dart#L38)。

---

### 3. Locale 與 Material 內建元件英文適配
* 現況：[main.dart:325-328](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/main.dart#L325-L328) 已設定 `GlobalMaterialLocalizations.delegates` 與 `Locale("en", "US")`。
* 調整需求：
  1. 在 [main.dart:112-114](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/main.dart#L112-L114) 將 `_appLocale` 與 `fallbackLocale` 擴充支援英文設定（回傳 `const Locale('en', 'US')`）。
  2. 在 [zh_convert.dart:8,31](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/utils/zh_convert.dart#L8-L31) 擴充 `ZhScript.english` 與解析分支。
  * 設定後，DatePicker、返回鍵 Tooltip 等 Material 元件將自動透過 Flutter Localizations 顯示英文。

---

### 4. 插值字串（Interpolated strings）分析
* **比例**：靜態字面量約佔 85%~90%（~3,000 處），含 `$` 插值中文約佔 10%~15%（~400 處）。
* **5 個代表範例**：
  1. [style_settings.dart:99](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/pages/setting/models/style_settings.dart#L99)：`'當前：${(Pref.fullscreenCenterRatio * 100).round()}%'`
  2. [date_utils.dart:26](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/utils/date_utils.dart#L26)：`'$diffInMins分鐘前'`
  3. [style_settings.dart:916](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/pages/setting/models/style_settings.dart#L916)：`'$columns 排'`
  4. [mine/view.dart:204](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/pages/mine/view.dart#L204)：`"${anonymity ? '退出' : '進入'}無痕模式"`
  5. [mine/view.dart:225](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/pages/mine/view.dart#L225)：`'切換至${controller.nextThemeType.label}主題'`
* **模板匹配建議**：在 `ZhConvert` 引入 Regex 模板表（例如 `^(\d+)\s*分鐘前$` $\to$ `$1 minutes ago`），以解決中英翻譯語序顛倒問題。

---

### 5. 萃取腳本複用與保護清單
* **複用現有腳本**：結合 [dartlex.py:11-72](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/scripts/dartlex.py#L11-L72)（能精準剖析 Dart 字面量並略過 `${}` 表達式）與 [gen_zh_dict.py:128-146](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/scripts/gen_zh_dict.py#L128-L146) 的掃描邏輯，即可將所有 UI 字串擷取為待翻譯 JSON。
* **嚴禁翻譯字面量（白名單）**：
  * 與伺服端響應比對之字串：[to_traditional.py:26-46](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/scripts/to_traditional.py#L26-L46) 的 `PROTECT` 列表（如 `投稿视频`、`竖屏`、`会员`、`连载`、`账号未登录`、`充电专属` 等）。
  * 數字解析單位與正規式：[num_utils.dart:5,9-14](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/utils/num_utils.dart#L5-L14)（`[千万亿]`、`'千'`、`'万'`、`'亿'`）。
  * 語系選項標籤自身：[style_settings.dart:922](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/pages/setting/models/style_settings.dart#L922)（`'简体中文'` 需保留）。
  * 私訊來源識別：`chat_item.dart` 中的 `['source'] == '直播'`。
