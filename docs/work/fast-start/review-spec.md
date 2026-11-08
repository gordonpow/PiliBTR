### 1. 首播畫質請求與 API 次數矛盾（更簡設計）
- **規格章節**：C.1（補齊畫質不阻擋）
- **問題**：`_queryVideoUrl` 於現有程式碼固定請求最高畫質 `hdrVivid`（line 956），B 站此請求多半不含 1080P/720P。若僅改為不 await `_supplementVideoQualities`，開播時在 `dash.video` 根本找不到 1080P 串流，導致播放器被迫播 4K/HDR（違反 AC-10 預設 1080P 上限）或選流異常；且背景仍必發第二次 API，未達成需求「少一次 API」。
- **程式碼證據**：[`lib/pages/video/controller.dart:906-913`](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/pages/video/controller.dart#L906-L913)、[`lib/pages/video/controller.dart:956-960`](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/pages/video/controller.dart#L956-L960)
- **具體修正**：首播直接以目標畫質（1080P，`cacheVideoQa`）請求 `_getVideoUrl`。B 站回傳結果原生包含 1080P、720P、480P、360P，首播直接命中且無需補齊畫質，徹底省下開播第二次 API；僅當使用者手動切換至 >1080P 時才在背景補齊。

---

### 2. Prefetch 快取機制假設錯誤與無法命中（未覆蓋邊界情況）
- **規格章節**：C.2（重用 prefetch）
- **問題**：
  1. `VideoPreview.prefetch` 受 `if (enabled)` 限制，使用者關閉影片預覽時完全不會觸發 tap-down 預取（AC-9 失效）。
  2. 卡片層通常僅有 `aid/bvid`，需額外打 `SearchHttp.ab2cWithDimension` 取 `cid`，耗時過長，點擊進入影片頁時 `PlayUrlCache`（以 cid 為鍵）根本尚未生成。
  3. 預覽與影片頁參數（網路類型、編碼、音量平衡等）難以完全對齊，以全參數為鍵導致命中率極低；且未納入 `mid`，換帳號會誤用上一帳號權限的串流。
- **程式碼證據**：[`lib/common/widgets/video_card/video_preview.dart:163-165, 200-213`](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/common/widgets/video_card/video_preview.dart#L163-L213)、[`lib/pages/video/controller.dart:942-954`](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/pages/video/controller.dart#L942-L954)
- **具體修正**：Tap-down prefetch 脫離 `VideoPreview` 開關；卡片跳轉時提前傳遞已快取的 `cid` 或由卡片實體提供；快取 key 簡化為 `bvid + cid + mid`；切換帳號或登出時強制清空快取。

---

### 3. EDL 頂層開啟失敗漏捕、重試未解除 BTR（現有程式碼假設錯誤）
- **規格章節**：B.1（重試條件 AC-6）
- **問題**：DASH 播放時 `video` 會包裝為 `edl://...`。若 EDL 本身開啟失敗，mpv 報錯為 `Failed to open edl://...`，現有 line 1309-1314 會因非 `https://` 直接 `return` 吞掉錯誤，規格只補 `http://127.0.0.1` 仍會漏抓。此外，line 1302 呼叫 `refreshPlayer()`，若未重新取用原始 `dataSource.videoSource` 開檔，僅重播原 `video` 字串，重試仍會打入本機代理。
- **程式碼證據**：[`lib/plugin/pl_player/controller.dart:1063-1070`](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/plugin/pl_player/controller.dart#L1063-L1070)、[`lib/plugin/pl_player/controller.dart:1282-1286, 1302, 1309-1314`](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/plugin/pl_player/controller.dart#L1282-L1314)
- **具體修正**：錯誤監聽條件加入 `Failed to open edl://`；在 `refreshPlayer()` 中強制還原為未經 `BtrProxy.wrap` 的原始 CDN 網址重新開檔。

---

### 4. 過早 flush 標頭破壞直通 Fallback 與連線洩漏（並行與取消邊界情況）
- **規格章節**：A.2, A.3, A.5（立即送標頭與開頭串流）
- **問題**：`dart:io` 的 `HttpResponse` 一旦 `flush()`，狀態碼與標頭即被送出並鎖定。若隨後開頭片段首 byte 逾時或節點全滅嘗試退回 `_passthrough`，會拋出 `StateError: Cannot set header after headers have been sent` 導致崩潰。此外，`pipeRemaining` 失敗拋出例外時，line 480 `catch` 漏掉 `res.close()`，連線懸掛。
- **程式碼證據**：[`lib/services/download/btr_proxy.dart:189-202`](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/services/download/btr_proxy.dart#L189-L202)、[`lib/services/download/btr_proxy.dart:465-483`](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/services/download/btr_proxy.dart#L465-L483)
- **具體修正**：標頭不在 probe 完立即 flush，延後至開頭片段收到首個 chunk 寫入時再送出；所有節點連線失敗時方可安全 fallback 至 `_passthrough`；`_Pump.run` 最外層加上 `finally { try { await res.close(); } catch (_) {} }`。
