Project: Flutter app at C:\presonal_project\bilibili_bata\PiliPlus (Android first). Read docs/work/touch-preview-open-time/1-requirements.md and docs/work/touch-preview-open-time/2-spec.md first; the spec is the source of truth (its 審查紀錄 table explains decisions).

Rules:
- Comments and UI text in Traditional Chinese (Taiwan) or English; never Simplified Chinese (except existing string constants compared with server text).
- Do not commit, do not run git commands that change state. Do not run `dart format` on the whole lib folder; if you format, only format the files you changed.
- Another implementer edits other files in parallel: only change the files listed for your task.
- Check with: C:/src/flutter/bin/flutter analyze <the files you changed> (use exactly this flutter path; C:\flutter is wrong). Fix all new issues.
- When done, reply in Traditional Chinese (under 300 words): files changed, what you did per spec item, analyze result, and any spec deviation with reason.

Your task: T-1 (spec section "A. 碰到即預覽", items 1, 2, 3, 3a, 4).
Files you may change:
- lib/common/widgets/video_card/swipe_preview.dart
- lib/common/widgets/video_card/card_preview.dart
- lib/common/widgets/video_card/video_preview.dart (only item 3a: clear _progress in start)
- lib/pages/setting/models/recommend_settings.dart
- lib/pages/setting/models/setting_tree.dart (only titles for the renamed/removed switches)
- lib/utils/storage_key.dart only if the unused videoPreviewOnSwipe constant causes an analyze issue (otherwise leave it)
Search the whole lib/ for the old setting titles 「長按影片預覽」「滑動時預覽」 and for SwipePreviewDetector.enabled usages; update every reference.
Notes: SwipePreviewTarget.build must wrap child in Listener(behavior: HitTestBehavior.translucent, onPointerDown: ...). Pointer-down start needs the same checks as the old _onRest (route isCurrent, TickerMode enabled, widget.enabled, VideoPreview.enabled, active != item). Only primary button / touch.
