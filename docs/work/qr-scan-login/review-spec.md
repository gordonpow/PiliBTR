依據需求與現有程式碼審查規格，發現以下 4 項實質問題（由重至輕排列）：

### 1. 純文字判斷順序錯誤，導致「一般文字」永遠無法觸發（違反 AC-7）
- **規格章節**：結果處理（T-2）第 3、4 點。
- **問題**：規格在第 3 點直接執行 `PiliScheme.routePushFromUrl(value)`，並規定「回傳 false 時改用 `/webview` 開啟」，完全未先驗證 `value` 是否為網址。掃到純文字或條碼時，也會強制以 WebView 開啟，永遠無法走到第 4 點（顯示純文字與複製按鈕）。
- **原因與證據**：[`lib/utils/app_scheme.dart:88-90, 99-101`](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/utils/app_scheme.dart#L88-L90) 會將非 URL 字串強行加上 `https://` 前綴嘗試解析，失敗時 catch 回傳 `false`；規格在回傳 `false` 時開 `/webview`，造成 [`lib/pages/webview/view.dart:63`](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/webview/view.dart#L63) 載入非法網址。
- **修復方式**：在第 3 點前加入正規 URL 驗證（如 `final uri = Uri.tryParse(value); if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https'))`），確定為 HTTP(S) 才走路由與 WebView，其餘直接進入第 4 點文字對話框。

---

### 2. WebView 傳參方式會破壞網址 Query，導致網頁登入失敗（違反 AC-5）
- **規格章節**：結果處理（T-2）第 2 點（網頁版登入）。
- **問題**：規格要求以 `Get.toNamed('/webview', parameters: {'url': value})` 傳遞含 `qrcode_key` 的網址。GetX 拼接路由 query 時未編碼的 `?` 與 `&` 會被提前拆解，造成 `parameters['url']` 被截斷而遺失登入 key。
- **原因與證據**：[`lib/pages/webview/view.dart:62-63`](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/webview/view.dart#L62-L63) 依賴 `parameters['url']!` 解析網址，但頁面同時原生支援構造參數 `widget.url`（[`lib/pages/webview/view.dart:34, 42`](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/webview/view.dart#L34-L42)）。
- **修復方式**：改用更簡潔穩定的 `Get.to(() => WebviewPage(url: value))`，直接傳入未受 query 解析破壞的完整 URL。

---

### 3. 路由跳轉非同步返回，造成相機並發掃描與資源浪費（違反 AC-8）
- **規格章節**：掃描頁（T-1）防重複機制與結果處理。
- **問題**：規格假設「處理結束（頁面跳轉返回）後若仍在掃描頁，重設 `_handling = false` 並 `controller.start()`」。但外部路由跳轉會立即回傳，不會等待目標頁面關閉，導致新頁面開啟時底層掃描頁相機立即重啟並重複觸發。
- **原因與證據**：[`lib/utils/app_scheme.dart:105-126`](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/utils/app_scheme.dart#L105-L126) 的 `routePush` 在完成 `Get.toNamed` 後立即 `return true`；且 Flutter 跳轉新頁不會觸發系統級生命週期暫停。
- **修復方式**：跳轉至其他頁面時直接以 `Get.offNamed` 關閉掃描頁，或參考 [`lib/pages/webview/view.dart:48, 75-77`](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/webview/view.dart#L48) 透過 `RouteAware` 在 `didPushNext` / `didPopNext` 管理相機暫停與重啟。

---

### 4. 錯誤引用主帳號 Extra 參數範例（設計誤解）
- **規格章節**：結果處理（T-2）第 1 點。
- **問題**：規格寫「必要時在 Options(extra: {'account': Accounts.main})，參考 `controller.dart:195` 的用法」。該處引用恰恰是為了「隔離主帳號」而設計，誤導了認證機制的實作。
- **原因與證據**：[`lib/pages/login/controller.dart:195`](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/pages/login/controller.dart#L195) 傳入的是 `AnonymousAccount()` 以避免帶入現有登入 Cookie；而專案在 [`lib/http/login.dart:42, 62`](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/http/login.dart#L42-L62) 中發起請求時，預設即自動掛載主帳號資訊。
- **修復方式**：移除對 `controller.dart:195` 的參照描述，維持 `LoginHttp` 原有慣例直接呼叫 `Request().post`。
