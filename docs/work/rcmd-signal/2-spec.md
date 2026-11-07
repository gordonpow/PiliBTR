# 規格：改善推薦訊號回傳（rcmd-signal）

需求：[1-requirements.md](1-requirements.md)

## 參考資料（第三方，未經官方確認）

Hikari0618/bilibili-client-research `docs/watch-report.md`（2026-11-01 靜態逆向）：

- `POST https://api.bilibili.com/x/report/heartbeat/mobile`，form-urlencoded。
- START：第一幀開始播放時送一次，累計欄位全為 0。END：暫停、停止、切換分 P、seek 時送，帶累計值。原生播放沒有定時心跳。
- 只有 `aid > 0 && cid > 0` 時送。
- 欄位：`session`、`mid`、`aid`、`cid`、`sid`（UGC 空字串）、`epid`（UGC 0）、`type`（UGC `3`、PGC `4`）、`sub_type`（0）、`quality`（qn）、`total_time`、`paused_time`、`played_time`（不含暫停的累計播放秒數）、`actual_played_time`（依倍速加權）、`video_duration`（秒）、`start_ts`、`play_type`、`network_type`（1 WiFi、2 行動網路）、`last_play_progress_time`、`max_play_progress_time`、`from`（預設 6）、`from_spmid`、`spmid`、`epid_status`、`play_status`（空字串）、`user_status`（大會員 `1`，否則 `0`）、`auto_play`、`list_play_time`、`miniplayer_play_time`、`is_auto_qn`、`is_audio_play`（影片 `2`）、`cur_language`、`track_id`。
- 共同參數：`platform`、`mobi_app`、`appkey`、`build`、`channel`、`access_key`、`c_locale`、`s_locale`、`ts`、`sign`。
- 推薦卡片在 `/x/v2/feed/index` 回應中帶 `track_id`。

## 設計

### B-2：統一推薦請求的裝置身分（T-1）

現況（`lib/http/video.dart:114-179`）：簽名用 `Constants.appKey`（`dfca71928277209b`，HD 版），header `app-key: android_hd`，UA `Constants.userAgent`（`mobi_app/android_hd`、build 2001100），但 query `mobi_app=android_i`、`build=8430300`、`statistics=Constants.statisticsApp`（appId 1）。gRPC 也用 `android_hd`、build 2001100（`lib/utils/accounts/grpc_headers.dart`）。

做法：`rcmdVideoListApp` 統一為 HD 身分，和簽名金鑰、gRPC 一致。

- query：`mobi_app=android_hd`、`build=2001100`、`statistics=Constants.statistics`（appId 5）。其他參數不變。
- header：`app-key: android_hd`、`User-Agent: Constants.userAgent`（不變）。
- **前置檢查**：改之前，先用腳本（例如 Python，md5 簽名依 `lib/utils/app_sign.dart`；不帶 `access_key`）各打一次舊參數與新參數的 `/x/v2/feed/index`，比對：`code == 0`、`data.items` 非空、卡片仍有 `card_goto`、`player_args`、`args`、`param`、`track_id`。腳本放 scratchpad 或 `docs/work/rcmd-signal/`，輸出存成 `feed-identity-check.txt`。**若 HD 參數的卡片結構不同或失敗，停止 B-2 的 mobi_app／build 修改並回報**，只做下面的 fp／session 修改。

fp 與 session：新增 `lib/utils/device_fp.dart`：

- `DeviceFp.fpLocal` / `DeviceFp.fpRemote`：依 buvid 產生 64 字元 fp，App 啟動後第一次讀取時計算並快取在記憶體（同一次啟動內固定）：
  1. `source = md5(buvid + model + radio)`，32 字元小寫 hex；`model` 用 `'android'`，`radio` 用空字串。
  2. `ts = yyyyMMddHHmmss`（本地時間）。
  3. `rand = 16 個隨機 hex 字元`。
  4. `s = source + ts + rand`（62 字元）；`check = (s 每 2 字元當 hex 數值相加) % 256`，轉 2 字元小寫 hex。
  5. 結果 `s + check`（64 字元）。`fpRemote` 與 `fpLocal` 相同值。
- `DeviceFp.sessionId`：App 啟動時產生一次的 8 字元隨機小寫 hex。
- buvid 用 `Accounts.get(AccountType.recommend).buvid`（和現有 header 相同來源）。
- 套用到四個位置：`video.dart:152-154`（rcmd）、`video.dart:221-223`（story）、`live.dart:226-228`、`live.dart:304-306`。story 與 live 只改 fp／session，不改 mobi_app 等其他參數。

### B-1 + B-3：App 心跳帶點擊歸因（T-2、T-3）

#### 資料流

1. `RcmdVideoItemAppModel.fromJson`（`lib/models/home/rcmd/result.dart`）解析 `json['track_id']`。在 `BaseRcmdVideoItemModel`（`lib/models/model_rec_video_item.dart`）加 `String? trackId`，web 推薦模型維持 null。
2. `VideoCardV.onPushDetail` 的 `av` 分支（`lib/common/widgets/video_card/video_card_v.dart:59-68`）：`videoItem.trackId` 非空時，呼叫 `PageUtils.toVideoPage` 帶 `extraArguments: {'trackId': trackId, 'fromSpmid': 'tm.recommend.0.0'}`。`bangumi` 分支（`:37-41`，`PageUtils.viewPgc`）：若 `viewPgc` 最後也走 `toVideoPage`，加一個可選參數把同樣的 extraArguments 傳下去；若改動需要超過 `viewPgc` 本身與其直接呼叫的函式，就只做 `av` 分支，並記在「實作偏差」。其他入口不帶。
3. `VideoDetailController`（`lib/pages/video/controller.dart:428` 附近讀 `args`）：讀 `args['trackId'] as String? ?? ''`、`args['fromSpmid'] as String? ?? ''`，存成欄位。
4. 播放器設定資料來源時，把 `trackId`、`fromSpmid` 傳給 `PlPlayerController`（找出 VideoDetailController 把 aid／cid／epid 等交給 PlPlayerController 的地方，一起傳）。每次新影片都要覆寫，避免沿用上一部（PlPlayerController 是共用實例，迷你播放器會接手）。
5. 同一頁內切換分 P／選集、或從相關影片進入新影片：分 P／選集沿用同一個 `trackId`（同一次點擊）；從相關影片開新頁時是新的 VideoDetailController，不帶 trackId。

#### App 心跳 session（T-3）

在 `PlPlayerController` 新增 App 心跳狀態（可抽成同檔或新檔 `lib/plugin/pl_player/utils/mobile_heartbeat.dart` 的類別）：

| 欄位 | 計算 |
|---|---|
| `session` | 新 session 開始時產生的 32 字元隨機小寫 hex |
| `start_ts` | 新 session 開始時的 epoch 秒；START 也填這個值 |
| `played_time` | 播放中經過的牆鐘秒數累計（用 `Stopwatch` 或時間戳，只在 playing 狀態累加） |
| `paused_time` | 暫停中經過的秒數累計 |
| `total_time` | `played_time + paused_time` |
| `actual_played_time` | 每段播放秒數 × 當時倍速，累計後取整 |
| `last_play_progress_time` | 目前播放位置（秒） |
| `max_play_progress_time` | 本 session 最大播放位置（秒） |
| `video_duration` | 影片長度（秒） |
| `quality` | 目前畫質 qn，取不到填 0 |

session 生命週期：

- **開始**：某個 (aid, cid) 第一次進入 playing 狀態時，建立 session，送 START（累計欄位 0、`last/max_play_progress_time` 0）。
- **END**：暫停（playing → paused）、播放完成、離開頁面／交給迷你播放器以外的關閉、切換分 P 前，送 END（累計值）。暫停後再播放沿用同一個 session（不再送 START），下次暫停再送 END（累計到當時）。
- **結束 session**：播放完成、切換 cid、頁面 dispose、睡眠定時結束。之後同一 cid 再播放會開新 session。
- 掛點：**不要**呼叫或修改現有 web 的 `makeHeartBeat` 判斷（它會擋掉 `progress == 0` 與暫停狀態：`lib/plugin/pl_player/controller.dart:1171`、`:1739-1742`）。App 心跳獨立處理：
  - START／暫停 END：在 `stream.playing.listen`（`lib/plugin/pl_player/controller.dart:1150-1174`）中依 `playing` true／false 直接處理，不受 `seconds != 0` 限制。
  - 完成：`stream.completed`（`:1186` 附近）送 END 並結束 session。
  - 離開與切換：在 `lib/pages/video/controller.dart:1290-1313` 的 `makeHeartBeat` 呼叫點旁（頁面 dispose、分 P 切換）與 `lib/services/shutdown_timer_service.dart:122` 呼叫 App 心跳的「結束 session」，但交給迷你播放器時不結束。
  - 不在每個 position tick 送 App 心跳。
- **session 快照**：session 建立時把 `aid`、`cid`、`epid`、`seasonId`、`type`、`subType`、`trackId`、`fromSpmid`、`videoDuration` 複製進 session 物件；END 一律使用 session 內的值，不讀 PlPlayerController 目前的欄位，避免換片時把新影片的 trackId 送給舊影片。PlPlayerController 的 `trackId`／`fromSpmid` 欄位在每次 VideoDetailController 設定新影片時覆寫（非推薦入口覆寫為空字串）。
- seek 不送（不做）。
- 條件：與 web 心跳相同的開關（`enableHeart`：`Accounts.heartbeat.isLogin && !Pref.historyPause`）；`isLive` 不送；只處理 `videoType` 為 UGC（type 3）與 PGC（type 4），其他型別不送；`aid > 0 && cid > 0`。

#### 請求（T-3）

`lib/http/api.dart` 新增 `Api.heartBeatMobile = '/x/report/heartbeat/mobile'`（api.bilibili.com，和現有 `heartBeat` 同 base）。`lib/http/video.dart` 新增 `VideoHttp.heartBeatMobile(...)`：

- `POST`，`Options(contentType: Headers.formUrlEncodedContentType)`。
- 參數：上表欄位，加上：
  - `mid`：`Accounts.heartbeat.mid`
  - `aid`、`cid`；`sid`（PGC 用 seasonId，UGC 空字串）；`epid`（PGC 用 epId，UGC 0）
  - `type`：UGC `3`、PGC `4`；`sub_type`：PGC 用現有 subType（pgcType），否則 0
  - `from`：`6`；`from_spmid`：傳入值；`spmid`：UGC `main.ugc-video-detail.0.0`，PGC `pgc.pgc-video-detail.0.0`
  - `track_id`：傳入值（可為空字串）
  - `play_type`：`1`；`network_type`：`1`；`auto_play`：`0`；`user_status`：大會員 `1`，否則 `0`（專案已有 VIP 狀態時使用，沒有就填 `0`）
  - `epid_status`、`play_status`：空字串；`list_play_time`、`miniplayer_play_time`：`0`；`is_auto_qn`：`0`；`is_audio_play`：`2`；`cur_language`：`zh-Hans`
  - 共同參數：`platform=android`、`mobi_app=android_hd`、`build=2001100`、`channel=master`、`c_locale=zh_CN`、`s_locale=zh_CN`、`access_key=Accounts.heartbeat.accessKey`
  - `Accounts.heartbeat.accessKey` 為 null 或空字串時，**整個 App 心跳不送**（建立 session 前就判斷），web 心跳照舊。
  - 最後用 `AppSign.appSign(params)`（預設 HD 金鑰）加 `appkey`、`ts`、`sign`。
- 帳號路由：在 `lib/utils/accounts/api_type.dart` 把 `Api.heartBeatMobile` 加入和 `Api.heartBeat` 相同的 heartbeat 分類，讓 interceptor 使用「記錄觀看」帳號，未登入時取消。
- 錯誤處理：整個呼叫包 try/catch，失敗只在 `kDebugMode` 下 `debugPrint` code／message，不丟例外、不提示使用者。成功時 `kDebugMode` 下也 `debugPrint` 一行（含 START/END、track_id 是否非空），方便使用者用 debug 版確認。
- 現有 web 心跳 `VideoHttp.heartBeat` 完全不變。

## 任務

| 任務 | 內容 | 檔案 | 相依 |
|---|---|---|---|
| T-1 | `DeviceFp`、feed/index 統一 HD 身分（含前置檢查腳本）、四處 fp／session 替換 | `lib/utils/device_fp.dart`（新）、`lib/http/video.dart`（114-230）、`lib/http/live.dart` | 無 |
| T-2 | 解析 `track_id`、卡片傳遞、VideoDetailController 讀取並傳給 PlPlayerController | `lib/models/model_rec_video_item.dart`、`lib/models/home/rcmd/result.dart`、`lib/common/widgets/video_card/video_card_v.dart`、`lib/pages/video/controller.dart`、`lib/plugin/pl_player/controller.dart` | 無 |
| T-3 | App 心跳 API、session 計算、掛點、帳號路由 | `lib/http/api.dart`、`lib/http/video.dart`（新函式）、`lib/utils/accounts/api_type.dart`、`lib/plugin/pl_player/controller.dart`、`lib/pages/video/controller.dart`、`lib/services/shutdown_timer_service.dart`、可選新檔 `lib/plugin/pl_player/utils/mobile_heartbeat.dart` | T-2（同檔，交給同一個子代理依序做） |

分派：T-1 一個 Sonnet 子代理；T-2 + T-3 一個 Sonnet 子代理。兩者都會改 `lib/http/video.dart` 的不同區段，編輯前重新讀檔。

## AC 驗證方式

| AC | 方式 |
|---|---|
| AC-1、AC-2、AC-3 | diff 審查；使用者用 debug 版看 `debugPrint` log 測試（待使用者測試） |
| AC-4 | diff 審查：web 心跳程式碼未變、開關條件共用 |
| AC-5 | diff 審查 |
| AC-6 | T-1 前置檢查腳本輸出 `feed-identity-check.txt`；使用者實機確認 |
| AC-7 | diff 審查：try/catch、不提示 |
| AC-8 | `flutter analyze` |

## 邊界情況與風險

- 伺服器可能拒絕 HD 金鑰簽的 `heartbeat/mobile`（官方 App 簽名在 native）。AC-7 保證安全失敗；debug log 可看到 code。
- 迷你播放器接手：PlPlayerController 共用，session 與 trackId 必須依 (aid, cid) 判斷是否是新 session；交給迷你播放器時不結束 session。
- 倍速中途改變：`actual_played_time` 依每段倍速累計。
- App 進背景時播放器會暫停：照一般暫停處理送 END。
- 參數表來自第三方逆向，欄位可能不完整；伺服器若對未知欄位回 `-400`，debug log 會看到，再調整。
- 回退：移除 `heartBeatMobile` 呼叫即可；B-2 只改 query 與 header 常數。

## 審查紀錄

agy（gemini-3.8-flash-high）2026-11-07，逾時但回傳 4 條，全部採用：

1. 掛點錯誤：現有 web `makeHeartBeat` 會擋掉 0 秒與暫停狀態，START／暫停 END 送不出。改為在 `stream.playing` 獨立處理。
2. `access_key` 可能為空：改為沒有 access_key 時不送 App 心跳。
3. 推薦頁番劇卡片漏傳：`bangumi` 分支也傳 trackId（改動過大時記為偏差）。
4. 換片時 END 可能帶到新影片的 trackId：session 建立時快照識別欄位。

## 實作偏差

（實作時填寫）

- T-1：無（前置檢查通過：舊／新參數皆 code=0，items 12／20，五個 key 皆齊全；已改為 HD 身分）
- T-2/T-3：`PageUtils.viewPgc` 新增可選參數 `trackId`／`fromSpmid`，在直接呼叫的 `toVideoPage` 中放進 extraArguments（bangumi 分支已傳）。
- T-3：`account_mgr.dart` 的未登入取消判斷（原本只比對 `Api.heartBeat`）加入 `Api.heartBeatMobile`，落實「未登入時取消」。
- T-3：額外在 `PlPlayerController.dispose()` 最終銷毀路徑（含迷你播放器關閉）呼叫結束 session；倍速改變前先把前一段計入 `actual_played_time`；位置只在 position listener 中記錄（不送請求）。
- T-3：`quality` 由 `VideoDetailController.playerInit` 寫入 `PlPlayerController.hbQuality`。`user_status` 用 `Accounts.isMainVip`。
