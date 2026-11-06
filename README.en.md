# PiliBTR

<img src="assets/images/logo/logo.png" width="96" alt="PiliBTR icon">

[中文](README.md) | English

PiliBTR is a third-party Bilibili client for Android. It is a modified version of [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus).

PiliBTR adds BTR (Bilibili Thread Ripper) multi-CDN acceleration, based on [Bilibili-thread-ripper-desktop](https://github.com/MrTangLuyao/Bilibili-thread-ripper-desktop) (MIT):

- Playback: a local proxy splits each player request into small pieces and downloads them from several CDN nodes at the same time. When one node is slow or stops, other nodes continue, so playback stutters less.
- Offline download: files download in parallel pieces, with pause and resume.

Other changes: Traditional Chinese (Taiwan) UI, in-app mini player, swipe down to shrink the video, long-press preview on the home page.

## Speed: without BTR and with BTR

Test on 2026-11-06, home network in Taiwan, Windows PC, 480P video, overseas mode (4 nodes, 8 threads, 512 KB pieces), 7 rounds of 17.7 MB each.

| | Without BTR | With BTR |
|---|---|---|
| Median speed | 11.38 MB/s | 12.58 MB/s (about +10%) |
| Range (lowest to highest) | 8.56 to 13.27 MB/s | 8.63 to 17.15 MB/s |

The difference in download speed is small and not stable in this test. BTR is designed to keep playback going when one node becomes slow: other nodes fill in the missing pieces. Playback smoothness has no measured data yet; on the author's real phone, playback feels smooth. Results on other networks can be different. See [README.md](README.md) for details.

## Download

Download the APK from [Releases](https://github.com/gordonpow/PiliBTR/releases/latest).

## License

- GPL v3, the same as PiliPlus.
- For learning and testing only. Do not use it for commercial purposes.
