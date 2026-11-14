# 規格：一鍵投放影片到 PiliBTRTV

需求：[1-requirements.md](1-requirements.md)。

本規格涉及兩個 repo：
- 手機：`C:\presonal_project\bilibili_bata\PiliPlus`（以下稱 **P**）
- 電視：`C:\presonal_project\PiliBTRTV`（以下稱 **T**）

## 協定（v1）

### 探索（手機端）

不用 UDP 廣播。原因是路由器常擋廣播，而且電視端可以少開一個 socket（審查 #3）。

手機從 t=0 同時做兩件事：
- 直接連已知電視：`GET http://<host>:<port>/api/cast/info`。
- 掃描子網：
  - 範圍：每個私有 IPv4 介面所在的 /24，位址 1～254，跳過手機自己。
  - 請求：`GET http://<ip>:3322/api/cast/info`。
  - 逾時 500 ms，最多同時 64 個。254 個位址約 2 秒掃完。

Dart 拿不到 netmask，所以一律當成 /24。遇到下列情況，只能用 QR code 或手動輸入：
- 網段不是 /24。
- 電視的服務落在 3323～3331 埠。

回覆的處理規則：
- 回覆的 `app` 必須是 `PiliBTRTV`，否則忽略。
- 以 `id` 去重。已知電視的 IP 變了就更新。

整個探索在 3 秒時結束（AC-1）。清單邊找邊顯示。

### HTTP（T 的 `LocalServer`，埠 3322～3331）

共通規則：
- `/api/cast/` 的路由放在 local_server.dart:146-161 的 CORS 段之前，不加 CORS 標頭。
- POST 必須帶 `Content-Type: application/json`，否則回 415（比照 :379）。這樣網頁無法用不需預檢的 `text/plain` 跨站送出請求。
- 寫回應時用 try/catch 包起來，因為手機斷線時 `close` 會丟例外。
- `appNavigatorKey.currentState` 為 null 時，回 `503 {"ok":false,"reason":"not_ready"}`。這發生在 App 啟動中：`LocalServer.start()` 在 main.dart:61，早於 :72 的 `runApp`。

#### `GET /api/cast/info`

不驗證，只回公開資訊：

```json
{"app":"PiliBTRTV","v":1,"id":"<uuid>","name":"<製造商 型號>","port":3322}
```

#### `POST /api/cast/play`

body 用 `_readLimitedJson` 讀取，上限 8 KB：

```json
{"v":1,"deviceId":"<uuid>","deviceName":"<手機名稱>","token":"<可省略>",
 "bvid":"BV...","aid":123,"cid":456,"epId":null,"seasonId":null,
 "positionMs":61234,"title":"<可省略>"}
```

必要欄位：
- `deviceId`
- `deviceName`（截到 40 字）
- `bvid` 或 `epId` 至少一個

缺少必要欄位時，回 `400 {"reason":"bad_request"}`。

依 `token` 分成三種情況：

1. 有 `token`，而且與已配對清單中同一個 `deviceId` 的 token 相同（constant-time 比對）：
   - 回 `200 {"ok":true}`。
   - 開始播放。
2. 有 `token`，但不相符：
   - 回 `403 {"reason":"bad_token"}`。
   - 手機收到後清掉 token，再不帶 token 重送一次。
3. 沒有 `token`，需要在電視上詢問：
   - 已經有一個詢問在等待：回 `409 {"reason":"busy"}`。
   - 同一個 `deviceId` 在 60 秒內被拒絕過：回 `429 {"reason":"too_many"}`。
   - 同一個來源 IP 在 10 分鐘內已經詢問 3 次：回 `429 {"reason":"too_many"}`。
   - 其他情況：
     - 產生 16 字元的 `reqId`，立刻回 `202 {"ok":true,"pending":true,"reqId":"..."}`。
     - 電視顯示對話框「允許 <deviceName>（<來源 IP>）投放影片到這台電視？」，按鈕為允許和拒絕，預設焦點在拒絕。
     - 最多等 30 秒。逾時就用 `Navigator.pop` 關閉對話框，結果記為拒絕。
     - 按允許時：
       - 用 `Random.secure()` 產生 32 字元的 token。
       - 把 `{deviceId, deviceName, token, pairedAt}` 存入已配對清單。
       - 結果記為 `{ok:true, token}`。
       - 開始播放。
     - 按拒絕時：
       - 結果記為 `denied`。
       - 記錄拒絕時間。

#### `GET /api/cast/result?id=<reqId>`

- 還在等待：回 `200 {"pending":true}`。
- 已有結果：回 `{"ok":true,"token":"..."}`，或 `403 {"reason":"denied"}`。
- 不存在：回 `404`。

結果保留 60 秒。

#### QR code 內容

```
pilibtrtv://cast?host=<ip>&port=<port>&id=<uuid>&name=<urlencoded 名稱>
```

## 電視端（T）

### T-1：投放路由、配對、詢問框、設定頁

新檔 `lib/services/cast/cast_service.dart`：
- TV id：
  - 第一次使用時產生 UUID。
  - 存在 SharedPreferences（`SettingsService.prefs`），key 為 `cast_tv_id`。
- 電視名稱：
  - 格式為 `'<manufacturer> <model>'`。
  - 來源是原生 `getDeviceInfo`（MainActivity.kt:49-58；Dart 端寫法參考 error_report_service.dart:24-28）。
- 已配對清單：
  - 存成 JSON 字串，key 為 `cast_paired`。
  - 提供讀取、新增、移除。
  - 解析時用 try/catch，資料壞掉就當成空清單。
- `Future<bool> handle(HttpRequest)`：處理 `/api/cast/*`，流程照協定。
- 詢問框用全域的 `appNavigatorKey` 顯示。
  - 在 `lib/main.dart` 新增 `final appNavigatorKey = GlobalKey<NavigatorState>();`。
  - 傳給 `MaterialApp(navigatorKey: ...)`（main.dart:115）。
- 允許後呼叫 T-2 的 `CastPlayback.open(CastRequest)`。

`lib/services/local_server.dart`：
- 在 `_handleRequest` 的 CORS 段之前，把 `/api/cast/` 開頭的請求交給 `CastService.handle`。
- 新增 `List<String> get localIps`，列出所有私有 IPv4 位址。

設定頁：
- 入口：在 `lib/screens/home/settings/tabs/plugins_settings.dart:30` 附近加一個 `SettingActionRow`「投放配對」。
- 新頁面 `lib/screens/home/settings/cast_settings_page.dart`：
  - 開頁時先呼叫 `LocalServer.refreshAddress()`（local_server.dart:46）。
  - 每個私有 IP 顯示一個 QR code，內容為 `pilibtrtv://cast?...`。用 `QrImageView`，參考 login_view.dart:425。
  - 每個 QR code 旁顯示「IP:埠」與電視名稱。
  - 列出已配對的手機，每一列有「移除」（AC-7），可以用遙控器移動焦點操作。
  - 沒有任何私有 IP 時，顯示「未連上區網」。

### T-2：依投放請求開影片

新檔 `lib/services/cast/cast_playback.dart`：
- `class CastRequest { String? bvid; int? aid; int? cid; int? epId; int? seasonId; int positionMs; String title; }`
- `static Future<void> open(CastRequest r)`：
  - 番劇（有 `epId`）：用 `Video(bvid:'', title, pic:'', seasonId, epId, forceEpId: epId, forceStartMs)`。
  - 一般影片：用 `Video(bvid, title, pic:'', aid, forceStartMs)` 搭配 `PlayerRoute(startCid: cid ?? 0)`。指定分 P 沿用既有的 `startCid`。
  - 開頁方式：
    - `PlayerScreen.activeCount > 0` 時，先 `popUntil` 回到最上層的播放頁，再 `pushReplacement`。
    - 否則直接 `push`。
  - 用 `_opening` 旗標防止重複進入，參考 player_action_mixin.dart:2394-2407。

`lib/models/video.dart`：
- 新增可選欄位 `int? forceStartMs`、`int? forceEpId`。
- 這兩個欄位不寫進 toJson，也不寫進快取。

選集與分 P：
- PGC：在 `_setupPgcSeason`（player_action_mixin.dart:785-797）中，`forceEpId` 的優先順序最高，高於伺服器的 lastEpId 和本地快取。
- UGC：
  - 舊路徑（:157-176）已經在最後用 `startCid` 覆寫，不需要改。
  - 新路徑 `PlaybackPreparer.prepare`（playback_preparer.dart:84，選 cid 在 :167-186）也加入 `startCid`，優先順序最高；前提是它在分 P 清單內。
  - 實作時先確認 UGC 實際走哪一條路徑，兩條都要測。

起播位置（`forceStartMs` 有值時）：
- UGC：在 preparer :375 的 resume 之後覆寫，並跳過「接近片尾就從頭播」的判斷。
- PGC：在 :446-451（本地快取把進度歸零）和 :474 之後覆寫，並跳過 :483 的片尾判斷。
- 不接手暖機播放器，三處都要跳過：
  - player_screen.dart:63
  - mixin :544-546 的 `isPendingFor`／`waitAndTake`
  - mixin :722-726

MPD 清除競態：
- 原因：`disposePlayer` 在 `await videoController?.dispose()`（:2024）之後才清 MPD。用 `pushReplacement` 換頁時，舊頁可能把新頁剛寫入的 MPD 清掉。
- 修法：
  - `setMpdContent` 改為回傳遞增的 token。
  - 新增 `clearMpdContentIf(int token)`：只在 token 是目前內容的 token 時才清除。
  - 無參數的 `clearMpdContent()` 不變（:1130、1540、3067、3333 照舊使用）。
  - 播放頁每個 `setMpdContent` 的呼叫點，都把回傳的 token 存到 `_mpdToken`：preparer:285，mixin :326、1164、1572、3112、3355。
  - :2026 改呼叫 `clearMpdContentIf(_mpdToken)`。

## 手機端（P）

### T-3：投放服務、選單、掃描

新檔 `lib/services/cast/tv_cast.dart`：
- 資料：
  - `TvDevice {id, name, host, port, token?}`。
  - 已知電視存在 `GStorage.localCache`，key 為 `LocalCacheKey.castTvs`，型別 `List<Map>`。讀取時用 try/catch，資料壞掉就當成空清單。
  - 手機 id 是 UUID，存在 `LocalCacheKey.castDeviceId`。
  - 手機名稱用 `device_info_plus` 取 `'<manufacturer> <model>'`，參考 feedback_report.dart:142-146。
- `Stream<TvDevice> discover()`：照協定探索，3 秒結束。
- `Future<TvDevice?> probe(String host, int port)`：呼叫 `/api/cast/info`，逾時 3 秒。
- `Future<CastResult> play(TvDevice tv, CastPayload p, {CancelToken? cancel})`：
  - 用自己的 `Dio`，不帶 cookie（參考 translator.dart:155-162）。
  - 連線逾時 3 秒；每個請求的接收逾時 5 秒（AC-8）。
  - 收到 202 時，每 1 秒輪詢一次 `/api/cast/result`，總共最多 35 秒，可以取消。
  - 收到 `bad_token` 時，清掉 token，不帶 token 重送一次。
  - 結果 ok 而且帶 token 時，把 token 存到這台電視。

`lib/pages/video/controller.dart` 的 `onCast`（:1950）改成先顯示 bottom sheet「投放到」。按鈕在 header_control.dart:1667-1680，一般影片和番劇共用。選單內容：
- PiliBTRTV 電視：
  - 邊探索邊加入清單。
  - 探索中顯示轉圈；沒找到時顯示「找不到電視」。
- 「掃描 QR code」：開掃描頁。返回後重新讀取已知電視，並重新探索。
- 「輸入 IP」：
  - 接受 `ip` 或 `ip:port`，埠預設 3322。
  - 呼叫 `probe`。成功就加入已知電視；失敗顯示「找不到 PiliBTRTV」。
- 「DLNA 裝置」：執行原本的流程（`tvPlayUrl` 再到 `/dlna`）。

選了電視之後：
1. 在同一個同步區塊內取得要送出的資料：
   - 一般影片：`bvid`、`aid`、`cid.value`。
   - 番劇：另外加上 `epId`、`seasonId`。
   - `positionMs`：`plPlayerController.positionInMilliseconds`。
   - `title`：目前影片的標題。
2. 顯示可取消的等待對話框：
   - 送出時顯示「正在連線…」。
   - 收到 202 後改為「請在電視上按允許」。
   - 按「取消」會取消請求與輪詢。
3. 依結果顯示：

   | 結果 | 手機的處理 |
   |---|---|
   | 成功 | 呼叫 `plPlayerController.pause()`，toast「已投放到 <名稱>」（AC-5） |
   | `denied` | 「電視拒絕投放」 |
   | 409 | 「電視正在等待其他手機的允許」 |
   | 429 | 「請稍後再試」 |
   | 503 | 「電視尚未就緒」 |
   | 連線失敗、逾時 | 「無法連線到 <名稱>」（AC-8） |

掃描：在 `lib/pages/scan/handler.dart:16` 之後處理 `pilibtrtv://cast`：
- 解析參數後呼叫 `probe` 確認是電視。
- 成功就加入已知電視，並顯示對話框「已加入電視 <名稱>」。對話框外面要包 `_withL10n`（:325）。
- 解析失敗時，顯示「不是有效的投放 QR code」。

介面文字補到 `i18n/en.json`，並提高語言包的版本號。

## 任務

| 任務 | repo | 內容 | 相依 |
|---|---|---|---|
| T-1 | T | 投放路由、配對、詢問框、設定頁、navigatorKey | 只呼叫 T-2 的 `CastPlayback.open` |
| T-2 | T | `CastPlayback`、Video 新欄位、選集／分 P／起播位置覆寫、MPD token | 無 |
| T-3 | P | `tv_cast.dart`、投放選單、掃描、語言包 | 本文件的協定 |

T-1 和 T-2 都改電視端，分工如下：
- 兩者只透過 `CastRequest` 和 `CastPlayback.open` 相連。T-2 建立這兩個名稱；T-1 只 import 並呼叫。
- `local_server.dart` 兩者都會改：T-1 改路由部分，T-2 改 MPD 部分。兩邊在不同函式；不要重新格式化整個檔案。

## 驗證方式

| AC | 方式 |
|---|---|
| AC-1、AC-2（掃描與 QR） | 模擬器之間無法互相看到，只能在真機驗證，列為「待使用者測試」 |
| AC-2（電視 QR 顯示） | 電視模擬器截圖設定頁；手機模擬器從相簿選這張截圖掃描，確認電視被加入 |
| AC-3、AC-7 | 電視模擬器執行 `adb forward tcp:3322 tcp:3322`，從電腦用 curl 測：未配對時回 202 並顯示詢問框；按允許或拒絕後輪詢拿到結果；帶 token 再送一次不再詢問；移除配對後回 bad_token |
| AC-4 | 電視模擬器先製造歷史紀錄（多 P 影片看第 2 P、番劇看第 2 集），再用 curl 指定第 3 P 或第 3 集和位置，截圖確認集數與進度 |
| AC-6 | 電視正在播放、以及停在其他頁面時，各用 curl 送一次 |
| AC-5、AC-8 | 手機模擬器執行 `adb reverse` 後，手動輸入 IP 連到電視模擬器的 forward：確認成功後手機暫停；關閉電視 App 後，計時確認 5 秒內出現錯誤 |
| 全部 | 兩個 repo 都跑 analyze 與 release 建置 |

## 邊界與風險

- 同一台電視有多個網卡（有線＋Wi-Fi）：以 `id` 去重。
- 網段不是 /24、電視的埠不是 3322、手機開 VPN 或熱點：探索可能找不到，改用 QR code 或手動輸入。
- 防火牆或 AP 隔離：探索和投放都會失敗，手機顯示錯誤。這種情況無法處理，寫在說明中。
- 通訊用明文 http，token 在區網上看得到。風險可以接受，理由是只在同一個 Wi-Fi 內，而且 token 只能讓電視播影片。寫在說明中。
- 電視睡眠或 App 在背景：請求會逾時，手機顯示「無法連線」。
- 回退：手機的投放選單保留 DLNA；電視端拿掉 cast 路由後，舊功能不受影響。

## 審查紀錄

Sonnet 審查提出 10 條，全部採用：

1. PGC 選集、UGC 分 P 會被歷史紀錄蓋掉。
   - 新增 `forceEpId`，優先順序最高。
   - UGC 改用既有的 `startCid`，preparer 也加入。
2. MPD 清除的改動範圍不夠：新增 `clearMpdContentIf`，並記錄所有 `setMpdContent` 呼叫點的 token。
3. 子網掃描在 3 秒內掃不完：改成 t=0 就開始平行掃描（同時 64 個、逾時 500 ms），並移除 UDP。
4. 35 秒的長請求違反 AC-8，而且無法取消。
   - 改用 202 加輪詢，手機的等待對話框可以取消。
   - 電視端逾時時關閉詢問框。
5. 可能被跨站請求或冒名：
   - 要求 `Content-Type: application/json`。
   - 依來源 IP 限制頻率。
   - 詢問框顯示來源 IP。
6. App 啟動中還沒有 navigator：回 503 `not_ready`。
7. 暖機接手漏了 :544-546 這一處，也要跳過。
8. 設定頁的問題：
   - 檔案路徑寫錯，已修正。
   - IP 可能過期：開頁時先呼叫 `refreshAddress`。
   - 多網卡：每個 IP 各顯示一個 QR code。
9. 其他遺漏，都已補上：
   - 已存的資料壞掉。
   - `bad_token` 和 `denied` 混在一起。
   - 送出資料的取值時機（改為同一個同步區塊）。
10. 驗證方式補上可以實際執行的步驟。

## 實作偏差

- 電視：`/api/cast/info` 不檢查 navigator（啟動中也回應），只有 play 回 503。
- 電視：body 讀取逾時回 400 而非 408；OPTIONS 與未知方法回 405。
- 電視：投放的 bvid 若實為番劇（UGC 轉 PGC），指定位置會遺失（手機投番劇一律帶 epId，不會走到）。
- 手機：`onCast` 改接收按鈕的 context（`Get.context` 是 Navigator 本身，開 bottom sheet 會失敗）；之後的對話框用根 Navigator 的 overlay context。
- 手機：子網掃描另用連線逾時 500 ms 的 Dio（Dio `Options` 無法設定連線逾時）。
- 手機：以 QR code 加入電視後，掃描頁不會自動關閉。

## 驗證紀錄（2026-11-14，模擬器）

電視模擬器 `Android_TV_API36`＋`adb forward`，curl 測試：

| 項目 | 結果 |
|---|---|
| text/plain → 415；epId=0 → 400 | 通過 |
| 未配對 → 202、電視詢問框（顯示 127.0.0.1、焦點在拒絕） | 通過 |
| 允許 → 輪詢拿到 token；影片從 30 s 起播 | 通過 |
| 帶 token → 200、播放中切換、50 s 覆蓋歷史進度 | 通過 |
| 連續投放兩次只留一層播放頁 | 通過 |
| 詢問中再來請求（含已配對手機）→ 409 | 通過 |
| 拒絕 → denied；60 s 冷卻 429；同 IP 第 4 次 429 | 通過 |
| 30 s 逾時自動關閉詢問框 | 通過 |
| 設定頁 QR、IP、已配對清單；移除後 bad_token、焦點移到「重新整理」 | 通過 |
| 手機端 UI（投放選單） | 未驗證：模擬器上用 adb 點播放器上方的任何按鈕（返回以外的聽音訊、投放、更多）都沒反應，無法開啟選單 |
| 番劇、指定分 P、自動探索、掃 QR code | 未驗證 |

