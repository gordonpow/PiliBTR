1. `lib/pages/danmaku/controller.dart:38`、`lib/services/translate/translate_queue.dart:1039, 1084`
- **問題**：`PlDanmakuController` 初始化 `TranslateQueue` 未設 `maxPending`（無上限），且 `_takeBatch` 每 12 筆就對全佇列做一次 `sort()`。
- **失敗情境**：熱門影片數萬條彈幕湧入，主執行緒每批次都對數萬筆資料重新配置 List 並排序，造成劇烈 UI 卡頓掉幀；且模型會在背景無休止翻譯全片彈幕，耗盡 CPU 與電力。
- **修復方式**：傳入合理 `maxPending`（如 500）並捨棄超出當前播放時間過遠的彈幕。

2. `lib/services/translate/translator.dart:945, 974, 1017`
- **問題**：ML Kit 中翻英需 `zh` 與 `en` 兩模型，但 `isOfflineReady`、`modelStatus` 與 `deleteModel` 僅檢查並刪除 `_zh`。
- **失敗情境**：若 `zh` 成功但 `en` 下載中斷，`modelStatus` 仍誤報已下載，播放時 ML Kit 因缺 `en` 連續拋出例外崩潰；且點擊刪除只刪 `zh`，約 30MB 的 `en` 模型永久殘留成孤兒檔案。
- **修復方式**：狀態檢查改為同時驗證 `isModelDownloaded(_zh)` 與 `_en`；`deleteModel` 同時刪除兩者。

3. `lib/pages/video/controller.dart:1254, 1260`
- **問題**：字幕翻譯缺乏 in-flight 狀態防護。
- **失敗情境**：線上翻譯耗時數秒期間，若使用者再次點選同軌道或切換後迅速切回，會併發觸發兩次 `_translateSubtitle`，向 DeepL / Google 送出兩次完全相同的數百行字幕請求，雙倍消耗付費額度。
- **修復方式**：以 `Set<String> _translatingKeys` 記錄進行中的軌道，翻譯完成前不重複發起請求。

4. `lib/services/translate/translate_queue.dart:1099-1102`
- **問題**：離線模型未就緒時，佇列直接呼叫 `_jobs.clear()` 清空所有任務。
- **失敗情境**：模型未下載完成時開播，已載入分段的彈幕全被清空；因分段已標記為已載入，即便稍後模型下載完成，該影片已清空的分段彈幕也永遠不會再被翻譯。
- **修復方式**：未就緒時提早 return 或暫停處理，保留佇列待模型就緒，不可直接清空。

5. `lib/pages/setting/models/play_settings.dart:292`、`lib/services/translate/translator.dart:742, 768`
- **問題**：非 Android 平台不支援離線模型，但 `service` 預設為 `offline`。
- **失敗情境**：桌面端使用者填寫了 DeepL / Google 金鑰，若未手動進入「翻譯服務」切換，`onlineConfigured` 判為 false，字幕完全不會發起線上翻譯。
- **修復方式**：非 Android 平台填寫金鑰後自動切換至該線上服務，或在選單中隱藏離線模型。
