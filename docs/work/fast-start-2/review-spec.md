### 1. 設計 B（併發與串流競態）
- **問題**：tap-down 到開播僅約 100～200 ms，512 KB 未載完時播放器即發起請求。若 `_warmHead` 完工後才賦值，`serve` 會誤判無快取而自 byte 0 重複請求 CDN，造成頻寬浪費與連線競態。
- **證據**：`lib/services/download/btr_proxy.dart:66, 117`
- **具體修正**：`_warmHead` 改為支援邊載邊讀的 Stream/Completer，或 `serve` 遇預熱中時等待首區塊資料，避免重複向 CDN 請求同範圍。

### 2. 規格 AC-1 / 設計 A（欠缺捲動取消機制致限流）
- **問題**：未在再次捲動時取消/清空佇列。使用者連續滑動時，背景佇列積壓舊卡片請求，將塞滿併發通道並極易觸發 412 退避。
- **證據**：`lib/utils/play_url_cache.dart:79-90`
- **具體修正**：在 `ScrollStartNotification` 觸發時立即清空尚未發出的預取佇列。

### 3. 規格 AC-5 / 設計 C（假設錯誤且 AC 不可驗證）
- **問題**：`_entries` 僅存於記憶體，冷啟動時必為空且無預設 host。「App 啟動後預連線」因無網址可用必定被略過，該 AC 實質為死代碼且無法驗證。
- **證據**：`lib/utils/play_url_cache.dart:26`、`docs/work/fast-start-2/2-spec.md:18, 49`
- **具體修正**：刪除 AC-5 啟動預連要求，僅保留 playurl 預取成功後的預連線。

### 4. 設計 C（對現有 Dio 行為假設錯誤）
- **問題**：`Request.http11Dio.clone()` 共享底層 adapter，直接修改其 `idleTimeout` 會污染全 App 的全域 HTTP/1.1 連線。
- **證據**：`lib/services/download/btr_cdn.dart:8-13`
- **具體修正**：為 `btrDio` 獨立建立新的 `IOHttpClientAdapter` 實例，不直接修改 clone 繼承的 adapter。

### 5. 設計 B（生命週期邊界致 404）
- **問題**：「30 秒未用釋放」若刪除 `_sources[id]`，使用者延遲點擊時播放器向代理請求會直接收到 404。
- **證據**：`lib/services/download/btr_proxy.dart:110-114`
- **具體修正**：逾時僅釋放 `_warmHead` 位元組陣列，嚴禁移除 `_BtrSource` 代理映射。
