# 需求：改善推薦訊號回傳（rcmd-signal）

日期：2026-11-07

## 目標

讓 PiliBTR 首頁推薦（App 端 `/x/v2/feed/index`）更接近官方 App 的準確度。做法是補上官方 App 會回傳、但目前沒有回傳的行為訊號，並讓 App 請求的裝置身分一致。

## 背景

- 推薦卡片的 `track_id` 目前沒有被記錄或回傳，推薦系統不知道使用者點了它推薦的哪一部。
- 觀看時長只用 web 版心跳 `/x/click-interface/web/heartbeat` 回報。依第三方逆向筆記（Hikari0618/bilibili-client-research，2026-11-01），官方 Android App 用 `POST https://api.bilibili.com/x/report/heartbeat/mobile`，並帶 `track_id`、`from_spmid`、`spmid`，所以 B-1（點擊歸因）與 B-3（App 版心跳）合併實作。
- 推薦請求的 `app-key`（`android_hd`）、`mobi_app`（`android_i`）、UA（`mobi_app/android`）互相不一致，`fp_local`、`fp_remote`、`session_id` 填固定假值。

## 驗收條件

- **AC-1**：從首頁推薦（App 端）點進影片，播放開始與暫停／結束時，送出 `POST /x/report/heartbeat/mobile`，參數包含該卡片的 `track_id` 與 `from_spmid=tm.recommend.0.0`。
- **AC-2**：從其他入口（搜尋、動態、歷史等）點進影片時，App 心跳的 `track_id` 為空字串，`from_spmid` 不是 `tm.recommend.0.0`。
- **AC-3**：App 心跳的 `played_time`、`total_time`、`paused_time`、`actual_played_time`、`video_duration`、`start_ts`、`session` 依規格的計算方式填入；START 時累計值為 0。
- **AC-4**：原有的 web 心跳與觀看紀錄行為不變（觀看紀錄仍會出現在歷史中；暫停觀看紀錄、無痕等設定仍然有效，關閉時兩種心跳都不送）。
- **AC-5**：推薦請求 `/x/v2/feed/index` 的 `app-key`、`mobi_app`、UA 的 `mobi_app` 一致；不再送固定的 `1111…` `fp_local`／`fp_remote` 與 `11111111` `session_id`。
- **AC-6**：推薦請求修改後仍能正常回傳推薦列表（code 0、有卡片）。
- **AC-7**：App 心跳請求失敗（非 0 code 或網路錯誤）不影響播放，也不顯示錯誤給使用者。
- **AC-8**：`flutter analyze` 無新增錯誤或警告。

## 不做的範圍

- 曝光埋點（`/x/report/click/android2` 的加密 body、InfoEyes 事件）。
- 推薦語系改 `zh_TW`（B-4）。
- 番劇（PGC）以外的特殊播放型別（課程、直播）的 App 心跳；PGC 依規格處理，不能確認的欄位填預設值。
- 不保證推薦一定變準：伺服器端行為無法從客戶端證明，需要使用者實際使用一段時間觀察。

## 限制

- 依據的參數表來自第三方靜態逆向筆記，未經官方確認；`sign` 用專案現有的 App 簽名方式，若伺服器拒絕要能安全失敗（AC-7）。
- 心跳用「記錄觀看」帳號（`Accounts.heartbeat`）。
- 介面文字、註解用繁體中文。不 commit，除非使用者要求。

## 關卡

使用者已選擇實作 B-1、B-2、B-3（2026-11-07）。
