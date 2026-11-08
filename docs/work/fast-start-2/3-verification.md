# 驗證：快速開播第二階段（fast-start-2）

對應規格：[2-spec.md](2-spec.md)　日期：2026-11-08  
原始量測：[emulator-results.md](emulator-results.md)　原始 Log：[emulator-log.txt](emulator-log.txt)

## 環境

- Debug 版 APK：`flutter build apk --debug --target-platform android-x64`（EXIT 0）。
- 模擬器：AVD `Medium_Phone_API_37.0`，覆蓋安裝，保留登入狀態，未改動設定。
- 量測限制：模擬器網路與 DNS 走宿主機，與實機環境不同；OPEN-TIME 記錄早於實際畫面解碼出圖（例如 #8 OPEN-TIME 記 1318 ms，但 10 秒截圖全黑），數據存在低估。

## 自動檢查

| 檢查 | 指令 | 結果 |
|---|---|---|
| 靜態分析 | `flutter analyze` | 通過（39 infos, 0 errors, 0 warnings，執行於 2026-11-08） |
| 建置 | `flutter build apk --debug --target-platform android-x64` | 通過（EXIT 0） |

## AC 對照表

| AC | 結果 | 證據（Log / 檔案依據） |
|---|---|---|
| AC-1 首頁推薦可見卡片預取 playurl（最多 6 張、併發 2） | 部分 | `emulator-log.txt` 含 24 筆 `PlayUrlCache visible prefetch bvid=... cid=...`（如 18:34:33 兩兩併發發送）；web 端推薦未驗證。 |
| AC-2 playurl 快取 10 分鐘、最多 30 筆、去重 | 部分 | Log 出現 `PlayUrlCache hit bvid=...`（12 次開啟均有 hit 行）；同 key 重開（#11、#12）playurl 請求數為 0；10 分鐘 TTL 與 30 筆上限無 Log 證據。 |
| AC-3 風控 412 / -412 / -352 退避 5 分鐘 | 未驗證 | Log 中全程未出現 412 等風控錯誤代碼，無退避觸發之 Log 證據。 |
| AC-4 tap-down 預熱首 512 KB，開檔記憶體直讀 | 部分 | Log 含 `BTR: warm start` 與 `warm hit`（#3 命中 `455227,524288`、#5 命中 `524288,524288` bytes）；但有 11 行 `warm failed ... request cancelled`，閒置 30 秒丟棄無 Log 證據。 |
| AC-5 CDN 預連線（bytes=0-0）、連線逾時 60 秒 | 部分 | Log 出現 6 行 `BTR: preconnect <host>`（如 `upos-sz-mirrorcosov.bilivideo.com`）；60 秒連線逾時無 Log 證據。 |
| AC-6 開頭 0.8 秒 hedge 競速，勝者採用，敗者取消不計失敗 | 部分 | Log 含 25 次 `BTR: hedge start` 及落敗取消的 `DioException [request cancelled]`；但 `BTR: hedge win` 為 0 次（無勝出記錄）。 |
| AC-7 BTR 關閉時功能退回 | 未驗證 | 本次模擬器測試全程開啟 BTR，未採集關閉 BTR 之 Log 證據。 |
| AC-8 離開首頁或進背景停止排程預取 | 未驗證 | Log 中無顯式停止預取的 Log 輸出，背景凍結無直接 Log 記錄。 |
| AC-9 flutter analyze 無新增錯誤或警告 | 通過 | 2026-11-08 執行結果：39 infos, 0 errors, 0 warnings。 |

## 量測結果

### 開播耗時統計（OPEN-TIME ms）與 Phase 1 對比

- **Phase 1 基準（11 次）**：min 219 / 中位數 999 / max 2688 ms；≤500 ms 共 3 次。
- **Phase 2 總體（12 次）**：min 182 / 中位數 698.0 / max 1834 ms；≤500 ms 共 3 次（#1 357、#11 294、#12 182 ms；#3 為 505 ms）。
  - 中位數自 999 ms 降至 698 ms（改善約 30%），最大值自 2688 ms 降至 1834 ms。
  - **目標達成情況**：模擬器環境中位數為 698 ms，**未達成 0.5 秒目標**。
- **分情境統計**：
  - 情境 A（停止捲動等 2 秒後點擊）：min 357 / 中位數 589.0 / max 1197 ms（n=4，≤500 ms：1 次）。
  - 情境 B（捲動後立即點擊）：min 568 / 中位數 723 / max 974 ms（n=3，≤500 ms：0 次）。
  - 情境 C（快速捲動點擊未預取卡片）：min 1315 / 中位數 1318 / max 1834 ms（n=3，≤500 ms：0 次）。
  - 情境 R（同影片重開）：min 182 / 中位數 238.0 / max 294 ms（n=2，≤500 ms：2 次）。

### 機制觀察

- **visible prefetch**：觸發 24 筆，停止捲動後以 2 筆併發發出；A、B、R 情境點擊前均已預取完成。
- **BTR preconnect**：觸發 6 行（#1、#5、#9 均有記錄）。
- **warm hit**：#3 命中 455227/524288 bytes，#5 命中 524288/524288 bytes；其餘未命中。
- **hedge**：啟動 25 次（點擊後段佔 14 次），但 `hedge win` 0 次（無 hedge 節點率先抵達）。

### 觀察到的問題

1. **fallback 與封鎖**：出現 4 次 `BTR: fallback to original URL at 0: head piece failed`（#6、#10、#11）；`node banned` 2 次、`host banned 10 min upos-sz-mirrorali` 1 次。
2. **預熱過早取消**：出現 11 行 `warm failed ... request cancelled`，預熱資料常被取消。
3. **解碼錯誤**：出現 18 行 `ffmpeg: amediacodec: MediaCodec$CodecException` 硬解異常（模擬器環境特徵）。

## 審查結果

依據 [review-impl-btr.md](review-impl-btr.md) 與 [review-impl-app.md](review-impl-app.md)，所有審查缺失均已修正：
- BTR：修正 hedge 勝出時 primary 遭誤判 slow 降速、未滿 2 秒 hedge 誤判 slow、tap-down 綁定預覽開關導致關閉預覽時預熱失效、以及 LRU 淘汰時強制釋放讀取中 buffer 的問題。
- App：移除 Release 模式下拋錯的 `grid.debugNeedsLayout`、在 `_RcmdPageState.dispose()` 補上 `clearPending()`、將 `prefetchVisible` 改為 async 增加參數比對防禦網路切換。

## 已知限制與待辦

1. **實機驗證（待使用者測試）**：模擬器網路、DNS 與硬解不同於真實手機，真實開播時間與 0.5 秒達標情況需實機量測。
2. **首幀出圖精確量測**：OPEN-TIME 早於實際畫面渲染，後續評估需依據真實可見畫面的測量工具。
3. **風控與關閉 BTR 驗證**：AC-3（412 退避）與 AC-7（BTR 關閉情境）未在本次量測觸發，待補測。
