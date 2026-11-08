# 規格

## 原因
1. `PlDanmakuController.queryDanmaku` 失敗時移除段落標記，下一個 100ms 播放 tick 立即重送；每次逾時都經 `AccountManager.toast` 跳提示。
2. 播放器 `PlPlayerController` 是單例；被新影片頁蓋住的舊頁 `PlDanmaku` 仍掛著位置監聽（`didPushNext` 只移除頁面自己的監聽），會用舊 cid 請求彈幕並佔用連線。
3. 離開頁面時進行中的彈幕請求不會取消。
4. `PopupMenuButton` 有 `tooltip` 時內部包 `Tooltip`，其長按手勢在競技場中比外層 `GestureDetector.onLongPressStart` 先勝出，所以長按只顯示 tooltip。

## 任務
- T-1 `lib/grpc/grpc_req.dart`、`lib/grpc/dm.dart`：`request`／`dmSegMobile` 加可選 `CancelToken`。
- T-2 `lib/pages/danmaku/controller.dart`：每個控制器一個 `CancelToken`，`dispose` 時取消並標記 `_disposed`；失敗後 10 秒內不重送（`_retryAfter`）；回應在 dispose 後忽略。
- T-3 `lib/pages/danmaku/view.dart`：`videoPositionListen` 在 `playerController.cid` 與 `widget.cid` 不同時略過。
- T-4 `lib/utils/accounts/account_manager/account_mgr.dart`：`toast` 略過 `DioExceptionType.cancel`，`skipShow` 加 `DmSegMobile`。
- T-5 `lib/plugin/pl_player/view/view.dart`：長按複製開啟時 `tooltip: ''`（`Tooltip` 空訊息直接回傳 child，不建立手勢）。

## 驗證
AC-1～AC-6：diff 審查 + `flutter analyze` + 建置；功能待使用者實機測試。

## 追加：子母畫面
原因：
5. `PlPlayerController.autoPiP` 是 `late final`，`_isAutoEnterPip` 只在單例建構時決定；迷你播放器讓單例長期存在，之後才開啟設定不會生效。
6. `AndroidHelper.updatePipActions` 每次播放／緩衝都送出不含 autoEnter 的新 `PictureInPictureParams`；Android 12（API 31/32）的 `copyOnlySet` 會把 autoEnter 覆蓋成 false。

任務：
- T-6 `lib/plugin/pl_player/controller.dart`：`autoPiP`、`_isAutoEnterPip` 改為每次讀設定的 getter；Android < 12 一律註冊 `onUserLeaveHint`，在 callback 內檢查設定；新增 `syncAutoEnterPip()`。
- T-7 `lib/pages/setting/models/play_settings.dart`：設定切換後呼叫 `PlPlayerController.instance?.syncAutoEnterPip()`。
- T-8 `AndroidHelper.java`：記錄最後的 autoEnter 狀態，`updatePipActions` 在 API 31+ 一併送出。
