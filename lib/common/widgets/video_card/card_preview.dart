import 'package:PiliPlus/common/widgets/video_card/swipe_preview.dart';
import 'package:PiliPlus/common/widgets/video_card/video_preview.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart';

/// Preview behaviour of one video card, shared by all cards: first long
/// press plays a preview in the cover, the next one runs the old long press
/// action; tap prefetches; swipe preview through [wrapTarget].
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

  bool get _on => canPreview && !suspended && VideoPreview.enabled;

  void prefetch() => VideoPreview.prefetch(aid: aid, bvid: bvid, cid: cid);

  /// For `InkWell.onTapDown`. Gets the playurl (and the BTR warm-up) early,
  /// even when the preview is off; `VideoPreview.prefetch` creates no preview
  /// player in that case.
  GestureTapDownCallback? get onTapDown =>
      canPreview && !suspended ? (_) => prefetch() : null;

  /// For `InkWell.onLongPress`: preview first, [second] when it plays.
  void longPress(VoidCallback second) =>
      _on && VideoPreview.active.value != item
      ? VideoPreview.start(item)
      : second();

  /// For `InkWell.onLongPress` of a card whose old action may be null.
  VoidCallback? longPressOr(VoidCallback? second) =>
      canPreview ? () => longPress(second ?? () {}) : second;

  /// Position of the preview of this card (null if it does not play), and
  /// stops it. Call it when the card opens the video.
  PreviewProgress? take() {
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
          child: child,
        )
      : child;
}
