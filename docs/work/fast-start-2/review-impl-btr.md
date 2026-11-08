1. `lib/services/download/btr_proxy.dart:1109-1110`
- **問題**：Hedge 勝出時，落敗的 primary 節點被誤判為 `slow: true, cancelled: false` 並遭降速懲罰，違反 AC-6、Design D 與實作偏差 T-3（「primary 輸給 hedge 也只取消（不降速）」）。
- **具體失敗情境**：Primary 節點正常且在 0.9 秒回傳第一個 chunk，但 hedge 節點在 0.85 秒先抵達並勝出。Primary 落敗進入清理迴圈時，因符合 `r == reqs.first` 導致 `slow` 為 true、`cancelled` 為 false；`pool.report` 與 `BtrHostStats` 將其速度 EMA 減半，使原本良好的節點在後續請求中被錯誤降權。
- **具體修復**：只要有 winner，未出錯的落敗者（無論 primary 或 hedge）皆僅為單純取消：
```dart
slow: !genuine && !stopped && winner == null,
cancelled: stopped || (!genuine && winner != null),
```

2. `lib/common/widgets/video_card/card_preview.dart:30, 35`
- **問題**：`onTapDown` 綁定 `_on`，而 `_on` 依賴 `VideoPreview.enabled`。當使用者關閉「卡片預覽」時，按下卡片不會觸發 `prefetch()`，導致 tap-down 預熱完全失效，違反 AC-4 與實作偏差 T-2（「預覽啟用與否都會預熱」）。
- **具體失敗情境**：使用者在設定中關閉影片預覽。在首頁推薦按下卡片時，因 `VideoPreview.enabled == false` 使得 `onTapDown` 為 null，完全不會呼叫 `VideoPreview.prefetch`，造成 `_warmHead` 與 `warmStreams` 永遠不被執行。
- **具體修復**：讓 `onTapDown` 不受預覽開關限制，卡片可用即可觸發預取：
```dart
GestureTapDownCallback? get onTapDown =>
    canPreview && !suspended ? (_) => prefetch() : null;
```

3. `lib/services/download/btr_proxy.dart:1090, 1109`
- **問題**：Hedge 計時器僅有一個從 primary 起算的 2 秒 `silentTimer`；0.8 秒啟動的 hedge 節點在 2.0 秒被截斷時僅運行了 1.2 秒，卻在 `winner == null` 時被判定為 `slow` 降速，違反實作偏差 T-3（「兩者都 2 秒無資料才各自 slow」）。
- **具體失敗情境**：Primary 靜默，hedge 於 0.8 秒啟動且其連線正常但在 1.3 秒才傳回資料。2.0 秒時 `silentTimer` 觸發中斷，hedge 在僅等候 1.2 秒（未滿 2 秒）的情況下被記入 `slow: true`，速度遭折半懲罰。
- **具體修復**：統計 `slow` 時檢查該請求是否確實達到 2 秒逾時：
```dart
slow: !genuine && !stopped && winner == null && r.watch.elapsed >= _BtrSource._headTimeout,
```

4. `lib/services/download/btr_proxy.dart:346, 448`
- **問題**：預熱超過 4 筆淘汰最舊項目時，直接呼叫 `releaseWarm()` -> `release()`，未檢查 `users > 0`，違反實作偏差 T-2（「serve 讀取中不會釋放」）。
- **具體失敗情境**：播放器正在透過 `_serveWarm()` 讀取預熱緩衝區（`users == 1`）。此時若快速觸發其他卡片預熱使 `_warmed` 超過 4 筆，正在播放的 source 被逐出並執行 `release()`，`buffer` 被強制設為 null，導致 `_serveWarm()` 讀取中斷，被迫改向 CDN 重新連線拉取剩餘開頭。
- **具體修復**：`release()` 檢查若 `users > 0` 則先只執行 `onRelease()`（移出佇列），保留 `buffer` 待 `_serveWarm` 結束時由 `armRelease()` 延後釋放。
