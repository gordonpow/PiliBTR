# 需求：錯誤／建議回報（寄到開發者信箱）

## 目標
讓 PiliBTR 使用者在 App 內直接送出錯誤回報或建議（附日誌，可加文字描述），開發者在 Gmail 收到信，並能從信件分辨來自 PiliBTR 還是 PiliBTRTV。

## 做法（使用者 2026-11-10 選定）
沿用 PiliBTRTV 的 Google Apps Script 代寄（`kReportScriptUrl` 同一個 `/exec` 網址）。App 內不放任何信箱密碼或金鑰。

## 驗收條件
- AC-1：設定 → 關於，有「回報錯誤／建議」項目；錯誤日誌頁右上也有回報入口。點了開啟回報頁。
- AC-2：回報頁可選類型（錯誤回報、功能建議、其他），有多行文字描述（選填），有「附上錯誤日誌」開關（預設開）。描述空白且不附日誌時不能送出。
- AC-3：送出時 POST JSON 到腳本：`app: "PiliBTR"`、6 碼 `id`、`installId`、`category`、`version`（`btrVersion`）、`device`、`android`、`report`。`report` 開頭是 App 名稱、版本、裝置、時間、描述，之後是日誌（UTF-8 超過 400 KB 時保留頭尾、中間截斷）。
- AC-4：送出成功時顯示回報編號；失敗時顯示原因（網路、逾時、太頻繁、今日額度用完、其他）。送出中按鈕停用，不會重複送出。
- AC-5：腳本更新並重新部署後，PiliBTR 的信件標題是「[PiliBTR 回報 編號] …」，PiliBTRTV（不帶 `app`）仍是「[PiliBTRTV 回報 編號] …」。

## 不做
- PiliBTRTV 端的修改（TV 端不送 `app`，腳本預設值即為 PiliBTRTV）。
- 回報狀態查詢（TV 的 report_status.json 機制）、回報紀錄列表、截圖附件、聯絡信箱欄位。
- 新介面文字的英文語言包（未翻譯的字串沿用中文）。

## 限制
- 腳本限制：同一裝置每小時 5 封、全部每小時 30 封（兩個 App 共用）、單封約 1 MB。
- 介面文字繁體中文（台灣用語）。
- 腳本改動要使用者在 script.google.com 重新部署（「管理部署作業」→ 編輯 → 新版本，網址不變）。
