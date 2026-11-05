# PiliBTR（PiliPlus 線程撕裂者版）

<img src="assets/images/logo/logo.png" width="96" alt="PiliBTR icon">

> **PiliBTR** is a third-party Bilibili client for Android, based on [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus). It downloads video from several Bilibili CDN nodes at the same time, so playback stutters less (especially outside mainland China) and offline downloads are faster. Traditional Chinese UI. Download the APK from [Releases](https://github.com/gordonpow/PiliBTR/releases/latest).

本版本 fork 自 [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus)，加入「線程撕裂者」（Bilibili Thread Ripper，BTR）的多 CDN 並行加速。設計參考 [Bilibili-thread-ripper-desktop](https://github.com/MrTangLuyao/Bilibili-thread-ripper-desktop)（MIT），並移植到 Android 手機。

## 為什麼要做

- **問題**：Bilibili 的播放與下載，一次只從一個 CDN 節點、用一條連線抓資料。那個節點如果慢或不穩，影片就會一直緩衝、卡頓，在海外更明顯。
- **BTR Desktop 的做法**：攔截官方 Windows 客戶端的請求，把每段資料拆成小塊，同時交給多個 CDN 節點下載。它只能用在 Windows，手機沒辦法用同樣的補丁方式。
- **本版本的目標**：在 Android 上做出同樣的效果。
  - 看影片時，播放緩衝由多個 CDN 同時下載，減少卡頓。
  - 離線快取也改成多線程並行下載。

## 新增功能

| 功能 | 說明 |
|---|---|
| 播放加速 | 播放器的每個 Range 請求切成小塊，由多個 CDN 節點並行下載，依序交回播放器 |
| 下載加速 | 離線快取分塊並行下載，可暫停、可續傳 |
| CDN 模式 | 大陸（9 個節點）、海外（4 個節點）、自訂（最多 32 個） |
| 線程數 | 自動（推薦），或手動選 4、8、16、32、64、128 |
| 容錯 | 自動停用壞節點，依速度挑節點，卡住時補抓，最後可退回原網址 |
| 繁體中文介面 | 全部介面文字改為繁體中文（台灣用語），系統元件使用 zh_TW 語系 |
| App 名稱與圖示 | App 名稱改為 PiliBTR，新圖示：撕成 4 條線程的播放鍵 |
| 迷你播放器 | 離開影片頁時，影片縮成小視窗繼續播放；可拖曳並吸附四個角落，旋轉螢幕後留在同一角落，底部導覽列收起時貼齊螢幕邊緣 |
| 斜滑縮小 | 在播放器上往左下或右下斜滑，視窗跟著手指縮小；放開後變成迷你播放器，距離不夠則彈回 |
| 長按預覽 | 首頁長按影片卡片，直接在卡片上播放預覽（預設靜音），有進度條與 CC 字幕開關；點卡片會從預覽位置接著播放 |
| 推薦帳號切換 | 登入、登出或切換推薦帳號後，首頁推薦立即重新載入，不再顯示遊客推薦 |

設定位置：**設定 → 播放設定**（迷你播放器、斜滑縮小、視窗大小）、**設定 → 推薦設定**（長按影片預覽）

設定位置：**設定 → 影片設定 → 線程撕裂者（多 CDN 加速）**

## 架構

```
                    ┌──────────────── App ────────────────┐
 播放器 (mpv) ──Range──▶ BtrProxy（127.0.0.1 本機代理）     │
                    │      │ 切成 128 KB / 512 KB 小塊      │
                    │      ▼                                │
 離線快取 ─────────▶ DownloadManager（分塊、.btr 進度檔）  │
                    │      │                                │
                    │      ▼                                │
                    │  BtrNodePool（節點池：測速、停用、輪換）│
                    └──────┼────────────────────────────────┘
                           ▼
            CDN 節點 A   CDN 節點 B   CDN 節點 C ...（同時下載）
```

### 播放加速（`lib/services/download/btr_proxy.dart`）

- **需求**：播放時減少卡頓，而且不能改到播放器本身。
- **設計**：
  - PiliPlus 使用 mpv 播放器，沒辦法像 BTR Desktop 那樣攔截瀏覽器的 `fetch`。所以 App 內開一個只監聽 `127.0.0.1` 的 HTTP 代理，播放網址改成指向這個代理。
  - 代理收到播放器的 `Range` 請求後，把範圍切成小塊，最多 N 塊同時下載，N 等於線程數。
  - 下載好的小塊依順序寫回播放器，第一塊只有 128 KB，所以開播很快。
  - 對每一塊都測量下載時間。目前最前面那塊花的時間超過平均的 1.5 倍（0.7 到 2.5 秒之間）時，會在另一個節點同時下載同一塊（hedge），先完成的就用。
  - 使用者拖動進度條時，播放器會中斷連線，代理也立即取消進行中的請求。
  - 所有節點都失敗時，剩下的部分改用原網址單連線補完，播放不會中斷。
  - 直播和本機檔案不經過代理。
- **整合點**：`lib/plugin/pl_player/controller.dart`，播放器開啟媒體前呼叫 `BtrProxy.wrap()`。

### 下載加速（`lib/services/download/download_manager.dart`）

- **需求**：離線快取更快，而且中斷後可以接著下載。
- **設計**：
  - 先發 `Range: bytes=0-0` 取得檔案大小，同時確認伺服器支援分段下載。不支援就改回原本的單連線下載。
  - 檔案切成 512 KB 到 8 MB 的區塊，由多個工作者並行下載，寫入同一個檔案的對應位置。寫入會排隊，因為 `RandomAccessFile` 不能同時寫。
  - 進度存在 `<檔名>.btr`，記錄已完成的區塊。暫停或失敗後可以續傳，完成後自動刪除。
  - 舊版單連線下載到一半的檔案也能接著下載。
  - 對外介面跟原本一樣，所以 `download_service.dart` 不用改。

### 節點池（`lib/services/download/btr_cdn.dart`）

播放加速和下載加速共用同一套節點規則，沿用 BTR 的做法：

- **換節點**：只換網址的主機名稱，路徑和簽名參數保留。原網址在 Akamai 時，也可以用它當來源換到其他主機。
- **不換節點的網址**：mcdn 中繼網址（`mcdn` 主機、`/v1/resource/` 路徑、`os=mcdn`）不換。Akamai 也不會被當成換過去的目標，因為它的簽名格式不同。
- **停用規則**：連續 2 次收到 0 byte 的節點，在這部影片中停用。全部停用時重新啟用，最多 3 輪，只要有一次成功就重新計算。
- **選節點**：先每個節點試一次。之後每次選「實測速度 ÷ 進行中的請求數」最高的節點，比最快節點慢 12 倍以上的節點跳過。
- **逾時**：連線逾時 4 秒，下載停頓 5 秒就換節點。播放時每塊最多試 6 次，下載時每塊最多試 12 次，已收到的部分保留不重抓。

### 設定（`lib/services/download/btr_config.dart`、`lib/pages/setting/widgets/btr_settings_dialog.dart`）

| 設定鍵 | 預設 | 說明 |
|---|---|---|
| `btrPlayback` | 開 | 播放加速 |
| `btrEnable` | 開 | 下載加速 |
| `btrCdnMode` | 大陸 | CDN 模式：大陸、海外、自訂 |
| `btrCustomCdn` | 空 | 自訂節點，每行一個 |
| `btrAutoThreads` | 開 | 自動線程：播放用 8 條，下載依檔案大小用 4 到 16 條 |
| `btrThreads` | 16 | 手動線程數 |

在海外（例如台灣）建議選「海外」模式，大陸節點常連不上或很慢。

## 變更檔案

| 檔案 | 變更 |
|---|---|
| `lib/services/download/btr_proxy.dart` | 新增：播放用的本機代理和並行下載 |
| `lib/services/download/btr_cdn.dart` | 新增：節點池和專用 Dio，連線逾時 4 秒 |
| `lib/services/download/btr_config.dart` | 新增：設定和節點清單 |
| `lib/pages/setting/widgets/btr_settings_dialog.dart` | 新增：設定視窗 |
| `lib/services/download/download_manager.dart` | 改寫：多線程分塊下載和續傳 |
| `lib/plugin/pl_player/controller.dart` | 播放網址改經過代理 |
| `lib/pages/setting/models/video_settings.dart` | 加入設定入口 |
| `lib/utils/storage_key.dart` | 加入 6 個設定鍵 |
| `lib/scripts/to_traditional.py`、`lib/scripts/dartlex.py` | 新增：把介面字串轉成繁體中文的腳本 |
| `lib/main.dart` | 語系改為 zh_TW |
| `lib/common/constants.dart`、`lib/http/api.dart` | App 名稱、原始碼網址、檢查更新改指向 PiliBTR |
| `assets/images/logo/`、`android/app/src/main/res/` | 新圖示、啟動畫面、App 名稱 |
| `lib/plugin/pl_player/mini_player.dart` | 新增：迷你播放器、斜滑縮小的跟手預覽 |
| `lib/plugin/pl_player/view/view.dart` | 斜滑手勢 |
| `lib/common/widgets/video_card/video_preview.dart` | 新增：卡片長按預覽（BTR、字幕、進度條） |
| `lib/common/widgets/video_card/video_card_v.dart` | 長按預覽、預取播放網址、從預覽位置開啟影片 |
| `lib/utils/accounts.dart`、`lib/pages/rcmd/controller.dart` | 推薦帳號變更時重新載入首頁推薦 |

## 建置（Windows，Android）

1. 安裝 Flutter 3.47.9、Android SDK（API 37）和 NDK 28.2.13676358。
2. 開啟 Windows 開發人員模式，並執行 `git config --global core.longpaths true`。
3. PiliPlus 需要先修補 Flutter SDK 和 `material_ui` 套件。設定環境變數 `FLUTTER_ROOT` 和 `GITHUB_WORKSPACE`，再執行 `lib/scripts/patch.ps1 android`。在 Windows 上，要把腳本裡的 `~/.pub-cache` 改成 `$env:LOCALAPPDATA/Pub/Cache`。
4. 執行 `flutter build apk --release --split-per-abi`。

### 繁體中文轉換

上游 PiliPlus 的介面字串是簡體中文，直接寫在 Dart 程式裡。本版本用 [OpenCC](https://github.com/BYVoid/OpenCC)（`s2twp`，台灣用語）轉換字串常數，註解和程式碼不變。和 Bilibili 伺服器回傳的簡體文字做比對的字串會保留簡體，清單在腳本的 `PROTECT` 裡。

每次合併上游之後，執行：

```sh
pip install opencc
python lib/scripts/to_traditional.py
```

腳本可以重複執行。影片標題、評論等伺服器內容仍是原文。

## 授權

- 本專案沿用 PiliPlus 的 **GPL v3** 授權。
- 加速規則參考 Bilibili-thread-ripper-desktop（MIT，作者 MrTangLuyao）。
- 本專案僅供學習和測試，請勿用於商業用途。

---

以下為上游 PiliPlus 原始說明。

<div align="center">
    <img width="200" height="200" src="assets/images/logo/logo.png">
</div>



<div align="center">
    <h1>PiliPlus</h1>
<div align="center">

中文 | [English](README.en.md)

![GitHub repo size](https://img.shields.io/github/repo-size/bggRGjQaUbCoE/PiliPlus) 
![GitHub Repo stars](https://img.shields.io/github/stars/bggRGjQaUbCoE/PiliPlus) 
![GitHub all releases](https://img.shields.io/github/downloads/bggRGjQaUbCoE/PiliPlus/total) 
</div>
    <p>使用Flutter開發的BiliBili第三方客戶端</p>
    
<img src="assets/screenshots/510shots_so.png" width="32%" alt="home" />
<img src="assets/screenshots/174shots_so.png" width="32%" alt="home" />
<img src="assets/screenshots/850shots_so.png" width="32%" alt="home" />
<br/>
<img src="assets/screenshots/main_screen.png" width="96%" alt="home" />
<br/>
</div>


<br/>

## 適配平台

- [x] Android
- [x] iOS
- [x] Pad
- [x] Windows
- [x] Linux

[![Packaging status](https://repology.org/badge/vertical-allrepos/piliplus.svg)](https://repology.org/project/piliplus/versions)

## refactor

- [ ] gRPC [wip]
- [x] 使用者介面
- [x] 其他

## feat

- [x] 編輯動態
- [x] DLNA 投屏
- [x] 離線快取/播放
- [x] 移動端支援點選彈幕懸停，點贊、複製、舉報 by [@My-Responsitories](https://github.com/My-Responsitories)
- [x] 播放音訊
- [x] 跳過番劇片頭/片尾
- [x] 安卓端 `loudnorm` 適配 by [@My-Responsitories](https://github.com/My-Responsitories)
- [x] Win/Mac 支援極驗、簡訊登入 by [@My-Responsitories](https://github.com/My-Responsitories)
- [x] 影片擷取動圖 by [@My-Responsitories](https://github.com/My-Responsitories)
- [x] AI 原聲翻譯
- [x] SuperChat
- [x] 播放課堂影片
- [x] 發起投票
- [x] 釋出動態/評論支援`富文本編輯`/`表情顯示`/`@使用者`
- [x] 修改訊息設定
- [x] 修改聊天設定
- [x] 展示摺疊訊息
- [x] 檢視使用者圖文
- [x] 動態話題
- [x] 直播分割槽
- [x] 分享`影片`/`番劇`/`動態`/`專欄`/`直播`至訊息
- [x] 建立/修改/刪除關注分組
- [x] 移除粉絲
- [x] 直播彈幕傳送表情
- [x] 收藏夾排序
- [x] 稍後再看 ~~`未看`~~ / `未看完` / ~~`已看完`~~ 分類
- [x] WebDAV 備份/恢復設定
- [x] 儲存評論/動態
- [x] 高階彈幕 by [@My-Responsitories](https://github.com/My-Responsitories)
- [x] 取消/置頂評論
- [x] 記筆記
- [x] 多賬號支援 by [@My-Responsitories](https://github.com/My-Responsitories)
- [x] 遮蔽帶貨動態/評論
- [x] 互動影片
- [x] 發評/動態反詐
- [x] 高能進度條
- [x] 滑動跳轉預覽影片縮圖
- [x] Live Photo
- [x] 複製/移動/排序收藏夾/稍後再看影片
- [x] 超解析度
- [x] 合併彈幕
- [x] 會員彩色彈幕
- [x] 播放全部/繼續播放/倒序播放
- [x] Cookie登入
- [x] 顯示影片分段資訊
- [x] 調節字幕大小
- [x] 調節全屏彈幕大小
- [x] 收藏夾/稍後再看多選刪除
- [x] 搜尋使用者動態
- [x] 直播彈幕
- [x] 修改頭像/使用者名稱/簽名/性別/生日
- [x] 建立/編輯/刪除收藏夾
- [x] 評論樓中樓檢視對話
- [x] 評論樓中樓定位點選檢視的評論
- [x] 評論樓中樓按熱度/時間排序
- [x] 評論點踩
- [x] 私信發圖
- [x] 投幣動畫
- [x] 取消/追番，更新追番狀態
- [x] 取消/訂閱合集
- [x] SponsorBlock
- [x] 顯示影片完整合集
- [x] 三連動畫
- [x] 番劇三連
- [x] 帶圖評論
- [x] 影片TAG
- [x] 篩選搜尋
- [x] 轉發動態
- [x] 合集圖片
- [x] 刪除/置頂/撤回私信
- [x] 舉報使用者/評論/影片/動態
- [x] 刪除/釋出/置頂文本/圖片動態
- [x] 其他

## opt

- [x] 專欄介面
- [x] 私信介面
- [x] 收藏面板
- [x] PIP
- [x] 影片封面
- [x] 回覆介面
- [x] 系統通知
- [x] 評論顯示
- [x] 亮度調節
- [x] 影片播放
- [x] 影片staff
- [x] 防止bottomsheet遮擋全屏影片
- [x] 其他

## fix

- [x] 番劇分集點贊/投幣/收藏
- [x] bugs

<br/>

## 功能

- [x] 推薦影片列表(app端)
- [x] 最熱影片列表
- [x] 熱門直播
- [x] 番劇列表
- [x] 遮蔽黑名單內使用者影片
- [x] 無痕模式（播放視為未登入）
- [x] 遊客模式（推薦視為未登入）

- [x] 使用者相關
  - [x] 粉絲、關注使用者、拉黑使用者檢視
  - [x] 使用者主頁檢視
  - [x] 關注/取關使用者
  - [x] 離線快取
  - [x] 稍後再看
  - [x] 觀看記錄
  - [x] 我的收藏
  - [x] 站內私信
  
- [x] 動態相關
  - [x] 全部、投稿、番劇分類檢視
  - [x] 動態評論檢視
  - [x] 動態評論回覆功能

- [x] 影片播放相關
  - [x] 雙擊快進/快退
  - [x] 雙擊播放/暫停
  - [x] 垂直方向調節亮度/音量
  - [x] 垂直方向上滑全屏、下滑退出全屏
  - [x] 水平方向手勢快進/快退
  - [x] 全屏方向設定
  - [x] 倍速選擇/長按2倍速
  - [x] 硬體加速（視機型而定）
  - [x] 畫質選擇（高畫質畫質未解鎖）
  - [x] 音質選擇（視影片而定）
  - [x] 解碼格式選擇（視影片而定）
  - [x] 彈幕
  - [x] 字幕
  - [x] 記憶播放
  - [x] 影片比例：高度/寬度適應、填充、包含等
     
- [x] 搜尋相關
  - [x] 熱搜
  - [x] 搜尋歷史
  - [x] 預設搜尋詞
  - [x] 投稿、番劇、直播間、使用者搜尋
  - [x] 影片搜尋排序、按時長篩選
    
- [x] 影片詳情頁相關
  - [x] 影片選集(分p)切換
  - [x] 點贊、投幣、收藏/取消收藏
  - [x] 相關影片檢視
  - [x] 評論使用者身份標識
  - [x] 評論(排序)檢視、二樓評論檢視
  - [x] 主樓、二樓評論回覆功能
  - [x] 評論點贊
  - [x] 評論筆記圖片檢視、儲存

- [x] 設定相關
  - [x] 畫質、音質、解碼方式預設      
  - [x] 圖片質量設定
  - [x] 主題模式：亮色/暗色/跟隨系統
  - [x] 震動反饋(可選)
  - [x] 高幀率
  - [x] 自動全屏
  - [x] 橫屏適配
- [ ] 等等

<br/>

## 下載

可以從 [Releases](https://github.com/bggRGjQaUbCoE/PiliPlus/releases) 下載，或克隆倉庫拉取程式碼後在本地編譯。

<br/>

## 宣告

此專案（PiliPlus）是個人為了興趣而開發，僅用於學習和測試，請於下載後24小時內刪除。
所用API皆從官方網站收集，不提供任何破解內容。
在此致敬原作者：[guozhigq/pilipala](https://github.com/guozhigq/pilipala)
在此致敬上游作者：[orz12/PiliPalaX](https://github.com/orz12/PiliPalaX)
本倉庫做了更激進的修改，感謝原作者的開源精神。

感謝使用


<br/>

## 致謝

- [bilibili-API-collect](https://github.com/SocialSisterYi/bilibili-API-collect)
- [flutter_meedu_videoplayer](https://github.com/zezo357/flutter_meedu_videoplayer)
- [media-kit](https://github.com/media-kit/media-kit)
- [dio](https://pub.dev/packages/dio)
- 等等

<br/>
<br/>
<br/>

## Star History

<a href="https://star-history.dera.page/#bggRGjQaUbCoE/PiliPlus&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://star-history.dera.page/svg?repos=bggRGjQaUbCoE/PiliPlus&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://star-history.dera.page/svg?repos=bggRGjQaUbCoE/PiliPlus&type=Date" />
   <img alt="Star History Chart" src="https://star-history.dera.page/svg?repos=bggRGjQaUbCoE/PiliPlus&type=Date" />
 </picture>
</a>
