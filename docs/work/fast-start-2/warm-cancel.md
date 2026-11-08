### 1. 取消 warm 下載的所有程式碼路徑
1. **首位元組超時**（[`lib/services/download/btr_proxy.dart#L320-L322`](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/services/download/btr_proxy.dart#L320-L322)）：`_headTimeout`（2 秒）內未收到第一個 chunk 呼叫 `token.cancel()`。
2. **Buffer 被釋放**（[`lib/services/download/btr_proxy.dart#L340-L344`](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/services/download/btr_proxy.dart#L340-L344)）：`w.buffer == null` 時呼叫 `token.cancel()`。來源為 `_Warm.release()`（L250），包含 LRU 淘汰（L105）、30 秒閒置逾時（L233）及 `_serveWarm` finally 釋放（L949）。

### 2. 日誌對應與主因分析
- **主因：2 秒首位元組超時（`_headTimeout`）**。
  - **日誌證據**：所有 11 行 `BTR: warm failed ... request cancelled`（L76、L80、L92、L253、L259、L611、L628、L1798-L1835）的時間差皆精準吻合 2.0～2.1 秒（attempt 0 與 attempt 1）。
  - **程式碼證實**：若由 buffer 釋放（LRU 或閒置）引起，L363-L372 的 `released` 為 `true` 會直接 `return`，不會輸出 `warm failed`。該日誌只在 `w.buffer != null` 時印出，證實 100% 是 2 秒計時器所取消。
- **其他假設排除**：
  - **滾動/手勢取消**：[`card_preview.dart#L37`](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/common/widgets/video_card/card_preview.dart#L37) 無 `onTapCancel`，滾動不會取消 warm。
  - **LRU 淘汰（>4）**：日誌中多次僅預熱 2 條即取消，且淘汰不會輸出日誌。
  - **詳情頁 pump/serve、res.done/seek、預覽播放器**：`_runWarm` 的 `token` 是局部變數，未與外部共享。
  - **帳號切換/reset**：日誌中無重置，且 `reset()` 不會 cancel token。

### 3. _serveWarm 是否實際讀取 warm 數據
**有**。當 CDN 節點在 2 秒內返回首位元組並完成下載時，詳情頁開啟時會完整命中並讀取。
- **證據**：`warm-lines.txt` 中有 4 行 hit（2 次開頁）：L455（音訊 455,227 bytes）、L459（視訊 524,288 bytes）、L867 與 L870（各 524,288 bytes）。
- **機制**：[`play_url_select.dart#L98`](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/utils/play_url_select.dart#L98) 的 `warmStreams` 與詳情頁的 `BtrProxy.wrap` 均使用相同參數與 `http2https` 規範化，產生相同 source `id`，由 [`btr_proxy.dart#L915`](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/services/download/btr_proxy.dart#L915) 的 `_serveWarm` 順利讀取緩衝區。

### 4. 具體修復方案
在 [`lib/services/download/btr_proxy.dart#L275`](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/services/download/btr_proxy.dart#L275) 定義獨立的預熱首位元組超時：
```dart
static const _warmTimeout = Duration(seconds: 4);
```
並在 [`lib/services/download/btr_proxy.dart#L320`](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/services/download/btr_proxy.dart#L320) 將計時器改用 `_warmTimeout`：
```dart
final timer = Timer(_warmTimeout, () {
```
對齊 `btrDio.connectTimeout`（4 秒），避免在 TLS 握手與 CDN 延遲正常（1.5～2.5 秒）時被 2 秒過早掐斷。
