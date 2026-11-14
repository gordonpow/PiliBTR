import 'package:PiliPlus/common/widgets/video_card/swipe_preview.dart';
import 'package:PiliPlus/services/open_timing.dart';
import 'package:PiliPlus/common/widgets/video_card/video_preview.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart';

/// Preview behaviour of one video card, shared by all cards: touching the
/// card plays a preview in the cover (through [wrapTarget]); long press stops
/// it and runs the old long press action; tap prefetches.
class CardPreview {
  const CardPreview({
    required this.item,
    required this.bvid,
    this.aid,
    this.cid,
    this.canPreview = true,
    this.suspended = false,
  });

  /// The key of the card (see [VideoPreview.active]).
  final Object item;
  final String bvid;
  final int? aid;
  final int? cid;

  /// False for cards that are not a normal video.
  final bool canPreview;

  /// True while the list is in multi-select or sort mode: no preview.
  final bool suspended;

  void prefetch() => VideoPreview.prefetch(aid: aid, bvid: bvid, cid: cid);

  /// For `InkWell.onTapDown`. Gets the playurl (and the BTR warm-up) early,
  /// even when the preview is off; `VideoPreview.prefetch` creates no preview
  /// player in that case.
  GestureTapDownCallback? get onTapDown =>
      canPreview && !suspended ? (_) => prefetch() : null;

  /// For `InkWell.onLongPress`: the preview already started on touch, so stop
  /// it and run the original long press action [second].
  void longPress(VoidCallback second) {
    VideoPreview.stop(item);
    second();
  }

  /// For `InkWell.onLongPress` of a card whose old action may be null.
  VoidCallback? longPressOr(VoidCallback? second) {
    if (!canPreview || second == null) return second;
    return () => longPress(second);
  }

  /// Position of the preview of this card (null if it does not play), and
  /// stops it. Call it when the card opens the video.
  PreviewProgress? take() {
    OpenTiming.markTap();
    final progress = VideoPreview.active.value == item
        ? VideoPreview.progressOf(bvid)
        : null;
    VideoPreview.stop(item);
    return progress;
  }

  /// The preview over the cover. Put it in a [Stack] of the cover.
  Widget overlay({BorderRadius? radius}) {
    if (!canPreview) return const SizedBox.shrink();
    return Positioned.fill(
      child: ValueListenableBuilder(
        valueListenable: VideoPreview.active,
        builder: (context, active, _) {
          if (active != item) return const SizedBox.shrink();
          final preview = InlineVideoPreview(
            item: item,
            aid: aid,
            bvid: bvid,
            cid: cid,
          );
          return radius == null
              ? preview
              : ClipRRect(borderRadius: radius, child: preview);
        },
      ),
    );
  }

  /// Makes the card a target of the swipe preview.
  Widget wrapTarget(Widget child) => canPreview
      ? SwipePreviewTarget(
          item: item,
          enabled: !suspended,
          onPrefetch: prefetch,
          prefetchKey: switch (cid) {
            final cid? when bvid.isNotEmpty => (bvid, cid),
            _ => null,
          },
          child: child,
        )
      : child;
}
