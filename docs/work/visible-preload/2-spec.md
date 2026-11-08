# 需求與規格：預載入畫面上所有影片卡（visible-preload）

日期：2026-11-08
前一階段：[../fast-start-2/](../fast-start-2/)（停止捲動後預取前 6 張卡片的 playurl；開頭只在 tap-down 預熱，最多保留 4 個網址）

## 需求

目標：首頁推薦停止捲動後，畫面上所有影片卡都預先準備好（播放網址＋開頭資料），點哪一張都能接近即點即播；流量行為由使用者在設定中選擇。

使用者決定（2026-11-08）：設定中可選：關閉／僅 Wi-Fi／一律（**預設：一律**，Wi-Fi 與行動網路都預載入）。

### 驗收條件

- **AC-1**：新增設定「預載入畫面上的影片」，選項：關閉、僅 Wi-Fi、一律（預設）。設定搜尋找得到。
- **AC-2**：模式為「僅 Wi-Fi」且目前是 Wi-Fi，或模式為「一律」時：停止捲動後（沿用現有 300 ms debounce），畫面上**所有**可見且有 bvid、cid 的影片卡（不再限 6 張）都預取 playurl，並在 playurl 完成後預熱影片與音訊開頭（沿用 `selectStreams`／`warmStreams`，只在 BTR 播放開啟時）。
- **AC-3**：模式為「關閉」，或「僅 Wi-Fi」但目前是行動網路時：維持目前行為（可見卡片只預取 playurl，最多 6 張；開頭只在 tap-down 預熱）。
- **AC-4**：預熱保留上限由 4 改為可容納整個畫面：最多 16 個網址（約 8 部影片的影片＋音訊）；超過時釋放最舊且沒有讀取中的。
- **AC-5**：可見卡片的預熱併發最多 2 部影片（4 個網址）；`ScrollStartNotification` 時清空尚未開始的預熱佇列（已開始的讓它完成，不取消）。
- **AC-6**：已預熱或預熱中的網址不重複預熱；playurl 快取命中但已過期時重新取得後再預熱。
- **AC-7**：遇到限流退避（現有 5 分鐘）期間，可見卡片的 playurl 預取與預熱都暫停；tap-down 不受影響。
- **AC-8**：頁面不可見、App 進背景時（現有 `isPaused`）不排程新的預熱。
- **AC-9**：`flutter analyze` 無新增錯誤或警告。

### 不做

- 推薦以外的頁面。
- 預先建立播放器。

## 設計

- 設定：`lib/utils/storage_key.dart` 加 key、`lib/utils/storage_pref.dart` 加 getter（enum 或 int：0 關閉、1 僅 Wi-Fi、2 一律，預設 2）；設定頁放在播放或推薦相關的設定 model（選現有最合適者，用 Popup/Radio 類型的既有 model），並登錄到 `lib/pages/setting/models/setting_tree.dart` 對應節點的 `titles`。
- 網路判斷：沿用專案現有的 Wi-Fi 判斷（`ConnectivityUtils.isWiFi` 或同等），每次排程時判斷一次。
- `lib/pages/rcmd/view.dart`：`_collectVisible` 只負責收集畫面上所有可見卡片（不截斷、不判斷網路）；截斷 6 張與 Wi-Fi／設定判斷都在非同步的 `PlayUrlCache.prefetchVisible` 內處理（`ConnectivityUtils.isWiFi` 是 Future）。
- `lib/utils/play_url_cache.dart`：`prefetchVisible` 依設定與網路決定是否預熱、是否截斷 6 張；playurl 完成後對該卡片預熱。**快取命中且未過期的卡片不能直接略過**（`:172-176` 目前會 `continue`）：要用快取的結果送入預熱佇列。預熱佇列併發 2 部影片、去重、可清空（`clearPending` 與 `clear()` 都要清空預熱佇列；帳號切換走 `clear()`）；退避與 `isPaused` 期間不排程。
- `lib/utils/play_url_select.dart`：沿用 `defaultSelectParams()`／`warmStreams()`，確保與影片頁選到同一網址。
- `lib/services/download/btr_proxy.dart`：`_maxWarmed` 改 16；淘汰時跳過讀取中的（現有 `evict` 延後釋放邏輯保留）。
  - `BtrProxy.warm` 目前是 `void`、背景執行：改為回傳下載完成（成功或失敗）的 `Future`，讓預熱佇列能真正限制同時下載數（`warmStreams` 也回傳 Future，等影片與音訊都結束）。
  - `hasWarm` 目前檢查 `_warm != null`，釋放後仍為 true，過期後永遠不會再預熱：改為「有可用的 buffer 或正在下載」才算已預熱，釋放後可重新預熱。

## 任務

| 任務 | 內容 | 檔案 |
|---|---|---|
| T-1 | 全部（單一 Sonnet 子代理） | 上述檔案 |

## 驗證

`flutter analyze`；功能待使用者實機測試（debug log：`PlayUrlCache visible prefetch`、`BTR: warm start`、`BTR: warm hit`）。

## 風險

- 流量：預設「一律」，行動網路每次停止捲動約多 6～8 MB（使用者 2026-11-08 選擇此預設）；使用者可改為僅 Wi-Fi 或關閉。
- 記憶體：最多 16 × 512 KB ≈ 8 MB。
- 限流：playurl 請求變多；已有退避。

## 審查紀錄

agy（gemini-3.8-flash-high）2026-11-08，5 條全部採用：

1. `BtrProxy.warm` 沒有 Future，佇列無法限制併發：改回傳完成的 Future。
2. 快取命中的卡片被略過，開頭永遠不預熱：命中時用快取結果送入預熱佇列。
3. `hasWarm` 釋放後不重置：改為有 buffer 或下載中才算已預熱。
4. `ConnectivityUtils.isWiFi` 是 Future，不能在 `_collectVisible` 判斷：改在 `prefetchVisible` 處理截斷與網路。
5. 帳號切換沒清空預熱佇列：`clear()` 也要清空。

## 實作偏差

- 設定放在「首頁推薦」設定頁（`recommend_settings.dart`，NormalModel＋SelectDialog，仿「網速單位」），title 登錄在 setting_tree 的 `recommend` 節點。
- 可見卡片的 playurl 完成後，只在「世代」未變（期間沒有 `clearPending`／`clear`）時才加入預熱佇列，避免捲動後仍預熱已離開畫面的卡片。
- 預熱中取得 playurl 遇到風控錯誤時，同樣觸發退避。
- 「預熱開啟」另需 `BtrConfig.playback` 為 true；否則維持只預取 playurl（最多 6 張）。

### 審查修正

- LRU 淘汰改為釋放最舊且沒有讀取者（users == 0）的預熱；全都在讀取時不淘汰。
- 預熱失敗（received == 0）立即釋放 buffer；`hasWarm` 為「下載中，或有 buffer 且 received > 0」，可重試。
- `prefetchVisible` 在 await 後檢查 `_generation`、`isPaused`、退避，過期就返回。
- 快取命中的卡片先用 `BtrProxy.isWarm` 判斷兩條串流是否已預熱，已預熱就不排入佇列。
- `warmStreams` 加 15 秒逾時，`finally` 一律釋放併發名額。
- 移除固定的 `_maxWarmed`：容量 = max(4, 可見卡片數 × 2 + 2)，由 `BtrProxy.setWarmCapacity` 在 `prefetchVisible` 設定，縮小時依相同規則淘汰。
