# PiliBTR 專案紀錄

最後更新：2026-11-06

本檔記錄專案介紹、新增功能與開發對話紀錄。每次對話結束或功能完成時更新。

## 1. 專案介紹

- **名稱**：PiliBTR
- **性質**：第三方 Bilibili Android 用戶端，基於 [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus)（Flutter，GPL v3）修改。
- **Repo**：https://github.com/gordonpow/PiliBTR（remote 名稱 `pilibtr`，分支 `main`）
- **核心目標**：把「線程撕裂者」（Bilibili Thread Ripper，BTR）的多 CDN 並行下載移植到手機。Bilibili 一次只從一個 CDN 節點用一條連線抓資料，節點慢時影片會卡頓（海外更明顯）。BTR 把資料切成小塊，同時交給多個 CDN 節點下載。
- **參考**：[Bilibili-thread-ripper-desktop](https://github.com/MrTangLuyao/Bilibili-thread-ripper-desktop)（MIT，只支援 Windows）
- **技術**：Flutter 3.47.9、Dart、GetX、Hive、mpv（media_kit）
- **本機路徑**：`C:\presonal_project\bilibili_bata\PiliPlus`
- **版本**：目前發布到 `v2.2.0-btr.9`；下一版為 `btr.10`

### 架構重點

| 模組 | 檔案 | 說明 |
|---|---|---|
| 播放加速 | `lib/services/download/btr_proxy.dart` | 127.0.0.1 本機 HTTP 代理，把播放器的 Range 請求切塊，多節點並行下載後依序交回 |
| 下載加速 | `lib/services/download/download_manager.dart` | 離線快取分塊並行下載，`.btr` 進度檔支援續傳 |
| 節點池 | `lib/services/download/btr_cdn.dart` | 測速、停用壞節點、依「速度 ÷ 進行中請求數」選節點 |
| 設定 | `lib/services/download/btr_config.dart` | CDN 模式（大陸、海外、自訂）、線程數 |
| 繁簡轉換 | `lib/utils/zh_convert.dart` | 顯示時轉換文字（OpenCC 字典），不改資料 |

## 2. 新增功能

### 已發布（已 commit 並推送）

| Commit | 功能 |
|---|---|
| `370c05388` | 掃描 QR code 偶爾黑屏：自行排隊停止／啟動相機，點畫面可重新啟動 |
| `a7e8338d4` | 錯誤／建議回報，經 Apps Script 寄到開發者信箱 |
| `ee58a912d` | 快取與下載彈窗播放器可播放、全螢幕與全螢幕手勢（同主播放器） |
| `365c23c56` | BTR 多 CDN 加速：播放與下載 |
| `2247ef887` | App 改名 PiliBTR、新圖示、介面改繁體中文 |
| `1b67ba74e` | 離開影片頁時的 App 內迷你播放器；修正台灣用語與卡片溢出 |
| `2eb38f372` | 往左下或右下斜滑把影片縮成迷你播放器；預設開啟自動播放 |
| `c822d21f9` | 迷你播放器飛入動畫、邊緣吸附、大小設定（大、中、小） |
| `d6a0d2aa9` | 斜滑時視窗跟著手指縮小 |
| `5cfc01bb9` | 修正登入後首頁推薦仍為遊客內容 |
| `0a6b14aa3` | 首頁影片卡片長按預覽（進度條、CC 字幕開關、點進去接著播） |
| `5d6ff0445` | 迷你播放器改為吸附四個角落，旋轉後保持同一角落 |
| `e307f8c07` | 修正預覽與影片頁載入時的黑畫面 |
| `18355d26a` | 預設關閉首頁「上次看到這裡」提示 |
| `cdb84d2b2` | 首頁與底欄改為 bilibili App 風格（首頁、關注、訊息、我的） |
| `87602878e` | 改善斜滑縮小手勢（依速度判定）與迷你播放器放大時沿用快取 |
| `7b525b328` | 修正關注頁排版 |
| `14eed55f4` | 更新設定與 App 內安裝更新（自動或手動檢查、紅點提示） |
| `5cdad3184` | 影片「下載」按鈕，直接存成 MP4（可設定路徑，預設 Download） |
| `d97751deb` | 「我的」頁在收藏上方顯示觀看紀錄 |
| `19cbe1053` | 首頁滑動時預覽手指下的影片 |
| `7083fbca4` | 修正迷你播放器與底欄之間的空隙 |
| `1772e6b4a` | 斜滑縮小後回到第一個影片頁之前的頁面 |
| `df933f262` | 自動檢查更新的間隔設定（預設 24 小時，開啟 App 時也檢查） |
| `eb9722c5c` | README 只保留 PiliBTR 說明並加入網速比較 |
| `5490e777b` | 影片列表統一使用直式卡片 |
| `bf85b4d00` | 影片卡片排數設定（直向、橫向分開設定） |
| `545c2cc78` | 繁簡切換、速度滑桿、CDN 設定改版、重啟提示、登入地區碼 |
| `0c3a91d74` | 全螢幕三區手勢、子母畫面、小視窗雙指縮放、背景播放預設開、橫向頁面、旋轉偵測、「屏」改「螢幕」 |
| `84740e6b4` | 設定改為樹狀分類、設定搜尋紀錄 |

發布：v2.2.0-btr.10（2026-11-07）包含以上三項。

| `b460a435d` | 快取與下載管理器、播放彈窗、MP4 暫停續傳、全域網速單位、自動連播倒數、CDN 狀態、CDN 依系統語言、倍速 ± 按鈕、選單精簡、載入相關預設開啟、相關推薦直式卡片與橫向排數、橫向退出全螢幕分欄、多項修正 |

發布：v2.2.0-btr.11（2026-11-07）。

| `6871e45f2` | 豎屏模式、全部影片卡片預覽、直播預覽與直播小視窗、直播／番劇／影視排數依設定 |

發布：v2.2.0-btr.12（2026-11-07）。

| `333d62559` | 豎屏模式預載下一部（雙播放器、使用 story feed 播放網址）；出錯重試從原位置繼續（F-1） |
| `6c6e27f1e` | 關閉縮小視窗時，全螢幕往下滑改為退出全螢幕 |

發布：v2.2.0-btr.13（2026-11-07）。功能待使用者實機測試。

| `436547e3c` | 豎屏預載 3 部（4 個播放器）、預取網址、畫質依 Wi-Fi／行動網路設定、AVC 退路、網址過期重取 |

發布：v2.2.0-btr.14（2026-11-07）。尚未驗證，待使用者實機測試。

| `b4a917e3d` | 推薦卡片 `track_id` 點擊歸因、App 版心跳 `/x/report/heartbeat/mobile`、推薦請求統一 HD 身分與 fp／session_id |

發布：v2.2.0-btr.15（2026-11-07）。模擬器實測 App 心跳 START／END 皆 code 0；推薦是否變準待使用者長期觀察。

| `9460b0b51` | 「我的」頁掃描 QR code：電視／盒子登入確認、網頁版登入（WebView）、相簿選圖、其他網址開啟 |
| `69936f5bd` | 冷啟動開場動畫（可在設定關閉、點擊跳過） |

| `a865920a5` | 還原被版本號腳本清空的 `lib/btr_version.dart` |

發布：v2.2.0-btr.16（2026-11-08，tag 指向 `a865920a5`）。尚未驗證，待使用者實機測試。

| `58f3c8744` | 啟動畫面與開場動畫一律黑底 |
| `8323c992e` | 預覽聲音開關在所有預覽間同步 |
| `b59b9b9a1` | 快速開播：BTR 平行試連／開頭串流／hedge／全域節點統計、BTR 失敗改原始網址重試、可見卡片預取 playurl、tap-down 預熱開頭、首播 1080P |

發布：v2.2.1（2026-11-08，版本命名改為不加 btr 序號；pubspec 2.2.1+2）。模擬器開播中位數 698 ms；待使用者實機測試。

| `a613de0fc` | 預載入畫面上所有影片卡（設定可選，預設一律）、預熱保留上限依畫面卡片數 |

發布：v2.2.2（2026-11-08，pubspec 2.2.2+3）。待使用者實機測試。

| `1eedfcb15` | CDN 狀態面板改標「目前下載」並說明節點速度為歷史平均 |
| `74cfe53bd` | 捲動中持續預載畫面上的影片、設定「同時預載影片數」（預設不限制） |

發布：v2.2.3（2026-11-08，pubspec 2.2.3+4）。待使用者實機測試。

| `71abd606c` | 掃描 QR code 後相機黑屏且沒反應（不在 onDetect 中 await stop、攔截例外） |
| `6f374fec5` | 英文介面（語言包 i18n/en.json，切換時下載）、字幕翻譯（B 站英文字幕優先，ML Kit 離線／DeepL／Google Cloud）、彈幕翻譯（離線） |
| `e7819d529` | README 改為英文版，中文版改名 README.zh-TW.md |

發布：v2.2.4（2026-11-08，pubspec 2.2.4+5）。功能待使用者實機測試；flutter test 因本機缺 MSVC 無法執行。

| `31def5b5f` | 英文模式翻譯影片內容（卡片／影片頁標題、推薦理由、分類標籤直接替換；簡介、評論、動態下方附譯文；K／M／B 數字單位；設定「翻譯影片內容」） |

發布：v2.2.5（2026-11-08，pubspec 2.2.5+6）。待使用者實機測試。

| `642533a2a` | 掃描電視 QR code 出現 Null check 錯誤（掃描頁缺 MaterialLocalizations，showDialog 失敗）；以 Localizations.override 補上 |


| `d75d58857` | 長按播放器 CC 按鈕複製字幕（純文字／含時間文字／SRT，合併所有字幕軌，已翻譯的用譯文）；設定「長按字幕按鈕複製字幕」預設關閉 |

發布：v2.2.6（2026-11-08，pubspec 2.2.6+7，tag 在 `5fd1cce46`）。待使用者實機確認電視登入與字幕複製。

| `9c05811ba` | 彈幕分段請求失敗不跳提示、10 秒內不重送、離開頁面取消；被蓋住的影片頁不再請求彈幕 |
| `acbdcedc8` | 開啟長按複製時 CC 按鈕移除 tooltip，長按選單可正常跳出 |
| `5dbd51228` | 子母畫面設定即時生效；Android 12 自動進入 PiP 的旗標不再被覆蓋 |
| `c3c3ce3a5` | issue #79：極驗驗證碼載入中提示、載入失敗／逾時顯示錯誤與重試、JS 改 ES5、關閉只關一次 |
| `9df8d3b15` | 縮小視窗殘留並與影片頁同畫面（OverlayEntry 已插入未 build 時未 remove） |

發布：v2.2.7（2026-11-08，pubspec 2.2.7+8）。模擬器已驗證極驗與縮小視窗；子母畫面、單點 CC 待使用者實機測試。

| `3c85ca8ad` | 登入 cookie 被清空後 App 卡在啟動畫面：忽略清空登入 cookie 的 Set-Cookie、啟動時移除失效帳號 |
| `64be68251` | 掃描電視 QR code 確認後沒有提示：改顯示登入中與結果對話框 |

發布：v2.2.8（2026-11-09，pubspec 2.2.8+9）。結果對話框未在模擬器驗證（記憶體不足，使用者選擇跳過），待使用者實機測試。

| `cc601757b` | 掃描網頁版登入 QR code 直接確認（web/qrcode/check、scene、confirm，access_key 簽名）；電視確認改用 access_key 簽名 |
| `890923534` | 掃描頁可重複掃同一個 QR code |

發布：v2.2.9（2026-11-09，pubspec 2.2.9+10）。使用者以手機測試版確認電視與網頁登入可用。

| `cd19f53fa` | 掃描 http／區網網址改用瀏覽器開啟（PiliBTRTV 手機登入頁說明），非 bilibili 網址不再開兩個 WebView |
| `fde9dd688` | 回報紀錄與處理狀態（`report_status.json`） |
| `8a90929ea` | 豎屏影片頁彈幕開關長按開啟彈幕設定 |
| `4b65042b3` | 語言新增「原文（不轉換）」選項（值 4，同 TV 版） |

發布：v2.2.12（2026-11-12，pubspec 2.2.12+13）。

### 已實作、尚未 commit

- 碰到即預覽：手指按下影片／直播卡片立即預覽，滑動時跟著手指換卡（無等待），橫滑停止，長按恢復原動作，移除「滑動時預覽」開關（`swipe_preview.dart`、`card_preview.dart`、`video_preview.dart`、`recommend_settings.dart`）
- 開影片計時：CDN 狀態面板顯示最近一次首幀與 playurl／開檔／首 byte 分段，及最近 20 次平均（`lib/services/open_timing.dart` 等）
- 快速起播設定（預設開）：mpv `demuxer-lavf-probe-info=nostreams`（設定 → 播放「緩衝時長」下方）

### 待辦

- 決定：豎屏快速連滑可能錯片（F-3，未重現）是否修。
- 決定：橫向全螢幕時是否隱藏播放器的「豎屏」按鈕（目前會以橫向開啟豎屏頁）。


- 實機確認：小視窗雙指縮放、背景播放、全螢幕手勢手感、自動連播卡片的「取消／立即播放」、快取分頁的暫停與停止、CDN 依系統語言預設（模擬器無法或尚未驗證）。
- 直向 4 排時卡片溢出的處理方式（限制最多 3 排，或隱藏統計資訊）待決定。
- 「倍速設定」自訂清單頁是否保留待決定（速度選單已固定 4 個選項）。
- 模擬器設定已改動：關閉硬解（模擬器 MediaCodec 失敗）、CDN 改為 CDN 節點。

## 3. 對話紀錄

時間為台灣時間（UTC+8）。只列使用者的請求與結果；貼上的長 log 省略。

### 2026-11-04：建立專案與 BTR 加速

| 時間 | 請求 | 結果 |
|---|---|---|
| 14:39 | 讀 `對話摘要.md`，描述要做的事 | 說明移植 BTR 到 PiliPlus 的計畫 |
| 15:09 | Android Studio 要選哪個 API 相容性最好 | 說明 minSdk 與 compileSdk 選擇 |
| 15:16–15:22 | 專案建好後的下一步；更新摘要為 PiliPlus；「幫我做」 | 設定開發環境 |
| 15:42–15:46 | Android SDK 授權、開發人員模式、cmdline-tools | 引導使用者執行 `flutter doctor --android-licenses` |
| 15:57–16:25 | 接上手機、USB 偵錯；`flutter run -d R5CY136L62J` 並自動除錯 | 在實機上跑起 App |
| 16:33 | 開始做多線程下載（附參考選項截圖） | 開始實作 |
| 17:16 | 參考 BTR Desktop：把快取交給多個 CDN 同步下載，減少卡頓 | 實作播放代理與分塊下載（`365c23c56`） |
| 17:45–17:51 | 寫 README（更新內容、架構、需求），匯出 APK 放到 GitHub Releases；repo 為 gordonpow/PiliBTR | 寫 README、發 Release |
| 00:41（11-05） | Releases 頁面是空的 | 修正發布 |
| 00:45 | App 改名 PiliBTR、設計圖示、介面全部繁體中文 | 完成（`2247ef887`） |
| 01:13 | 直接 push | 已推送 |

### 2026-11-05：迷你播放器、預覽、底欄、更新

| 時間 | 請求 | 結果 |
|---|---|---|
| 14:04 | 像 YouTube 一樣下拉縮成小視窗；推薦內容與官方 App 差異很大 | 迷你播放器（`1b67ba74e`） |
| 14:30 | 左下或右下滑縮成小視窗，新增選項預設開；自動播放預設開 | 完成（`2eb38f372`） |
| 14:42 | 斜滑有漸變動畫、邊緣吸附、大中小尺寸設定 | 完成（`c822d21f9`） |
| 15:03 | 視窗動畫跟隨滑動距離 | 完成（`d6a0d2aa9`） |
| 15:17–15:21 | 推上去；刪除協作者 Claude 並發新版本 | 已推送、發 Release |
| 15:32 | 安裝 herdr skill | 已安裝 |
| 15:35–15:39 | 如何讓 repo 被更多人看見；寫 Threads 推廣文案 | 提供建議與文案 |
| 15:53 | 登入後首頁仍是遊客推薦；首頁長按預覽（可關閉）；新增 git commit 規範全域 skill | 完成（`5cfc01bb9`、`0a6b14aa3`），建立 `git-commit-message` skill |
| 16:11–17:13 | 長按沒反應；改為在原介面預覽；加 CC 字幕開關（預設開）；預覽進度條、減少開始延遲；預覽走 BTR，點進去接著播 | 完成 |
| 17:46–18:01 | 小視窗不吸附上下；旋轉後位置跑掉；底欄收起時不貼底 | 完成（`5d6ff0445`） |
| 18:09 | README 與 commit 只能用繁體中文或英文，加入全域規則，發 Release | 完成（`9eaa63a68`），寫入全域 CLAUDE.md |
| 18:28–18:33 | 預覽與點進影片有短暫黑畫面；commit 並發 Release | 修正（`e307f8c07`） |
| 18:45 | 不要「上次看到這裡」 | 預設關閉（`18355d26a`） |
| 20:13 | 首頁與底欄做成和官方 App 一樣（首頁、關注、訊息、我的），底欄常駐、變扁 | 完成（`cdb84d2b2`） |
| 21:14 | 斜滑依速度判定；誤判為上下滑；放大後不要重新緩衝；關注頁排版 | 完成（`87602878e`、`7b525b328`） |
| 21:56–22:26 | 開 App 不彈更新；設定可選自動或手動更新，有紅點提示；不要彈出某介面；發 Release | 完成（`14eed55f4`） |
| 22:34 | 快取旁新增「下載」，存到 Download，可自訂路徑 | 完成（`5cdad3184`） |
| 23:42 | 收藏上方加觀看紀錄（可左右滑）；首頁滑動時預覽手指下的影片 | 完成（`d97751deb`、`19cbe1053`） |
| 00:02（11-06） | 建立 Agent 工作流 skill（需求 → 規格 → 實作 → 驗證） | 建立 `dev-workflow` skill |
| 00:08–00:16 | 底欄變扁後小視窗下方有空隙；發 Release | 修正（`7083fbca4`） |
| 00:33–00:52 | 工作流有沒有跑；回覆用中文；用 herdr 開 tab；實作用 Sonnet 省 token | 更新全域規則與 skill |
| 00:58 | 影片卡片大小統一並可自訂；滑動時預覽造成卡頓 | 開始（`docs/work/video-card-unify/`） |
| 01:22 | 工作流移除 Google 模型，只用 Claude | 更新 skill，重新執行 |

### 2026-11-06：返回邏輯、README、排數、語言、CDN

| 時間 | 請求 | 結果 |
|---|---|---|
| 02:09 | 從推薦影片點進影片 2 後斜滑，小窗應播影片 2，主畫面回首頁；按返回則回影片 1 | 完成 |
| 02:28 | 主畫面回到第一個影片頁之前的頁面（搜尋、觀看紀錄等）；README 移除 PiliPlus 說明，加入有無 BTR 的網速比較 | 完成（`1772e6b4a`、`eb9722c5c`） |
| 02:44 | 自訂檢查更新間隔（預設 24 小時），開 App 時也檢查 | 完成（`df933f262`） |
| 02:48–16:43 | 用模擬器測播放順暢度；使用者認為卡頓是模擬器問題，實機很順；照此改 README；commit 並推送 | 完成 |
| 18:27–18:33 | 自訂影片卡片排數，直向與橫向分開；commit 並推送 | 完成（`5490e777b`、`bf85b4d00`） |
| 20:10 | 裝到模擬器看功能 | 已安裝 |
| 20:32 | 4 項需求：改排數後提示重啟；BTR 與 CDN 擇一；繁簡切換（預設跟隨系統）；播放速度滑桿 | 已實作，未 commit |
| 21:14 | CDN 設定改為兩個項目加互斥開關，點項目展開設定，移除外層線程撕裂者 | 已實作，未 commit |
| 21:34 | 排數對話框第一層不要圓圈 | 已改 |
| 21:46 | 速度滑桿改窄，固定選項只留 1.0、1.25、1.5、2.0 | 已改 |
| 22:04 | 簡訊登入沒有地區碼，台灣手機驗證失敗 | 新增地區碼選擇 |
| 22:09 | 繁體模式下「中國台灣」改成「台灣」 | 已改 |
| 22:34 | 6 項需求（見下方） | 尚未開始 |
| 22:40 | 輸出對話紀錄、新增功能、專案介紹為 .md，並把此規則寫入全域規則 | 本檔；全域 CLAUDE.md 新增「專案紀錄」規則 |

2026-11-06 22:34 的 6 項需求：

1. 全螢幕播放畫面分成橫向三區塊，可在外觀設定調整中間區塊寬度（左右等寬），有即時預覽。全螢幕時上滑中間區塊顯示推薦影片；下滑中間區塊，或在任何地方往左下或右下滑，縮成小視窗並有動畫（同 YouTube App）。左右區塊上下滑維持控制亮度與音量。
2. 子母畫面（PiP）：回到手機主畫面時以小視窗繼續播放，設定中可開關。
3. 迷你播放器可用兩指縮放大小，尺寸選項新增「自訂」，記住上次大小。
4. 設定切到背景時是否暫停。
5. 首頁等頁面支援橫向版面，依手機自動旋轉。
6. 持續偵測手機方向：先轉橫再點開影片時，影片應直接橫向。

### 2026-11-06（續）：GitHub issue、播放器與設定需求

| 時間 | 請求 | 結果 |
|---|---|---|
| 15:00 | 6 項播放器需求進入 dev-workflow | 盤點現有功能（autoPiP、背景繼續播放、橫屏適配已存在），確認做法 |
| 15:05 | 把之前的修正全寫成 issue | 28 個 BTR commit 建成 gordonpow/PiliBTR #1–#28，附 commit 說明並關閉 |
| 15:10 | 子母畫面改名預設關閉、背景播放預設開啟、橫屏適配預設開啟、上滑顯示相關推薦（番劇選集） | 寫入第一批需求 |
| 15:15 | 追加：預設全螢幕方向為「不改變當前方向」、「屏」全改「螢幕」（屏蔽改封鎖）、設定搜尋紀錄、設定介面樹狀分類（多層頁面） | 分兩批，需求已確認 |
| 15:25 | 第一批規格 | 完成初稿，送審查 |
| 15:30–16:30 | 第一批實作 T-1～T-9 | 完成，未 commit；尚未在模擬器或實機驗證 |
| 16:40–17:05 | 第一批丟模擬器測試，之後做第二批 | 測試中修正 3 個問題（面板未關閉、面板太透明、返回時方向被重設），見 3-verification.md |
| 17:05–17:20 | 第二批：設定樹狀分類、搜尋紀錄 | 規格審查 10 點全部採用；實作後在模擬器測試，修正子分類無法開啟（GetX preventDuplicates） |
| 17:30 | 分三個 commit 並推送，發布新版本 | `545c2cc78`、`0c3a91d74`、`84740e6b4`；版本號 btr.10，發布 v2.2.0-btr.10 |
| 17:40–18:10 | 6 項問題：預覽載入圈、推薦卡片尺寸、全螢幕縮小先轉直、橫向退出全螢幕變直向、CDN 依系統語言、CDN 即時狀態 | 已修正，模擬器驗證 AC-1～4、6 通過，AC-5 未驗證；未 commit |
| 17:55 | 追加 3 項：速度滑桿 ± 微調、橫向小視窗未貼齊底部、「我的」新增快取與下載管理器（暫停、停止、繼續、即時網速、全域網速單位） | 小視窗貼底已修正；其餘待處理 |
| 18:15–18:30 | 快取與下載管理器、網速單位、速度 ± 按鈕 | 規格審查 7 點與其他小問題全部採用；模擬器驗證 AC-1、2、4、6、7、9 通過，AC-3 部分通過，AC-5、8 未驗證；未 commit |
| 18:40 | 分工改為 Opus 規劃、Sonnet 實作與驗證，寫入全域 dev-workflow skill | 已更新 skill、全域 CLAUDE.md、記憶 |
| 18:45 | 7 項：長按快取／下載開管理器、橫向推薦排數、YouTube 式自動連播倒數、選單移除 5 項、提前初始化預設開、載入相關設定開、下載進度條變細 | Sonnet 實作與模擬器驗證；驗證子代理自行改的「自動連播一律播相關影片」依使用者決定還原；彈幕列表改由彈幕設定面板進入 |
| 19:30 | commit、發布 btr.11、加上 issue | `b460a435d`；版本號 btr.11 |
| 19:50 | 4 項：豎屏模式、番劇／影視／直播排數同步、直播預覽與小視窗、全部卡片可預覽 | 分兩批；第一批完成實作與程式碼驗證（analyze、建置、diff 審查），功能由使用者測試；第二批豎屏模式待開始 |
| 20:00 | 驗證只做程式碼，功能由使用者測試 | 寫入 dev-workflow skill 與記憶 |
| 20:10 | 豎屏模式直接開始；模擬器刪除舊版重灌最新版 | 實測 story API 可用（免登入、台灣可用）；Opus 審查規格後改用專屬播放器；Sonnet 實作與程式碼驗證；release 版已裝到模擬器 |
| 20:40 | 使用者直接在子代理要求豎屏分頁改為卡片格線、播完自動下一部 | 已完成並重新安裝 |
| 20:50 | commit、發布 btr.12、加上 issue | `6871e45f2`；版本號 btr.12 |
| 21:00 | 豎屏向上滑下一部載入很慢 | 選做 A（雙播放器預載）與 D（使用 player_preload）；Sonnet 實作，Haiku 驗證並安裝到模擬器 |
| 21:05 | 驗證與檢查改用最小的模型 | dev-workflow、CLAUDE.md、記憶改為 Haiku 驗證 |
| 21:10 | agy（Gemini）改為 auto mode、不再詢問 | settings.json：agentMode auto、toolPermission always-proceed、enableTerminalSandbox true |
| 05:27 | 改用 Claude 與 agy 模型分工 | Opus 規劃、Sonnet 實作、Haiku 檢查、agy `gemini-3.8-flash-high` 審查；更新 dev-workflow、CLAUDE.md、記憶 |
| 05:27 | 修正 F-1（預載影片出錯重試從 0 秒播放） | `_onSlotError` 重試前把目前位置存入 `_startAt`；analyze 通過，待使用者測試 |
| 05:32 | 關閉縮小視窗功能時，全螢幕往下滑沒反應 | `pl_player/view/view.dart`：不能縮成小視窗時改為退出全螢幕回影片詳細頁；analyze 通過，待使用者測試 |
| 05:41 | 推送、發布 btr.13 | `333d62559`、`6c6e27f1e`；版本號 btr.13 |
| 06:43 | 豎屏往下滑仍慢、畫質差 | 原因：feed 固定 qn 32（480P）、只預載 1 部。改為預載 3 部、畫質跟一般設定；agy 規格審查逾時改 Haiku，採用 9／10 條；Sonnet 實作，analyze 通過，尚未驗證 |
| 06:48 | commit、開 issue、發布 btr.14 | `436547e3c`；版本號 btr.14 |
| 13:00 | 加上 SponsorBlock 自動跳過廣告、贊助、片頭片尾，可自訂開關 | 查到 PiliPlus 已內建「空降助手」（設定 → 其他設定，bsbsb.top，每種片段可設跳過方式），使用者選擇不修改 |
| 13:10 | 官方 App 推薦為何比較準 | 說明差異：缺曝光／點擊回傳、裝置身分不一致、推薦帳號角色、地區與 App 端過濾 |
| 13:20 | 實作 B-1 點擊歸因、B-2 統一裝置身分、B-3 App 版心跳 | 需求與規格寫入 `docs/work/rcmd-signal/`；agy 規格審查 4 條全採用；Sonnet 兩個子代理平行實作；HD 身分推薦 API 實測 code 0；flutter analyze 0 error、0 warning |
| 13:10 | 開模擬器驗證 | 第一次模擬器因記憶體不足被關，改 `-memory 2048` 重開；debug 版實測 App 心跳 START／END 皆 code 0，推薦入口帶 track_id、其他入口為空；結果見 `docs/work/rcmd-signal/3-verification.md` |
| 13:20 | commit 並發布新版 | `b4a917e3d`；版本號 btr.15 |
| 23:10 | 「我的」右上角新增掃描 QR code，用來登入其他裝置 | 使用者選 mobile_scanner、支援電視／網頁版登入、相簿、其他網址；網頁版確認 API 查無文件，改用 WebView 帶 cookie 開確認頁；agy 規格審查 4 條全採用；Sonnet 實作，analyze 通過 |
| 23:30 | 新增開啟 App 動畫 | 使用者選 Flutter 開場動畫、可關閉、點擊跳過、只冷啟動；agy 審查採用 3 條、部分採用 1 條（不改 OverlayEntry，避免首頁先閃一幀）；Sonnet 實作，analyze 0 error、0 warning |
| 23:40 | 發布 | `9460b0b51`、`69936f5bd`；版本號 btr.16 |
| 23:55 | 發布 btr.16 出錯與修正 | 版本號腳本清空 `btr_version.dart`，建置失敗卻上傳了舊 APK；先改草稿、還原檔案（`a865920a5`）、重新建置上傳、經使用者同意重建 tag 後正式發布 |

### 2026-11-08

| 時間 | 請求 | 結果 |
|---|---|---|
| 00:10 | 深色模式開機動畫背景是白色，要一律黑色 | `splash_overlay.dart` 背景固定 `#000000`、文字白色；`flutter_native_splash` 顏色全改 `#000000` 並重新產生 Android 資源（iOS 變動還原）；analyze 通過 |
| 00:20 | 預覽聲音開關要同步：一個開聲音後面都開，一個關後面都關 | `video_preview.dart` 新增共用 `PreviewAudio.muted`，影片與直播預覽開始時套用、切換時寫回；analyze 通過 |
| 00:40 | 原版點開即播，PiliBTR 要載入 1～3 秒甚至卡住 | 調查：BTR 等完整開頭片段、依序試連、重試只認 https、mpv 5 秒逾時、playurl 多打一次、預設 8K；使用者選修卡住、快速開播、少一次 API、1080P；agy 規格審查 4 條採用；實作審查 agy 兩次逾時改 Sonnet／Haiku，共 11 條問題已修；analyze 通過 |
| 01:30 | 開播要控制在 0.5 秒內；給 Sonnet 驗證 | 第一階段模擬器中位數 999 ms；使用者選可見卡片預取、tap-down 預熱、CDN 預連線、0.8 秒 hedge；第二階段中位數 698 ms（重開同片 238 ms），head first byte 仍 1.5～2.3 秒、hedge 0 次勝出、預熱常被取消、OPEN-TIME 早於實際畫面 |
| 02:00 | token 分流：哪些交給 agy | dev-workflow、CLAUDE.md、記憶改為只讀工作（探索、查資料、審查、文件草稿）交給 agy，analyze／建置由 Opus 用 Bash；新增 `scripts/run-agy.sh`（自動開 log 視窗、結束自動關閉），不設 `--print-timeout` |
| 07:50 | 查出預先下載的開頭為什麼常被取消 | agy 調查並經抽查確認：預熱共用開頭片段的 2 秒首 byte 逾時，模擬器 CDN 首 byte 1.5～2.3 秒；改用獨立 5 秒逾時，analyze 通過；手機測試用 release APK 放在下載資料夾 |
| 08:00 | 直接發布新版 +0.0.1 | 使用者選版本號 v2.2.1；`58f3c8744`、`8323c992e`、`b59b9b9a1` |
| 08:30 | 畫面中的影片卡全部預載入；不要固定上限；推送發布 | 設定「預載入畫面上的影片」預設一律；agy 規格審查 5 條、實作審查 5 條全採用；保留上限改依畫面卡片數；`a613de0fc`，版本 v2.2.2 |
| 09:10 | 捲動時不要停止預載、同時 2 部太少、可自訂（預設不限制）；網速偵測怪怪的 | 第二輪實作，agy 審查 4 條：3 條照建議修、1 條（請求風暴）改由「佇列只留畫面卡片」處理，保留不限制預設；網速：總網速是當下交給播放器的量、節點速度是歷史平均，改面板文字 |
| 09:30 | 發布 | `1eedfcb15`、`74cfe53bd`；版本 v2.2.3 |
| 09:40 | 新增英文語言；字幕也要翻譯；彈幕也翻譯 | 介面用對照表語言包、字幕／彈幕用 ML Kit 離線模型（可填 DeepL／Google 金鑰）；agy 探索、規格審查 7 條、2,448 筆字串分 10 批由 agy 翻譯、實作審查 12 條全修；三個 Sonnet 平行實作 |
| 10:30 | 掃描 QR code 後相機黑屏、電視沒登入 | onDetect 中 await stop() 不返回；改為不停止相機並攔截例外 |
| 11:00 | README 全部換成英文並列出功能 | agy 起草、Opus 核對事實（刪除未證實的 sub-second 描述） |
| 11:20 | 發布 | `71abd606c`、`6f374fec5`、`e7819d529`；版本 v2.2.4 |
| 13:50 | 英文模式下影片卡、標題、評論等仍是中文 | 使用者選翻譯卡片／影片頁標題、簡介、評論、動態、分區名稱，加開關預設開；agy 探索、規格審查；Sonnet 實作；agy 實作審查 4 條 |
| 15:15 | 確認階段、完成工作並發布 | 審查 4 條（ML Kit 併發、重複訂閱、失敗冷卻、譯文跑繁簡轉換）由 Sonnet 修正；補 25 筆英文字串；analyze 0 error、0 warning；`31def5b5f`，版本 v2.2.5 |
| 15:55 | 掃描電視 QR code 顯示「Null check operator used on a null value」，電視沒反應 | 解碼截圖確認是 TV auth_code 網址；Sonnet 在模擬器取得 stack：掃描頁取不到 MaterialLocalizations，showDialog 失敗；以 Localizations.override 修正，模擬器確認對話框出現；`642533a2a`，版本號 v2.2.6；release 經使用者同意後發布 |
| 16:30 | 流程全數改用 Claude | dev-workflow、全域 CLAUDE.md、記憶移除 agy：探索用 Explore、查資料與草稿用 Haiku、審查用全新 Sonnet／Haiku 子代理、實作與裝置操作用 Sonnet |
| 16:40 | 使用者回報：長按 CC 字幕按鈕直接複製字幕檔 | 使用者選：跳出選單選格式、複製所有字幕軌、已翻譯的複製譯文；追加「預設關閉，可在設定開啟」；Sonnet 實作，analyze 0 error、0 warning；`d75d58857` 已推送 |
| 17:00 | 推送、發布 | 重新建置含字幕複製的 APK，發布 v2.2.6；issue #77、#78 |
| 21:50 | 快速連點影片時一直跳 DmSegMobile 響應超時；長按 CC 沒反應；開了子母畫面回桌面沒有 PiP | 原因：彈幕失敗後立即重送且每次跳提示、被蓋住的頁面仍依共用播放器請求彈幕；PopupMenuButton 的 Tooltip 搶走長按；autoPiP 只在播放器建立時讀一次設定、Android 12 updatePipActions 覆蓋 autoEnter。修正後 analyze 無 issue、release 建置成功；兩次 Sonnet diff 審查無確認錯誤，採用 3 條建議；功能待使用者實機測試，APK 放在下載資料夾 |
| 22:20 | 修復 issue #79（手機登入時驗證碼頁全黑無法操作），連同之前問題做模擬器驗證 | Sonnet 模擬器重現：深色模式載入中全黑只剩 X；加載入提示、錯誤／逾時、ES5、關閉只關一次。測試版（極驗網址不可達）確認錯誤與重試；之前修正中長按 CC 通過，子母畫面、彈幕顯示未驗到 |
| 23:00 | 為何影片與縮小視窗同畫面 | 子代理重現並取得 log：`_removeEntry` 依 mounted 判斷，entry 已插入未 build 時只 dispose 不 remove；改記錄是否已插入；模擬器 3 輪通過 |
| 23:30 | 修完 commit、推送並發布新版 | 5 個 Fix commit；Sonnet diff 審查採用 1 條（Object.assign 非 ES5）；版本 v2.2.7 |

### 2026-11-09

| 時間 | 請求 | 結果 |
|---|---|---|
| 00:10 | 掃描電視 QR code 按確認登入後電視沒反應，手機只是對話框消失 | 模擬器重現：confirm 回應的 Set-Cookie 把 SESSDATA、DedeUserID 清空並存進主帳號，下次冷啟動 int.parse 失敗卡在啟動畫面；掃描頁 toast 看不到。修正 cookie 防護、啟動移除失效帳號、結果改用對話框；使用者協助模擬器重新登入後 confirm 回 code 0、電視端 poll 0、重開仍登入 |
| 02:20 | 跳過驗證直接發布 | `3c85ca8ad`、`64be68251`；版本 v2.2.8 |
| 02:50 | 掃網頁版登入 QR code 後確認按鈕無法按、叫我下載 APK | h5 確認頁只能在官方 App 內使用；參考上游 PiliPlus #2933 與 BiliPai，改呼叫 web/qrcode/check → scene → confirm（access_key + 簽名）；Sonnet 實作，analyze 通過；測試版 APK 放下載資料夾 |
| 03:15 | 測試版顯示「登入失敗（-101）：账号未登录」，相機掃過就無法再掃 | 電視確認改用 access_key 簽名；掃描器 noDuplicates 改 normal 並略過 2 秒內同一個 QR code；第二版測試 APK |
| 03:30 | 可以了，推送 | `cc601757b`、`890923534`；版本 v2.2.9 |
| 22:40 | PiliBTRTV 最新版網頁版掃碼，用 PiliBTR 掃描後手機全黑；開模擬器用截圖測試 | 模擬器 v2.2.9 debug 從相簿選電視截圖：check → scene → confirm 都回 code 0，顯示「登入成功」，返回掃描頁正常，無法重現黑屏。推測手機版本舊於 v2.2.9（舊版用 WebView 開 h5 頁面）或相機掃描路徑的問題，請使用者確認版本或改用相簿測試。另發現確認框未顯示登入位置（API 欄位為 `qrcode_location`），尚未修改。模擬器因記憶體不足被系統停止 |
| 16:20（11-10） | 打包專案、簽章、對話紀錄，要在另一台電腦繼續修 | 產生 `C:\presonal_project\PiliBTR_transfer_20261110.zip`：原始碼（含 .git、未 commit 檔，排除 build 類資料夾）、`~/.android/debug.keystore`（APK 簽章）、Claude 對話紀錄與 memory、CLAUDE.md、dev-workflow／git-commit-message skill，附還原說明 |

### 2026-11-10（新電腦還原）

| 時間 | 請求 | 結果 |
| --- | --- | --- |
| 18:25 | 從搬移包還原專案並在模擬器安裝 | 解壓到 `C:\presonal_project\bilibili_bata`；`debug.keystore` 覆蓋（舊的備份為 `debug.keystore.bak-20261110`）。Flutter 另複製一份到 `C:\src\flutter` 並執行 `patch.ps1 android`（`C:\flutter` 給 PiliBTRTV 用，未修改）。注意：`C:\Users\abcz0` 本身是 git repo，在 pub cache 執行 `git apply` 會顯示成功但實際跳過；需設 `GIT_CEILING_DIRECTORIES` 為 pub cache 的 `hosted\pub.dev` 再套 `material_ui` patch。Platform 37 由 Gradle 自動下載（`android-37.0`），第二次建置可找到。debug APK（x64）已安裝到 Pixel_9_Pro_XL 模擬器並正常開啟首頁。Claude 對話紀錄合併被權限擋下，未還原 |
| 19:20 | 快取與下載的彈窗播放器無法播放、無法全螢幕、進度條難看 | 原因：彈窗用 media_kit 預設 `VideoController`，Android 要等影片參數才掛 surface，本機檔一直黑畫面停在 00:00。`lib/common/widgets/video_popup_player.dart` 改用和主播放器相同的設定（`androidAttachSurfaceAfterVideoParameters: false`、`hwdec`、`ao`、`force-window=no`）；全螢幕改為 `Dialog.fullscreen`、橫向影片轉橫向、點畫面顯示／隱藏控制列、返回鍵先退出全螢幕並還原方向；進度條改用主播放器的 `ProgressBar`，控制列改深色；`showDialog` 設 `useSafeArea: false` 讓全螢幕蓋過瀏海區。模擬器實測：快取（EDL 影音分離）與下載 MP4 都能播放、拖曳跳轉、全螢幕與退出正常。`useSafeArea` 修正因模擬器空間不足未重裝實測。為騰空間已從 emulator-5556 移除 PiliBTRTV（使用者同意）。尚未 commit |
| 19:45 | 模擬器靜音；用戶回報直式影片右側綠色區塊、畫面被壓窄；快取與下載全螢幕手勢與一般影片相同 | 兩個 AVD 的 `config.ini` 設 `hw.audioOutput = no`（下次啟動生效）。截圖確認是 PiliBTRTV 播放器（platformView／SurfaceView，硬體解碼輸出的空白區），需要 BV 號與裝置型號才能重現，使用者去問用戶，尚未修改。手勢：Sonnet 在 `video_popup_player.dart` 全螢幕時加入雙擊快退／快進／播放暫停、水平拖動調進度、左側亮度／右側音量、長按倍速，依主播放器同一組 Pref 設定；analyze 無 issue，尚未實機測試、未 commit |
| 20:10 | 開模擬器、建置並安裝 | Pixel_9_Pro_XL 以 `-no-audio` 啟動；debug APK（x64）建置成功，但 /data 只剩 400MB 裝不下。擴大 `disk.dataPartition.size` 無效（資料在 qcow2 覆蓋檔，需 wipe 才套用），設定已還原。經使用者同意移除 Firefox，並把 `sys_storage_threshold_percentage` 設 1、`sys_storage_threshold_max_bytes` 設 50MB 後安裝成功並啟動 |
| 20:20 | 推送 | `ee58a912d`（彈窗播放器修正與全螢幕手勢）推送到 pilibtr main，未發布新版 |
| 20:40 | 發布 | `6a5c7aa57` 版本 v2.2.10（2.2.10+11），release 附 3 個 APK 與 SHA256SUMS（Latest）；issue #88、#89 已關閉。手勢未實機測試 |
| 20:55 | 新增錯誤／建議回報，傳送日誌或日誌加描述到我的信箱，區分 PiliBTR 與 PiliBTRTV | 使用者選擇沿用 PiliBTRTV 的 Google Apps Script 代寄（App 不放密碼或金鑰）。需求與規格在 `docs/work/feedback-report/`。Sonnet 實作回報頁（類型、描述、附日誌開關、成功顯示編號）、`/feedback` 路由、關於頁與日誌頁入口；新檔 analyze 0 issue（全專案 39 個 info 皆為原有）。PiliBTRTV 的 `docs/report-gmail/apps_script.gs` 改為依 `app` 欄位寫標題（預設 PiliBTRTV），`doGet` 回 `PiliBTR report` 以便確認重新部署；待使用者重新部署。未 commit、未實機測試 |
| 21:10 | 推送 | `a7e8338d4` 推送到 pilibtr main；PiliBTRTV 的腳本與 README 另推到 PiliBTRTV。Apps Script 尚未重新部署（仍回 PiliBTRTV report） |
| 21:30 | 掃 QR code 後有時還是黑屏，要重開掃描頁；改完發布 | 原因：mobile_scanner 7.5.0 生命週期處理 unawaited stop／start，快速 inactive→resumed 時平台 start 與未完成的 stop 交錯，相機停掉但狀態仍為運作中。Sonnet 改為掃描頁自行排隊停止／啟動（各 3 秒逾時）、處理完自動重啟、點畫面重新啟動；analyze 0 issue，未實機測試。`370c05388`；發布 v2.2.11（2.2.11+12），含回報功能 |
| 00:10（11-11） | 重新部署 Apps Script | 使用者重新部署；curl 確認網址回 `{"ok":true,"service":"PiliBTR report"}`，新版腳本已生效（未寄測試信） |
| 02:50（11-12） | 修正回報 8N3Y3M（v2.2.11、SM-S9380、Android 17：掃 PiliBTR 登入頁 QR code 後整個畫面全黑）；新增錯誤回報紀錄（使用者選紀錄加處理狀態） | 報告日誌只有 mpv 訊息、無 Dart 例外；相簿路徑正常、相機路徑黑，判斷為相機預覽 Texture 問題。Sonnet 改為偵測到 QR code 即移除 MobileScanner、處理完丟棄並以新 key 重建 controller（模擬重開頁面），點畫面重建，`[Scan]` 診斷日誌。另一 Sonnet 做回報紀錄（本機 20 筆）與狀態（`raw.githubusercontent.com/gordonpow/PiliBTR/main/report_status.json`，同 TV 格式），關於頁與回報頁入口；新增 `report_status.json`（8N3Y3M 處理中）。analyze 0 issue；未實機測試、未 commit |
| 03:20（11-12） | 使用者手機（SM-S9380，即回報者）開偵錯，用 v2.2.11 重現 | logcat：掃描後相機關閉、同時建立兩個 InAppWebView，畫面全黑（截圖確認連 AppBar 都沒有）。QR code 是 PiliBTRTV 登入頁「手機登入」的區網網址 `http://<電視IP>:3322/login?t=…`：PiliBTR 當一般網址，`routePushFromUrl` 對非 bilibili 網址開一次 WebView 又回 false，掃描頁再開一次；且 Android 預設禁止明文 http，WebView 全黑。先前「相機 Texture」推測錯誤，`scan/view.dart` 的重建修改已還原。修正 `handler.dart`：非 bilibili 的 http 或區網網址顯示對話框（PiliBTRTV 手機登入有專屬說明，建議改用 TV 掃碼），可複製或用瀏覽器開啟；其他網址用 `selfHandle: true` 只開一個 WebView。analyze 0 issue；arm64 release 測試 APK 放下載資料夾，手機已斷線未安裝 |
| 2026-11-12 | 豎屏長按彈幕開關可開啟彈幕設定 | `lib/pages/video/view.dart` tab 列彈幕開關 `IconButton` 加 `onLongPress`，經 `headerCtrKey` 呼叫 `HeaderControlState.showSetDanmaku()`；短按仍切換開關。analyze 0 issue；未實機測試、未 commit |
| 2026-11-12 | 語言新增與 TV 版相同的「原生」選項，不經過翻譯 | 參照 PiliBTRTV（值 4「原文」）：`ZhConvert.resolve` 把 4 視為繁體，`init` 在值 4 時設 `original` 並不載入繁簡表（`convert` 無表即回傳原字串）；設定 → 語言對話框加第 5 項「原文（不轉換）」。analyze 0 issue；未實機測試、未 commit |
| 2026-11-12 | 推送並發布 | 拆成 4 個 commit，`report_status.json` 8N3Y3M 改為已解決；升版 v2.2.12（2.2.12+13），推到 pilibtr main 並發布 |
| 2026-11-13 | 1. 載入速度能否像原版 100~300 ms；2. 手指碰到影片卡就預覽，不影響上下滑動 | 1：目前只有 debug 計時，無實測；原版快在 feed 內嵌 playurl、自家播放器、大陸邊緣節點，台灣只能用海外 CDN，估計快取＋預熱可到 300~600 ms，不保證 100~300。使用者選擇：計時＋mpv 起播參數、滑動直接跟手指換卡、長按恢復原動作、直接取代現有方式。完整流程（`docs/work/touch-preview-open-time/`），Sonnet 規格審查 10 條（採用 8、不採用 2）。agy 額度用完，改由 Sonnet 子代理實作；Opus 修正 BTR 首 byte 計時時機。analyze 無新 issue；未實機測試、未 commit |
| 2026-11-13 | 驗證載入速度，盡量做到 100~300 ms | 另開模擬器 PiliBTR_Test（emulator-5560，未登入）用 `--dart-define=btr.timing=true` 建置分段計時與 mpv log。修正：預熱量依位元率抓約 3 秒（影片 0.5~2MB、音訊 128~512KB，原固定 512KB 不夠起播）、預熱保留 30 秒改 3 分鐘、Wi-Fi 狀態 5 秒快取。修正後預熱完整命中，App＋網路部分約 100 ms；首幀仍 600~900 ms，mpv log 顯示主要是模擬器 goldfish 解碼器啟動約 320 ms＋首幀解碼約 210 ms，需真機量測確認。計時只在測試建置開啟 |
| 2026-11-13 | 先推上去 | 補英文語言包字串（版本 202611131200），推送到 pilibtr main，未發布新版；真機量測待做 |
| 2026-11-13 | 發佈新版 | `45e696a7f` 版本 v2.2.13（2.2.13+14），release 附 3 個 APK 與 SHA256SUMS（Latest）；issue #96、#97 已關閉。真機首幀尚未量測 |
