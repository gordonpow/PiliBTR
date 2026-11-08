### 程式碼審查報告

---

#### 1. `lib/pages/rcmd/view.dart:243`
* **問題**：在 `_collectVisible` 檢查 `grid.debugNeedsLayout`。Flutter 的 `debugNeedsLayout` 是僅限除錯模式的 getter（內部由 `assert` 守衛），在 Release 模式下會直接拋出 `StateError: debugNeedsLayout is only available in debug mode.`。
* **具體失敗情境**：在正式 Release 建置下，首頁推薦載入完成或停止捲動 300 ms 後，Timer 觸發 `_collectVisible()`，執行到第 243 行直接拋出未捕捉的 `StateError`，導致 App 崩潰。
* **修復方式**：移除 `grid.debugNeedsLayout`，保留 `if (grid == null || grid.geometry == null) return const [];` 即可（`grid.geometry != null` 已能保證完成佈局）。

---

#### 2. `lib/common/widgets/video_card/card_preview.dart:30, 35`
* **問題**：`CardPreview.onTapDown` 綁定 `_on`（`_on => canPreview && !suspended && VideoPreview.enabled`），當使用者關閉「影片預覽」時，`onTapDown` 回傳 `null`。雖然 [video_preview.dart](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/common/widgets/video_card/video_preview.dart#L28-L33) 已實作預覽關閉時仍預熱與預取，但外層手勢根本不會觸發。違反 AC-4 與規格實作偏差（「預覽啟用與否都會預熱」）。
* **具體失敗情境**：使用者在設定關閉卡片預覽後，點擊可見卡片時因 `InkWell.onTapDown` 為 `null`，完全不執行 `_warmHead`（開頭不預熱）與 `PlayUrlCache.prefetch`，使 tap-down 快播完全失效。
* **修復方式**：修改 [card_preview.dart](file:///c:/presonal_project/bilibili_bata/PiliPlus/lib/common/widgets/video_card/card_preview.dart#L35)，手勢脫離預覽開關限制：
  ```dart
  GestureTapDownCallback? get onTapDown => canPreview && !suspended ? (_) => prefetch() : null;
  ```

---

#### 3. `lib/pages/rcmd/view.dart:170`
* **問題**：`_RcmdPageState.dispose()` 僅設定 `PlayUrlCache.isPaused = true;`，遺漏呼叫 `PlayUrlCache.clearPending()`。
* **具體失敗情境**：推薦頁面銷毀時（如帳號登出或路由重建），佇列中尚未發出的項目殘留在靜態變數 `_pending` 中；若後續恢復預取，會發送這些已離開視野的舊卡片請求，佔用併發名額。
* **修復方式**：在 `dispose()` 加入 `PlayUrlCache.clearPending();`：
  ```dart
  PlayUrlCache.isPaused = true;
  PlayUrlCache.clearPending();
  ```

---

#### 4. `lib/utils/play_url_cache.dart:677`
* **問題**：`prefetchVisible` 去重檢查 `if (cached != null && now.difference(cached.time) < _ttl) continue;`，未比對請求參數 `params`。
* **具體失敗情境**：使用者在行動網路下產生了 720P 快取，切換至 Wi-Fi 後停止捲動，`prefetchVisible` 因快取未過期直接跳過；點擊進入影片頁時，影片頁使用 Wi-Fi 的 1080P 參數比對快取失敗（`cached.params != params`），造成快取未命中並重發網路請求。
* **修復方式**：在 `_pending` 排程前或 `_runVisible` 內比對當前 `defaultParams()`，若參數不同則不跳過更新。
