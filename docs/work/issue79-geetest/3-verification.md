# 驗證：issue #79 極驗驗證碼全黑、縮小視窗殘留

日期：2026-11-08。環境：模擬器 Medium_Phone_API_37.0（直向 1080x2400），debug x64 版。

## 原因
- 極驗載入前對話框只有空白 WebView，深色模式下全黑、只剩左上 X；載入失敗、gettype 錯誤只印 log，沒有逾時；JS 使用 arrow function 與 `?.`，舊版 Android WebView 會語法錯誤。
- 使用者截圖的「影片頁與縮小視窗同畫面」：`MiniPlayer._removeEntry` 依 `OverlayEntry.mounted` 決定是否 remove，entry 已插入但尚未 build 時只 dispose 不 remove（log：`An OverlayEntry must first be removed from the Overlay before dispose is called`），entry 殘留。

## 驗收對照
| 項目 | 結果 | 證據 |
|---|---|---|
| 載入中顯示轉圈與「驗證碼載入中…」（淺色／深色） | 通過 | 模擬器截圖 A1b_3、A2d_8 |
| 極驗就緒後提示消失、滑塊出現 | 通過 | A1b_8、A1_t10 |
| 腳本網址不可達時顯示錯誤、重試、關閉 | 通過 | 測試版 APK（網址改 10.255.255.1）：A3_w1、A3_retry1/2、A3_afterclose |
| 關閉按鈕深色背景可見；X 只關對話框不退出登入頁 | 通過 | 3 次（載入中、檢測中、滑塊出現後）皆停在登入頁 |
| JS 為 ES5 | 通過 | 程式碼審查（Object.assign 已改 for-in） |
| 快速進出影片後縮小視窗不殘留 | 通過 | 3 輪重現步驟皆消失，log 0 筆 assertion |
| 長按 CC 跳出複製選單（之前修正） | 通過 | B3_long_on_menu |
| 快速連點影片不跳 DmSegMobile 提示（之前修正） | 通過 | 無 toast；彈幕顯示因模擬器網路慢未驗證 |
| 單點 CC、關閉設定後長按、子母畫面 AC-7/8 | 未驗證 | 模擬器座標操作不穩定、影片載入慢 |

## 審查
Sonnet diff 審查 4 條：採用 1 條（`Object.assign` 非 ES5）；不採用 3 條（retry 時舊頁回呼競態、`_html` 在 setState 外賦值、Linux 多餘 rebuild，皆低風險）。

## 靜態分析
`flutter analyze`：0 error、0 warning（info 皆在未修改檔案）。
