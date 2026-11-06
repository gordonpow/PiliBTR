# 規格：重啟提示、CDN 合併、簡繁切換、速度滑桿

需求見 `1-requirements.md`。

## 1. 重啟（AC-1～3、AC-13）

- `android/app/src/main/kotlin/com/example/piliplus/MainActivity.kt`：在 `pilibtr/update` channel 加 `restart` 方法：
  取 `packageManager.getLaunchIntentForPackage(packageName)`，加 `FLAG_ACTIVITY_NEW_TASK | FLAG_ACTIVITY_CLEAR_TASK`，
  用 `Intent.makeRestartActivityTask(component)` 啟動後 `Runtime.getRuntime().exit(0)`。
- 新檔 `lib/utils/app_restart.dart`：
  - `AppRestart.restart()`：Android 呼叫 channel；其他平台 `SmartDialog.showToast('請手動重新啟動 App')`。
  - `AppRestart.ask(BuildContext? context)`：顯示 AlertDialog「需要重新啟動」，內文「設定需要重新啟動 App 才會生效。」，按鈕「稍後」「重新啟動」。用 `showDialog(context: Get.context!)`。
- `lib/pages/setting/models/style_settings.dart` `_showCardColumnsDialog`：寫入排數後（值有改變時）呼叫 `AppRestart.ask()`，取代原本的 toast（若有）。

## 2. CDN 合併（AC-4～8）

- `lib/pages/setting/widgets/select_dialog.dart` `CdnSelectDialog`：改成 `SelectDialog<Object>`，`values` = 三個 `BtrCdnMode`（標籤 `線程撕裂者：${mode.label}`）+ 原本 `CDNService.values`。
  - 目前選取：`BtrConfig.playback ? BtrConfig.cdnMode : VideoUtils.cdnService`。
  - 測速 subtitle：前三列顯示「多個 CDN 同時緩衝」，其餘列用 `index - 3` 對應原本的測速結果。
- 新函式（放 `lib/services/download/btr_config.dart` 或新檔 `lib/utils/cdn_choice.dart`）：
  - `String cdnChoiceLabel()`：`BtrConfig.playback ? '線程撕裂者（${cdnMode.label}）' : cdnService.desc`。
  - `Future<bool> applyCdnChoice(Object choice)`：
    - `BtrCdnMode`：自定義且 `BtrConfig.customCdn` 為空 → toast「請先到線程撕裂者設定輸入自定義節點」，回傳 false；否則寫 `btrPlayback=true`、`btrCdnMode=index`。
    - `CDNService`：寫 `btrPlayback=false`、`CDNService`，更新 `VideoUtils.cdnService`。
    - 回傳 true 表示有改變。
  - 選 BTR 時不改 `VideoUtils.cdnService`；播放加速開啟時，`VideoUtils.getCdnUrl` 未指定 `defaultCDNService` 時改用 `CDNService.backupUrl` 當來源（避免 akamai 簽章與 PCDN 網址讓 BTR 失效）。
  - 有改變時呼叫新的 `BtrProxy.reset()`，清掉來源快取（`_sources`、`_idByUrl`），讓同一部影片切換 BTR 模式立即生效。
- `lib/pages/setting/models/video_settings.dart`：`_showCDNDialog` 用 `applyCdnChoice`；subtitle 改 `當前使用：${cdnChoiceLabel()}…`。線程撕裂者 subtitle 移除 CDN 模式（改「加速：播放、下載，執行緒數：…」，播放依 `BtrConfig.playback`）。
- `lib/pages/setting/widgets/btr_settings_dialog.dart`：移除「播放加速」開關與 CDN 模式 SegmentedButton；儲存時不寫 `btrPlayback`、`btrCdnMode`。自定義節點輸入框一律顯示（說明「CDN 設定選『線程撕裂者：自定義』時使用」）。下半部設定可用條件改為 `_enable || BtrConfig.playback`。儲存檢查：`BtrConfig.playback && cdnMode == custom && hosts.isEmpty` 時阻擋。
- `lib/pages/video/widgets/header_control.dart`：CDN 選單 subtitle 用 `cdnChoiceLabel()`；結果用 `applyCdnChoice`，改變時 toast「已設定為 ${cdnChoiceLabel()}，正在重新載入影片」並 `queryVideoUrl(fromReset: true)`。

## 3. 簡繁切換（AC-9～15）

### 3.1 字典與轉換器

- 新檔 `lib/scripts/gen_zh_dict.py`：從 OpenCC GitHub（`BYVoid/OpenCC` master `data/dictionary/*.txt`，Apache-2.0）下載字典，輸出兩個資產：
  - `assets/zh/s2t.txt`：`STPhrases` + `STCharacters`，再套 `TWVariants`（繁體模式用；對應 OpenCC `s2tw`）。
  - `assets/zh/t2s.txt`：`TWVariantsRevPhrases`、`TWVariantsRev`、`TWPhrasesRev`、`TSPhrases`、`TSCharacters`（簡體模式用；對應 `tw2sp`）。
  - 格式：每行 `來源\t目標`（一對多只取第一個候選）。授權檔 `assets/zh/LICENSE`。
  - 字典合併方式：多階段轉換用「依序套用」實作太複雜時，可改成產生最終對照：對每個詞條 key 用 Python `opencc` 套件（已安裝）轉換得到目標值，確保與 OpenCC 結果一致。
- `pubspec.yaml` assets 加 `assets/zh/`。
- 新檔 `lib/utils/zh_convert.dart`：
  - `enum ZhScript { traditional, simplified }`；`ZhConvert.script`、`ZhConvert.init()`（`main()` 中 `GStorage.init()` 之後 await，只載入當前模式需要的那份字典）。
  - 轉換：最長前綴比對（以 `Map<String,String>` + 最長詞長度），先查詞再查字；非 CJK 字元直接複製（快速路徑：字串沒有 CJK 字元時原樣回傳）。
  - 快取：`LinkedHashMap` LRU，上限 4096 條，只快取長度 ≤ 200 的字串。
  - 字典未載入或轉換出錯時原樣回傳。
- 設定：`SettingBoxKey.appLanguage`（int：0 跟隨系統、1 繁體、2 簡體），`Pref.appLanguage`。
  系統判斷用 `PlatformDispatcher.instance.locale`：`languageCode == 'zh'` 且（`scriptCode == 'Hans'` 或 `countryCode` 為 `CN`/`SG`）→ 簡體；否則繁體。

### 3.2 顯示層轉換

所有顯示文字都在繪製前轉換，資料本身不動（AC-14、AC-15）：

- 新檔 `lib/common/widgets/zh_text.dart`：定義 `class Text extends StatelessWidget`，建構子與 Flutter `Text`、`Text.rich` 參數完全相同（`const`）。`build` 回傳 Flutter 的 `Text`（以 `import ... as flutter` 取得），`data` 經 `ZhConvert.convert`，`textSpan` 經 `ZhConvert.span`（遞迴重建 `TextSpan`，保留 style、recognizer、mouseCursor、onEnter/onExit、semanticsLabel、locale、spellOut；`WidgetSpan` 與其他 `InlineSpan` 原樣保留）。
- 新檔 `lib/common/widgets/zh_material.dart`：`export 'package:material_ui/material_ui.dart' hide Text; export 'zh_text.dart';`。
  同樣做 `zh_widgets.dart`（`package:flutter/widgets.dart`）與 `zh_flutter_material.dart`（`package:flutter/material.dart`）。
- 新腳本 `lib/scripts/use_zh_text.py`（可重複執行）：把 `lib/**/*.dart` 中上述三種 import 改成對應的 `zh_*.dart`，保留原本的 `hide`/`show` 子句（`hide X` → 匯出檔已 hide Text，原子句照搬）。排除：`lib/common/widgets/zh_*.dart` 本身、`lib/common/widgets/flutter/**`（vendored Flutter 原始碼）、`*.pb*.dart`、已經 `hide Text` 的檔案。
- `BaseText`（`lib/common/widgets/flutter/text/text.dart`，用於 `TextEllipsis`、`TextMore` 的留言與簡介）：在 build／傳給 render 物件前轉換 `data`、`textSpan`。
- 其他不經過 `Text` 的顯示點，逐一處理：
  - Toast：`CustomToast` 本身用 `Text`，import 改寫後自動轉換，不另外處理。
  - 分段（章節）標題：`segment_progress_bar.dart` 的 `addText`。「檢視更多」：`paragraph_more.dart`。
  - 媒體通知：`audio_handler.dart` `setMediaItem` 轉換 title、artist。
  - 彈幕：建立 `DanmakuContentItem` 的地方（`lib/pages/danmaku/view.dart`、`lib/pages/live_room/controller.dart`、`lib/pages/video/send_danmaku/view.dart`）文字經 `ZhConvert.convert`。
  - `Tab`、`TextField`：`zh_material_widgets.dart` 以子類別覆寫 `text`／`decoration` getter 轉換，由 `zh_material.dart` 匯出取代原類別。
  - `tooltip:`、`InputDecoration` 的 `hintText`/`labelText`/`helperText`、`AppBar`/`SliverAppBar` 以外以 String 傳給 Flutter 元件的參數：Flutter 內部用自己的 Text 繪製，不會經過轉換。用 `rg` 列出後，介面字串在簡體模式下若沒轉換即為已知限制；常見的 `Tab(text:)` 改成 `Tab(child: Text(...))`，`hintText` 等改成 `hint: Text(...)`／`label: Text(...)`（Flutter 版本支援時）。無法改的列入驗證文件的已知限制。
- `main.dart`：GetMaterialApp `locale`／`fallbackLocale` 依模式用 `_zhTW` 或 `Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN')`。

- 字典：多字詞條全部保留（含與逐字結果相同者，最長比對時需要它們擋住重疊詞）。
  簡體模式不用會改寫簡體內容的台灣詞（如 智慧→智能、影片→视频）：只保留含繁體專用字的 TWPhrasesRev 詞條；
  另產生 `assets/zh/t2s_ui.txt`，對程式中不含插值的介面字串整句套完整 tw2sp。
  繁體模式內容用 s2tw（不轉詞，避免改到人名作品名），介面字串本來就是 s2twp 的結果。

### 3.3 設定介面

- `lib/pages/setting/models/style_settings.dart`：新增 NormalModel「語言」，subtitle 顯示目前選項；點擊開 `SelectDialog<int>`：`跟隨系統`、`繁體中文`、`简体中文`（此字串為簡體，加註解說明）。值有改變 → 寫入設定 → `AppRestart.ask()`。
- 注意：「简体中文」在簡體模式會被轉換器原樣保留；在繁體模式會被 `Text` 轉成「簡體中文」。用 `Text` 以外的方式無法避免時可接受，但最好讓選項文字不經轉換：`SelectDialog` 的標題字串在繁體模式轉成「簡體中文」可接受。

## 4. 速度滑桿（AC-16～17）

- `lib/plugin/pl_player/view/view.dart` `BottomControlType.speed`：PopupMenu 的 `itemBuilder` 最前面加一個 `PopupMenuItem<double>(enabled: false)`，內容為 `StatefulBuilder`：左側顯示 `x.xxX` 數值，`Slider`（min 0.25、max 4.0、divisions 75，`activeColor` 白色系，寬 200 左右）。`onChanged` 更新顯示並呼叫 `plPlayerController.setPlaybackSpeed(v)`（數值四捨五入到 0.05）。
- 下方保留原固定清單（AC-17）。
- 顯示數值：`playbackSpeed` 若不是清單內的值也要正確顯示（用 `toStringAsFixed(2)` 去尾零）。

## 任務

| ID | 內容 | 相依 | 執行者 |
|---|---|---|---|
| T-1 | 重啟：Kotlin channel + `app_restart.dart` + 排數對話框接上 | — | Opus |
| T-2 | CDN 合併（§2） | — | Sonnet |
| T-3 | 速度滑桿（§4） | — | Sonnet |
| T-4 | 字典產生腳本 + 資產 + `zh_convert.dart` + 設定鍵 + `main.dart` init/locale | — | Opus |
| T-5 | `zh_text.dart`、`zh_*.dart` 匯出、`use_zh_text.py` 執行、`BaseText`、toast、彈幕 | T-4 | Opus |
| T-6 | Tab/hint 等參數掃描與替換 | T-5 | Sonnet |
| T-7 | 語言設定 UI（§3.3） | T-1、T-4 | Opus |

## 驗證方式

| AC | 方式 |
|---|---|
| AC-1～3、13 | 模擬器操作：改排數／語言 → 對話框 → 重新啟動 |
| AC-4～8 | 模擬器操作 CDN 設定、播放頁選單；讀設定值 |
| AC-9～12 | 模擬器切換三種模式截圖首頁、影片頁、留言 |
| AC-14、15 | 讀 diff：轉換只在 widget build／toast／彈幕顯示；輸入框不受影響 |
| AC-16、17 | 模擬器操作播放頁倍速選單 |
| 全部 | `flutter analyze lib` 無 error/warning；`flutter build apk --debug` 成功 |

## 邊界情況與風險

- `zh_text.dart` 的 `Text` 與 Flutter `Text` 型別不同：程式中 `is Text`、`Text?` 型別參數傳給要求 Flutter `Text` 的 API 會出錯 → analyze 會抓到，逐一修正。
- `const Text(...)` 仍是 const（建構子為 const），無效能退化；轉換在 build 中發生並有快取。
- 長文字（留言、簡介）不快取，每次 build 轉換；字典比對為線性時間，可接受。
- 繁體模式對已是繁體的介面字串再做 s2tw：大多不變；少數字（如「著」「裡」）可能有差異，需抽查設定頁截圖。
- 升級上游後要重跑 `to_traditional.py` 與 `use_zh_text.py`。
- 回退：設定選「繁體中文」等同舊行為（介面字串大致不變，只多了內容轉繁）；整體回退用 git revert。

## 審查紀錄

規格審查（全新 Claude 子代理）採用：
- BTR 模式切換不生效 → `BtrProxy.reset()`。
- BTR 來源 → 播放加速時用 backupUrl。
- tw2sp 改寫簡體內容 → 過濾詞條 + 介面整句表。
- 刪除 identity 詞條造成不一致 → 全部保留；以 Python 依 Dart 演算法比對 2134 個介面字串，s2t 與 OpenCC 0 差異。
- Tab/TextField/分段標題/檢視更多/媒體通知 → 補上。
- 速度滑桿：clamp、拖動結束才套用、長按加速中停用。
- 重啟前 flush 設定；`needReboot` 改走 `AppRestart.ask()`。
不採用：
- 進階彈幕（mode 7）文字：JSON 結構內嵌，量少，列已知限制。
- tooltip 190 處：只在長按時出現，列已知限制。
- 預設 CDN 模式改海外：非本次需求，維持原預設。
- ProcessPhoenix 式重啟：先用 makeRestartActivityTask，實機有問題再改。

## 實作偏差

- CDN 合併改版（使用者後續要求）：「CDN 設定」改為 `CdnSettingsDialog`（`lib/pages/setting/widgets/cdn_settings_dialog.dart`），
  兩列「線程撕裂者（多 CDN 加速）」「CDN 節點」，右側開關互斥（只能開一個）；點列開子設定（`BtrSettingsDialog` 含 CDN 模式／執行緒／下載加速；`CdnSelectDialog` 只列單一 CDN）。
  影片設定頁外層的「線程撕裂者」項目刪除。播放頁 CDN 選單共用同一對話框，以 `cdnSignature()` 前後比較決定是否重新載入影片。
  取代原規格的「單一清單含三個線程撕裂者選項」與 `applyCdnChoice`。
