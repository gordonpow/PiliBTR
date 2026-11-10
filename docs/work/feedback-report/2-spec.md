# 規格：錯誤／建議回報

## 設計
- `lib/services/feedback_report.dart`（新增）
  - `const kReportScriptUrl`：與 PiliBTRTV `lib/config/report_config.dart` 相同網址。
  - `enum FeedbackCategory { bug('錯誤回報'), suggestion('功能建議'), other('其他') }`
  - 回報編號產生、UTF-8 截斷、腳本回應解析、錯誤碼對應訊息：移植 PiliBTRTV `lib/services/report_send_service.dart`（`generateReportId`、`truncateReportBytes`、`parseScriptResponse`、`reportErrorMessage`、`isRedirectStatus`）。
  - `installId`：16 碼隨機，存在 `GStorage.setting`（新的 key，例如 `feedbackInstallId`），不用 shared_preferences。
  - 裝置資訊：`device_info_plus`（Android：`manufacturer model`、`Android version.release (SDK sdkInt)`；其他平台給平台名稱）。
  - 日誌：讀 `LoggerUtils.getLogsPath()` 的內容（每行一筆 JSON），由新到舊排列，格式化成可讀文字（每筆至少含時間與錯誤／stack；解析失敗就放原始行）。
  - `send()`：用 `dio`（專案已有）或 `dart:io HttpClient` 送 POST，`Content-Type: text/plain;charset=utf-8`，不自動跟隨 302；收到 302 時 GET `Location` 取 JSON，GET 失敗視為已送出（同 TV）。逾時 20 秒。
- `lib/pages/feedback/view.dart`（新增）：回報頁（AC-2、AC-4）。成功對話框顯示編號（可複製）並關閉頁面。
- 路由：`lib/router/app_pages.dart` 加 `/feedback`。
- 入口：`lib/pages/about/view.dart` 在「問題反饋」旁新增「回報錯誤／建議」；`lib/pages/setting/pages/logs.dart` AppBar 加按鈕。
- 腳本：`C:\presonal_project\PiliBTRTV\docs\report-gmail\apps_script.gs`：`const app = s(d.app) || 'PiliBTRTV';` 標題 `'[' + app + ' 回報 ' + id + '] ...'`，內文加「App：」行；PiliBTRTV README 補一句。

## 任務
- T-1：service + 頁面 + 路由 + 入口（PiliPlus）。
- T-2：腳本與 README（PiliBTRTV，只改 docs，不 commit）。Opus 自己做。

## 驗證
- analyze 0 issue；建置 debug APK。
- AC-5：使用者重新部署後，用 curl 送 `app: "PiliBTR"` 測試信確認標題。
- 功能：使用者實測。

## 風險
- 腳本未重新部署前，PiliBTR 的信標題會寫 PiliBTRTV；`report` 內文開頭仍有「App：PiliBTR」可分辨。
- 共用頻率上限（每小時 30 封）。
