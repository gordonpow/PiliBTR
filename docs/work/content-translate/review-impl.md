### 1. 內容佇列與彈幕佇列併發呼叫 ML Kit
- **位置**：`lib/services/translate/translator.dart:260`（關聯 `content_translator.dart:170`、`translate_queue.dart:93`）
- **問題**：違反 AC-7「同時只送一批給 ML Kit」。`ContentTranslator` 與彈幕 `TranslateQueue` 各自獨立運作，兩者皆直接呼叫 `Translator.translateBatch()`，底層共用同一個 `OnDeviceTranslator` 單例且缺乏全域互斥鎖。
- **具體失敗情境**：在英文模式下開啟彈幕播放影片，此時同時載入評論區或捲動推薦卡片。彈幕佇列與內容佇列同時發起離線翻譯，透過 Platform Channel 並行調用原生模型，導致 Channel 阻塞、CPU 負載激增或 ML Kit 拋出逾時異常，使彈幕與介面文字雙雙退回原文。
- **具體修正**：在 `Translator` 內部加入佇列互斥鎖（例如串接 `Future` 鏈），確保 `_translateOffline` 於同一時間僅有一批推論在執行。

---

### 2. VideoCardH 巢狀重複訂閱 ContentTextBuilder
- **位置**：`lib/common/widgets/video_card/video_card_h.dart:73`、`:152`
- **問題**：`VideoCardH` 外層已使用 `ContentTextBuilder` 監聽標題，但在其 `builder` 內部，當 `titleList` 為空或翻譯完成時，又回傳了 `ContentText`，而 `ContentText` 內部又建立了第二層 `ContentTextBuilder`。
- **具體失敗情境**：在非搜尋情境下渲染水平卡片時，每個標題皆會註冊兩組 `_ContentBinding` 監聽器。譯文完成時會引發兩次 `setState` 重繪，且在清單快速捲動回收時造成雙重訂閱／解約負擔。
- **具體修正**：在 `VideoCardH` 的 `builder` 中直接回傳文字元件：`translated` 為 true 時回傳 `flutter.Text(shown!, ...)`；未翻譯時回傳 `Text(videoItem.title, ...)`，避免在內部再次包裝 `ContentText`。

---

### 3. 失敗阻擋時間戳覆蓋導致冷卻時間失真
- **位置**：`lib/services/translate/content_translator.dart:181`
- **問題**：第 181 行使用 `_failedUntil ??= DateTime.now().add(_failedRetry);`。若已有失敗句子設定了到期時間，後續新失敗的句子不會更新時間戳；而第 118 行在到期後會無差別清空整個 `_failed` 集合。
- **具體失敗情境**：在 t=0s 時句子 A 翻譯失敗（到期時間設為 t+60s）；在 t=58s 時句子 B 失敗，但因 `??=` 使得 `_failedUntil` 仍為 t+60s。到了 t+60s 若有新請求觸發，`_failed.clear()` 會將剛失敗 2 秒的句子 B 一併清除並提早重試，破壞 60 秒冷卻防護。
- **具體修正**：改用 `Map<String, DateTime> _failed` 分別記錄每個字串的重試期限，並在 `request()` 中依據該字串專屬的時間戳進行比對與過期清除。

---

### 4. 搜尋面板卡片譯文未跳過繁簡轉換
- **位置**：`lib/pages/search_panel/live/widgets/item.dart:715`、`lib/pages/search_panel/pgc/widgets/item.dart:779`
- **問題**：違反 AC-1 / AC-8 / 審查紀錄 3。這兩處在 `translated` 為 true 時回傳 `Text(shown!)`（使用的是 `zh_text.dart` 的 `Text`），而非 Flutter 原生 `flutter.Text`。
- **具體失敗情境**：翻譯後的純英文內容仍會傳入 `ZhConvert.convert()` 進行全文字典比對與 OpenCC 處理，造成無謂效能浪費；若譯文中含有符合字典鍵值的特殊字元，可能導致非預期的文字置換。
- **具體修正**：引入 `flutter/widgets.dart as flutter`，並將上述兩處的 `Text(shown!)` 替換為 `flutter.Text(shown!)`。
