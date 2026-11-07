import 'dart:async';

import 'package:PiliPlus/common/widgets/video_card/video_preview.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart';

/// A video card that can play a preview when the finger rests on it after
/// a swipe. It registers itself so [SwipePreviewDetector] can find the
/// card under the finger.
class SwipePreviewTarget extends StatefulWidget {
  const SwipePreviewTarget({
    super.key,
    required this.item,
    required this.onPrefetch,
    required this.child,
    this.enabled = true,
  });

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

class _SwipePreviewTargetState extends State<SwipePreviewTarget> {
  /// The nearest detector above this card, if any.
  _SwipePreviewDetectorState? _detector;

  @override
  void initState() {
    super.initState();
    _detector = context.findAncestorStateOfType<_SwipePreviewDetectorState>();
    _detector?._targets.add(this);
  }

  @override
  void dispose() {
    _detector?._targets.remove(this);
    _detector = null;
    super.dispose();
  }

  Rect? get _globalRect {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Plays a preview of the card under the finger after a swipe, so the user
/// does not have to long press. The preview starts only when the finger
/// rests: while the finger keeps moving (scrolling), no player starts, so
/// the scroll stays smooth.
class SwipePreviewDetector extends StatefulWidget {
  const SwipePreviewDetector({super.key, required this.child});

  final Widget child;

  /// Setting: preview on swipe (on by default).
  static bool get enabled => GStorage.setting.get(
    SettingBoxKey.videoPreviewOnSwipe,
    defaultValue: true,
  );

  @override
  State<SwipePreviewDetector> createState() => _SwipePreviewDetectorState();
}

class _SwipePreviewDetectorState extends State<SwipePreviewDetector> {
  static const _dwell = Duration(milliseconds: 250);

  /// The finger counts as resting while it stays this close to the point
  /// where the dwell timer started.
  static const double _still2 = 12 * 12;

  /// Squared distance the finger must move before it counts as a swipe
  /// (a still finger is a tap or a long press).
  static const double _slop2 = 18 * 18;

  /// The cards below this detector (not a global list: another page under
  /// this one must not be hit).
  final Set<_SwipePreviewTargetState> _targets = {};

  int? _pointer;
  Offset _down = Offset.zero;
  Offset _position = Offset.zero;
  bool _swiping = false;

  /// Where the finger was when the dwell timer started.
  Offset _anchor = Offset.zero;
  Timer? _timer;

  bool get _active => VideoPreview.enabled && SwipePreviewDetector.enabled;

  void _onDown(PointerDownEvent e) {
    if (_pointer != null) return;
    _pointer = e.pointer;
    _down = _position = e.position;
    _swiping = false;
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    _position = e.position;
    if (!_swiping) {
      final delta = _position - _down;
      if (delta.distanceSquared < _slop2 || !_active) return;
      // Only a vertical swipe scrolls the list. A horizontal swipe changes
      // the home tab: it must not start a preview.
      if (delta.dx.abs() >= delta.dy.abs()) {
        _pointer = null;
        return;
      }
      _swiping = true;
      _restart();
      return;
    }
    // The finger moved on: wait until it rests again.
    if ((_position - _anchor).distanceSquared > _still2) _restart();
  }

  void _restart() {
    _anchor = _position;
    _timer?.cancel();
    _timer = Timer(_dwell, _onRest);
  }

  void _onEnd(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _swiping = false;
    _timer?.cancel();
  }

  /// The finger rested for [_dwell]: preview the card under it.
  void _onRest() {
    if (!_swiping || !mounted) return;
    // A page on top of this one, or a hidden tab: do nothing.
    if (ModalRoute.of(context)?.isCurrent == false) return;
    if (!TickerMode.valuesOf(context).enabled) return;
    for (final t in _targets) {
      if (!t.widget.enabled) continue;
      if (t._globalRect?.contains(_position) ?? false) {
        final item = t.widget.item;
        if (VideoPreview.active.value != item) {
          t.widget.onPrefetch();
          VideoPreview.start(item);
        }
        return;
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
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
