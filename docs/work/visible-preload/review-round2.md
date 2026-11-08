### 1. `lib/utils/play_url_cache.dart:242`、`lib/services/download/btr_proxy.dart:153`
- **問題**：不可見項目未淘汰且容量無法縮容，導致可見卡片被滑過的舊卡片擠出淘汰。`setWarmCapacity` 取 `_warmed.length` 導致容量上限永不縮小（直到 30 秒逾時釋放）；且預熱上限僅約當前畫面（約 14 條），佇列消化不可見卡片時，新開頭會直接透過 `_trimWarmed` 釋放（`users == 0` 被視為 idle）畫面上剛預熱好的影片。
- **具體失敗情境**：快速滑過 10 張卡片後停下。目前畫面卡片 A 優先預熱完成進 `_warmed`。接著佇列繼續消化剛才滑過的 10 張舊卡片，每下載一條開頭就觸發 `_trimWarmed`，卡片 A 的 buffer 被立刻 `evictWarm()` 釋放。使用者點擊 A 時開頭已被淘汰，預載完全失效且白費頻寬。
- **具體修正**：停止捲動時應清空非當前畫面的 `_pending` 與 `_warmPending`（不應無止境背景補載）；`setWarmCapacity` 移除 `_warmed.length`，改由真正的畫面卡片數決定上限，縮容時淘汰非畫面且非讀取中的項目。

### 2. `lib/utils/play_url_cache.dart:323`、`lib/utils/storage_pref.dart:321`
- **問題**：AC-16 預設 0（不限制）且無防護，引發請求風暴與 412 風控。`_pumpWarm` 在 `_concurrencyCap == 0` 時以 `while` 迴圈瞬間發起所有累積影片的預熱，連線數無上限。
- **具體失敗情境**：使用者連續滑動 5 秒累積 20 部影片，playurl 完成後瞬間發出 40 條 512 KB 的 CDN 下載連線，並伴隨高頻 playurl API 請求，立即觸發 B 站 Wbi 412 風控（觸發 5 分鐘退避，全部預載暫停）並塞爆網路。
- **具體修正**：AC-16 預設值應改為 2 或 4；即使設定 0，內部仍應保留最大併發防護上限（如 6~8 部）。

### 3. `lib/utils/play_url_cache.dart:185, 200`
- **問題**：非同步競態造成 `_visibleOrder` 順序倒錯與世代無效。`prefetchVisible` 在更新 `_visibleOrder` 前會 `await`（網路/參數判斷），捲動中每 500 ms 觸發一次，且捲動不再遞增 `_generation`。
- **具體失敗情境**：第 1 次呼叫在 `await ConnectivityUtils.isWiFi` 卡住 600 ms，第 2 次呼叫 50 ms 完成並寫入最新畫面順序；隨後第 1 次才完成，將 `_visibleOrder` 覆寫為舊畫面。佇列優先權倒錯，已滑出的卡片被視為最高優先，最新可見卡片反而飢餓。
- **具體修正**：加入呼叫序號計數器（seq），若返回時序號小於全域最新序號則直接放棄，不得覆寫 `_visibleOrder`。

### 4. `lib/pages/rcmd/view.dart:124`
- **問題**：設定「關閉」時捲動仍持續每 500 ms 預取 playurl，違反 AC-3。
- **具體失敗情境**：使用者將「預載入畫面上的影片」設為「關閉」，但在首頁捲動時，`_onScroll` 仍定時每 500 ms 收集並發送最多 6 張卡片的 playurl 請求。
- **具體修正**：啟動 `_scrollThrottle` 前應檢查 `Pref.visiblePreloadMode != 0`，關閉時不啟動定時器。
