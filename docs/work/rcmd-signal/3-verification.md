# 驗證：改善推薦訊號回傳（rcmd-signal）

日期：2026-11-07
環境：模擬器 `Medium_Phone_API_37.0`（`-memory 2048`），debug 版 `com.example.piliplus.debug`，使用者登入後手動操作，Claude 監看 `adb logcat -s flutter:I`。

## AC 對照

| AC | 結果 | 證據 |
|---|---|---|
| AC-1 推薦入口送 App 心跳並帶 track_id | 通過 | `13:09:48 heartBeatMobile START code=0 trackId非空=true aid=117450712620900 cid=42795142354`；`13:10:06 heartBeatMobile END code=0 trackId非空=true`（同 aid／cid） |
| AC-2 其他入口 track_id 為空 | 通過 | `13:10:11 heartBeatMobile START code=0 trackId非空=false aid=117456014153249 cid=42820438093`、`13:10:21 END code=0 trackId非空=false`；`13:10:38 START code=0 trackId非空=false aid=117155970550014`（使用者確認從搜尋頁進入） |
| AC-3 累計欄位計算 | 部分：伺服器接受（code 0），欄位數值未逐一檢查 | 同上 log；計算邏輯見 `lib/plugin/pl_player/utils/mobile_heartbeat.dart` |
| AC-4 web 心跳與觀看紀錄不變 | 未驗證（程式碼未改 `VideoHttp.heartBeat`） | — |
| AC-5 推薦請求身分一致、無假 fp | 通過 | logcat 中 feed/index 請求為 `mobi_app=android_hd`、`build=2001100`、`statistics` appId 5；header 改用 `DeviceFp` |
| AC-6 推薦列表正常 | 通過 | `feed-identity-check.txt`（code 0、20 張卡片）；模擬器首頁推薦正常載入 |
| AC-7 失敗不影響播放 | 未驗證（無失敗案例） | 程式碼 try/catch |
| AC-8 analyze | 通過 | `analyze.txt`：0 error、0 warning |

## 審查

- 規格審查：agy，4 條全部採用（見 `2-spec.md` 審查紀錄）。
- 實作 diff 審查：未做（使用者未要求）。

## 已知限制

- 推薦是否變準需長期觀察，無法從客戶端證明。
- 模擬器的 CDN DNS 失敗、硬解錯誤為環境問題，與本次修改無關。
