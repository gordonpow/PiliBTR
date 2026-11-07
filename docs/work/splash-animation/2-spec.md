# 需求與規格：開啟 App 動畫（splash-animation）

日期：2026-11-07

## 需求

目標：冷啟動時在系統啟動畫面之後播放一段 PiliBTR 開場動畫，再進入首頁。

使用者決定（2026-11-07）：Flutter 開場動畫；設定中可關閉；點擊可跳過；只在冷啟動播放。

### 驗收條件

- **AC-1**：冷啟動時，系統啟動畫面結束後顯示開場動畫：與系統啟動畫面相同的背景色（淺色 `#ffffff`、深色 `#212121`，依 App 目前亮度），中央 `assets/images/logo/logo_2.png` 由 0.85 倍縮放到 1.0 倍並淡入，接著下方「PiliBTR」文字淡入並上移，最後整個畫面淡出露出首頁。總長約 1.4 秒。
- **AC-2**：動畫期間點擊畫面任何位置，立即淡出（約 200 毫秒）並進入首頁。
- **AC-3**：設定 → 外觀 新增開關「開場動畫」（預設開啟，副標題「冷啟動時播放 PiliBTR 開場動畫」）。關閉後冷啟動直接顯示首頁。設定搜尋找得到這個項目。
- **AC-4**：從背景回到 App、旋轉螢幕、切換主題、從其他頁返回時都不播放。
- **AC-5**：動畫不延後 App 初始化：首頁在動畫底下同時建立與載入資料。
- **AC-6**：只在 Android 與 iOS 播放；桌面平台不播放。
- **AC-7**：`flutter analyze` 無新增錯誤或警告。

### 不做

- Android 12+ 系統動態圖示、開屏廣告或影片、自訂動畫內容。

## 設計

- 新檔 `lib/common/widgets/splash_overlay.dart`：`SplashOverlay`（StatefulWidget，`onFinished` 回呼）。
  - 一個 `AnimationController`（約 1400ms），用 `Interval` 分段：0～0.45 圖示縮放（`Curves.easeOutBack` 或 `easeOutCubic`）與淡入；0.3～0.65 文字淡入、上移 12px；0.8～1.0 整體淡出。結束時呼叫 `onFinished`。
  - `GestureDetector(behavior: HitTestBehavior.opaque, onTap: 跳過)`：跳過時把 controller 以 200ms 動畫到 1.0（或另一個淡出 controller），結束時 `onFinished`。
  - 動畫期間攔截點擊，不讓底下首頁收到。
  - 背景色依 `Theme.of(context).brightness`（或 `MediaQuery.platformBrightnessOf` 搭配 `ThemeUtils.themeMode`）選 `#ffffff`／`#212121`。圖示大小與系統啟動畫面接近（約 寬 0.3 倍螢幕寬，上限 160）。文字用 `Theme.of(context).textTheme.headlineSmall`，顏色依亮度。
  - 圖示先 `precacheImage` 完成後才啟動 controller（解碼前只顯示背景色），避免圖示突然跳出。
  - 外層包 `PopScope(canPop: false)`，動畫期間的返回鍵／返回手勢視同跳過，不傳給首頁。
  - dispose 時釋放 controller。
- 掛載：`lib/main.dart` 的 `_builder`（:349）回傳值外層包一個 `Stack`：`[child, if (_showSplash) SplashOverlay(onFinished: ...)]`。
  - 「只播一次」用靜態旗標（例如 `SplashOverlay.shown` 或 main.dart 的 static bool），App 程序生命週期內只為 true 一次；`onFinished` 時設為已完成並觸發重建移除覆蓋層（例如 `ValueNotifier<bool>` + `ValueListenableBuilder`，因為 `_builder` 是 static）。
  - 條件：`Pref.enableSplashAnimation && PlatformUtils.isMobile`（專案慣例），在 App 啟動時讀一次。
  - 覆蓋層必須在 `MediaQuery`、`Directionality`、`Theme` 可用的位置（`_builder` 內 child 外層即可，確認 `Directionality` 存在；不存在就包 `Directionality(textDirection: TextDirection.ltr)`）。
- 設定：
  - `lib/utils/storage_key.dart` 加 `SettingBoxKey.enableSplashAnimation = 'enableSplashAnimation'`。
  - `lib/utils/storage_pref.dart` 加 `Pref.enableSplashAnimation`（預設 true）。
  - `lib/pages/setting/models/style_settings.dart` 加 `SwitchModel(title: '開場動畫', subtitle: '冷啟動時播放 PiliBTR 開場動畫', leading: Icon(Icons.animation), setKey: ..., defaultVal: true)`，只在 Android／iOS 顯示，放在語言項目附近。
  - 必要：在 `lib/pages/setting/models/setting_tree.dart`「外觀」節點的 `titles` 加入 `'開場動畫'`，否則設定搜尋找不到（`setting_tree.dart:28-29`）。

## 任務

| 任務 | 內容 | 檔案 |
|---|---|---|
| T-1 | SplashOverlay、掛載、設定開關 | `lib/common/widgets/splash_overlay.dart`（新）、`lib/main.dart`、`lib/utils/storage_key.dart`、`lib/utils/storage_pref.dart`、`lib/pages/setting/models/style_settings.dart`、`setting_tree.dart` |

## AC 驗證方式

AC-1、AC-2、AC-4：模擬器或實機操作（待使用者測試）。AC-3、AC-5、AC-6：diff 審查。AC-7：`flutter analyze`。

## 風險

- `_builder` 在每次重建（旋轉、主題變更）都會被呼叫：只播一次靠靜態旗標，不能放在會重建的 State。
- 系統啟動畫面到 Flutter 第一幀之間的顏色要一致，避免閃一下：背景色與 `flutter_native_splash` 設定相同。
- 回退：設定預設改 false 或移除 Stack 包裝。

## 審查紀錄

agy（gemini-3.8-flash-high）2026-11-07：

1. 採用：圖示未預載會突然跳出 → 先 `precacheImage` 再啟動動畫。
2. 採用：返回手勢會穿透到首頁 → `PopScope(canPop: false)`，返回視同跳過。
3. 採用：設定搜尋必須在 `setting_tree.dart` 登錄。
4. 部分採用：平台判斷改用 `PlatformUtils.isMobile`。不採用改成 `OverlayEntry`：首頁建立後才插入會讓首頁先閃出一幀；`Stack` 從第一幀就蓋住，結束後移除，殘留成本可忽略。冷啟動 toast 顯示在動畫上方可接受。

## 實作偏差

- `setting_tree.dart`：「開場動畫」加到「字型與縮放」群組（與「語言」同組，外觀節點下的子節點），並把該群組副標題改為「語言、開場動畫、字型、介面縮放」；外觀節點本身沒有 `titles` 可加。
- 跳過淡出用第二個 `AnimationController`（200ms），因此 State 使用 `TickerProviderStateMixin`。
- `_builder` 在啟用時始終維持 `Directionality > ValueListenableBuilder > Stack` 結構（動畫結束後只移除覆蓋層），避免首頁因 widget 結構改變而被重建。
