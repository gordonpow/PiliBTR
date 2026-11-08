1. `lib/services/download/btr_proxy.dart:107-109`
- **問題**：LRU 淘汰無條件執行 `_warmed.removeAt(0).evictWarm()`，未依 AC-4 與規格「淘汰時跳過讀取中的」。
- **失敗情境**：使用者點擊影片播放中（`_serveWarm` 讀取中，`users > 0`），後續預熱將 `_warmed` 增至 16 以上，播映中影片被移出並標記 `evicted = true`。首個 chunk 讀完時 `users` 短暫歸零觸發 `release()`，緩衝區直接釋放，播放器後續區段無法命中。
- **修復**：走訪 `_warmed` 尋找第一個 `source._warm?.users == 0` 的項目淘汰；若皆在讀取中則不淘汰。

2. `lib/services/download/btr_proxy.dart:300-303, 308-312`
- **問題**：`_Warm` 建立即配置 512KB buffer，若 `_runWarm` 失敗（節點錯誤、網路中斷），`buffer` 仍不為 null。`hasWarm` 判定 `buffer != null || !done`，導致失敗時（`received == 0`）仍回傳 `true`。
- **失敗情境**：預熱下載失敗，`hasWarm` 仍回傳 `true`。在 30 秒釋放前，後續停捲或手動 tap-down，`BtrProxy.warm` 均因 `hasWarm == true` 直接返回不予重試，喪失預熱機會且白佔 512KB 記憶體。
- **修復**：`hasWarm` 改為 `w != null && ((w.buffer != null && w.received > 0) || !w.done)`；`_runWarm` 結束時若 `w.received == 0` 立即執行 `w.release()`。

3. `lib/utils/play_url_cache.dart:202-236`
- **問題**：`prefetchVisible` 在 `await defaultParams()` 與 `await isWiFi` 前後未比對 `_generation`，跨非同步間隙存在世代競爭。
- **失敗情境**：停捲排程預熱後，正在非同步查詢 Wi-Fi 時使用者滑動觸發 `clearPending()`（世代加一並清空佇列）。Wi-Fi 查詢返回後未察覺世代變更，將已滑走的舊卡片塞入 `_pending`，以新世代執行預取與預熱，AC-5 清空機制失效。帳號切換（`clear()`）同理。
- **修復**：函式開頭記錄 `final gen = _generation;`，await 結束後檢查 `if (gen != _generation || isPaused || _inBackoff) return;`。

4. `lib/utils/play_url_cache.dart:198, 290`
- **問題**：預熱完成後自 `_warmInFlight` 移除，但快取命中路徑無「已預熱」標記，造成重複入隊（違背 AC-6）。
- **失敗情境**：卡片預熱完成後仍在畫面上，每次微幅捲動停頓（300ms debounce），快取命中的卡片均重新加入 `_warmPending` 並佔用 `_warmConcurrency`（2 個名額）反覆執行 `_runWarm`，阻塞新卡片預熱。
- **修復**：新增 `_warmCompleted` 集合記錄已預熱 key；入隊前過濾已完成者，於 `clear()` 時重置。

5. `lib/utils/play_url_cache.dart:314-316`
- **問題**：`_runWarm` 內 `await warmStreams` 缺乏總體 timeout。若 CDN 串流極慢或掛死，`_warmActive` 無法遞減，併發名額永久洩漏。
- **失敗情境**：2 部影片的 CDN 節點在首 byte 後掛死，佔滿 `_warmConcurrency = 2`，後續所有卡片預熱永久卡死在 `_warmPending`。
- **修復**：`warmStreams(...)` 加上 `.timeout(const Duration(seconds: 15))`。
