import 'dart:async';

import 'package:PiliPlus/common/widgets/video_card/video_preview.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:material_ui/material_ui.dart';

/// A video card that can play a preview when the finger scrolls over it.
/// It registers itself so [SwipePreviewDetector] can find the card under
/// the finger.
class SwipePreviewTarget extends StatefulWidget {
  const SwipePreviewTarget({
    super.key,
    required this.item,
    required this.onPrefetch,
    required this.child,
  });

  /// The item given to [VideoPreview.start].
  final Object item;

  /// Gets the preview streams early.
  final VoidCallback onPrefetch;
  final Widget child;

  @override
  State<SwipePreviewTarget> createState() => _SwipePreviewTargetState();
}

class _SwipePreviewTargetState extends State<SwipePreviewTarget> {
  @override
  void initState() {
    super.initState();
    SwipePreviewDetector._targets.add(this);
  }

  @override
  void dispose() {
    SwipePreviewDetector._targets.remove(this);
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

/// Plays a preview of the card under the finger while the finger scrolls
/// the list, so the user does not have to long press. The card must stay
/// under the finger for [_dwell] first: cards that pass quickly do not
/// start a player.
class SwipePreviewDetector extends StatefulWidget {
  const SwipePreviewDetector({super.key, required this.child});

  final Widget child;

  /// Setting: preview on swipe (on by default).
  static bool get enabled => GStorage.setting.get(
    SettingBoxKey.videoPreviewOnSwipe,
    defaultValue: true,
  );

  static final Set<_SwipePreviewTargetState> _targets = {};

  @override
  State<SwipePreviewDetector> createState() => _SwipePreviewDetectorState();
}

class _SwipePreviewDetectorState extends State<SwipePreviewDetector> {
  static const _dwell = Duration(milliseconds: 250);

  /// Squared distance the finger must move before it counts as a swipe
  /// (a still finger is a tap or a long press).
  static const double _slop2 = 18 * 18;

  int? _pointer;
  Offset _down = Offset.zero;
  Offset _position = Offset.zero;
  bool _swiping = false;
  Object? _candidate;
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
      if ((_position - _down).distanceSquared < _slop2 || !_active) return;
      _swiping = true;
    }
    _check();
  }

  void _onEnd(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _swiping = false;
    _candidate = null;
    _timer?.cancel();
  }

  /// Finds the card under the finger and starts the dwell timer when it
  /// changes.
  void _check() {
    _SwipePreviewTargetState? hit;
    for (final t in SwipePreviewDetector._targets) {
      if (t._globalRect?.contains(_position) ?? false) {
        hit = t;
        break;
      }
    }
    final item = hit?.widget.item;
    if (item == _candidate) return;
    _candidate = item;
    _timer?.cancel();
    if (hit == null || item == null || VideoPreview.active.value == item) {
      return;
    }
    hit.widget.onPrefetch();
    _timer = Timer(_dwell, () {
      if (_swiping && _candidate == item) VideoPreview.start(item);
    });
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
