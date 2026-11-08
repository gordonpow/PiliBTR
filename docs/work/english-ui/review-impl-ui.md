1. `lib/pages/setting/models/style_settings.dart:368-370`
- **問題**：在 `Navigator.pop()` 後立即呼叫 `status.dispose()` 與 `progress.dispose()`。
- **具體失敗情境**：`Navigator.pop()` 僅觸發路由退場動畫，對話框中的 `ValueListenableBuilder` 尚未自元件樹卸載。下一個 frame 或元件 dispose 觸發 `removeListener` 時，會拋出 `FlutterError: A ValueNotifier was used after being disposed` 導致除錯模式崩潰。
- **具體修復方式**：將進度對話框改為有狀態元件（`StatefulWidget`）由其 `State.dispose` 負責清理，或等待路由退場 Future 完成後再 dispose。

2. `lib/utils/i18n_pack.dart:668`
- **問題**：Windows 上 `File.rename` 在目標檔案已存在時會拋出例外。
- **具體失敗情境**：已下載過語言包的使用者點擊「更新語言包」或背景更新時，因 `en.json` 已存在，`tmp.rename(file.path)` 在 Windows 拋出 `FileSystemException (errno = 183)`，更新永遠失敗。
- **具體修復方式**：重新命名更換前先檢查並刪除舊檔：
  ```dart
  if (await file.exists()) await file.delete();
  await tmp.rename(file.path);
  ```

3. `lib/pages/setting/models/style_settings.dart:304-307`
- **問題**：切換為英文時無條件呼叫 `_downloadEnglishPack` 強制聯網下載。
- **具體失敗情境**：使用者先前已下載語言包，切換至中文後於離線狀態（如飛航模式）欲切回英文，因連線失敗跳出提示並中斷切換，無法依需求 AC-1「下載後離線使用」。
- **具體修復方式**：下載前先檢查本機 `en.json` 是否存在且有效，若已有本機語言包則直接 `load()` 並允許切換，僅在無本機包時強制聯網。

4. `lib/common/widgets/zh_material_widgets.dart:64-188`
- **問題**：`IconButton` 包裝元件遺漏 `IconButton.filled` 與 `IconButton.filledTonal` 建構子。
- **具體失敗情境**：`zh_material.dart` 隱藏了 `material_ui` 原生 `IconButton`，全域程式碼一旦呼叫 `IconButton.filled` 或 `IconButton.filledTonal` 即編譯錯誤。
- **具體修復方式**：補齊 `IconButton.filled` 與 `IconButton.filledTonal` 建構子並轉發至 `super.filled()` / `super.filledTonal()`。

5. `lib/services/translate/translator.dart:201`
- **問題**：Google Cloud Translation 金鑰透過 URL Query Parameter 傳遞。
- **具體失敗情境**：請求超時或出錯時，`DioException.requestOptions.uri` 包含完整 URL，經 Catcher2 或 logger 輸出至紀錄檔，造成金鑰明文洩漏。
- **具體修復方式**：改用 HTTP Header 傳遞金鑰：`options: Options(headers: {'X-goog-api-key': googleApiKey})`。

6. `lib/services/translate/translator.dart:244, 316`
- **問題**：模型狀態判定與刪除只針對 `_zh`，忽略 `_en`。
- **具體失敗情境**：使用者於設定中點擊「刪除離線翻譯模型」，僅刪除中文模型，約 30 MB 的英文模型永久殘留佔用磁碟；且若 `_en` 未下載成功，`isOfflineReady()` 仍誤判為 true。
- **具體修復方式**：`isOfflineReady` 需同時檢查 `_zh` 與 `_en`；`deleteModel` 需依序刪除 `_zh` 與 `_en` 兩個模型。

7. `lib/utils/zh_convert.dart:104`
- **問題**：`_table.isEmpty` 會直接 return 原文。
- **具體失敗情境**：若繁簡轉換字典載入失敗或處於無 assets 的測試環境，即使英文語言包已成功載入，`convert()` 仍於開頭直接中斷，完全無法顯示英文介面。
- **具體修復方式**：在 `script == ZhScript.english` 時先執行 `I18nPack.translate`，未命中退回繁體時才受 `_table.isEmpty` 防護。
