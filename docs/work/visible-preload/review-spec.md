### 1. 設計與 AC-5：`BtrProxy.warm` 為非同步但無 Future，併發限制失效
* **章節**：AC-5 / 設計
* **問題**：`warmStreams` 呼叫的 `BtrProxy.warm` 為 `void`，其內部 `startWarm` 非同步執行且無任何回傳。若預熱佇列僅 await `warmStreams`，會在瞬間將所有網址排入背景下載，導致「併發最多 2 部影片」限制完全失效。
* **程式碼依據**：[play_url_select.dart:98-99](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/utils/play_url_select.dart#L98-L99) 與 [btr_proxy.dart:95, 295-301](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/services/download/btr_proxy.dart#L95-L103)。
* **具體修復**：在 `BtrProxy.warm` / `_BtrSource` 暴露下載完成的 Future，或由 `BtrProxy` 內部管理暖機併發，使佇列能真正控制在途下載數。

---

### 2. AC-2 與 AC-6：快取命中項目直接被略過，導致開頭永不預熱
* **章節**：AC-2、AC-6 / 設計
* **問題**：`prefetchVisible` 遍歷卡片時，若命中未過期快取會直接 `continue`。使用者滑回或前次已取 playurl 的卡片將永遠不會觸發開頭預熱。
* **程式碼依據**：[play_url_cache.dart:172-176](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/utils/play_url_cache.dart#L172-L176)。
* **具體修復**：快取命中且未預熱者不可 `continue`，應直接提取其 `PlayUrlModel` 送入預熱佇列。

---

### 3. AC-6：`hasWarm` 釋放後不重置，過期後永久無法重新預熱
* **章節**：AC-6 / 設計
* **問題**：`_Warm.release()` 釋放 buffer 後未清空 `_BtrSource._warm`，使 `hasWarm`（檢查 `_warm != null`）永久為 `true`。30 秒閒置過期後再次可見時會被誤判已預熱，違反 AC-6。
* **程式碼依據**：[btr_proxy.dart:253, 293, 100](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/services/download/btr_proxy.dart#L253)。
* **具體修復**：將 `hasWarm` 改為 `_warm?.buffer != null`，或在 `release()` 時將 `_warm` 設為 null。

---

### 4. 簡化設計與錯誤假設：`rcmd/view.dart` 內做上限與網路判斷
* **章節**：AC-2、AC-3 / 設計
* **問題**：規格要求 `_collectVisible` 依模式決定上限，但 `ConnectivityUtils.isWiFi` 為非同步 `Future<bool>`，無法在同步的渲染樹走訪中讀取，且將策略耦合至 UI。
* **程式碼依據**：[rcmd/view.dart:141, 156](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/pages/rcmd/view.dart#L141-L156) 與 [play_url_cache.dart:47](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/utils/play_url_cache.dart#L47)。
* **具體修復**：`_collectVisible` 僅負責收集畫面可見卡片；截斷 6 張與 Wi-Fi/設定檢查統一由非同步的 `PlayUrlCache.prefetchVisible` 處理。

---

### 5. 邊界情況：帳號切換遺漏清空預熱佇列
* **章節**：設計
* **問題**：規格僅在 `clearPending` 清空預熱佇列，遺漏了 `PlayUrlCache.clear()`。切換帳號時未完成的預熱會以舊帳號權限與網址繼續發起。
* **程式碼依據**：[play_url_cache.dart:238-241](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/utils/play_url_cache.dart#L238-L241)。
* **具體修復**：在 `PlayUrlCache.clear()` 內加入清空預熱佇列與重置預熱狀態。
