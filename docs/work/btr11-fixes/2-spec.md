# 規格：預覽載入圈、推薦卡片、全螢幕方向、CDN 預設與 CDN 狀態

對應需求：[1-requirements.md](1-requirements.md)

## 設計

1. **AC-1**（`lib/common/widgets/video_card/video_preview.dart`）
   - 原因：`stream.playing` 送出 true 時，`_opened` 還是 false（它在 `await player.open()` 之後才設定），所以 `_isMine` 為 false，事件被忽略，之後也不會再送一次。
   - 修正：`_opened = true` 之後，用 `player.state.playing` 與 `player.state.duration` 補設 `_playing` 與 `_duration`。
2. **AC-3、AC-4**（`lib/plugin/pl_player/controller.dart`、`lib/pages/video/controller.dart`）
   - 影片頁版面改回依 `horizontalScreen`（手機橫向時顯示分欄）：`VideoDetailController.horizontalScreen` 改回 `plPlayerController.horizontalScreen`。
   - `exitFullScreenRotation()` 改回原本的規則：`horizontalScreen ? fullMode() : portraitUpMode()`。
     - 手機退出全螢幕時用 `fullMode`，所以橫拿時維持橫向（AC-4）。
     - 縮小成小視窗時也不會先鎖直向（AC-3）。
   - 新增 `_rotateToFullScreen = !horizontalScreen || (Android 手機)`，用來取代 `_onOrientationChanged` 與 `syncOrientation` 中的 `!videoPageHorizontal`：
     - 轉橫向且不在全螢幕：進入全螢幕。
     - 轉直向且是自動進入的全螢幕：退出全螢幕。
     - 不在全螢幕時轉直向：`portraitUpMode()`（現有邏輯）。
     - 平板的值等於 `!horizontalScreen`，行為不變。
   - 移除 `videoPageHorizontal`。
3. **AC-5**（`lib/services/download/btr_config.dart`、`lib/main.dart`）
   - 新增 `BtrConfig.applyLocaleDefault()`，在 `Pref.migrateBtrDefaults()` 旁邊呼叫：
     1. 如果 `btrCdnLocaleDefaultV1` 已存在，直接結束。
     2. 如果沒有 `btrCdnMode` 存值，依 `PlatformDispatcher.instance.locale` 設定 CDN 模式。
     3. 寫入 `btrCdnLocaleDefaultV1`。
   - 判斷規則：
     - `scriptCode == 'Hant'`，或 `countryCode` 屬於 TW、HK、MO：海外。
     - `languageCode == 'zh'`：大陸。
     - 其他語言：不改動。
4. **AC-2**（`lib/pages/video/related/view.dart`）
   - 改用 `VideoGridMixin`：`videoGridDelegate`、`videoGridSkeleton`。
   - 卡片改為 `VideoCardH(vertical: true)`，和熱門頁相同。
5. **AC-6**
   - `btr_cdn.dart`：`BtrNode` 新增 `int bytes`，在 `report` 時累加。
   - `btr_proxy.dart`：
     - `_BtrSource` 新增 `int served`：寫給播放器的位元組數。
     - 新增 `BtrProxy.statsFor(String originalUrl)`，回傳 `({int served, List<BtrNode> nodes})?`。用 `_idByUrl` 找到來源。
   - 新檔 `lib/plugin/pl_player/widgets/cdn_status_panel.dart`：
     - `CdnStatusPanel(videoUrl, audioUrl)` 每秒用 `Timer` 取樣。網速 = `served` 的差值；節點速度 = `speed * 1000` B/s。
     - BTR 關閉，或沒有找到來源時，顯示原始 URL 的主機。
   - `PlPlayerController` 新增 `RxBool showCdnStatus`。
   - `header_control.dart` 的「⋮」選單新增 ListTile「CDN 狀態」，用來切換開關。
   - `pl_player/view/view.dart` 在 `showCdnStatus` 為 true 時，疊加 `Positioned(left: 8, top: 48)` 面板。URL 取自 `videoDetailController.videoUrl`、`audioUrl`。

## 任務

| ID | 任務 | 執行 |
|---|---|---|
| T-1 | AC-1 | Opus |
| T-2 | AC-3、AC-4 | Opus |
| T-3 | AC-5 | Opus |
| T-4 | AC-2 | Opus（小修改） |
| T-5 | AC-6 | Sonnet |
| T-6 | 建置、模擬器檢查 | Opus |

## 邊界情況

- 手機橫向、非全螢幕時開啟影片頁：`syncOrientation` 會依 MediaQuery 進入全螢幕，和現在相同。
- 退出全螢幕時改用 `fullMode`，手機直拿時畫面維持直向。
- 使用者手動退出全螢幕後維持橫向；這時沒有新的感測事件，不會又自動進入全螢幕。
- AC-5 的舊使用者：如果從未選過 CDN 模式，升級後的第一次開啟也會套用。這符合「第一次點開」與「使用者選過就不改」。

## 審查紀錄

| 來源 | 意見 | 處理 |
|---|---|---|
| 審查子代理 | 1 從分欄按全螢幕時，`mode=none` 不會鎖定方向，轉直會變成直向全螢幕 | 採用：進入全螢幕時沒有指定方向、且目前是橫向，就鎖定目前的橫向 |
| 審查子代理 | 2 手動退出後，返回子頁或翻轉 180° 又會自動進入全螢幕 | 採用：新增 `_userExitedFS`，轉回直向或開新影片頁時清除 |
| 審查子代理 | 3 `_rotateToFullScreen` 等於 `!videoPageHorizontal` | 採用：保留 `videoPageHorizontal`，只改版面與 `exitFullScreenRotation` |
| 審查子代理 | 4 系統自動旋轉關閉時 AC-4 不成立 | 記錄：AC-4 的前提是系統自動旋轉已開啟 |
| 審查子代理 | 5 手機橫向非全螢幕時，HeaderControl 不顯示時間 | 記錄：這是平板的既有行為 |
| 審查子代理 | 6 縮成小視窗時可能閃出一幀分欄 | 記錄：可接受 |

## 實作偏差

- 縮成小視窗後，「手動退出」旗標仍在，導致下一部影片不會自動全螢幕。改成 `syncOrientation(newPage: true)` 時重設旗標。
- CDN 狀態：BTR 關閉時，總網速改讀 mpv 的 `cache-speed`。
- 手機橫向分欄時，按讚等按鈕的文字換行並溢出 12px。按鈕文字改為一行並用 `FittedBox(scaleDown)` 縮小。
- 使用者追加：橫向時小視窗沒有貼齊底部。原因是側邊欄版面也保留了底欄空間；`_bottomGap` 在沒有底欄時改為 0。
