# 驗證：豎屏模式

對應規格：[2-spec.md](2-spec.md)　日期：2026-11-07

範圍：僅程式碼驗證，功能由使用者自行測試。diff 見 [diff.patch](diff.patch)（`pl_player/view/view.dart` 內的 `_canSwipeToMini` 變更屬 grid-preview-live，不是豎屏的一部分）。

## 自動檢查

| 檢查 | 指令 | 結果 |
|---|---|---|
| 靜態分析 | `flutter analyze --no-pub lib` | 通過：38 個既有 info，0 error、0 warning（修正前後相同） |
| 測試 | 無 | 專案沒有對應測試，未執行 |
| 建置 | `flutter build apk --release --target-platform android-x64` | 通過（app-release.apk 38.5MB） |
| 安裝 | `adb -s emulator-5554 install -r ...` | Success（保留資料），已啟動 App |

## 驗收條件

| AC | 結果 | 證據 |
|---|---|---|
| AC-1 首頁「豎屏」分頁（2026-11-07 改為卡片格線，使用者要求） | 待使用者測試 | 程式碼：`HomeTabType.reels` 加在 enum 最後、`defaultOrder` 放在 rcmd 與 hot 之間；分頁為 `ReelsFeedPage` 卡片格線（`VideoCardStyle.gridDelegate`），點卡片開 `/reels` 從該影片開始；雙擊分頁捲到頂部或重新整理；長按卡片預覽 |
| AC-2 播放器「豎屏」按鈕 | 待使用者測試 | 程式碼：`BottomControlType.reels` 只在 `isVertical` 時顯示；`_openReels` 帶 aid、bvid、cid、進度，種子影片是第一部並從進度開始 |
| AC-3 右側操作與狀態 | 待使用者測試 | 程式碼：`ReelsItemCtr` 處理按讚、投幣、收藏、關注；登入時用 `videoRelation` 校正狀態；未登入提示「帳號未登入」 |
| AC-4 自動載入更多 | 待使用者測試 | 程式碼：`onPageChanged` 在距離最後 3 部時 `loadMore`；以 aid 去重，單次最多 5 次呼叫 |
| AC-5 只顯示豎屏 | 待使用者測試 | 程式碼：`StoryItem.isVertical`（rotate 為 1 時寬高互換）；`loadMore` 略過非豎屏。真實樣本（story_full.json、story_p1.json）都是 1920x1080 橫式，確認 API 會混入橫式影片，篩選有必要 |
| AC-6 離開時暫停 | 待使用者測試 | 程式碼：`_evaluate` 同時看 App 生命週期與 `TickerMode`（全螢幕路由），兩項都成立才 `setActive(true)` |
| AC-7 播完自動下一部（2026-11-07 新增） | 待使用者測試 | 程式碼：`completed` 事件 → `_onCompleted`，有下一部 `nextPage`，沒有則重播並 `loadMore`；以 `_isMine` 與 `_active` 過濾 |

## 實作審查

| 發現 | 查證結果 | 處理 |
|---|---|---|
| controller.dart `_createPlayer`：Player 建立期間頁面關閉（快速進出 `/reels` 或離開分頁）時，`onClose` 當下 `_player` 還是 null，之後建立完成的 Player 沒人釋放 | 成立（競態，程式碼推導） | 已修正：`VideoController.create` 後檢查 `isClosed`，是的話 `dispose` 並返回 |
| controller.dart `_startItem`：`open(play: _active)` 期間若被 `setActive(false)`，`pause()` 先於 open 完成，之後 open 仍會開始播放（切走分頁後仍有聲音） | 成立（窄競態） | 已修正：open 完成後若 `!_active` 補一次 `pause()` |
| JSON 解析缺欄位 | 不成立：`param` 是字串、`req_user` 未登入時為 `{}`、`owner.relation.status` 為 int，都已用 `_int`、`?? const {}` 處理；缺 aid、bvid、cid 回傳 null；單筆例外被 `try/catch` 吃掉 | 不處理 |
| 首頁 tab 遷移 | 不成立：旗標 `homeTabReelsV1` 只遷移一次；已有 reels 不重複；沒有 rcmd 時插到 index 1；使用者之後刪除不會被加回；無自訂排序者直接用 `defaultOrder`；設定頁 `defaultBars` 也改為 `defaultOrder` | 不處理 |
| `HomeTabType` 與 `BottomControlType` switch 完整性 | 不成立：analyze 無錯誤；`HomeTabType` 其他使用處（pgc、hot、main）只做相等比較；`ctr()` 的 `_reelsScrollAdapter` 沒有 clients，`toTopOrRefresh` 有 `hasClients` 檢查，不會出錯 | 不處理 |
| HomeController／MainController 未註冊 | 已過時：嵌入式可見性邏輯已移除 | — |
| 嵌入分頁的 ReelsController 與 Player 只在首頁銷毀時釋放 | 已過時：2026-11-07 改為卡片格線，豎屏只以全螢幕路由運行，離開路由即釋放 | 已移除嵌入式程式碼 |
| `_openReels` 在全螢幕（橫向）時按下，`/reels` 會在橫向畫面開啟 | 疑似（未實測） | 不處理：屬於較大的改動（需先退出全螢幕與還原方向）；請使用者實測。建議在全螢幕時隱藏該按鈕或先 `toggleFullScreen` |
| 換頁競態：快速滑動時舊的播放網址請求回來 | 不成立：`_gen` 在每個 await 後比對；`_isMine` 以 media uri 過濾舊事件；`_player.stop()` 先於取網址 | 不處理 |
| 投幣、收藏、關注邏輯 | 不成立：投幣上限依 `copyright`（缺少時保守為 1）；關注 `relationMod` act 1/2；`_isProcessing` 防重入 | 不處理 |
| 多個豎屏頁並存 | 不成立：每個 `ReelsPage` 以 `identityHashCode` 為 tag，`dispose` 時刪除 | 不處理 |
| 2026-11-07 卡片格線與自動下一部審查：`ReelsFeedController` 重新整理失敗時 `_seen` 已被清空，之後載入更多可能重複 | 成立 | 已修正：沒有拿到新影片時還原 `_seen` |
| 首頁雙擊分頁對豎屏是空的 adapter | 成立 | 已修正：`ReelsFeedController` 實作 `ScrollOrRefreshMixin`，`HomeTabType.ctr` 指向它 |
| 卡片沒有長按預覽 | 共用 `CardPreview` 可直接套用 | 已加入（長按預覽、再長按存封面、點卡片帶預覽進度） |
| `_onCompleted` 重複前進／單一影片迴圈 | 不成立：`_isMine` 與 `_active` 過濾，換頁後 `_opened=false`；沒有下一部時只重播並載入更多，不換頁 | 不處理 |
| 格線排數 | 成立：`VideoCardStyle.gridDelegate` 取用 `fixedColumns` 設定 | 無需修改 |

## 已知限制

- 沒有 PiP、倍速、字幕、畫質切換；彈幕不可發送，也不套用過濾規則與合併，略過高級彈幕。
- 評論開啟整頁而非底部面板。
- 沒有版權資訊的影片（以種子開啟時，在 `videoIntro` 回來前）投幣上限為 1。
- 豎屏頁沒有心跳與歷史回報，不會計入觀看紀錄。
- 全螢幕橫向時按「豎屏」的行為未驗證（見上）。
- 未實際執行 App 操作，所有功能 AC 僅有程式碼層級的審查。

## 需要使用者做的事

模擬器（已安裝並啟動）或手機測試清單：

1. 首頁：確認「豎屏」在「推薦」與「熱門」之間；舊使用者（已自訂排序）也有；分頁是卡片格線，排數跟隨「影片卡片排數」設定；下拉重新整理、捲到底載入更多、雙擊首頁分頁捲到頂部／重新整理；長按卡片預覽；點卡片進入全螢幕從該影片播放，上滑下一部、下滑回上一部，連續滑 10 部以上確認自動載入。
1a. 播完自動播放下一部（不跳兩次）；最後一部播完時重播並載入更多。
2. 非豎屏影片不應出現（API 會混入橫式影片）。
3. 在全螢幕豎屏進入影片頁、評論頁、按 Home 鍵再回來：聲音要停止，回來要繼續，且同時只有一個影片在播。
4. 快速上下滑與快速進出 `/reels`：不出現兩部同時播放、聲音重疊或錯誤影片。
5. 右側按鈕：登入後測試按讚、投幣、收藏（開收藏面板）、評論（整頁）、分享、彈幕開關、完整影片（帶進度；返回後豎屏頁恢復）；未登入時應提示。關注／取消關注 UP 主。
6. 底部進度條：拖動與點選。
7. 一般影片頁（豎屏影片）：播放器底部全螢幕鈕左側有「豎屏」按鈕；點選後從目前進度進入，返回鍵顯示並可回影片頁；橫向全螢幕時按下的行為。
8. 小視窗播放中進入豎屏：小視窗應被暫停。
9. 設定的「首頁標籤頁」排序：豎屏可移除、還原預設。
10. 離線或 API 失敗：顯示「暫時沒有豎屏影片」與重試。
