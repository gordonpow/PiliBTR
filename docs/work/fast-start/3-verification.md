# 驗證：點開影片快速開播（fast-start）

需求：[1-requirements.md](1-requirements.md)　規格：[2-spec.md](2-spec.md)
原始 log：[emulator-log.txt](emulator-log.txt)　播放截圖：[emulator-playing.png](emulator-playing.png)

## 環境

- Debug 版 APK：`flutter build apk --debug --target-platform android-x64`，結果 `EXIT 0`（`build/app/outputs/flutter-apk/app-debug.apk`）。
- 模擬器：AVD `Medium_Phone_API_37.0`，`-memory 2048 -no-snapshot-save`，1080x2400。
- 套件 `com.example.piliplus.debug`，用 `adb install -r` 覆蓋安裝（未解除安裝，已登入狀態保留）。
- 沒有修改任何設定（未關閉硬解）。本次測試中影片仍能播出（見截圖），但 log 出現 `h264_mediacodec: Failed to flush codec`，見「觀察到的問題」。
- 測試方式：`adb logcat -c` → `input tap` 首頁推薦卡片 → 等 10 秒（open1 等 12 秒）→ 以 `flutter` tag 過濾 → `BACK`。
- **模擬器網路與 DNS 和實機不同**（模擬器走主機網路、部分 CDN host DNS 失敗或連線逾時），本結果不能直接代表實機開播時間。

## 每次開啟的結果

playurl 次數 = log 中 `api.bilibili.com/x/player/wbi/playurl` 的 uri 行數 / 2（Request 與 Response 各印一次）。

| # | 情境 | OPEN-TIME | BTR head first byte（host） | playurl 次數 | PlayUrlCache hit | fallback / ban / timeout |
|---|---|---|---|---|---|---|
| 1 | 卡片 1 | 937 ms | 918 ms（cosov）、1145 ms（cosov）、1986 ms（hw） | 1 | 無 hit 行 | 無 |
| 2 | 卡片 2 | 469 ms | 1306 ms（hw）、502 ms（cosov，在 coso1 2040 ms 無首 byte 後切換） | 0（hit） | 是 | head switch 一次 |
| 3 | 卡片 3 | 926 ms | 1037 ms、1001 ms（estgoss；coso1 2082 / 2052 ms 無首 byte 後切換） | 1 | 是（等進行中的 prefetch） | head switch 兩次 |
| 4 | 卡片 4 | 1476 ms | 1333 ms（cosov）、1439 ms（estgoss） | 1 | 是（等進行中的 prefetch） | 無 |
| 5 | 卡片 5 | 1619 ms | 1113 ms（akamaized）、1866 ms（cosov） | 1 | 是（等進行中的 prefetch） | 無 |
| 6 | 卡片 6 | 999 ms | 1573 ms（cosov；coso1 2029 ms 無首 byte 後切換） | 1 | 是（等進行中的 prefetch） | head switch 兩次 |
| 7 | 捲動後卡片 A（與 #1 同影片，間隔 > 60 秒） | 2688 ms | 無 first byte 行；estgoss 2102 ms、cos 2272 ms 無首 byte，連續切換 | 1 | 無 hit 行 | head switch 兩次 |
| 8 | 捲動後卡片 B | 2079 ms | 1065 ms（cosov）；estgoss 2100 ms、cos 2145 ms、14b 2140 ms、hw 2052 ms 無首 byte | 1 | 無 hit 行 | head switch 多次 |
| 9 | 同 #8 影片，第 1 次重開 | 470 ms | 1670 ms（bos）；14b 2062 ms、hw 2142 ms 無首 byte | 0（hit） | 是 | head switch 多次 |
| 10 | 同 #8 影片，第 2 次重開 | 219 ms | log 窗口內無 BTR 行 | 0（hit） | 是 | 無 |
| 11 | 首頁閒置 > 60 秒後開卡片 | 1234 ms | 1258 ms（cos）、988 ms（cosov）；cos 2074 ms 無首 byte 後切換 | 1 | 無 hit 行 | head switch 一次 |

另有一輪未存檔的探測（先用較雜的過濾條件，log 已覆寫）：第一次開卡片 1 為 5809 ms；`BTR: host banned 10 min upos-sz-mirrorali`、`BTR: node banned upos-sz-mirror08c`（DNS 失敗 `Failed host lookup`）、`BTR: hedge piece` 有出現；同影片重開 111 ms（hit）。這幾筆不計入下方統計。全部存檔 log 中沒有 `BTR: fallback to original URL`，也沒有 `OPEN-TIME first frame timeout 8 s`。

## 統計（11 次存檔開啟）

- 最小 219 ms、中位數 999 ms、最大 2688 ms。
- 小於等於 500 ms：3 / 11（#2、#9、#10，皆為快取命中的情境，其中 #10 是同影片第二次重開）。
- **0.5 秒目標：在此模擬器環境未達成**（中位數約 1.0 秒）。實機結果待使用者測試。
- 非快取命中或需等 prefetch 的開啟（#1、#3 至 #8、#11）：926 至 2688 ms。

## 剩餘時間的主要來源（依 log 判斷）

1. playurl 往返：#1 uri 時間 30.378 到 30.883（約 0.5 秒）、#4 約 0.75 秒、#5 約 1.0 秒、#7 約 1.6 秒；OPEN-TIME 與此高度相關，快取命中（0 次 playurl）時降到 219 至 470 ms。這是最大的可見因素。
2. BTR 首 byte：多數 head 要 0.9 至 2 秒，且常見「2 秒無首 byte 後切節點」（約 2.0 至 2.3 秒）。但這些 log 行多半在 OPEN-TIME 行之後才出現，所以 OPEN-TIME 沒有算進去，會影響實際出圖時間。
3. 解碼：截圖流程顯示，#11 在 OPEN-TIME 記為 1234 ms 的情況下，10 秒時畫面仍是黑的，再過約 8 至 10 秒（點擊後約 20 秒內）才有畫面（見下）。

## AC 對照

| AC | 本次實測證據 | 狀態 |
|---|---|---|
| AC-1 標頭延到首 chunk、串流開頭片段 | 有 `BTR: head first byte N ms` 行，代表開頭片段串流路徑被執行；未直接觀察標頭送出時機 | 部分有 log 佐證；其餘已審查 diff |
| AC-2 2 秒無資料即換節點 | `BTR: head no first byte on ... after 20xx ms` 後接 `BTR: head switch to ...`（#2、#3、#6 等） | 有 log 佐證 |
| AC-3 平行試連 | 開檔時對同一檔案同時發出多個 host 的請求（如 #1 探測輪的 cosov / ali / hw 同毫秒發出） | 有 log 佐證（間接，來自 Dio 請求時間） |
| AC-4 全域節點統計與封鎖 | 探測輪出現 `BTR: host banned 10 min upos-sz-mirrorali`、`node banned upos-sz-mirror08c`（log 未存檔） | 部分有佐證；跨影片共用、10 分鐘到期未驗證 |
| AC-5 失敗路徑關閉回應 | 無 | 未驗證（已審查 diff） |
| AC-6 開檔失敗重試改用原始網址 | 本輪沒有出現 `Failed to open` 或 fallback | 未驗證（已審查 diff） |
| AC-7 network-timeout 15 | 無 | 未驗證（已審查 diff） |
| AC-8 補齊畫質不阻擋 | 每次開啟只有 1 次 playurl（#1、#3 至 #8、#11），沒有第二次補齊請求 | 有 log 佐證 |
| AC-9 重用 prefetch | `PlayUrlCache hit bvid=.. cid=.. qn=80`（#2 至 #6、#9、#10）；快取命中且當下 prefetch 尚在進行（#3 至 #6）時，影片頁只有 1 次 playurl | 有 log 佐證 |
| AC-10 預設畫質 1080P | playurl 請求與快取 hit 的 `qn=80` | 有 log 佐證（此帳號未確認是否為手動設定值） |
| AC-11 關閉 BTR 時行為不變 | 本輪 BTR 皆開啟 | 未驗證（已審查 diff） |
| AC-12 analyze、release 建置 | 本輪只建置 debug，`EXIT 0` | 未驗證 release 與 analyze |

## 觀察到的問題

1. **OPEN-TIME 與實際出圖不一致**：#11 記錄 `OPEN-TIME first frame 1234 ms`，但 10 秒後截圖（原 emulator-playing.png 取樣時）影片區仍是全黑，點擊後約 20 秒的截圖才有畫面（現在的 emulator-playing.png）。因此 OPEN-TIME 的「first frame」可能早於真正解碼出圖，0.5 秒目標需要更貼近實際出圖的量測方式。
2. **硬解錯誤**：`ffmpeg/video: h264_mediacodec: Failed to flush codec`（17:45:12.499，#11 後），之後 `Consider trying --profile=fast and/or --hwdec=auto`。推測與模擬器的 MediaCodec 有關，實機未知；本輪沒有改設定。
3. **BTR 首 byte 常逾 2 秒**：`head no first byte ... after 2026 / 2040 / 2082 / 2100 ms` 在 #2、#3、#6、#7、#8、#9、#11 都有，會一路切換節點，總計多等 2 至 4 秒。可能是模擬器網路，但也顯示 2 秒門檻在慢網路下會連續觸發。
4. **離開影片頁後仍有舊影片的 BTR 請求**：#2 的存檔 log 中，離開 #1 的頁面後 10 秒內仍有 `42699131347`（#1 的影片）的 piece 請求；實機上是否一樣、是否為預期的預載，未確認。
5. **host 失敗**：`upos-sz-mirror08c` DNS 失敗、`upos-sz-mirrorali` 連線逾時（探測輪，log 未存檔）；符合已知模擬器問題，且被封鎖後後續 log 不再見 mirror08c 的失敗。

## 限制

- 11 次存檔開啟加 1 輪未存檔探測；樣本小，網路波動大。
- 模擬器網路與 DNS 和實機不同，不能當作實機開播時間；實機結果待使用者測試。
- 沒有直接量測「點擊到畫面出圖」的時間，只有 app 自己印的 OPEN-TIME。
