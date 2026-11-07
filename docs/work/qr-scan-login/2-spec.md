# 規格：「我的」頁掃描 QR code（qr-scan-login）

需求：[1-requirements.md](1-requirements.md)

## 設計

### 相依與權限

- `flutter pub add mobile_scanner`（用當時最新穩定版；Android 使用內建 ML Kit 模型）。確認它對 `minSdk` 的要求與專案相容（`android/app/build.gradle*` 的 `minSdk = flutter.minSdkVersion`）；不相容時停下回報。
- `android/app/src/main/AndroidManifest.xml` 加 `<uses-permission android:name="android.permission.CAMERA" />`，以及 `<uses-feature android:name="android.hardware.camera" android:required="false" />`（避免沒有相機的裝置被商店過濾）。
- 從相簿選圖用專案已有的 `image_picker`（`pubspec.yaml:127`）。

### 進入點（T-1）

`lib/pages/mine/view.dart` 右側按鈕列（`right: Row(... children: [...])`，約 :163）最前面加一個 `IconButton`：

- 圖示 `Icons.qr_code_scanner`，tooltip「掃描」，沿用同列的 `iconSize`、`padding`、`style`。
- 只在 `Platform.isAndroid` 時顯示。
- `onPressed: () => Get.toNamed('/scan')`。
- `lib/router/app_pages.dart` 註冊 `GetPage(name: '/scan', page: () => const ScanPage())`。

### 掃描頁（T-1）

新檔 `lib/pages/scan/view.dart`（`ScanPage`）：

- 全螢幕 `MobileScanner`，`MobileScannerController(formats: [BarcodeFormat.qrCode], detectionSpeed: DetectionSpeed.noDuplicates)`。
- 上方 AppBar（透明）：返回、標題「掃描 QR code」、手電筒切換、「相簿」按鈕。
- 中央半透明遮罩加方框提示「將 QR code 放入框內」。
- `errorBuilder`：權限被拒或相機錯誤時，顯示說明「無法使用相機，請到系統設定允許相機權限，或從相簿選擇圖片」，不閃退；「相簿」按鈕仍可用。
- 相簿：`ImagePicker().pickImage(source: gallery)` → `controller.analyzeImage(path)`；結果為 null 或沒有 barcode 時 `SmartDialog.showToast('未辨識到 QR code')`。
- 防重複：`bool _handling`；取得第一個非空的 `rawValue` 後設為 true、`controller.stop()`，交給 `QrScanHandler.handle(value)`。
  - 結果是「跳到其他頁面」（網頁版登入、其他網址）：handler 先 `Get.back()` 關閉掃描頁，再開新頁（路由跳轉會立即返回，不等新頁關閉，所以不能在掃描頁等待後重啟相機）。
  - 結果是「對話框或 toast」（電視登入、未登入提示、一般文字、相簿未辨識）：對話框關閉後仍在掃描頁，重設 `_handling = false` 並 `controller.start()`。
  - handler 回傳值表示是否已離開掃描頁（例如 `Future<bool> handle(String)`，true 表示已離開）。
- dispose 時釋放 controller。

### 結果處理（T-2）

新檔 `lib/pages/scan/handler.dart`（`QrScanHandler`）。依序判斷 `value`：

1. **電視／盒子登入**：`Uri.tryParse(value)` 成功、host 為 `passport.bilibili.com`、query 有 `auth_code`。
   - 未登入（`!Accounts.main.isLogin`）→ toast「請先登入」。
   - 否則顯示確認對話框：標題「登入確認」，內容「要用目前帳號（{名稱}）登入其他裝置嗎？」，按鈕「取消」「確認登入」。帳號名稱取現有的使用者資訊（例如 `MineController` 或 `Accounts.main` 可取得的 uname；取不到就顯示 mid）。
   - 確認後呼叫新函式 `LoginHttp.confirmTvQrcode(authCode)`：`POST Api.qrcodeConfirm`（`lib/http/api.dart:625`，已存在未使用），form 參數 `auth_code`、`build: 7082000`、`csrf: Accounts.main.csrf`，沿用 `LoginHttp` 既有慣例直接 `Request().post`（預設帶主帳號；`lib/pages/login/controller.dart:195` 的 `AnonymousAccount` 是刻意不帶帳號，不要照抄）。
   - `code == 0` → toast「登入成功」；否則 toast 伺服器 `message`（例如「二維碼已失效」）。網路錯誤 → toast 錯誤訊息。
2. **網頁版登入**：query 有 `qrcode_key`（host 為 `*.bilibili.com`）。
   - 未登入 → toast「請先登入」。
   - 否則 `await LoginUtils.setWebCookie(Accounts.main)`，再用 `Get.to(() => WebviewPage(url: value))` 開啟（`WebviewPage` 有 `url` 建構參數；不要用 `parameters`，GetX 會拆掉網址中的 `?`、`&`，使 `qrcode_key` 遺失）。
3. **其他 http(s) 網址**：先確認 `Uri.tryParse(value)` 的 scheme 是 `http` 或 `https`（`routePushFromUrl` 會替非網址字串補 `https://`，不能拿它判斷）。是網址才 `PiliScheme.routePushFromUrl(value)`；回傳 false 時用 `Get.to(() => WebviewPage(url: value))`。
4. **一般文字**：對話框顯示文字（可選取），按鈕「複製」（`Utils.copyText` 或 `Clipboard.setData` + toast「已複製」）與「關閉」。

## 任務

| 任務 | 內容 | 檔案 | 相依 |
|---|---|---|---|
| T-1 | 相依套件、權限、入口按鈕、路由、掃描頁 | `pubspec.yaml`、`pubspec.lock`、`android/app/src/main/AndroidManifest.xml`、`lib/pages/mine/view.dart`、`lib/router/app_pages.dart`、`lib/pages/scan/view.dart`（新） | 無 |
| T-2 | 結果處理與電視登入確認 API | `lib/pages/scan/handler.dart`（新）、`lib/http/login.dart` | T-1 的頁面呼叫介面（`QrScanHandler.handle(String) → Future<void>`） |

T-1、T-2 交給同一個 Sonnet 子代理依序完成。

## AC 驗證方式

| AC | 方式 |
|---|---|
| AC-1、AC-2、AC-3、AC-8 | diff 審查；模擬器手動（相機可用模擬器虛擬場景或相簿圖片） |
| AC-4 | 使用者實機掃電視／盒子 QR code（待使用者測試）；可用專案自己的 TV 登入 QR（`Api.getTVCode` 產生的 url）在另一裝置顯示來測 |
| AC-5 | 使用者用電腦開 www.bilibili.com 登入頁掃描（待使用者測試） |
| AC-6、AC-7 | diff 審查；模擬器相簿圖片測試 |
| AC-9 | `flutter analyze`、`flutter build apk --release --split-per-abi` |

## 邊界情況與風險

- `mobile_scanner` 的 Android 版本需求可能高於專案 `minSdk`：不相容時回報，不自行調高。
- WebView 開網頁版確認頁時 cookie 尚未寫入：先 `await setWebCookie` 再開頁。
- 確認 API 回傳 `-101`（未登入）或 `86038`（過期）：顯示伺服器訊息。
- 掃描頁在背景時相機資源：`MobileScanner` 會跟隨生命週期；若需要，於 `AppLifecycleState` 停止／啟動。
- 回退：移除按鈕與路由即可；套件與權限可一併移除。

## 審查紀錄

agy（gemini-3.8-flash-high）2026-11-07，4 條全部採用：

1. 一般文字會被 `routePushFromUrl` 補 `https://` 後開 WebView：先判斷 scheme 是 http(s)。
2. `Get.toNamed(parameters:)` 會截斷含 `?`、`&` 的網址：改用 `WebviewPage(url:)` 建構參數。
3. 路由跳轉立即返回，相機會在新頁開啟時重啟：跳頁前先關閉掃描頁；只有對話框情況才重啟相機。
4. 錯誤參照 `AnonymousAccount` 用法：改為沿用 `LoginHttp` 預設帳號。

## 實作偏差

- 對話框改用 `showDialog(context: Get.context!)`，因專案的 GetX 版本沒有 `Get.dialog`。
- `confirmTvQrcode` 回傳 `({bool success, String msg})`，錯誤在函式內攔截。
