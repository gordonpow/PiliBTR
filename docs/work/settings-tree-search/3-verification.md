# 驗證：設定介面樹狀分類與設定搜尋紀錄

日期：2026-11-07
環境：模擬器 `Medium_Phone_API_37.0`，debug APK（x64）。
截圖：session scratchpad `shots/`，未存入 repo。

## AC 對照

| AC | 結果 | 證據 |
|---|---|---|
| AC-1 多層頁面 | 通過 | 首頁只顯示第一層（t1）；「播放」顯示 7 個子分類（t2）；子分類顯示設定項（t7）；「網路與加速」沒有子分類，直接顯示設定項（t5） |
| AC-2 不遺漏、不重複 | 通過（靜態） | `python lib/scripts/check_setting_tree.py`：`93 listed titles, 273 titles in the lists: OK`。沒列出的項目依來源清單落入預設節點，由程式結構保證不遺失 |
| AC-3 分類說明 | 通過 | 每個分類列都有說明（t1、t2） |
| AC-4 行為不變 | 通過（設計） | 設定項仍來自原清單的 `.widget`，key 與預設值沒有改動；「背景播放」顯示開啟，「子母畫面」顯示前次測試開啟的狀態（t7） |
| AC-5 橫向雙欄 | 通過 | 左欄顯示目前層級並有返回列，右欄顯示設定項，AppBar 顯示路徑；系統返回鍵會回到上一層（l7、l8、l9） |
| AC-6 更新紅點 | 未驗證 | 沒有新版本可觸發紅點；程式沿用原本的 `Obx(Badge)` |
| AC-7 搜尋紀錄 | 通過 | 空白輸入框顯示「搜尋紀錄」與「清除全部」，每筆有刪除鈕（u4） |
| AC-8 點紀錄搜尋 | 通過 | 點「cdn」帶入關鍵字並顯示結果（u5）。單筆刪除與清除全部未實測 |
| AC-9 記錄時機、去重 | 部分 | 按 Enter 會記錄（u4）；點結果記錄與去重未實測 |
| AC-10 結果可直接操作、標示路徑 | 通過 | 結果上方顯示「網路與加速」，開關在結果中可見（u1） |

## 測試中發現並修正

1. 直向時，在「播放」頁點子分類沒有反應。
   原因：`Get.to` 預設 `preventDuplicates: true`，而從 `SettingNodePage` 再推入同型別的 `SettingNodePage` 會被當成重複頁面而略過。
   修正：改用 `preventDuplicates: false`。

## 附帶驗證（第一批 AC-14）

系統自動旋轉關閉時（`accelerometer_rotation=0`），Activity 要求 `SCREEN_ORIENTATION_FULL_USER`。轉動模擬器 3 次，畫面都維持直向，確認會遵守系統的旋轉鎖定。

## 實作審查

未做 diff 審查。
