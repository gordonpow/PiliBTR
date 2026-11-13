# 規格：碰到即預覽、開影片計時與快速起播

對應需求：[1-requirements.md](1-requirements.md)

## 設計

### A. 碰到即預覽

現況：
- `CardPreview.longPress`：第一次長按預覽，第二次執行原動作（`lib/common/widgets/video_card/card_preview.dart:41-48`）。
- `SwipePreviewDetector`（頁面層 `Listener`）：垂直滑動超過 18px 後，手指停 250 ms 才預覽手指下的卡片（`swipe_preview.dart`）。只有部分頁面包了 detector。
- 每張可預覽卡片都經 `CardPreview.wrapTarget` 包成 `SwipePreviewTarget`（16 個檔案）。

新做法：
1. **卡片層按下即預覽**：`SwipePreviewTarget.build` 改成回傳 `Listener(behavior: HitTestBehavior.translucent, onPointerDown: ...)` 包住 child。按下時（只處理主要觸控／滑鼠左鍵，`e.buttons` 含 primary 或 kind 為 touch）：
   - 若 `enabled`、`VideoPreview.enabled`、目前 route 是最上層（`ModalRoute.of(context)?.isCurrent != false`）、`TickerMode` 開啟，且 `VideoPreview.active.value != item`：呼叫 `onPrefetch()` 再 `VideoPreview.start(item)`。
   - `Listener` 不參與手勢競爭，所以 `InkWell` 的點擊、長按與外層 `Scrollable` 捲動都不受影響。
   - 因為放在卡片層，沒包 `SwipePreviewDetector` 的頁面（搜尋、UP 主頁等）也會生效。
2. **滑動跟著手指換卡**：`SwipePreviewDetector` 移除 dwell 計時（`_dwell`、`_still2`、`_anchor`、`_timer`、`_restart`）。在 `_onMove` 中只要是自己追蹤的 pointer，就找手指下的 target（沿用 `_onRest` 的查找與檢查邏輯，改名 `_previewUnderFinger`），不同於目前預覽的卡就立刻 `onPrefetch` + `start`。
   - 保留 slop 判斷：未超過 18px 前不處理（按下已由卡片層處理）；第一次超過時若橫向為主（切換首頁分頁），呼叫 `VideoPreview.stop()` 停止目前預覽（AC-4a），並停止追蹤。
   - 為避免每個 move 事件都 `start`，記住上次命中的 target，只在手指下的 target 改變時才 `start`。`_onDown` 時把「上次命中」設為按下位置下的 target（與卡片層 Listener 啟動的是同一張）。
   - 拖動時內容跟著手指移動，手指下的卡片通常不變，所以拖動中不會頻繁換卡；只有手指在卡片之間移動時換卡。慣性滑動沒有 pointer move，不換卡。
   - `SwipePreviewDetector.enabled`（`videoPreviewOnSwipe`）不再讀取；`_active` 只看 `VideoPreview.enabled`。
3. **長按恢復原動作**：`CardPreview.longPress(second)` 改為先 `VideoPreview.stop(item)` 再 `second()`；`longPressOr(second)` 改為：`second == null` 時回傳 null，否則回傳 `() { VideoPreview.stop(item); second(); }`（canPreview 為 false 時直接回傳 second）。保留方法簽名，呼叫端不用改。更新類別註解（不再是「第一次長按預覽」）。
3a. **清除舊進度（AC-4b）**：`lib/common/widgets/video_card/video_preview.dart` 的 `_progress` 只在 `_onPosition` 寫入、從不清除。`VideoPreview.start(item)` 時把 `_progress` 設為 null（新的預覽開始，舊位置作廢）；`stop` 時不清（影片頁 take 需要）。確認 `takeProgress`／`progressOf` 在 `_progress == null` 時回傳 null，影片頁就從頭（或歷史進度）播放。
4. **設定**：`lib/pages/setting/models/recommend_settings.dart`
   - 「長按影片預覽」改為標題「影片卡片預覽」、說明「手指碰到影片卡片就直接在卡片上預覽（預設靜音），滑動時跟著手指換卡」。key 仍為 `videoCardPreview`。
   - 移除「滑動時預覽」`SwitchModel`。若 `lib/pages/setting/models/setting_tree.dart` 的 `titles` 集合或其他地方列了「長按影片預覽」「滑動時預覽」標題，同步改名／移除（搜尋全專案字串）。`SettingBoxKey.videoPreviewOnSwipe` 常數保留（舊資料無害），但不再使用；若留下未使用常數造成 analyze 警告則刪除。

### B. 開影片計時

計時資料掛在影片頁 controller 實例上，避免預覽、預熱與其他頁面汙染；只把「完成的結果」放進全域歷史供面板顯示。

新增 `lib/services/open_timing.dart`：

```dart
/// One video open: times in ms from entering the video page.
class OpenTimingRecord {
  int? playUrlMs; bool playUrlCacheHit = false;
  int? openMs;     // player.open 呼叫（含 BtrProxy.wrap）到完成
  int? headMs;     // 這次開檔的 BTR 首 byte
  int? firstFrameMs;
  String summary(); // 例：「首幀 820 ms（playurl 40 ms 快取・開檔 300 ms・首 byte 180 ms）」；缺的段落省略
}

abstract final class OpenTiming {
  /// 最近一次完成的紀錄與本次啟動最近 20 次首幀（ms）。
  static OpenTimingRecord? last;
  static final List<int> recent = [];
  static void finish(OpenTimingRecord r); // 有 firstFrameMs 才加入 recent（上限 20，先進先出）
  static int? get averageMs;
  /// 影片頁開檔期間的紀錄與該頁串流的原始 URL；BTR 只在 URL 相符時記首 byte。
  static OpenTimingRecord? pending;
  static Set<String> pendingUrls = {};
}
```

記錄點：
- `lib/pages/video/controller.dart`：新增欄位 `final _timing = OpenTimingRecord();` 與旗標 `bool _timingDone = false;`。`_openWatch` 是欄位初始化就開始（`:433`），以它為時間基準。
- playurl：在 `queryVideoUrl` 的 `Success` 分支（約 `:1024`），只在首次查詢（`!fromReset`、`_timing.playUrlMs == null`）記 `playUrlMs`。快取命中：在呼叫 `PlayUrlCache.get` 前用新增的 `PlayUrlCache.has(bvid:, cid:, params:)`（同 `get` 的命中條件：存在、未過期、params 相同，含進行中的請求）判斷，記入 `playUrlCacheHit`。不要用全域 `lastHit` 旗標。
- 開檔：在 `playerInit` 呼叫 `setDataSource` 前，若 `!_timingDone`：設 `OpenTiming.pending = _timing`、`OpenTiming.pendingUrls = {videoUrl, audioUrl}`（非 null 者），並記下 `_openWatch` 時間；`setDataSource` 完成後 `openMs = 經過時間`，然後清 `pending`／`pendingUrls`。若 player 走重用路徑（`pl_player/controller.dart` `_canReuse`）也照記，`summary` 會如實反映。
  - 這樣不需改 `pl_player/controller.dart` 的計時邏輯（C 的參數仍改它）。
- 首 byte：`lib/services/download/btr_proxy.dart:1138` 附近（不限 debug），若 `OpenTiming.pending != null`、`pending.headMs == null`，且這次 head 請求的原始 URL（BTR 包裝前的 CDN URL，請在該函式找到對應變數；若只能拿到 path，則比對 URL 的 path 部分）屬於 `OpenTiming.pendingUrls`，記 `headMs = winner.watch.elapsedMilliseconds`。
- 首幀：`_watchFirstFrame` 只在 `!_timingDone` 時記錄（切畫質、重新 `playerInit` 不再記）。成功時 `firstFrameMs = _openWatch.elapsedMilliseconds`，`_timingDone = true`，`OpenTiming.finish(_timing)`；debug 仍 `debugPrint('OPEN-TIME ...')`。逾時時 `_timingDone = true`，不加入 recent。
  - 若 `waitUntilFirstFrameRendered` 在重用 controller 時已完成（立即完成），數字會偏小：可接受，但若 `firstFrameMs < (openMs ?? 0)` 就不加入平均。

顯示：`lib/plugin/pl_player/widgets/cdn_status_panel.dart` 加兩行（沒有資料時不顯示）：
- 「開啟耗時：<OpenTiming.last.summary()>」
- 「平均首幀：<averageMs> ms（最近 N 次）」
面板本來每秒重繪，直接讀即可。

### C. 快速起播參數

- 新增設定 `SettingBoxKey.fastStart = 'fastStart'`（`lib/utils/storage_key.dart`），`Pref.fastStart`（`lib/utils/storage_pref.dart`，預設 true）。
- 設定頁：放在播放相關設定（找 `bufferSec`／緩衝設定所在的 settings model 檔），`SwitchModel` 標題「快速起播」，說明「縮短開影片時的格式探測，加快首幀；若出現黑畫面或沒聲音請關閉」。若 setting_tree 需要登記標題，一併加入。
- `lib/plugin/pl_player/controller.dart` `_createVideoController`：非直播且非 FileSource、`Pref.fastStart` 為 true 時，在 `extras` 加入：
  - `'demuxer-lavf-probe-info': 'nostreams'`
  只用這一個（審查：`nostreams` 會跳過 `avformat_find_stream_info`，另外兩個參數幾乎無作用，也無法歸因）。B 站 DASH 為 fMP4，串流資訊在 init segment（moov）。是否對 `edl://` 子 demuxer 生效要實機 A/B（開關各開同一部影片數次比較面板的平均首幀）。
- 不改 `cache-secs` 等緩衝設定，不改 hwdec。

## 要改的檔案

| 檔案 | 改什麼 |
|---|---|
| `lib/common/widgets/video_card/swipe_preview.dart` | Target 加 `Listener` 按下即預覽；Detector 移除 dwell，移動時立即換卡 |
| `lib/common/widgets/video_card/card_preview.dart` | `longPress`／`longPressOr` 恢復原動作，更新註解 |
| `lib/pages/setting/models/recommend_settings.dart` | 預覽設定改名、移除滑動預覽開關 |
| `lib/pages/setting/models/setting_tree.dart` | 同步標題（若有） |
| `lib/services/open_timing.dart` | 新增 |
| `lib/pages/video/controller.dart` | 記錄 playurl、首幀，寫日誌 |
| `lib/utils/play_url_cache.dart` | 新增 `has()` 判斷命中 |
| `lib/common/widgets/video_card/video_preview.dart` | `start` 時清除舊進度 |
| `lib/plugin/pl_player/controller.dart` | 快速起播參數 |
| `lib/services/download/btr_proxy.dart` | 記錄首 byte |
| `lib/plugin/pl_player/widgets/cdn_status_panel.dart` | 顯示開啟耗時 |
| `lib/utils/storage_key.dart`、`lib/utils/storage_pref.dart`、播放設定 model | `fastStart` 設定 |

## 任務

| ID | 任務 | 相依 | 完成條件 |
|---|---|---|---|
| T-1 | A：碰到即預覽、滑動換卡、橫滑停止、長按恢復、清除舊進度、設定調整 | — | analyze 無新 issue |
| T-2 | B：OpenTiming 計時、CDN 面板顯示最近一次與平均 | — | analyze 無新 issue |
| T-3 | C：快速起播設定與參數 | T-2（同檔 `pl_player/controller.dart`，依序做） | analyze 無新 issue |

T-1 與 T-2/T-3 檔案不重疊，可平行；T-2、T-3 由同一個實作者依序做。

## 驗證計畫

| AC | 驗證方式 | 證據 |
|---|---|---|
| AC-1~AC-4b | 程式碼審查；使用者實機測試（劇本：按下即播；按下後上下拖動；手指跨卡移動換卡；按下後橫滑切分頁預覽停止；慣性滑動中按停；長按出選單且預覽停止；預覽過同一影片後再快速輕點，影片頁不從舊位置播） | diff 審查結果；待使用者測試 |
| AC-5 | 程式碼審查（設定 model） | diff |
| AC-6 | 程式碼審查；使用者開影片看 CDN 面板與日誌 | 待使用者測試 |
| AC-7 | 程式碼審查（extras 條件） | diff |
| AC-8 | `flutter analyze`、`flutter build apk --release --split-per-abi` | 結果行 |

## 邊界情況與風險

- 每次碰卡片都會啟動預覽播放器：耗流量與 CPU。預覽播放器全域只有一個（`video_preview.dart`），換卡不會累積播放器。
- 輕點開影片時，按下已啟動預覽（playurl 與影片頁共用 `PlayUrlCache`，但預覽的 BTR 下載會和影片頁搶頻寬），放開時 `take()` 立即停止。使用者要求零延遲，接受這個代價；若實測平均首幀明顯變差，再考慮按下延遲 80~100 ms。
- 點卡片按鈕（更多選單「⋮」）也會觸發預覽：可接受。
- 多選或排序模式：`enabled == false`，不預覽。
- 被上層頁面覆蓋或分頁隱藏時不預覽（route／TickerMode 檢查）。
- 多指：只處理第一個 pointer（Detector 已有 `_pointer` 判斷；Target 的按下也只在沒有其他 pointer 正在追蹤時才觸發，可簡化為直接觸發，因同一張卡不重複 start）。
- 快速起播參數可能導致少數影片探測不到音軌／畫面：有設定可關。
- 回退：還原本次 commit；或使用者關「快速起播」、關「影片卡片預覽」。

## 審查紀錄

| 來源 | 意見 | 處理 |
|---|---|---|
| 審查者（Sonnet） | 1. 輕點會帶出上次預覽的舊進度 | 採用：A.3a `start` 時清 `_progress`，新增 AC-4b |
| 審查者 | 2. 輕點開影片白白建立預覽，搶頻寬 | 不採用延遲：使用者要求零延遲；寫入風險，實測變差再加 80~100 ms 延遲 |
| 審查者 | 3. 拖動時手指不動、內容在動，會頻繁換卡 | 不採用：拖動捲動時內容跟著手指移動，手指下卡片不變；慣性滑動無 pointer move |
| 審查者 | 4. 按下後橫滑未停止預覽 | 採用：橫向判定時 `VideoPreview.stop()`，新增 AC-4a |
| 審查者 | 5. 上次命中要在 down 設定；長按時停止預覽 | 採用 |
| 審查者 | 6. release logger 等級為 warning，LoggerUtils 無寫入方法 | 採用：日誌檔為 Catcher JSON 格式，改為面板顯示最近一次與平均，修改 AC-6 |
| 審查者 | 7. 全域靜態計時會被預覽／預熱汙染；`lastHit` race | 採用：計時掛在 controller；BTR 只記 pendingUrls 的首 byte；`PlayUrlCache.has()` |
| 審查者 | 8. playurl 只記首次；首幀只記首次；重用 player 缺段 | 採用 |
| 審查者 | 9. 三個 lavf 參數只需 `nostreams` | 採用：只用 `nostreams`，預設開，使用者 A/B |
| 審查者 | 10. 缺手測劇本 | 採用：驗證計畫列出劇本。widget test 不做（本機無法跑 `flutter test`） |

## 實作偏差

- 實作者：agy 額度用完（429，約 119 小時後重置），T-1、T-2/T-3 改由 Sonnet 子代理實作。
- B：`OpenTiming.pending` 原規格在 `setDataSource` 完成後清除；但 `player.open` 送出 loadfile 就返回，BTR 首 byte 在之後才發生，會記不到。改為首幀完成／逾時、`videoController` 為 null、`onClose` 時才清（Opus 修正）。
- B：本機檔（`isFileSource`）不計時。
- A：`setting_tree.dart` 沒有舊標題，未改；`videoPreviewOnSwipe` 常數保留（無 analyze 警告）。
- 英文語言包 `i18n/en.json` 尚未加入新字串（影片卡片預覽、快速起播、開啟耗時等），英文模式會顯示中文。
