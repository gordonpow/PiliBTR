# fast-start-2 模擬器量測結果

環境：debug APK（`flutter build apk --debug --target-platform android-x64`，EXIT 0），AVD `Medium_Phone_API_37.0`（模擬器已在執行，未重啟），`adb install -r` 覆蓋安裝，未改任何設定。方法同 fast-start：`adb logcat -c` → 點擊 → 等 10 秒 → 過濾 log → BACK。每次開啟另存點擊前（捲動/等待期間）的 log，用來判斷「點擊前已 visible prefetch」。原始過濾 log：[emulator-log.txt](emulator-log.txt)；播放截圖：[emulator-playing.png](emulator-playing.png)（手動多開一次，播放中 00:02）。

欄位說明：
- 點擊前已 visible prefetch：該 bvid 在點擊前（或此前的 log）出現過 `PlayUrlCache visible prefetch`。R 情境為同影片重開，直接記 y。
- cache hit：開啟 log 有 `PlayUrlCache hit`（可能是 tap-down 預取或進行中的預取）。
- preconnect：點擊前後的 log 中 `BTR: preconnect` 行數。
- hedge win/start：`BTR: hedge win` 次數 / `BTR: hedge start` 次數（head 的 0.8 秒 hedge 啟動；win 只在 hedge 節點勝出時才印）。
- playurl 次數：點擊後 log 中 `wbi/playurl` Request 行數（含 tap-down 預取）。

## 每次開啟

| # | 情境 | bvid | OPEN-TIME ms | 點擊前已 visible prefetch | cache hit | warm hit bytes | preconnect | hedge win/start | head first byte ms | 開啟時 playurl 次數 | fallback | ban |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | A | BV1FV4v6vEYf | 357 | y | y | - | 2 | 0/1 | 1976 | 0 | 0 | 0 |
| 2 | A | BV1BVxP6gE5P | 673 | y | y | - | 0 | 0/0 | - | 0 | 0 | 0 |
| 3 | A | BV1BNnc6nEXS | 505 | y | y | 455227,524288 | 0 | 0/1 | 1482 | 0 | 0 | 0 |
| 4 | A | BV1J5nE6MEex | 1197 | y | y | - | 0 | 0/2 | - | 0 | 0 | 0 |
| 5 | B | BV1meJ967ELu | 974 | y | y | 524288,524288（10 秒窗口之後才出現，記在 #6 的點擊前段）| 2 | 0/1 | 2272 | 1 | 0 | 0 |
| 6 | B | BV18AxW6UEkR | 723 | y | y | - | 0 | 0/2 | 1850 | 2 | 1 | 1 |
| 7 | B | BV1Dsnq6VEPa | 568 | y | y | - | 0 | 0/0 | - | 0 | 0 | 0 |
| 8 | C | BV1jx4q6NEkQ | 1318 | n | y | - | 0 | 0/2 | 1930,1831 | 5 | 0 | 0 |
| 9 | C | BV1whnM62ESU | 1834 | n | y | - | 2 | 0/3 | 947 | 4 | 0 | 0 |
| 10 | C | BV1Ein66YE9Q | 1315 | n | y | - | 0 | 0/4 | - | 2 | 2 | 0 |
| 11 | R | BV1Ein66YE9Q | 294 | y | y | - | 0 | 0/2 | - | 0 | 1 | 1 |
| 12 | R | BV1Ein66YE9Q | 182 | y | y | - | 0 | 0/0 | - | 0 | 0 | 1 |

## 統計 (OPEN-TIME ms)
- 全部：min 182 / 中位數 698.0 / max 1834（n=12，≤500 ms：3）
- 情境 A：min 357 / 中位數 589.0 / max 1197（n=4，≤500 ms：1）
- 情境 B：min 568 / 中位數 723 / max 974（n=3，≤500 ms：0）
- 情境 C：min 1315 / 中位數 1318 / max 1834（n=3，≤500 ms：0）
- 情境 R：min 182 / 中位數 238.0 / max 294（n=2，≤500 ms：2）

## 與 phase 1 比較（模擬器，同方法）

- phase 1（11 次）：min 219 / 中位數 999 / max 2688 ms；≤500 ms 3/11（都是快取命中）。
- phase 2（12 次）：min 182 / 中位數 698 / max 1834 ms；≤500 ms 3/12（#1 357、#11 294、#12 182）；#3 為 505 ms。
- 中位數 999 -> 698 ms（約 -30%）；最大值 2688 -> 1834 ms。
- 情境 C（快速捲動後點下方卡片，點擊前沒有 visible prefetch）仍在 1315 至 1834 ms，與 phase 1 的非快取開啟（926 至 2688 ms）同級。情境 A 中位數 589 ms，B 723 ms。
- 12 次全部有 cache hit 行；但 C 的 3 次因點擊前尚無 prefetch，靠 tap-down 預取，開啟時 playurl 為 2 至 5 次。

## 機制是否觸發

- visible prefetch：觸發（log 內共 24 筆 `visible prefetch`，捲動停止後 2 張 2 張地發）。A、B、R 的點擊影片全部在點擊前已預取。C 的 3 次點擊前沒有。
- BTR preconnect：有，共 6 行（#1、#5、#9 的 log 窗口內各 2 行，host：`upos-sz-mirrorcosov`、`upos-hz-mirrorakam`）。
- warm hit：#3 有（`455227` 與 `524288` bytes）；#5 也有（兩次 `524288` bytes），但出現在 #5 的 10 秒窗口之後（記在 #6 的點擊前段）。其餘開啟沒有 `warm hit`。同時 log 有 11 行 `BTR: warm failed on <host>: DioException [request cancelled]`（預熱請求被取消，多半是離開影片頁或換節點時取消，並被計為 warm 失敗）。
- hedge：`hedge start` 25 次（含點擊前段與落在別次窗口者；點擊後段合計 14 次）（head 0.8 秒 hedge 已啟動），但 `hedge win` 0 次（hedge 節點從未先到）。
- head first byte 仍常見 1.5 至 2.3 秒（#1 1976、#3 1482、#5 2272、#6 1850、#8 1930/1831、#9 947 ms）。

## 問題與備註

1. `BTR: fallback to original URL at 0: head piece failed` 共 4 次（#6 一次、#10 兩次、#11 一次，見表中 fallback 欄），並有 `node banned` 2、`host banned 10 min upos-sz-mirrorali` 1。
2. warm 預熱常被取消：11 行 `warm failed ... request cancelled`；`warm hit` 只在 2 次開啟出現。請檢查預熱是否在 tap 後被 head 流程或離開頁面取消過早。
3. 異常/例外（flutter tag）：無 crash（沒有 `FATAL`／`AndroidRuntime`）。有 `*** DioException ***` 約 202 行，其中 193 行為 `request cancelled`（hedge／warm 落敗被取消的請求，預期內）；其餘為 `BTR: piece ... retry`（connection timeout、receive timeout、connection closed），屬模擬器網路。18 行 `ffmpeg: amediacodec: MediaCodec$CodecException`（硬解，與 phase 1 的 `h264_mediacodec` 錯誤同類，模擬器問題）。
4. 影片是否真的出圖：手動開啟一次（emulator-playing.png）畫面播放中（00:02）；#3 在點擊後 10 秒的截圖有畫面（顯示「載入中」覆蓋，畫面為影片內容，OPEN-TIME 505 ms）；#8 在 10 秒時截圖仍全黑（OPEN-TIME 記 1318 ms，與 phase 1 觀察相同：OPEN-TIME 早於真正出圖）。
5. 第一次執行腳本時，因 App 處於背景（凍結），點擊沒有開啟影片，該輪資料已作廢重跑；本檔數據來自重跑。
6. 樣本小（12 次），模擬器網路與 DNS 不代表實機。
