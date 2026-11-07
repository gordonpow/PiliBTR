# 規格：豎屏模式（類似 IG Reels）

對應需求：[1-requirements.md](1-requirements.md)

## API（已實測，見 scratchpad/probe）

- `GET https://app.bilibili.com/x/v2/feed/index/story`。不用登入，在台灣可用。App 的攔截器會自動加簽章與 access_key（`account_mgr.dart:58-81`）。
- 參數：
  - 同 `VideoHttp.rcmdVideoListApp`（`lib/http/video.dart:113-163`）的 android 參數與 headers。
  - 另加：`display_id`、`fnval=272`、`fnver=0`、`fourk=1`、`qn=32`、`request_from=1`、`from_spmid=main.ugc-video-detail.0.0`。
  - `aid` 可選，給的話會接續該影片推薦。
- 回應 `data.items[]`，每次約 5 筆，`goto` 為 `vertical_av`。欄位：
  - 識別：`param`（aid）、`bvid`、`player_args.{aid,cid}`
  - 內容：`title`、`desc`、`duration`、`cover`
  - UP 主：`owner.{mid,name,face}`、`relation.status`
  - 統計：`stat.{view,danmaku,reply,favorite,coin,share,like}`
  - 尺寸：`dimension.{width,height,rotate}`
  - `uri` 中的 `player_preload` 附帶 dash 播放網址，約 1 小時後過期。
  - `req_user`：登入時的按讚、投幣、收藏狀態。
- 分頁：沒有游標，每次呼叫都是新的推薦。`display_id` 遞增，可以帶上最後一部的 aid；客戶端依 aid 去除重複。偶爾會逾時，需要重試。
- **不一定是豎屏**：依 `dimension` 篩選（`rotate` 為 1 時寬高互換），只保留高大於寬的影片。如果一頁篩完沒有影片，就連續再抓，每次載入最多呼叫 5 次。

## 設計

1. **資料**：
   - `Api.storyFeed`，加進 `AccountType.recommend`（`lib/utils/accounts/api_type.dart`）。
   - `VideoHttp.storyFeed({int? aid, required int displayId})`，失敗時重試 1 次。
   - Model 放在 `lib/models_new/story/story_item.dart`，欄位：aid、bvid、cid、title、cover、owner、stat、dimension、`isVertical`、`reqUser`（like、coin、fav、follow 狀態），以及 `playerPreload` 的原始 JSON（可選）。
2. **控制器** `lib/pages/reels/controller.dart`（`ReelsController`）：
   - 狀態：`items`、`index`、`displayId`、`seen`（aid 集合）。
   - `loadMore()`：篩選豎屏並去除重複；距離最後 3 部時自動預先載入。
   - 可以用「種子影片」開始：`ReelsController(seed: {aid, bvid, cid, title, cover, owner, progress})`。第一部是種子影片，後面接 `storyFeed(aid: seed.aid)`。
3. **播放**：
   - 共用 `PlPlayerController`（單例），讓彈幕（`PlDanmaku`）、BTR、硬解、心跳等都沿用既有功能。
   - 換頁時呼叫 `setDataSource`：
     - 播放網址用 `VideoHttp.videoUrl(cid, bvid, qn: Pref 預設畫質)` 取 DASH 影音。
     - 由 `BtrProxy.wrap` 包裝。
   - 豎屏頁的 route 名稱是 `/reels`：
     - 不加入 `isVideoPage`，所以不觸發小視窗與方向邏輯。
     - 進入時 `PlPlayerController.getInstance()` 與 `MiniPlayer.handOver()` 的關係比照影片頁。
     - 要確認從豎屏頁開啟一般影片頁、再返回時，播放器的交接正確。
   - 也可以考慮不共用：豎屏頁用自己的 media_kit Player，彈幕另外用 canvas_danmaku 載入。實作者評估後選一種，並在「實作偏差」說明理由（重點是不和影片頁、小視窗搶同一個播放器狀態）。
   - 畫面填滿：BoxFit.cover（豎屏影片在手機上滿版）。
4. **畫面**（`lib/pages/reels/view.dart`，`ReelsPage`，完整版）：
   - 直向的 `PageView.builder`，滑到某一頁時播放該頁，其他頁顯示封面。
   - 點一下暫停或繼續，畫面中央顯示播放圖示。
   - 底部有細進度條，可以拖動。
   - 左下顯示 UP 主頭像、名稱、「關注」按鈕，以及標題（兩行，點選展開說明）。
   - 右側直列按鈕，每個按鈕下顯示數字：
     - 按讚：`VideoHttp.likeVideo`
     - 投幣：`PayCoinsPage.toPayCoinsPage` 加 `VideoHttp.coinVideo`
     - 收藏：`PageUtils.showFavBottomSheet`，需要 FavMixin；可以建立輕量的 controller 實作 FavMixin，或為每部影片建立 `UgcIntroController`，由實作者評估
     - 評論：開底部面板 `VideoReplyPanel`；不能直接用時，用評論 API 做簡易面板
     - 分享：複製連結或系統分享 `https://b23.tv/<bvid>`
     - 彈幕開關
     - 「完整影片」：`PageUtils.toVideoPage`，帶入 cid 與目前進度
   - 狀態（已讚、已投幣、已收藏、已關注）取自 `reqUser`；未登入時，按下會提示登入。
   - 頂部：返回鍵（從影片頁進入時才顯示）。
   - 生命週期：推入其他頁（`TickerMode` 關閉）、App 到背景時暫停；回到這頁時繼續。
   - 自動播放下一部：播放器的 `completed` 事件觸發（只計算目前這部影片，且頁面為作用中）。有下一部時 `PageController.nextPage`；沒有下一部時重播目前這部並 `loadMore`（只有一部也不會迴圈換頁）。播放失敗時 1.5 秒後同樣跳下一部。
5. **入口**：
   - **首頁分頁**（2026-11-07 依使用者要求修改為卡片格線）：
     - `HomeTabType` 在最後加上 `reels('豎屏')`，避免破壞已儲存的排序索引。
     - 預設排序把它放在 rcmd 與 hot 之間。
     - 已自訂過排序的使用者：用一次性遷移把 reels 插在 rcmd 後面（遷移旗標 `homeTabReelsV1`）。
     - 分頁內容是 `ReelsFeedPage`（`lib/pages/reels/feed.dart`）：影片卡片格線，排數用 `VideoCardStyle.gridDelegate`（跟隨「影片卡片排數」設定），下拉重新整理，捲到倒數第一張時載入更多；首頁雙擊分頁（`HomeTabType.ctr`）捲到頂部或重新整理。卡片支援長按預覽（共用 `CardPreview`），點卡片時帶預覽進度。
     - 點卡片開啟全螢幕路由 `/reels`，參數 `{aid, bvid, cid, title, cover, item, progress?}`：從該影片開始，往上滑接續推薦。豎屏播放器只以全螢幕路由運行，不再嵌入首頁。
   - **播放器「豎屏」按鈕**：
     - 豎屏影片（`VideoDetailController.isVertical`）在影片頁播放器底部控制列的全螢幕鈕左邊，顯示一個標有「豎屏」小字的按鈕，參考官方截圖。
     - 點選後開啟 `/reels`，以目前影片為種子並接續目前進度。開啟前暫停影片頁的播放，交給豎屏頁播放。

## 任務

| ID | 任務 | 執行 | 相依 |
|---|---|---|---|
| T-1 | API、model、ReelsController | Sonnet | — |
| T-2 | ReelsPage 播放與完整操作 | Sonnet | T-1（同一個子代理接續） |
| T-3 | 入口：首頁分頁加遷移、播放器「豎屏」按鈕、`/reels` 路由 | Sonnet | 依本規格的路由介面，可以和 T-1、T-2 平行 |
| T-4 | 程式碼驗證：analyze、建置、diff 審查 | Sonnet | 全部 |

**路由介面（T-2、T-3 共用）**：
- `Get.toNamed('/reels', arguments: {'aid': int, 'bvid': String, 'cid': int, 'title': String, 'cover': String, 'progress': int(ms)?})`。
- 首頁分頁使用 `ReelsFeedPage`（卡片格線），點卡片以上述路由介面開啟 `/reels`。

## 邊界情況

- API 失敗或沒有豎屏影片：顯示「暫時沒有豎屏影片」與重試按鈕。
- 地區限制或付費影片的 playurl 失敗：顯示錯誤並自動跳下一部。
- 同時只能有一個實際在播的影片；換頁時停止前一部。
- 小視窗正在播放時切到豎屏分頁：豎屏開始播放時關閉小視窗或暫停它（由實作者決定，並記錄在實作偏差）。

## 審查紀錄

| 來源 | 意見 | 處理 |
|---|---|---|
| 審查子代理 | 1 共用單例播放器會讓小視窗失效、計數無法歸零 | 採用：豎屏改用專屬的 media_kit Player（比照 VideoPreview），不送 heartbeat |
| 審查子代理 | 2 共用時彈幕與通知會出錯 | 採用：彈幕直接用 DanmakuScreen，搭配輕量載入器 |
| 審查子代理 | 3 可見性要涵蓋首頁分頁、主頁底部導覽、推入新頁、App 背景 | 採用：4 個條件都成立才播放；分頁 keep-alive，停穩後才載入；開始播放時暫停主播放器與小視窗 |
| 審查子代理 | 4 垂直 PageView 會觸發頂欄、底欄自動隱藏 | 採用：內嵌時攔下捲動通知 |
| 審查子代理 | 5 進度條和分頁橫滑搶手勢 | 採用：使用 CustomHorizontalDragGestureRecognizer，觸控高度至少 24dp |
| 審查子代理 | 6 VideoReplyPanel 依賴影片頁 | 採用：改用 `MainReplyPage.toMainReplyPage(oid, replyType: 1)` |
| 審查子代理 | 7 不能建立 UgcIntroController | 採用：仿照 AudioController 寫輕量 controller（TripleMixin、FavMixin）；沒有 copyright 欄位時，投幣上限保守設為 1 |
| 審查子代理 | 8 分頁排序遷移沒有問題 | — |

## 實作偏差


- T-1/T-2 播放器：改用豎屏專屬的 media_kit Player（`ReelsController` 持有，風格同 `VideoPreview`），不共用 `PlPlayerController`。理由：`getInstance()` 會增加 `_playerCount`、觸發 `MiniPlayer.handOver`，影響影片頁、小視窗返回與 PiP；專屬播放器不碰這些狀態，也沒有心跳與歷史回報。以 EDL 播放 DASH 影音（`BtrProxy.wrap`），畫質取不高於預設畫質的 H.264，下一部預先取得播放網址。開始播放時呼叫 `PlPlayerController.pauseIfExists()`（影片頁與小視窗共用該單例，一併暫停，小視窗保留不關閉）。
- 彈幕：`_ReelsDanmaku` 直接用 canvas_danmaku 的 `DanmakuScreen`，以 `DmGrpc.dmSegMobile` 依位置載入分段；簡化：不套用過濾規則與合併，略過高級彈幕（mode 7）；開關為頁面內狀態（初始值取自 `Pref.enableShowDanmaku`，不寫回設定）。
- 評論：用 `MainReplyPage.toMainReplyPage(oid: aid, replyType: 1)`（整頁，不是底部面板），因為 `VideoReplyPanel` 依賴 `VideoDetailController`。
- 收藏與投幣：`ReelsItemCtr`（`TripleMixin` + `FavMixin` 的輕量 controller，每部影片一個）。沒有版權資訊時視為轉載（最多 1 幣）。以種子開啟的影片會用 `videoIntro` 補 UP 主與統計；登入時用 `videoRelation` 校正按讚、投幣、收藏、關注狀態。
- 可見性：（原嵌入式的分頁可見性、keep-alive、攔截捲動通知已隨 2026-11-07 設計變更移除）豎屏只以全螢幕 `/reels` 路由運行，`TickerMode` 啟用且 App 在前景才播放。進度條使用 `CustomHorizontalDragGestureRecognizer`。
- 2026-11-07 設計變更：首頁分頁改為卡片格線（`ReelsFeedPage`），`ReelsPage` 只剩全螢幕路由；新增播完自動播放下一部。
- 限制：`/reels` 路由頁由 `Get.arguments` 取得種子；沒有 PiP、倍速、字幕、畫質切換；彈幕不可發送。
