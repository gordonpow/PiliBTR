# PiliBTR

<img src="assets/images/logo/logo.png" width="96" alt="PiliBTR icon">

[English](README.en.md)

> **PiliBTR** is a third-party Bilibili client for Android, based on [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus). It downloads video from several Bilibili CDN nodes at the same time, so playback stutters less (especially outside mainland China) and offline downloads are faster. Traditional Chinese UI. Download the APK from [Releases](https://github.com/gordonpow/PiliBTR/releases/latest).

基於 [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) 修改，加入「線程撕裂者」（Bilibili Thread Ripper，BTR）的多 CDN 並行加速。設計參考 [Bilibili-thread-ripper-desktop](https://github.com/MrTangLuyao/Bilibili-thread-ripper-desktop)（MIT），並移植到 Android 手機。

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
| 斜滑縮小 | 在播放器上往左下或右下斜滑，視窗跟著手指縮小；放開後變成迷你播放器，距離不夠則彈回。從推薦影片連續點進多個影片頁時，斜滑後小窗播放目前的影片，主畫面回到點進第一個影片頁之前的頁面（例如首頁、搜尋、觀看紀錄）；按返回則回到上一個影片頁 |
| 長按預覽 | 首頁長按影片卡片，直接在卡片上播放預覽（預設靜音），有進度條與 CC 字幕開關；點卡片會從預覽位置接著播放 |
| 推薦帳號切換 | 登入、登出或切換推薦帳號後，首頁推薦立即重新載入，不再顯示遊客推薦 |

設定位置：**設定 → 播放設定**（迷你播放器、斜滑縮小、視窗大小）、**設定 → 推薦設定**（長按影片預覽）

設定位置：**設定 → 影片設定 → 線程撕裂者（多 CDN 加速）**

## 網速比較：無 BTR 與有 BTR

| 項目 | 無 BTR | 有 BTR |
|---|---|---|
| 連線方式 | 1 條連線，只連原始 CDN 節點 | 8 條連線，每塊 512 KB，分散到 4 個海外節點 |
| 節點變慢或斷線時 | 播放器只能等，畫面緩衝、卡頓 | 自動改用較快的節點，慢的那塊在別的節點補抓 |
| 實測下載速度（中位數） | 11.38 MB/s | 12.58 MB/s（約 +10%） |
| 實測範圍（7 輪最低～最高） | 8.56～13.27 MB/s | 8.63～17.15 MB/s |
| 播放順暢度 | — | 作者在實體手機上使用，體感順暢（尚無量測數據） |

下載速度的測試條件：

- 時間與地點：2026-11-06，台灣家用網路，Windows 電腦（不是手機）。
- 影片：熱門影片 `BV1mpxR6KESh`，480P（未登入），原始節點 `upos-sz-mirrorcosov.bilivideo.com`。
- 方法：用 Python 腳本模擬 App 的做法（海外模式 4 個節點、8 線程、512 KB 分塊、依「實測速度 ÷ 進行中請求數」選節點、連線重用）。每輪各下載一段 17.7 MB、彼此不重複的資料，兩種方式交替先後，共 7 輪。

結果解讀：

- 這次測試中，原始節點本身就很快，所以平均速度只差約 10%，而且單一連線的速度波動比較大。7 輪中也有單一連線比較快的時候（第 2 輪 12.12 對 8.63 MB/s），所以這個差距不算穩定。
- 480P 影片只需要約 0.62 Mbps（約 0.08 MB/s），兩種方式都遠高於這個數字。BTR 的設計目的是原始節點變慢或卡住時，改由其他節點補上，讓播放不跟著停下來。
- 網路環境不同，結果可能不同（例如手機行動網路、原始節點分配到較慢的主機時）。
- 播放順暢度目前只有作者在實體手機上的使用體感，還沒有量測數據。Android 模擬器的 debug 版不適合拿來比較：播放資料要經過 Dart 寫的本機代理，debug 版沒有最佳化，可能讓開啟 BTR 時明顯變慢，關閉時則不受影響。

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
