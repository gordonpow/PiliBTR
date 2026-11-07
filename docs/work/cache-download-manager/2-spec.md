# 規格：快取與下載管理器、全域網速單位、速度微調按鈕

對應需求：[1-requirements.md](1-requirements.md)

## 設計

### 現況（探索結果）

- 離線快取頁：`lib/pages/download/download/view.dart`，路由是 `/download`。
  - 「正在快取」區塊使用 `DetailItem(isCurr: true)`。
  - 點項目後，未完成的會暫停或繼續（`item.dart:175-186`），已完成的會開影片頁（`item.dart:154-166`）。
  - 長按選單在 `item.dart:83-140`。
- `DownloadService`（`lib/services/download/download_service.dart`）：
  - 狀態：`curDownload`（Rxn）、`waitDownloadQueue`（RxList）。
  - 操作：`startDownload`、`cancelDownload(isDelete)`、`deleteDownload`。
  - 進度：`_onReceive` 大約每秒呼叫一次。
- `VideoExport`（`lib/services/download/video_export.dart`）：
  - 下載影片與音訊到暫存資料夾，再合併成 MP4，存到 `Pref.exportPath`。
  - 進度卡片是 SmartDialog。
  - 一次只能有一個下載，也沒有任何紀錄；暫存資料夾在開始與結束時都會刪掉。
- `DownloadManager`：`cancel(isDelete: false)` 是暫停。在同一個路徑建立新的 manager 就能繼續（BTR 用 `.btr` 進度檔，單線程用檔案長度）。
- 現有網速格式：`cdn_status_panel.dart:71`、`setting/widgets/select_dialog.dart:215`（CDN 測速）。

### 決策

1. **網速單位**
   - 新檔 `lib/utils/speed_format.dart`，提供 `String formatSpeed(num bytesPerSec)`：
     - 自動：1 MB/s 以上顯示 `x.x MB/s`，以下顯示 `n KB/s`。
     - KB/s：`n KB/s`。
     - MB/s：`x.xx MB/s`。
     - Mbps：`x.x Mbps`（bytes×8/1e6）。
     - 1 KB = 1024 B，1 MB = 1024 KB；Mbps 用十進位。
   - 新增 `SettingBoxKey.speedUnit`（int，預設 0）與 `Pref.speedUnit`。
   - 設定項放在 `video_settings.dart`，標題「網速單位」，用 `PopupModel` 或 `NormalModel` 加選擇對話框。`setting_tree.dart` 的「網路與加速」`titles` 加入「網速單位」。
   - CDN 測速：`select_dialog.dart` 改成以 bytes/s 計算後呼叫 `formatSpeed`。
   - CDN 狀態面板：`_fmt` 改用 `formatSpeed`。
2. **網速取樣**
   - 新增 `class SpeedMeter`（放在 `speed_format.dart`）：`update(int totalBytes)` 記錄時間與位元組數，`bytesPerSec` 取最近約 2 秒的平均。
   - `DownloadService`：新增 `final RxDouble speed`，在 `_onReceive` 中用 SpeedMeter 更新；暫停、完成或沒有下載時歸零。
   - `VideoExport`：影片與音訊收到的位元組加總後更新 `speed`（RxDouble）。
3. **VideoExport 改為可暫停**（`lib/services/download/video_export.dart`）
   - 狀態：`Rx<ExportState?> current`，`ExportState` 欄位如下：
     - 識別：`cid`、`title`、`cover`、`bvid`。
     - 進度：`stage`（downloading、paused、merging）、`progress`（0～1）。
     - 網速：`speed`。
   - 暫存資料夾 `tmp/export/<cid>` 只在「停止」或完成時刪除。開始新的下載時：
     - 同一個 cid：沿用暫存檔繼續。
     - 不同的 cid：先刪除舊的暫存檔。
   - `pause()`：兩個 manager 都 `cancel(isDelete: false)`，stage 設為 paused。
   - `resume()`：在相同路徑建立新的 manager 繼續下載，完成後合併。為此，`start` 要記住 `videoUrl`、`audioUrl` 與 headers。
   - `stop()`：等於原本的 `cancel`，刪除暫存檔並清除 `current`。
   - 合併中不能暫停，按鈕停用。
   - 完成時寫入紀錄：`LocalCacheKey.exportRecords`，`List<Map>`。每筆欄位：`path`、`title`、`cover`、`bvid`、`cid`、`size`、`time`（ms）。最新的放在前面。
   - 進度卡片（SmartDialog）加上「暫停／繼續」按鈕與網速。
   - 新增 `static List<ExportRecord> records()`：讀取紀錄並略過檔案已不存在的項目。另有 `deleteRecord(path, {deleteFile})`。
4. **播放彈窗**
   - 新檔 `lib/common/widgets/video_popup_player.dart`，函式 `showVideoPopup(BuildContext, {required String videoPath, String? audioPath, required String title})`。
   - `Dialog` 內放 16:9 的 `SimpleVideo`（參考 `gallery_viewer.dart` 的 `_initPlayer` 寫法：`Player.create`、`VideoController.create`）。
   - 有外部音訊時，`player.setAudioTrack(AudioTrack.uri(audioPath))`。如果 media_kit 的 API 不同，就用 mpv 的 `audio-files` 屬性，參考 `controller.dart:1054` 的寫法。
   - 控制項：
     - 點畫面：播放或暫停。
     - 下方：進度 Slider 與「目前時間／總長」。
     - 右上：關閉、全螢幕。全螢幕切換時，彈窗改為填滿整個畫面並隱藏系統列；關閉時恢復。
   - 關閉時呼叫 `player.dispose()`。
   - 不影響 App 主播放器（使用獨立的 Player），開啟時暫停主播放器或小視窗。
5. **頁面**
   - `DownloadPage` 改為 `DefaultTabController`，有兩個分頁「快取」「下載」，標題「快取與下載」。
   - 「快取」分頁：原本的 `CustomScrollView` 內容不變。
     - 正在快取的 `DetailItem` 在進度下方加一列：網速（`formatSpeed(service.speed)`）、暫停／繼續 IconButton、停止 IconButton。停止前要確認，然後執行 `deleteDownload(removeQueue: true, downloadNext: true)`。
     - 點已完成項目：改開播放彈窗。路徑依 `FileSource` 的規則（`data_source.dart:21-40`）組出影片與音訊。
     - 長按選單新增「在影片頁開啟」，執行原本的 `toVideoPage`。
   - 「下載」分頁（新檔 `lib/pages/download/export/view.dart`）：
     - 最上方：`Obx(VideoExport.current)` 進行中的卡片，包含封面、標題、進度條、階段文字、網速、暫停／繼續、停止。
     - 下面：`VideoExport.records()` 清單，每列顯示封面、標題、大小、日期。點選開啟播放彈窗，長按刪除（確認後刪除檔案）。
     - 沒有項目時顯示「還沒有下載的影片」。
   - `mine/controller.dart:53`：標題改為「快取與下載」。

## 任務

| ID | 任務 | 執行 |
|---|---|---|
| T-1 | AC-1 速度 ± 按鈕 | Opus（已完成） |
| T-2 | 網速單位與 SpeedMeter（決策 1、2 的格式部分）、套用到 CDN 狀態與測速、設定項 | Sonnet |
| T-3 | 播放彈窗（決策 4） | Sonnet |
| T-4 | VideoExport 暫停、繼續、紀錄、網速（決策 3） | Opus |
| T-5 | 頁面兩個分頁、快取控制、下載分頁、DownloadService 網速（決策 2、5） | Sonnet（T-2～T-4 之後） |
| T-6 | 建置與模擬器測試 | Opus |

## 邊界情況

- 暫停期間 App 被關閉：暫存檔還在，但 `current` 不會保存，所以下次無法繼續。開始同一部影片的下載時，會沿用暫存檔繼續（決策 3）。
- 下載路徑被使用者變更：紀錄存的是完整路徑，不受影響。
- 檔案被外部刪除：從清單中略過，紀錄保留在 localCache（不影響功能）。
- 播放彈窗開啟時，主播放器或小視窗先暫停，避免兩個聲音同時播放。

## 審查紀錄

| 來源 | 意見 | 處理 |
|---|---|---|
| 審查子代理 | 1 暫停會走進 catch，把暫存檔刪掉 | 採用：`_run` 的 catch 遇到 `_paused` 時保留暫存檔、狀態改為已暫停；暫存檔只在停止或完成時刪除 |
| 審查子代理 | 2 連結過期後，探測失敗會退回單線程並刪掉 `.btr` | 採用：探測回 200（不支援分段下載）才退回單線程，其他錯誤直接失敗並保留進度；繼續前檢查 `deadline`，過期時提示回影片頁重新下載（同串流會續傳）。偏差：不在背景重新取得連結 |
| 審查子代理 | 3 換畫質後沿用舊暫存檔會產生壞檔 | 採用：`meta.json` 比對 cid 與串流路徑，不同就清空 |
| 審查子代理 | 4 已完成的串流續傳時收到 416，回應內容被寫進檔案 | 採用：每個串流完成後寫入 `.done` 標記，續傳時跳過 |
| 審查子代理 | 5 合併中停止，`.part` 會殘留 | 採用：catch 時刪除 `.part` |
| 審查子代理 | 6 網速沒算音訊，續傳時會暴衝 | 採用：音訊 manager 也回報位元組數；開始時重設 SpeedMeter，第一筆只當基準 |
| 審查子代理 | 7 取得連結期間按暫停無效 | 採用：建立 manager 前，如果狀態是 pause 就直接 return；按鈕傳入 `downloadNext: false` |
| 審查子代理 | 播放彈窗的 `AudioTrack.uri` 時機風險 | 採用：改用 EDL，長度以 UTF-8 位元組計算 |
| 審查子代理 | 分頁化後，多選會讓 TabBar 消失 | 採用：TabBar 放在 body 頂端；搜尋與多選只在快取分頁顯示 |
| 審查子代理 | 停止快取時沒有刪觀看進度 | 採用 |

## 實作偏差

-
