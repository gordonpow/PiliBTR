import 'package:flutter/gestures.dart'
    show
        GestureDisposition,
        GestureRecognizer,
        Offset,
        PointerDownEvent,
        PointerEvent,
        PointerMoveEvent,
        RecognizerCallback,
        ScaleGestureRecognizer;

mixin PlayerGestureMixin on GestureRecognizer {
  bool isPosAllowed = true;

  @override
  T? invokeCallback<T>(
    String name,
    RecognizerCallback<T> callback, {
    String Function()? debugReport,
  }) {
    if (!isPosAllowed) return null;
    return super.invokeCallback(name, callback, debugReport: debugReport);
  }
}

class PlayerScaleGestureRecognizer extends ScaleGestureRecognizer
    with PlayerGestureMixin {
  PlayerScaleGestureRecognizer({
    super.debugOwner,
    super.supportedDevices,
    super.allowedButtonsFilter,
    super.dragStartBehavior,
    super.trackpadScrollCausesScale,
    super.trackpadScrollToScaleFactor,
  });

  /// True when a diagonal swipe down may shrink the video into the mini
  /// window. The recognizer then claims such a drag early.
  bool Function()? canClaimMiniSwipe;

  /// A portrait video makes the video header taller than its pinned height,
  /// so the page's scroll view also tracks vertical drags and wins the
  /// gesture arena after 18 px, before the player (36 px) can decide; the
  /// swipe to the mini window then only scrolls the page. Claim a drag that
  /// goes diagonally down as soon as its direction is clear.
  static const double _claimDistance2 = 12 * 12;
  static const double _minSlope = 0.4;

  final Map<int, Offset> _downAt = {};

  @override
  void handleEvent(PointerEvent event) {
    super.handleEvent(event);
    if (event is PointerDownEvent) {
      _downAt[event.pointer] = event.position;
    } else if (event is PointerMoveEvent) {
      final start = _downAt[event.pointer];
      if (start == null || _downAt.length != 1) return;
      final d = event.position - start;
      if (d.dy <= 0 || d.distanceSquared < _claimDistance2) return;
      final dx = d.dx.abs();
      if (dx > d.dy * _minSlope &&
          d.dy > dx * _minSlope &&
          (canClaimMiniSwipe?.call() ?? false)) {
        _downAt.remove(event.pointer);
        resolve(GestureDisposition.accepted);
      }
    } else {
      _downAt.remove(event.pointer);
    }
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _downAt[event.pointer] = event.position;
    super.addAllowedPointer(event);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _downAt.clear();
    super.didStopTrackingLastPointer(pointer);
  }
}
