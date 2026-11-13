Project: Flutter app at C:\presonal_project\bilibili_bata\PiliPlus (Android first). Read docs/work/touch-preview-open-time/1-requirements.md and docs/work/touch-preview-open-time/2-spec.md first; the spec is the source of truth (its 審查紀錄 table explains decisions).

Rules:
- Comments and UI text in Traditional Chinese (Taiwan) or English; never Simplified Chinese (except existing string constants compared with server text).
- Do not commit, do not run git commands that change state. Do not run `dart format` on the whole lib folder; if you format, only format the files you changed.
- Another implementer edits other files in parallel: only change the files listed for your task.
- Check with: C:/src/flutter/bin/flutter analyze <the files you changed> (use exactly this flutter path; C:\flutter is wrong). Fix all new issues.
- When done, reply in Traditional Chinese (under 300 words): files changed, what you did per spec item, analyze result, and any spec deviation with reason.

Your task: T-2 then T-3 (spec sections "B. 開影片計時" and "C. 快速起播參數").
Files you may change:
- lib/services/open_timing.dart (new)
- lib/pages/video/controller.dart
- lib/utils/play_url_cache.dart (add has())
- lib/services/download/btr_proxy.dart (record head first byte for pendingUrls)
- lib/plugin/pl_player/widgets/cdn_status_panel.dart
- lib/plugin/pl_player/controller.dart (only the fastStart extras)
- lib/utils/storage_key.dart (add fastStart key; do not touch other keys)
- lib/utils/storage_pref.dart (Pref.fastStart, default true)
- the playback settings model file that holds the buffer settings (find it under lib/pages/setting/models/), and lib/pages/setting/models/setting_tree.dart only to register the new 「快速起播」 title if titles are listed there.
Notes: BTR wraps CDN URLs into local proxy URLs; in btr_proxy.dart find the original CDN URL for the head request and compare with OpenTiming.pendingUrls (videoUrl/audioUrl from the video page controller are the original CDN URLs before BtrProxy.wrap). The extras map in pl_player _createVideoController is passed as per-file mpv options; add 'demuxer-lavf-probe-info': 'nostreams' only when not live, not FileSource and Pref.fastStart.
