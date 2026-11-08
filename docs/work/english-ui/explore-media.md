### 1. 字幕（Subtitles）
* **清單獲取**：`lib/pages/video/controller.dart:1246` 透過 `VideoHttp.playInfo` (`lib/http/video.dart:1056`) 取得；未登入備援為 `DmGrpc.dmView` (`lib/pages/video/controller.dart:1300`、`lib/grpc/dm.dart:25`)。
* **Model 欄位**：`Subtitle` (`lib/models_new/video/video_play_info/subtitle.dart:1-22`) 含 `lan`、`lanDoc` (`lan_doc`)、`subtitleUrl` (`subtitle_url`)、`subtitleUrlV2`、`isAi` (`type == 1`)。B 站原始 JSON 另有 `ai_type` 與 `ai_status`。
* **語言代碼**：`en-US`、`ai-en` 等代碼出現在 `Subtitle.lan`。
* **預設字幕選擇**：`Subtitle.compareTo` (`lib/models_new/video/video_play_info/subtitle.dart:24-30`) 優先排中文與非 AI；`_setSubtitle` (`lib/pages/video/controller.dart:1328-1342`) 依 `Pref.subtitlePreferenceV2` 挑選第 1 軌。若 App 語系為英文，應修改此排序比較邏輯優先匹配英文。
* **下載、解析與渲染**：`VideoHttp.getSubtitles` (`lib/http/video.dart:1081-1097`) 下載 JSON (`from`/`to`/`content`) 並經 `SubtitleUtils.json2Vtt` (`lib/utils/subtitle_utils.dart:24-34`) 轉為 WebVTT；`setSubtitle` (`lib/pages/video/controller.dart:1182-1193`) 傳入 `memory://` 由 mpv (`media_kit`) 原生渲染，非 Flutter 疊層。
* **最佳批次翻譯點**：`VideoHttp.getSubtitles` (`lib/http/video.dart:1086`) 取得 JSON `body` 後、傳入 `json2Vtt` 前，批次翻譯所有 `content`。

---

### 2. 彈幕（Danmaku）
* **拉取與分段**：`PlDanmakuController.queryDanmaku` (`lib/pages/danmaku/controller.dart:38-59`) 透過 `DmGrpc.dmSegMobile` (`lib/grpc/dm.dart:8-23`) 拉取 gRPC 分段；本地檔為 `_initFileDm` (`lib/pages/danmaku/controller.dart:115-131`)。
* **轉為渲染物件**：`_PlDanmakuState.videoPositionListen` (`lib/pages/danmaku/view.dart:138-157`) 轉為 `canvas_danmaku` 的 `DanmakuContentItem`。
* **直播彈幕路徑**：`LiveRoomController.initDm` (`lib/pages/live_room/controller.dart:550-560`) 透過 WebSocket (`lib/tcp/live.dart:1`) 接收，於 `_danmakuListener` (`lib/pages/live_room/controller.dart:580-641`) 轉成 `DanmakuContentItem`。
* **文字過濾機制**：影片彈幕在 `PlDanmakuController.handleDanmaku` (`lib/pages/danmaku/controller.dart:83`) 呼叫 `RuleFilter.remove` (`lib/models/user/danmaku_rule.dart:37-41`) 比對黑名單文字與正則；直播彈幕經 `isBlocked` (`lib/pages/live_room/controller.dart:467-469`) 比對。**去重與屏蔽必須使用原文先過濾**。
* **最佳批次翻譯點**：`PlDanmakuController.handleDanmaku` (`lib/pages/danmaku/controller.dart:82-90`)，在去重與過濾完成後、存入 `_dmSegMap` 前，對該段剩餘彈幕進行批次翻譯。

---

### 3. 現有翻譯工具與 HTTP 實例
* **現有翻譯**：專案無任何外接翻譯 API，僅有繁簡轉換 `ZhConvert` (`lib/utils/zh_convert.dart:1-50`，基於 OpenCC 本地字典)。
* **最佳 Dio 實例**：全域 `Request.dio` (`lib/http/init.dart:31, 201-251`) 預設含 B 站 `apiBaseUrl` 與 `AccountManager` (`lib/utils/accounts/account_manager/account_mgr.dart:44`，會自動注入 Cookie)。呼叫第三方翻譯 API 建議**建立獨立 `Dio` 實例**（繼承系統代理設定以防洩漏 Cookie），或在 `Request().get/post` 加上 `extra: {'account': const NoAccount()}` (`lib/utils/accounts/account.dart:6`)。

---

### 4. 設定頁面放置位置
* **字幕設定**：
  * 全域頁面：`lib/pages/setting/models/play_settings.dart:261`（「自動啟用字幕」）、`lib/pages/setting/models/play_settings.dart:156`（「拖拽字幕邊距」），屬於 `lib/pages/setting/models/setting_tree.dart:221-226`（播放 › 字幕節點）。
  * 播放器面板：`lib/pages/video/widgets/header_control.dart:1141-1367` (`showSetSubtitle`)。
* **彈幕設定**：
  * 全域頁面：`lib/pages/setting/models/dm_settings.dart:16-55` (`dmSettings`)，屬於 `lib/pages/setting/models/setting_tree.dart:214-219`（播放 › 彈幕節點）。
  * 偏好存取：`lib/plugin/pl_player/utils/danmaku_options.dart:49-66`。
* **語言設定**：`lib/utils/storage_pref.dart:210` (`Pref.appLanguage`)。
