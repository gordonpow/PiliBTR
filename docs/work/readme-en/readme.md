# PiliBTR

<img src="assets/images/logo/logo.png" width="96" alt="PiliBTR icon">

English | [繁體中文](README.zh-TW.md)

> **PiliBTR** is an open-source third-party Bilibili client for Android based on [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus). It integrates BTR (Bilibili Thread Ripper) multi-CDN parallel acceleration—inspired by [Bilibili-thread-ripper-desktop](https://github.com/MrTangLuyao/Bilibili-thread-ripper-desktop) (MIT)—to fetch video streams across multiple CDN nodes simultaneously. This drastically reduces buffering stalls (especially outside mainland China) and accelerates offline downloads. Pre-built APKs are available on [Releases](https://github.com/gordonpow/PiliBTR/releases/latest).

---

## Why

- **The Problem**: Bilibili streams and downloads media using a single connection to a single CDN node. If that assigned node suffers from network congestion, high latency, or packet loss, video playback constantly buffers and stutters. This issue is particularly noticeable when accessing Bilibili from outside mainland China.
- **The BTR Desktop Approach**: [Bilibili-thread-ripper-desktop](https://github.com/MrTangLuyao/Bilibili-thread-ripper-desktop) solved this on Windows by intercepting requests from the official desktop client, slicing data ranges into smaller chunks, and fetching them concurrently across multiple CDN nodes. However, its injection technique is restricted to Windows desktop environments and cannot run on mobile operating systems.
- **Goal of PiliBTR**: Port true multi-CDN parallel streaming and downloading to Android:
  - **Smooth Video Playback**: Streaming buffers are fetched in parallel from multiple CDN nodes, preventing slow individual nodes from interrupting playback.
  - **Accelerated Offline Downloads**: Caching uses multi-threaded segmented chunk downloading with pause and resume support.

---

## Features

| Area | Feature | Description |
|---|---|---|
| **Playback acceleration (BTR)** | Local HTTP Proxy (`127.0.0.1`) | Runs an internal loopback proxy that intercepts mpv player `Range` requests, splits requests into small chunks (128 KB initial chunk for fast first-frame display, 512 KB subsequent chunks), and downloads them concurrently across multiple CDN nodes before streaming bytes back to the player in order. |
| | Intelligent Node Pool | Dynamically tests node speeds and health; disables failing nodes (e.g. 2 consecutive 0-byte responses), distributes chunks based on `speed / active_requests`, and filters out nodes that are 12x slower than the fastest node. |
| | Request Hedging & Fallback | Hedges delayed chunks by dispatching duplicate requests to alternate nodes if a chunk takes longer than 1.5x the average response time (0.7s–2.5s); seamlessly falls back to the original URL if all CDN nodes fail so playback never breaks. |
| | CDN Modes & Concurrency | Offers Mainland (9 nodes), Overseas (4 nodes), and Custom (up to 32 nodes) modes. Concurrency can be set to Auto (8 playback threads, 4–16 download threads) or manually configured (4 to 128 threads). |
| | Real-Time CDN Status | In-player status panel showing current download throughput delivered to the player and historical average speeds per CDN node. |
| **Fast start & preloading** | Instant Playback Start | Sub-second video launch latency through parallel initial connection attempts, head streaming, request hedging, and global node latency statistics, defaulting to 1080P without redundant API roundtrips. |
| | Visible-Card Preload | Automatically prefetches playback URLs and preheats video streams for all video cards currently visible on the screen. Keeps preloading smoothly while scrolling without interruption. |
| | Tap-Down Preheating | Triggers initial chunk preheating on the touch-down event before finger release, significantly reducing perceived startup delay. |
| | Configurable Preload Settings | Customizable preloading behavior (Always, Wi-Fi only, or Off) and configurable concurrent video preload limits (default: unlimited, scoped dynamically to visible cards). |
| | Seamless Error Recovery | Retries playback from the exact current timestamp if an error occurs, avoiding restarting from 0 seconds. |
| **Player** | In-App Mini Player | Minimizes the playing video into a floating window when exiting the video details page. Snaps to the four screen corners, preserves corner placement across screen rotations, and sits flush against the bottom edge when the navigation bar collapses. Supports small, medium, large, or custom sizes. |
| | Diagonal Swipe Gesture | Swiping diagonally down-left or down-right on the player dynamically shrinks the video with your finger into the mini player. If entered from a chain of recommended videos, shrinking returns directly to the root page (Home, Search, History), while pressing Back returns to the preceding video. |
| | Fullscreen 3-Zone Gestures | Fullscreen view is split horizontally into three zones with customizable center zone width: swipe up on the center zone to reveal related videos or bangumi episodes; swipe down on the center zone (or diagonally anywhere) to minimize into the mini player or exit fullscreen; left and right zones control brightness and volume. |
| | Picture-in-Picture (PiP) | System-level Android Picture-in-Picture support when navigating back to the home screen or switching between apps. |
| | Vertical / Reels Mode | Full-screen vertical swipe feed for short videos with grid feed view, automatic playback of the next video upon completion, and background preloading of up to 3 upcoming videos using dual/quad player instances with Wi-Fi/cellular quality adaptation and AVC fallback. |
| | Card Long-Press Preview | Long-press any video card on the home page or in lists to play an inline preview with a progress bar and CC subtitle toggle; tapping the card seamlessly resumes playback from the preview timestamp. Audio mute toggle state is synchronized across all previews. |
| | Controls & Playback Tweaks | Playback speed slider with +/- micro-adjustment buttons (1.0x, 1.25x, 1.5x, 2.0x presets), background playback when screen is off, customizable auto-play countdown with cancel/play-now, and automatic landscape orientation detection. |
| **Downloads & cache** | Multi-Threaded Chunked Caching | Splits offline cache files into 512 KB to 8 MB blocks downloaded in parallel across CDN nodes. Tracks progress via `.btr` checkpoint files for resilient pause/resume without re-downloading; supports resuming legacy single-connection downloads. |
| | Direct MP4 Download | Dedicated "Download" button to save videos directly as standalone MP4 files to a custom directory (defaults to system Download directory), with pause and resume support. |
| | Cache & Download Manager | Dedicated management tab under the "My" page with batch pause, resume, stop, and real-time download speed monitoring with selectable speed units (MB/s, KB/s). |
| **Recommendations** | Recommendation Click Attribution | Carries recommendation card `track_id` upon navigation to report click attribution, improving recommendation relevance matching the official app. |
| | Mobile Heartbeat Reporting | Sends official mobile heartbeat telemetry (`/x/report/heartbeat/mobile` START and END events) reporting actual watch time. |
| | Unified Device Identity | Standardizes HD client headers, device fingerprints, and session tokens across recommendation API requests. |
| | Instant Account Switching Refresh | Immediately reloads home recommendations upon logging in, logging out, or switching accounts, preventing lingering guest feeds. |
| **Login** | QR Code Scanner | Built-in camera and gallery image QR scanner in the "My" page to authenticate logins for Bilibili TV / TV box clients and web browser sessions (via authenticated WebView confirmation). |
| | International SMS Region Codes | Phone SMS login includes international country/region dial codes (e.g. Taiwan, Hong Kong, and other international regions). |
| **Languages** | Traditional & Simplified Chinese | Complete Traditional Chinese interface (Taiwan terminology `zh_TW` converted via OpenCC) and Simplified Chinese mode, with an option to follow system language. |
| | English UI *(New in v2.2.4)* | Downloadable English language pack (`i18n/en.json`) fetched on demand and cached locally for offline use. Checks for updates every 7 days in the background (or manually via settings); Material UI components adapt to `en-US`. |
| | Subtitle Translation *(New in v2.2.4)* | Automatically defaults to official Bilibili English subtitles (`en-*`, `ai-en`) when available; otherwise translates Chinese subtitles into English using an on-device Google ML Kit offline model (~30 MB) or online API keys (DeepL / Google Cloud Translation). Translated subtitle tracks are marked with "(Translated)". |
| | Danmaku Translation *(New in v2.2.4)* | Translates on-screen danmaku (bullet comments) and live chat into English using the on-device ML Kit model after applying block/filter and deduplication rules, backed by a translation cache. |
| **Appearance** | Cold Start Splash Animation | Custom dark splash screen with animated launch sequence (can be disabled or tapped to skip; pure black `#000000` background). |
| | Official App Layout | Bottom navigation bar modeled after the official Bilibili mobile app (Home, Following, Messages, My). |
| | Video Card Grid Customization | Unified vertical video cards with separate portrait and landscape row/column counts (e.g. 1 to 4 columns), synchronized across anime, movies, and live streams. |
| | Hierarchical Settings | Tree-structured categorized settings menu with persistent settings search history. |
| **Updates** | In-App Updater | Checks GitHub Releases for new updates automatically or manually with notification badge indicators, customizable check frequency (default: every 24 hours, plus on app launch), and direct in-app download and installation. |

---

## Download & Install

Download the latest pre-compiled APK from [GitHub Releases](https://github.com/gordonpow/PiliBTR/releases/latest).

### Which APK to Choose?

| Architecture | Target Devices |
|---|---|
| `arm64-v8a` | **Recommended**. For almost all modern Android phones and tablets (64-bit ARM). |
| `armeabi-v7a` | For older 32-bit ARM Android devices. |
| `x86_64` | For Android emulators on PC or x86_64 Android tablets. |

### Installation Notes

- **Debug-Key Signing Note**: Release APKs are signed with a test/debug key. During installation, Android Play Protect or your system's package installer may display an "Unrecognized app" or security warning. This is expected for community builds—select "Install anyway" to proceed.
- **Cannot Overwrite Official PiliPlus**: PiliBTR uses a distinct package configuration and signature from upstream PiliPlus. It cannot directly overwrite or update an existing official PiliPlus installation. PiliBTR installs as a standalone application.

---

## Recommended Settings for Users Outside Mainland China

If you are using PiliBTR outside mainland China (e.g., in Taiwan, Hong Kong, Macau, Japan, North America, Southeast Asia, or Europe), mainland CDN nodes can be slow, throttled, or unreachable:

1. Go to **Settings** → **Video Settings** → **Thread Ripper (Multi-CDN Acceleration)** (or Settings → Video Settings).
2. Set **CDN Mode** to **Overseas** (`海外`). This routes video streaming chunks across 4 high-speed overseas CDN nodes.
3. Keep **Auto Threads** turned **ON** (recommended: 8 threads for streaming playback, dynamic 4–16 threads for offline downloads).

---

## Build from Source

### Prerequisites

- Flutter `3.47.9`
- Android SDK (API 37)
- Android NDK `28.2.13676358`
- Enable Windows Developer Mode and long path support:
  ```powershell
  git config --global core.longpaths true
  ```

### Build Steps

1. Clone the repository:
   ```bash
   git clone https://github.com/gordonpow/PiliBTR.git
   cd PiliBTR
   ```
2. Apply upstream Flutter SDK and package patches:
   PiliPlus requires patching the Flutter SDK and `material_ui` package. Set the `FLUTTER_ROOT` and `GITHUB_WORKSPACE` environment variables, then run:
   ```powershell
   .\lib\scripts\patch.ps1 android
   ```
   *(Note on Windows: Ensure `~/.pub-cache` in the script points to `$env:LOCALAPPDATA\Pub\Cache` if using standard Pub cache locations).*
3. Build the release APKs:
   ```bash
   flutter build apk --release --split-per-abi
   ```
   The generated APK files will be located in `build/app/outputs/flutter-apk/`.

---

## Credits & License

- **[PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus)**: This project is based on PiliPlus and is licensed under the **GNU General Public License v3.0 (GPL-3.0)**.
- **[Bilibili-thread-ripper-desktop](https://github.com/MrTangLuyao/Bilibili-thread-ripper-desktop)**: Acceleration rules and multi-CDN architecture are inspired by and ported from Bilibili-thread-ripper-desktop (MIT, by MrTangLuyao).

---

## Disclaimer

This project is for learning and testing purposes only. Do not use it for commercial purposes.
