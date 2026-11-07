### 1. 冷啟動圖示未預載導致動畫殘缺（AC-1 無法驗證）
- **章節**：設計 - [`SplashOverlay`](file:///C:/presonal_project/bilibili_bata/PiliPlus/docs/work/splash-animation/2-spec.md#L27)
- **問題**：冷啟動時 `assets/images/logo/logo_2.png` 需非同步解碼。Controller 在首幀即啟動 0～0.45 縮放淡入，解碼耗時會導致前段畫面空白、圖示突兀彈出（pop-in），使 AC-1 的縮放淡入無法被可靠驗證。
- **佐證**：[2-spec.md:28](file:///C:/presonal_project/bilibili_bata/PiliPlus/docs/work/splash-animation/2-spec.md#L28)
- **修正**：在動畫啟動前先以 `precacheImage` 預載完成，或待圖片 resolve 後再啟動 controller。

### 2. 未攔截 Android 返回手勢（Navigation 邊緣案例）
- **章節**：設計 - [`SplashOverlay`](file:///C:/presonal_project/bilibili_bata/PiliPlus/docs/work/splash-animation/2-spec.md#L27) / AC-2
- **問題**：規格僅以 `GestureDetector` 攔截點擊跳過，未處理 Android 系統返回鍵／手勢。動畫期間觸發 Back 會穿透至底層首頁 Navigator，導致非預期退出 App 或觸發首頁返回邏輯。
- **佐證**：[2-spec.md:29-30](file:///C:/presonal_project/bilibili_bata/PiliPlus/docs/work/splash-animation/2-spec.md#L29-L30)、[main.dart:349](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/main.dart#L349)
- **修正**：在 [`SplashOverlay`](file:///C:/presonal_project/bilibili_bata/PiliPlus/docs/work/splash-animation/2-spec.md#L27) 外層包覆 `PopScope(canPop: false, onPopInvokedWithResult: ...)`，將返回手勢視同跳過動畫。

### 3. 設定搜尋假設錯誤（AC-3 存在不可行風險）
- **章節**：設計 - 設定 / AC-3
- **問題**：規格將 `setting_tree.dart` 列為「若需要登錄／可能修改」。但 [`SettingNode`](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/pages/setting/models/setting_tree.dart#L9) 依據 `titles` 集合嚴格比對收納項目；若未登錄，AC-3 要求之「設定搜尋找得到這個項目」將直接失效。
- **佐證**：[2-spec.md:41](file:///C:/presonal_project/bilibili_bata/PiliPlus/docs/work/splash-animation/2-spec.md#L41)、[setting_tree.dart:28-29](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/pages/setting/models/setting_tree.dart#L28-L29)
- **修正**：將修改 [setting_tree.dart](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/pages/setting/models/setting_tree.dart) 列為必要任務，於「外觀」節點的 `titles` 加入 `'開場動畫'`。

### 4. `_builder` 掛載設計多餘且與 Dialog 衝突（更簡設計／Dialog 邊緣案例）
- **章節**：設計 - 掛載
- **問題**：在 `_builder` 用 `ValueListenableBuilder` + `Stack` 會使根節點常駐多餘 Widget。且因 `_builder` 位於 `FlutterSmartDialog.init` 內部，若冷啟動觸發 Toast 或更新對話框，將穿透疊在動畫上方。平台判斷亦應維持專案慣用的 `PlatformUtils.isMobile`。
- **佐證**：[2-spec.md:33-35](file:///C:/presonal_project/bilibili_bata/PiliPlus/docs/work/splash-animation/2-spec.md#L33-L35)、[main.dart:331-337](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/main.dart#L331-L337)、[style_settings.dart:86](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/pages/setting/models/style_settings.dart#L86)
- **修正**：改在首頁初始化後的根 `Overlay` 插入 `OverlayEntry`，播放完畢調用 `entry.remove()` 徹底銷毀，避免根樹殘留且能覆蓋全局。
