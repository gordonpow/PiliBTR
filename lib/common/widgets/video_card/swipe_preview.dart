import 'package:PiliPlus/common/widgets/video_card/video_preview.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart';
import 'package:PiliPlus/utils/visible_prefetch.dart';
import 'package:flutter/gestures.dart';

/// A video card that plays a preview as soon as a finger touches it. It
/// registers itself so [SwipePreviewDetector] can find the card under the
/// finger.
class SwipePreviewTarget extends StatefulWidget {
  const SwipePreviewTarget({
    super.key,
    required this.item,
    required this.onPrefetch,
    required this.child,
    this.enabled = true,
    this.prefetchKey,
  });

  /// Bvid and cid for [VisiblePrefetch] while the card is on screen; null
  /// for cards without a cid (they prefetch only on touch).
  final (String, int)? prefetchKey;

  /// False while the list cannot preview (multi-select, sort mode).
  final bool enabled;

  /// The item given to [VideoPreview.start].
  final Object item;

  /// Gets the preview streams early.
  final VoidCallback onPrefetch;
  final Widget child;

  @override
  State<SwipePreviewTarget> createState() => _SwipePreviewTargetState();
}

class _SwipePreviewTargetState extends State<SwipePreviewTarget>
    implements VisibleCard {
  /// The nearest detector above this card, if any.
  _SwipePreviewDetectorState? _detector;

  /// The list of this card: its scrolling state starts [VisiblePrefetch].
  ScrollPosition? _position;

  @override
  void initState() {
    super.initState();
    _detector = context.findAncestorStateOfType<_SwipePreviewDetectorState>();
    _detector?._targets.add(this);
    VisiblePrefetch.add(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Depend on the route and the tab: when the page comes back on top or
    // the tab shows again, collect the visible cards again.
    ModalRoute.of(context);
    TickerMode.valuesOf(context);
    final position = Scrollable.maybeOf(context)?.position;
    if (!identical(position, _position)) {
      _position?.isScrollingNotifier.removeListener(_onScrolling);
      _position = position;
      position?.isScrollingNotifier.addListener(_onScrolling);
    }
    VisiblePrefetch.schedule();
  }

  void _onScrolling() {
    final position = _position;
    if (position == null) return;
    VisiblePrefetch.onScrolling(
      position,
      position.isScrollingNotifier.value,
    );
  }

  @override
  (String, int)? get prefetchKey => widget.enabled ? widget.prefetchKey : null;

  @override
  Rect? get visibleRect {
    if (!mounted) return null;
    if (ModalRoute.of(context)?.isCurrent == false) return null;
    if (!TickerMode.valuesOf(context).enabled) return null;
    return _globalRect;
  }

  @override
  void dispose() {
    _position?.isScrollingNotifier.removeListener(_onScrolling);
    _position = null;
    VisiblePrefetch.remove(this);
    _detector?._targets.remove(this);
    _detector = null;
    super.dispose();
  }

  Rect? get _globalRect {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Starts the preview of this card, unless it cannot preview now or it
  /// already plays.
  void _startPreview() {
    if (!mounted || !widget.enabled || !VideoPreview.enabled) return;
    // A page on top of this one, or a hidden tab: do nothing.
    if (ModalRoute.of(context)?.isCurrent == false) return;
    if (!TickerMode.valuesOf(context).enabled) return;
    final item = widget.item;
    if (VideoPreview.active.value == item) return;
    widget.onPrefetch();
    VideoPreview.start(item);
  }

  void _onPointerDown(PointerDownEvent e) {
    // Only a touch or the primary mouse button.
    if (e.kind != PointerDeviceKind.touch &&
        (e.buttons & kPrimaryButton) == 0) {
      return;
    }
    _startPreview();
  }

  /// A [Listener] takes no part in the gesture arena, so taps, long presses
  /// and scrolling of the card and its parents are not affected.
  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _onPointerDown,
    child: widget.child,
  );
}

/// Moves the preview with the finger: while the finger moves over the cards,
/// the card under it plays. A card also starts on touch by itself
/// ([SwipePreviewTarget]), so this detector only handles the movement.
class SwipePreviewDetector extends StatefulWidget {
  const SwipePreviewDetector({super.key, required this.child});

  final Widget child;

  @override
  State<SwipePreviewDetector> createState() => _SwipePreviewDetectorState();
}

class _SwipePreviewDetectorState extends State<SwipePreviewDetector> {
  /// Squared distance the finger must move before it counts as a swipe
  /// (a still finger is a tap or a long press).
  static const double _slop2 = 18 * 18;

  /// The cards below this detector (not a global list: another page under
  /// this one must not be hit).
  final Set<_SwipePreviewTargetState> _targets = {};

  int? _pointer;
  Offset _down = Offset.zero;
  bool _swiping = false;

  /// The card the preview was last started for (by touch or by movement).
  _SwipePreviewTargetState? _lastHit;

  bool get _active => VideoPreview.enabled;

  _SwipePreviewTargetState? _targetAt(Offset position) {
    for (final t in _targets) {
      if (!t.widget.enabled) continue;
      if (t._globalRect?.contains(position) ?? false) return t;
    }
    return null;
  }

  void _onDown(PointerDownEvent e) {
    if (_pointer != null) return;
    _pointer = e.pointer;
    _down = e.position;
    _swiping = false;
    // The card under the finger starts by itself on touch.
    _lastHit = _targetAt(e.position);
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    if (!_swiping) {
      final delta = e.position - _down;
      if (delta.distanceSquared < _slop2 || !_active) return;
      // Only a vertical swipe scrolls the list. A horizontal swipe changes
      // the home tab: stop the preview that started on touch.
      if (delta.dx.abs() >= delta.dy.abs()) {
        _pointer = null;
        _lastHit = null;
        VideoPreview.stop();
        return;
      }
      _swiping = true;
    }
    _previewUnderFinger(e.position);
  }

  void _onEnd(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _swiping = false;
    _lastHit = null;
  }

  /// Previews the card under the finger when it changed.
  void _previewUnderFinger(Offset position) {
    if (!mounted) return;
    final t = _targetAt(position);
    if (t == null || identical(t, _lastHit)) return;
    _lastHit = t;
    t._startPreview();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _onDown,
    onPointerMove: _onMove,
    onPointerUp: _onEnd,
    onPointerCancel: _onEnd,
    child: widget.child,
  );
}
