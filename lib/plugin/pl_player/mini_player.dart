import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:PiliPlus/common/widgets/compact_navigation_bar.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:PiliPlus/services/service_locator.dart';
import 'package:PiliPlus/utils/android/bindings.g.dart';
import 'package:PiliPlus/utils/extension/size_ext.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:PiliPlus/common/widgets/zh_flutter_material.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// In-app mini player, like YouTube: when the user leaves a video page with
/// back, the video keeps playing in a small window over the app.
///
/// The mini player keeps one reference on [PlPlayerController] (the
/// reference of the closed video page). Tap the window to open the video
/// page again; it continues from the current position. A new player page
/// takes the player over through [handOver].
abstract final class MiniPlayer {
  static OverlayEntry? _entry;
  static PlPlayerController? _ctr;
  static Map<String, dynamic>? _args;
  static String? _heroTag;

  /// Setting: open the mini player when the user leaves a playing video.
  static bool get enabled =>
      GStorage.setting.get(SettingBoxKey.miniPlayerOnBack, defaultValue: true);

  /// Setting: a diagonal swipe down (to the bottom left or bottom right) on
  /// the video shrinks it to the mini player.
  static bool get swipeEnabled =>
      GStorage.setting.get(SettingBoxKey.miniPlayerOnSwipe, defaultValue: true);

  /// Labels of the window sizes, in the order of the stored index.
  static const sizeLabels = ['小', '中', '大', '自訂'];

  /// Setting: window size, an index in [sizeLabels]. Default: medium.
  static int get sizeIndex => (GStorage.setting.get(
    SettingBoxKey.miniPlayerSize,
    defaultValue: 1,
  ) as int).clamp(0, sizeLabels.length - 1);

  /// Setting: window width (logical px) of the custom size, set by pinch.
  /// Null if the user never pinched the window.
  static double? get customWidth {
    final v = GStorage.setting.get(SettingBoxKey.miniPlayerCustomWidth);
    return v is num ? v.toDouble() : null;
  }

  static bool _swipeRequest = false;
  static Rect? _swipeFrom;
  static bool _swipeToLeft = false;

  /// Called by the swipe gesture before it pops the video page: the next
  /// pop opens the mini player, also when [enabled] is false. The window
  /// flies from [from] (the global rect of the video) to the bottom left
  /// corner if [toLeft], else to the bottom right corner.
  static void requestFromSwipe({Rect? from, bool toLeft = false}) {
    _swipeRequest = true;
    _swipeFrom = from;
    _swipeToLeft = toLeft;
    // Clear the request if no video page pops.
    Future.delayed(const Duration(seconds: 1), () {
      _swipeRequest = false;
      _swipeFrom = null;
    });
  }

  /// Returns true (once) if a swipe gesture asked for the mini player.
  static bool takeSwipeRequest() {
    final request = _swipeRequest;
    _swipeRequest = false;
    return request;
  }

  // Interactive swipe: a preview of the video follows the finger.
  static OverlayEntry? _dragEntry;
  static GlobalKey<_SwipePreviewState>? _dragKey;
  static VoidCallback? _onDragRemoved;
  static Timer? _dragTimer;

  /// Starts the drag of a diagonal swipe down. A preview of [video] shows
  /// at [from] (the global rect of the video) and follows the finger to the
  /// bottom left corner if [toLeft], else to the bottom right corner.
  /// [onRemoved] is called when the preview goes away. Returns false if
  /// the preview cannot show.
  static bool startSwipe({
    required VideoController video,
    required Rect from,
    required bool toLeft,
    VoidCallback? onRemoved,
  }) {
    final overlay = Get.key.currentState?.overlay;
    if (overlay == null) return false;
    _removeDragEntry();
    final key = _dragKey = GlobalKey<_SwipePreviewState>();
    _onDragRemoved = onRemoved;
    final entry = _dragEntry = OverlayEntry(
      builder: (_) =>
          _SwipePreview(key: key, video: video, from: from, toLeft: toLeft),
    );
    overlay.insert(entry);
    return true;
  }

  /// Moves the preview: [dy] is the distance of the finger down since the
  /// start of the swipe.
  static void updateSwipe(double dy) => _dragKey?.currentState?.drag(dy);

  /// Ends the swipe. If the preview went far enough (or the fling was fast
  /// enough), it flies to the corner and [onCommit] is called (it must pop
  /// the video page). Else the preview goes back and is removed.
  static void endSwipe(double velocityDy, {required VoidCallback onCommit}) {
    final state = _dragKey?.currentState;
    if (state == null) {
      _removeDragEntry();
      return;
    }
    if (state.end(velocityDy)) {
      requestFromSwipe(toLeft: state.widget.toLeft);
      onCommit();
      // Remove the preview if no mini player takes it over.
      _dragTimer?.cancel();
      _dragTimer = Timer(const Duration(seconds: 2), _removeDragEntry);
    }
  }

  static bool _poppingPlayerPages = false;

  /// True while [popPlayerPages] pops the pages. A player page below the
  /// swiped one must not load its own video into the shared player and
  /// must not open the mini player.
  static bool get poppingPlayerPages => _poppingPlayerPages;

  /// Called when a swipe commits: pops the swiped page and the player pages
  /// below it, down to the page that opened the first of them (for example
  /// home, search or history). The swiped video continues in the mini
  /// player. If the page cannot pop now, or it is the first page, do the
  /// usual pop.
  static void popPlayerPages(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route == null) {
      Navigator.maybePop(context);
      return;
    }
    popPlayerPagesOf(Navigator.of(context), route);
  }

  /// Same as [popPlayerPages], for a caller whose context can be gone
  /// (for example after it left fullscreen). [route] is the swiped page.
  static void popPlayerPagesOf(NavigatorState navigator, ModalRoute route) {
    if (route.isFirst ||
        route.popDisposition == RoutePopDisposition.doNotPop) {
      navigator.maybePop();
      return;
    }
    _poppingPlayerPages = true;
    try {
      navigator.popUntil(
        (r) => r.isFirst || !PlPlayerController.isVideoPage(r.settings.name),
      );
    } finally {
      _poppingPlayerPages = false;
    }
  }

  /// Cancels the swipe at once (for example, the player closed).
  static void cancelSwipe() => _removeDragEntry();

  static void _removeDragEntryOf(GlobalKey key) {
    if (_dragKey == key) _removeDragEntry();
  }

  static void _removeDragEntry() {
    _dragTimer?.cancel();
    _dragTimer = null;
    _dragKey = null;
    final entry = _dragEntry;
    _dragEntry = null;
    final onRemoved = _onDragRemoved;
    _onDragRemoved = null;
    if (entry != null) {
      if (entry.mounted) entry.remove();
      entry.dispose();
    }
    onRemoved?.call();
  }

  static bool get active => _entry != null;

  /// Hides the window for a while (for example under the video popup of
  /// the cache and download page), without closing it.
  static final hidden = false.obs;

  /// Shows the mini player for [ctr]. [args] are the arguments of the
  /// video page route. Returns false if it cannot show.
  static bool show({
    required PlPlayerController ctr,
    required Map args,
    required String heroTag,
    required bool wasPlaying,
  }) {
    final overlay = Get.key.currentState?.overlay;
    if (overlay == null || ctr.videoController == null) return false;
    close();
    _ctr = ctr;
    _args = Map<String, dynamic>.from(args);
    _heroTag = heroTag;
    // A swipe preview gives its place to the window: the window continues
    // from there.
    final from = _dragKey?.currentState?.rect ?? _swipeFrom;
    final toLeft = from != null && _swipeToLeft;
    _swipeFrom = null;
    _removeDragEntry();
    final entry = _entry = OverlayEntry(
      builder: (_) => _MiniPlayerView(ctr: ctr, from: from, toLeft: toLeft),
    );
    // Called from a page dispose, when the widget tree is locked: insert
    // after the current frame.
    scheduleMicrotask(() {
      if (_entry == entry) overlay.insert(entry);
    });
    if (wasPlaying) ctr.play(hideControls: false);
    if (kDebugMode) debugPrint('MiniPlayer: show $heroTag');
    return true;
  }

  static void _removeEntry() {
    final entry = _entry;
    _entry = null;
    if (entry == null) return;
    if (entry.mounted) entry.remove();
    entry.dispose();
  }

  /// Called when a new player page gets the player: the mini player closes
  /// and gives its reference to the new page.
  static void handOver() {
    if (!active) return;
    final ctr = _ctr!;
    _removeEntry();
    if (ctr.playerStatus.isPlaying) ctr.pause();
    // The new page can keep the open streams and their buffer.
    ctr.reuseNextSource = true;
    _release(ctr);
    _clear();
  }

  /// Closes the mini player and stops the video.
  static void close() {
    if (!active) return;
    final ctr = _ctr!;
    _removeEntry();
    _release(ctr);
    _clear();
  }

  static void _release(PlPlayerController ctr) {
    if (_heroTag case final tag?) {
      videoPlayerServiceHandler?.onVideoDetailDispose(tag);
    }
    PlPlayerController.updatePlayCount();
  }

  static void _clear() {
    _ctr = null;
    _args = null;
    _heroTag = null;
  }

  /// Opens the video page again at the current position.
  static void expand() {
    final ctr = _ctr;
    final args = _args;
    if (ctr == null || args == null) return;
    args['progress'] = ctr.positionInMilliseconds;
    // The new page calls [handOver] when it gets the player.
    Get.toNamed('/videoV', arguments: args, preventDuplicates: false);
  }
}

class _MiniPlayerView extends StatefulWidget {
  const _MiniPlayerView({
    required this.ctr,
    this.from,
    this.toLeft = false,
  });

  final PlPlayerController ctr;

  /// Global rect of the video when the window opens with a swipe.
  final Rect? from;

  /// Open at the bottom left corner (else bottom right).
  final bool toLeft;

  @override
  State<_MiniPlayerView> createState() => _MiniPlayerViewState();
}

class _MiniPlayerViewState extends State<_MiniPlayerView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const double _margin = 8;
  static const double _barHeight = 40;

  /// Width as a part of the shortest screen side, and the maximum width,
  /// for each size in [MiniPlayer.sizeLabels].
  static const _widthFactor = [0.42, 0.55, 0.8];
  static const _maxWidth = [260.0, 360.0, 520.0];

  late bool _playing = widget.ctr.playerStatus.isPlaying;

  /// Current place of the window (global). Null until the first layout.
  Rect? _rect;

  /// Corner of the window. The window keeps this corner when the screen
  /// changes (for example rotation).
  late bool _left = widget.toLeft;
  bool _top = false;

  /// Space for the bottom navigation bar of the main page. The bar can
  /// hide when the list scrolls: then the window goes down to the edge.
  static const double _barSpace = CompactNavigationBar.height;
  Worker? _barWorker;
  bool _dragging = false;

  /// Pinch state: size at the start of the gesture, and if a pinch happened.
  double _startWidth = 0;
  bool _pinched = false;
  double? _pinchWidth;

  /// True if this window paused the player when the app went to background.
  bool _pausedByLifecycle = false;

  double get _bottomGap {
    if (!Get.isRegistered<MainController>()) return _barSpace;
    final main = Get.find<MainController>();
    // No bottom bar in landscape (navigation rail) or with the side bar:
    // the window goes down to the screen edge. Same rule as the main page.
    if (main.useSideBar || !MediaQuery.sizeOf(context).isPortrait) return 0;
    if (!main.hideBottomBar) return _barSpace;
    if (main.showBottomBar case final show?) return show.value ? _barSpace : 0;
    if (main.barOffset case final offset?) {
      final hidden = (offset.value / Style.topBarHeight).clamp(0.0, 1.0);
      return _barSpace * (1 - hidden);
    }
    return _barSpace;
  }

  void _listenBar() {
    if (!Get.isRegistered<MainController>()) return;
    final main = Get.find<MainController>();
    if (!main.hideBottomBar) return;
    if (main.showBottomBar case final show?) {
      _barWorker = ever<bool>(show, (_) => _onBarChanged(animate: true));
    } else if (main.barOffset case final offset?) {
      _barWorker = ever<double>(offset, (_) => _onBarChanged(animate: false));
    }
  }

  /// The bottom bar moved: a window at a bottom corner moves with it.
  void _onBarChanged({required bool animate}) {
    if (!mounted || _top || _dragging || _opening || _rect == null) return;
    final media = MediaQuery.of(context);
    final target = _cornerRect(
      media,
      _rect!.size,
      _left,
      bottomGap: _bottomGap,
    );
    if (animate) {
      _animateTo(target, duration: const Duration(milliseconds: 400));
    } else {
      _anim.stop();
      setState(() => _rect = target);
    }
  }

  RectTween? _tween;
  late final AnimationController _anim;
  late final CurvedAnimation _curve;

  /// Without a swipe, opacity grows from 0 while the window opens. With a
  /// swipe, the video stays visible while it flies to the corner.
  late double _opacity = widget.from == null ? 0 : 1;
  late bool _opening = widget.from == null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.ctr.addStatusLister(_onStatus);
    _listenBar();
    _anim = AnimationController(vsync: this)..addListener(_onTick);
    _curve = CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    final size = _windowSize(media);
    if (_rect == null) {
      final target = _cornerRect(
        media,
        size,
        _left,
        top: _top,
        bottomGap: _bottomGap,
      );
      // Open with a swipe: fly from the video. Else grow from the corner.
      final from =
          widget.from ??
          Rect.fromCenter(
            center: target.center,
            width: target.width * 0.6,
            height: target.height * 0.6,
          );
      _rect = from;
      _animateTo(
        target,
        duration: Duration(milliseconds: widget.from != null ? 380 : 240),
      );
    } else {
      // The screen changed (for example rotation): same corner, new place.
      _anim.stop();
      if (_opening) {
        _opening = false;
        _opacity = 1;
      }
      _rect = _cornerRect(
        media,
        size,
        _left,
        top: _top,
        bottomGap: _bottomGap,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.ctr.removeStatusLister(_onStatus);
    _barWorker?.dispose();
    _curve.dispose();
    _anim.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (!widget.ctr.continuePlayInBackground.value &&
          !(Platform.isAndroid && AndroidHelper.isPipMode) &&
          widget.ctr.playerStatus.isPlaying) {
        _pausedByLifecycle = true;
        widget.ctr.pause();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_pausedByLifecycle) {
        _pausedByLifecycle = false;
        widget.ctr.play(hideControls: false);
      }
    }
  }

  void _onStatus(PlayerStatus status) {
    if (mounted) setState(() => _playing = status.isPlaying);
  }

  void _onTick() {
    final tween = _tween;
    if (tween == null) return;
    setState(() {
      _rect = tween.transform(_curve.value);
      if (_opening) {
        _opacity = _anim.value.clamp(0.0, 1.0);
        if (_anim.isCompleted) _opening = false;
      }
    });
  }

  void _animateTo(Rect target, {required Duration duration}) {
    _tween = RectTween(begin: _rect, end: target);
    _anim
      ..duration = duration
      ..forward(from: 0);
  }

  static Size _windowSize(MediaQueryData media) {
    final i = MiniPlayer.sizeIndex;
    final double width;
    if (i < _widthFactor.length) {
      width = math.min(
        media.size.shortestSide * _widthFactor[i],
        _maxWidth[i],
      );
    } else {
      // Custom size: the saved width, or the medium size if none.
      width =
          MiniPlayer.customWidth ??
          math.min(media.size.shortestSide * _widthFactor[1], _maxWidth[1]);
    }
    return _sizeForWidth(media, width);
  }

  /// Window size for [width], clamped to the allowed range (16:9 + bar).
  static Size _sizeForWidth(MediaQueryData media, double width) {
    final shortest = media.size.shortestSide;
    final minW = shortest * 0.30;
    final maxW = math.max(
      minW,
      math.min(
        shortest * 0.95,
        media.size.width -
            media.padding.left -
            media.padding.right -
            2 * _margin,
      ),
    );
    final w = width.clamp(minW, maxW);
    return Size(w, w * 9 / 16 + _barHeight);
  }

  static double _minTop(MediaQueryData media) => media.padding.top + _margin;

  static double _maxTop(MediaQueryData media, Size size) => math.max(
    _minTop(media),
    media.size.height - size.height - media.padding.bottom - _margin,
  );

  static double _leftX(MediaQueryData media) => media.padding.left + _margin;

  static double _rightX(MediaQueryData media, Size size) => math.max(
    _leftX(media),
    media.size.width - size.width - media.padding.right - _margin,
  );

  /// Place of a corner. A bottom corner stays [bottomGap] above the
  /// bottom edge (space for the navigation bar).
  static Rect _cornerRect(
    MediaQueryData media,
    Size size,
    bool left, {
    bool top = false,
    double bottomGap = _barSpace,
  }) {
    final x = left ? _leftX(media) : _rightX(media, size);
    final y = top
        ? _minTop(media)
        : math.max(_minTop(media), _maxTop(media, size) - bottomGap);
    return Offset(x, y) & size;
  }

  /// Place for [rect] after a drag: snap to the nearest corner (also use
  /// the fling [velocity]).
  Rect _snapRect(MediaQueryData media, Rect rect, Offset velocity) {
    final center = rect.center + velocity * 0.15;
    _left = center.dx < media.size.width / 2;
    _top = center.dy < media.size.height / 2;
    return _cornerRect(
      media,
      rect.size,
      _left,
      top: _top,
      bottomGap: _bottomGap,
    );
  }

  void _onScaleStart(ScaleStartDetails details) {
    _dragging = true;
    _pinched = false;
    _pinchWidth = null;
    _startWidth = _rect!.width;
    _anim.stop();
    if (_opening) {
      _opening = false;
      _opacity = 1;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final rect = _rect!;
    if (details.pointerCount < 2) {
      setState(() => _rect = rect.shift(details.focalPointDelta));
      return;
    }
    _pinched = true;
    final media = MediaQuery.of(context);
    final size = _sizeForWidth(media, _startWidth * details.scale);
    _pinchWidth = size.width;
    // Keep the focal point at the same relative place in the window.
    final focal = details.focalPoint;
    final fx = rect.width == 0 ? 0.5 : (focal.dx - rect.left) / rect.width;
    final fy = rect.height == 0 ? 0.5 : (focal.dy - rect.top) / rect.height;
    final origin = Offset(
      focal.dx - fx * size.width,
      focal.dy - fy * size.height,
    );
    setState(() => _rect = origin & size);
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _dragging = false;
    if (_pinched && _pinchWidth != null) {
      GStorage.setting
        ..put(SettingBoxKey.miniPlayerCustomWidth, _pinchWidth)
        ..put(SettingBoxKey.miniPlayerSize, 3);
    }
    _pinched = false;
    _pinchWidth = null;
    final media = MediaQuery.of(context);
    _animateTo(
      _snapRect(media, _rect!, details.velocity.pixelsPerSecond),
      duration: const Duration(milliseconds: 260),
    );
  }

  void _seekBy(int seconds) {
    final ms = widget.ctr.positionInMilliseconds + seconds * 1000;
    widget.ctr.seekTo(Duration(milliseconds: math.max(0, ms)));
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (MiniPlayer.hidden.value) return const SizedBox.shrink();
      return _build(context);
    });
  }

  Widget _build(BuildContext context) {
    final videoController = widget.ctr.videoController;
    if (videoController != null && widget.ctr.isPipMode) {
      // System picture-in-picture: the app window is the PiP window. Show
      // only the video, over the main page.
      return Positioned.fill(
        child: ColoredBox(
          color: Colors.black,
          child: FittedBox(
            fit: BoxFit.contain,
            child: SimpleVideo(controller: videoController),
          ),
        ),
      );
    }
    final rect = _rect;
    if (videoController == null || rect == null) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    // The control bar keeps its height; the video part scales.
    final barHeight = math.min(_barHeight, rect.height * 0.3);

    return Positioned.fromRect(
      rect: rect,
      child: Opacity(
        opacity: _opacity,
        child: GestureDetector(
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onScaleEnd: _onScaleEnd,
          onTap: MiniPlayer.expand,
          child: Material(
            elevation: 8,
            color: Colors.black,
            clipBehavior: Clip.antiAlias,
            borderRadius: BorderRadius.circular(10),
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      FittedBox(
                        fit: BoxFit.contain,
                        child: SimpleVideo(controller: videoController),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: IconButton(
                          tooltip: '關閉',
                          iconSize: 20,
                          color: Colors.white,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black38,
                          ),
                          icon: const Icon(Icons.close),
                          onPressed: MiniPlayer.close,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: barHeight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: IconTheme(
                      data: theme.iconTheme.copyWith(color: Colors.white),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '倒退 10 秒',
                            iconSize: 22,
                            color: Colors.white,
                            icon: const Icon(Icons.replay_10),
                            onPressed: () => _seekBy(-10),
                          ),
                          IconButton(
                            tooltip: _playing ? '暫停' : '播放',
                            iconSize: 26,
                            color: Colors.white,
                            icon: Icon(
                              _playing ? Icons.pause : Icons.play_arrow,
                            ),
                            onPressed: () => _playing
                                ? widget.ctr.pause()
                                : widget.ctr.play(hideControls: false),
                          ),
                          IconButton(
                            tooltip: '快轉 10 秒',
                            iconSize: 22,
                            color: Colors.white,
                            icon: const Icon(Icons.forward_10),
                            onPressed: () => _seekBy(10),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Preview of the video while the user swipes it down to the mini player.
/// It moves and shrinks with the finger, from the video place to a bottom
/// corner, and the page behind gets darker.
class _SwipePreview extends StatefulWidget {
  const _SwipePreview({
    super.key,
    required this.video,
    required this.from,
    required this.toLeft,
  });

  final VideoController video;

  /// Global rect of the video on the page.
  final Rect from;

  /// Go to the bottom left corner (else bottom right).
  final bool toLeft;

  @override
  State<_SwipePreview> createState() => _SwipePreviewState();
}

class _SwipePreviewState extends State<_SwipePreview>
    with SingleTickerProviderStateMixin {
  /// Part of the way to the corner: 0 at the video place, 1 at the corner.
  double _progress = 0;

  /// Opacity of the dark scrim: 1 while the page shows, 0 when it closes.
  double _scrim = 1;

  late Rect _target;

  /// Finger distance (down) for the full way to the corner.
  late double _travel;

  late final AnimationController _anim = AnimationController(vsync: this)
    ..addListener(_onTick)
    ..addStatusListener(_onStatus);
  double _progressFrom = 0, _progressTo = 0;
  double _scrimFrom = 1, _scrimTo = 1;
  bool _removeWhenDone = false;

  /// Current global rect of the preview.
  Rect get rect => Rect.lerp(widget.from, _target, _progress)!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    final size = _MiniPlayerViewState._windowSize(media);
    _target = _MiniPlayerViewState._cornerRect(media, size, widget.toLeft);
    _travel = math.max(150, _target.top - widget.from.top);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void drag(double dy) {
    if (_anim.isAnimating) _anim.stop();
    setState(() => _progress = (dy / _travel).clamp(0.0, 1.0));
  }

  /// Returns true if the swipe opens the mini player.
  bool end(double velocityDy) {
    // The faster the finger, the shorter the distance that is enough:
    // half the way when it stops, a small part for a fast fling.
    final speed = (velocityDy / 1500).clamp(0.0, 1.0);
    final threshold = 0.5 - 0.44 * speed;
    final commit = velocityDy > -300 && _progress >= threshold;
    // Continue at the speed of the finger: a slow swipe ends slowly.
    final remaining = (commit ? 1 - _progress : _progress) * _travel;
    final pxPerMs = velocityDy.abs() / 1000;
    final ms = pxPerMs > 0.2
        ? (remaining / pxPerMs).clamp(150.0, 450.0)
        : (commit ? 420.0 : 260.0);
    _animate(
      progress: commit ? 1 : 0,
      scrim: commit ? 0 : 1,
      duration: Duration(milliseconds: ms.round()),
      removeWhenDone: !commit,
    );
    return commit;
  }

  void _animate({
    required double progress,
    required double scrim,
    required Duration duration,
    required bool removeWhenDone,
  }) {
    _progressFrom = _progress;
    _progressTo = progress;
    _scrimFrom = _scrim;
    _scrimTo = scrim;
    _removeWhenDone = removeWhenDone;
    _anim
      ..duration = duration
      ..forward(from: 0);
  }

  void _onTick() {
    final t = Curves.easeOutCubic.transform(_anim.value);
    setState(() {
      _progress = _progressFrom + (_progressTo - _progressFrom) * t;
      _scrim = _scrimFrom + (_scrimTo - _scrimFrom) * t;
    });
  }

  void _onStatus(AnimationStatus status) {
    if (status.isCompleted && _removeWhenDone) {
      final key = widget.key;
      if (key is GlobalKey) MiniPlayer._removeDragEntryOf(key);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _progress;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: Colors.black.withValues(alpha: 0.45 * p * _scrim)),
          Positioned.fromRect(
            rect: rect,
            child: Material(
              elevation: 8 * p,
              color: Colors.black,
              clipBehavior: Clip.antiAlias,
              borderRadius: BorderRadius.circular(10 * p),
              child: FittedBox(
                fit: BoxFit.contain,
                child: SimpleVideo(controller: widget.video),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
