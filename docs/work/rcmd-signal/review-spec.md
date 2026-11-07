針對 `docs/work/rcmd-signal/2-spec.md` 比對需求與現有程式碼，審查發現以下具體問題，依重要程度由高至低排列：

---

### 1. 設計錯誤：掛點機制假設錯誤，導致播放開始 START 與暫停 END 永遠無法送出
* **規格章節**：`### B-1 + B-3：App 心跳帶點擊歸因` -> `session 生命週期` 與 `掛點`（第 69–75 行）
* **問題說明**：
  規格假設沿用 `lib/plugin/pl_player/controller.dart:1172`（狀態變化）與現有 `makeHeartBeat` 即可送出 START 與暫停 END。但在現有程式碼中，影片於第 0 秒開始播放時會被 `if (seconds != 0)` 擋下；暫停時，`makeHeartBeat` 內部又會被 `(playerStatus.isPaused && !isManual)` 攔截而直接返回 `null`。這導致 START 在第 0 秒不可能被觸發，暫停時的 END 也會被直接丟棄，違反需求 AC-1 與 AC-3。
* **原因與程式碼證據**：
  1. [controller.dart:1170-1173](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/plugin/pl_player/controller.dart#L1170-L1173)：
     ```dart
     final seconds = videoPlayerController!.state.position.inSeconds;
     if (seconds != 0) {
       makeHeartBeat(seconds, type: .status);
     }
     ```
     影片從第 0 秒剛開始播放時，`seconds == 0`，第 1171 行直接略過，不會呼叫 `makeHeartBeat`。
  2. [controller.dart:1739-1742](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/plugin/pl_player/controller.dart#L1739-L1742)：
     ```dart
     if (isLive ||
         !enableHeart ||
         progress == 0 ||
         (playerStatus.isPaused && !isManual)) {
       return null;
     }
     ```
     當播放器狀態變為暫停時，第 1160 行設定 `playerStatus = .paused;`，接著第 1172 行呼叫 `makeHeartBeat(seconds, type: .status)` 時 `isManual` 為預設 `false`。進入第 1740 行時，`(playerStatus.isPaused && !isManual)` 成立，立即 return `null`。
* **具體修正**：
  不要將 App 心跳邏輯混入現有的 Web 端 `makeHeartBeat`。App 心跳應在 `stream.playing.listen`（[controller.dart:1150-1174](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/plugin/pl_player/controller.dart#L1150-L1174)）中獨立處理狀態轉換：
  - 當 `playing == true` 且該影片 session 尚未 START 時，直接發送 START 心跳（不依賴 `seconds != 0` 與 `progress == 0`）。
  - 當 `playing == false` 時，直接結算並發送 END 心跳（不被 `playerStatus.isPaused && !isManual` 攔截）。

---

### 2. 設計錯誤與邊界情況：帳號認證機制假設錯誤，Web 登入帳號缺乏 `access_key`
* **規格章節**：`### B-1 + B-3` -> `請求（T-3）`（第 89–91 行）
* **問題說明**：
  規格指定共同參數帶入 `access_key=Accounts.heartbeat.accessKey`，並將 `Api.heartBeatMobile` 加入 `AccountType.heartbeat`。但現有程式碼中，`Accounts.heartbeat` 是用於 Web 端歷史紀錄與心跳（使用 Cookie 與 CSRF）。若使用者是透過 Web QR code 登入，該帳號物件內根本沒有 `accessKey`（為 `null` 或空字串）。規格未定義 `accessKey` 為空時的處理方式，若直接以 `null` 或空字串參與 `AppSign.appSign` 簽名，會導致伺服器返回 `-400`（參數錯誤）或 `-101`（未登入）。
* **原因與程式碼證據**：
  [video.dart:850](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/http/video.dart#L850) 中現有心跳只使用 Web CSRF：
  ```dart
  'csrf': Accounts.heartbeat.csrf,
  ```
  而 [api_type.dart:7-27](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/utils/accounts/api_type.dart#L7-L27) 的 `AccountType.heartbeat` 分類下所有 API（如 `Api.heartBeat`、`Api.historyReport`）全依賴 Web Cookie。若在無 `accessKey` 的情況下簽入 `access_key`，簽名與請求將失敗。
* **具體修正**：
  在 `VideoHttp.heartBeatMobile` 組裝參數時，檢查 `Accounts.heartbeat.accessKey`：
  - 僅當 `accessKey` 非空時才加入 `params['access_key'] = accessKey`；
  - 若 `accessKey` 為空或 null，則不加入該欄位，避免傳入無效值造成簽名異常或請求被拒。

---

### 3. 驗收條件未覆蓋：推薦頁番劇（PGC）卡片漏傳 `track_id` 與 `from_spmid`
* **規格章節**：`### B-1 + B-3` -> `資料流` 第 2 點（第 44–45 行）
* **問題說明**：
  需求 AC-1 要求「從首頁推薦（App 端）點進影片，播放開始與暫停／結束時，送出 `POST /x/report/heartbeat/mobile`，參數包含該卡片的 `track_id` 與 `from_spmid=tm.recommend.0.0`」，且需求第 30 行明確包含 PGC（番劇）。然而規格第 44–45 行僅在 `VideoCardV.onPushDetail` 的 `av` 分支處理 `trackId`，完全忽略了 `bangumi` 卡片，導致推薦頁點入番劇時無法達成 AC-1。
* **原因與程式碼證據**：
  [video_card_v.dart:37-41](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/common/widgets/video_card/video_card_v.dart#L37-L41)：
  ```dart
  switch (videoItem.goto) {
    case 'bangumi':
      PageUtils.viewPgc(epId: videoItem.param!);
      break;
    case 'av':
  ```
  規格第 44 行僅敘述：「`VideoCardV.onPushDetail` 的 `av` 分支（`lib/common/widgets/video_card/video_card_v.dart:59-68`）：`videoItem.trackId` 非空時，呼叫 `PageUtils.toVideoPage` 帶 `extraArguments: ...`」。`case 'bangumi'` 完全未被納入規格。
* **具體修正**：
  在 `VideoCardV.onPushDetail` 的 `case 'bangumi'` 分支中，若 `videoItem.trackId` 非空，同樣將 `trackId` 與 `from_spmid: 'tm.recommend.0.0'` 傳入番劇開啟邏輯（如 `PageUtils.viewPgc`），使 PGC 影片在推薦入口點擊時亦具備完整的訊號回傳。

---

### 4. 設計錯誤與狀態競爭：分 P 與換片時未將識別訊號封裝進 session 物件
* **規格章節**：`### B-1 + B-3` -> `資料流` 第 4–5 點與 `App 心跳 session`（第 47–65 行）
* **問題說明**：
  規格將 `trackId` 與 `fromSpmid` 存於共用的 `PlPlayerController` 欄位中，而 session 狀態表（第 54–65 行）僅記錄計時數據，未包含 `aid`、`cid`、`trackId`、`fromSpmid`。當使用者切換分 P、換片或進入相關影片時，若新影片資料先行寫入 `PlPlayerController`，隨後舊影片觸發 END 心跳時，將帶入新影片的 `trackId`（或被清空的字串）；反之，若未即時清空，從非推薦入口進入時又會殘留上一部的 `trackId`，違反 AC-2。
* **原因與程式碼證據**：
  [controller.dart:129[agy] print timeout after 4m40s with turn in progress; returning partial output
error: print timeout after 4m40s with the turn still in progress; the response is partial
AGY_ERROR: {"short_error":"print timeout after 4m40s with the turn still in progress; the response is partial","status":"DEADLINE_EXCEEDED","retryable":false,"reason":"print_timeout"}
