import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:io' show File, Platform;

import 'package:PiliPlus/common/widgets/progress_bar/audio_video_progress_bar.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/mini_player.dart';
import 'package:PiliPlus/plugin/pl_player/models/duration.dart';
import 'package:PiliPlus/plugin/pl_player/utils/fullscreen.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';

/// 以彈窗播放本機影片（可附帶外部音訊檔）。
Future<void> showVideoPopup(
  BuildContext context, {
  required String videoPath,
  String? audioPath,
  required String title,
}) async {
  // 先暫停 App 主播放器
  PlPlayerController.pauseIfExists();
  // The mini player window would cover the popup.
  MiniPlayer.hidden.value = true;
  try {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      // Fullscreen also covers the display cutout; the header and the
      // controls keep their own SafeArea.
      useSafeArea: false,
      builder: (_) => _VideoPopup(
        videoPath: videoPath,
        audioPath: audioPath,
        title: title,
      ),
    );
  } finally {
    MiniPlayer.hidden.value = false;
  }
}

/// Direction of a one finger drag on the fullscreen video.
enum _DragType { horizontal, brightness, volume }

class _VideoPopup extends StatefulWidget {
  const _VideoPopup({
    required this.videoPath,
    required this.audioPath,
    required this.title,
  });

  final String videoPath;
  final String? audioPath;
  final String title;

  @override
  State<_VideoPopup> createState() => _VideoPopupState();
}

class _VideoPopupState extends State<_VideoPopup> {
  Player? _player;
  VideoController? _videoController;
  final List<StreamSubscription<dynamic>> _subs = [];

  bool _error = false;
  bool _playing = false;
  bool _fullscreen = false;
  bool _disposed = false;

  /// Controls in fullscreen: a tap on the video shows or hides them.
  bool _showControls = true;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  /// Seconds under the thumb while the user drags the progress bar.
  int? _dragSeconds;

  // Fullscreen gestures (same rules as the main player view).
  double _maxWidth = 0;
  double _maxHeight = 0;
  double _doubleTapDx = 0;
  _DragType? _dragType;
  Offset _dragStart = Offset.zero;

  /// Target position (ms) while the user drags horizontally.
  int? _seekMs;

  /// Brightness or volume (0..1) while the user drags vertically.
  double? _level;
  bool _brightnessChanged = false;
  DateTime _lastVolumeSet = DateTime.fromMillisecondsSinceEpoch(0);

  /// Brightness or volume indicator.
  ({IconData icon, String text})? _osd;
  Timer? _osdTimer;

  /// Double tap seek hint in seconds: negative is backward.
  int? _seekHint;
  Timer? _seekHintTimer;

  /// Speed while a long press is active, and the speed to go back to.
  double? _longPressRate;
  double _rateBeforeLongPress = 1.0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (!File(widget.videoPath).existsSync() ||
        (widget.audioPath != null && !File(widget.audioPath!).existsSync())) {
      setState(() => _error = true);
      return;
    }
    try {
      // Same output settings as the main player. With the media_kit
      // defaults, Android attaches the surface only after the first video
      // parameters, and a local file then stays black at 00:00.
      final player = await Player.create(
        configuration: PlayerConfiguration(
          logLevel: .error,
          options: {
            if (Platform.isAndroid) 'ao': Pref.audioOutput,
          },
        ),
      );
      final hwdec = Pref.enableHA ? Pref.hardwareDecoding : null;
      final VideoController controller;
      try {
        controller = await VideoController.create(
          player,
          configuration: VideoControllerConfiguration(
            enableHardwareAcceleration: hwdec != null,
            androidAttachSurfaceAfterVideoParameters: false,
            hwdec: hwdec,
          ),
        );
      } catch (_) {
        player.dispose();
        rethrow;
      }
      if (!mounted || _disposed) {
        player.dispose();
        return;
      }
      if (Platform.isAndroid) {
        player.setProperty('force-window', 'no');
      }
      _player = player;
      _videoController = controller;
      _subs.addAll([
        // Playing: an earlier error was one mpv recovered from.
        player.stream.position.listen((e) {
          if (mounted) {
            setState(() {
              _position = e;
              if (e > Duration.zero) _error = false;
            });
          }
        }),
        player.stream.duration.listen((e) {
          if (mounted) {
            setState(() {
              _duration = e;
              if (e > Duration.zero) _error = false;
            });
          }
        }),
        player.stream.playing.listen((e) {
          if (mounted) setState(() => _playing = e);
        }),
        // mpv also reports errors it recovers from (for example a failed
        // hardware decoder): only a file that never opened is an error.
        player.stream.error.listen((_) {
          if (mounted && _duration == Duration.zero) {
            setState(() => _error = true);
          }
        }),
      ]);
      setState(() {});
      // Video and external audio as one EDL source, like the main player
      // (lengths in UTF-8 bytes: the path can have Chinese characters).
      String edlPart(String path) => '%${utf8.encode(path).length}%$path';
      final media = switch (widget.audioPath) {
        final audio? =>
          'edl://!no_chapters;${edlPart(widget.videoPath)};'
              '!new_stream;!no_chapters;${edlPart(audio)}',
        null => widget.videoPath,
      };
      await player.open(Media(media), play: false);
      if (mounted && !_disposed) await player.play();
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final s in _subs) {
      s.cancel();
    }
    _osdTimer?.cancel();
    _seekHintTimer?.cancel();
    _player?.dispose();
    _resetBrightness();
    if (_fullscreen) _restoreScreen();
    super.dispose();
  }

  /// Back to the orientation and system bars of the app (as the main
  /// player does when it leaves fullscreen).
  void _restoreScreen() {
    showSystemBar();
    if (Pref.horizontalScreen) {
      fullMode();
    } else {
      portraitUpMode();
    }
  }

  /// Gives the brightness back to the system, as the main player does
  /// when it leaves (only the application brightness; Android).
  void _resetBrightness() {
    if (!_brightnessChanged) return;
    _brightnessChanged = false;
    if (Platform.isAndroid && !Pref.setSystemBrightness) {
      ScreenBrightnessPlatform.instance
          .resetApplicationScreenBrightness()
          .catchError((_) {});
    }
  }

  void _toggleFullscreen() {
    _endLongPress();
    _dragType = null;
    _seekMs = null;
    if (_fullscreen) _resetBrightness();
    setState(() {
      _fullscreen = !_fullscreen;
      _showControls = true;
      _osd = null;
      _seekHint = null;
    });
    if (_fullscreen) {
      hideSystemBar();
      // A portrait video stays portrait; otherwise turn to landscape.
      final state = _player?.state;
      if (state != null && state.height > state.width) {
        portraitUpMode();
      } else {
        landscapeLeftMode();
      }
    } else {
      _restoreScreen();
    }
  }

  static String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = two(d.inMinutes.remainder(60));
    final s = two(d.inSeconds.remainder(60));
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  void _onVideoTap() {
    if (_fullscreen) {
      setState(() => _showControls = !_showControls);
    } else {
      _player?.playOrPause();
    }
  }

  bool get _isCompleted {
    final state = _player!.state;
    return state.completed ||
        (state.duration - state.position).inMilliseconds <= 50;
  }

  Future<void> _onDoubleTapCenter() async {
    final player = _player;
    if (player == null) return;
    if (_isCompleted) {
      await player.seek(Duration.zero);
      player.play();
    } else {
      player.playOrPause();
    }
  }

  void _onDoubleTap() {
    final player = _player;
    if (player == null) return;
    if (!Pref.enableQuickDouble) {
      _onDoubleTapCenter();
      return;
    }
    final section = _maxWidth / 4;
    if (_doubleTapDx >= section && _doubleTapDx < section * 3) {
      _onDoubleTapCenter();
      return;
    }
    final seconds = Pref.fastForBackwardDuration;
    final forward = _doubleTapDx >= section * 3;
    final state = player.state;
    final target =
        state.position + Duration(seconds: forward ? seconds : -seconds);
    final to = target.clamp(Duration.zero, state.duration);
    player.seek(to).whenComplete(player.play);
    _seekHintTimer?.cancel();
    setState(() {
      _seekHint = forward ? seconds : -seconds;
      _position = to;
    });
    _seekHintTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _seekHint = null);
    });
  }

  void _showOsd(IconData icon, double value) {
    _osdTimer?.cancel();
    setState(() => _osd = (icon: icon, text: '${(value * 100).round()}%'));
    _osdTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _osd = null);
    });
  }

  void _onScaleStart(ScaleStartDetails details) {
    _dragType = null;
    _dragStart = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final player = _player;
    if (player == null || details.pointerCount > 1) return;
    if (_dragType == null) {
      final delta = details.localFocalPoint - _dragStart;
      if (delta.distanceSquared < 1) return;
      final dx = delta.dx.abs();
      final dy = delta.dy.abs();
      if (dx > 3 * dy) {
        if (_duration <= Duration.zero) return;
        _dragType = _DragType.horizontal;
        _seekMs = player.state.position.inMilliseconds;
      } else if (dy > 3 * dx) {
        if (!Pref.enableSlideVolumeBrightness) return;
        // The center zone has its own width (setting); the left and right
        // zones share the rest. Vertical drag in the center does nothing.
        final centerWidth = _maxWidth * Pref.fullscreenCenterRatio;
        final section = (_maxWidth - centerWidth) / 2;
        final x = details.localFocalPoint.dx;
        if (x >= section && x < section + centerWidth) return;
        _level = null;
        if (PlatformUtils.isDesktop) {
          _dragType = _DragType.volume;
          _level = player.state.volume / 100;
        } else if (x < section) {
          _dragType = _DragType.brightness;
          final brightness = Platform.isIOS || Pref.setSystemBrightness
              ? ScreenBrightnessPlatform.instance.system
              : ScreenBrightnessPlatform.instance.application;
          brightness
              .then((v) {
                if (_dragType == _DragType.brightness) _level ??= v;
              })
              .catchError((_) {});
        } else {
          _dragType = _DragType.volume;
          FlutterVolumeController.getVolume()
              .then((v) {
                if (_dragType == _DragType.volume && v != null) _level ??= v;
              })
              .catchError((_) {});
        }
      }
      return;
    }
    final delta = details.focalPointDelta;
    switch (_dragType!) {
      case _DragType.horizontal:
        final total = _duration.inMilliseconds;
        final scale = Pref.useRelativeSlide
            ? total * (Pref.sliderDuration / 100)
            : Pref.sliderDuration * 1000;
        final posDelta = (scale * delta.dx / _maxWidth).round();
        setState(() {
          _seekMs = ((_seekMs ?? 0) + posDelta).clamp(0, total);
        });
      case _DragType.brightness:
        final level = _level;
        if (level == null) return;
        final value = (level - delta.dy / (_maxHeight * 3)).clamp(0.0, 1.0);
        _level = value;
        _setBrightness(value);
        _showOsd(
          value < 1 / 3
              ? Icons.brightness_low
              : value < 2 / 3
              ? Icons.brightness_medium
              : Icons.brightness_high,
          value,
        );
      case _DragType.volume:
        final level = _level;
        if (level == null) return;
        final maxVolume = PlatformUtils.isDesktop ? Pref.maxVolume : 1.0;
        final value = clampDouble(
          level - delta.dy / (_maxHeight * 0.5),
          0.0,
          maxVolume,
        );
        _level = value;
        _setVolume(value);
        _showOsd(
          value == 0
              ? Icons.volume_off
              : value < 0.5
              ? Icons.volume_down
              : Icons.volume_up,
          value,
        );
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_dragType == _DragType.horizontal) {
      final ms = _seekMs;
      if (ms != null) {
        final to = Duration(milliseconds: ms);
        _player?.seek(to);
        setState(() {
          _position = to;
          _seekMs = null;
        });
      }
    }
    _dragType = null;
    _level = null;
  }

  Future<void> _setBrightness(double value) async {
    _brightnessChanged = true;
    try {
      if (Platform.isIOS || Pref.setSystemBrightness) {
        await ScreenBrightnessPlatform.instance.setSystemScreenBrightness(
          value,
        );
      } else {
        await ScreenBrightnessPlatform.instance.setApplicationScreenBrightness(
          value,
        );
      }
    } catch (_) {}
  }

  Future<void> _setVolume(double value) async {
    // Same throttle as the main player view.
    final now = DateTime.now();
    if (now.difference(_lastVolumeSet).inMilliseconds < 20) return;
    _lastVolumeSet = now;
    try {
      if (PlatformUtils.isDesktop) {
        await _player?.setVolume(value * 100);
      } else {
        FlutterVolumeController.updateShowSystemUI(false);
        await FlutterVolumeController.setVolume(value);
      }
    } catch (_) {}
  }

  void _onLongPressStart(LongPressStartDetails details) {
    final player = _player;
    if (player == null || !_playing || _longPressRate != null) return;
    HapticFeedback.lightImpact();
    _rateBeforeLongPress = player.state.rate;
    final rate = Pref.enableAutoLongPressSpeed
        ? _rateBeforeLongPress * 2
        : Pref.longPressSpeedDefault;
    player.setRate(rate);
    setState(() => _longPressRate = rate);
  }

  void _endLongPress() {
    if (_longPressRate == null) return;
    _longPressRate = null;
    _player?.setRate(_rateBeforeLongPress);
    if (mounted) setState(() {});
  }

  Widget _label(Widget child) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: DefaultTextStyle.merge(
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
          child: IconTheme.merge(
            data: const IconThemeData(color: Colors.white, size: 20),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _iconText(IconData icon, String text) {
    return _label(
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon), const SizedBox(width: 6), Text(text)],
      ),
    );
  }

  static String _fmtRate(double rate) {
    return rate.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  /// Hints on top of the fullscreen video.
  List<Widget> _buildGestureHints() {
    final seekMs = _seekMs;
    final hint = _seekHint;
    final osd = _osd;
    final rate = _longPressRate;
    return [
      if (seekMs != null)
        Center(
          child: _label(
            Text(
              '${_fmt(Duration(milliseconds: seekMs))} / ${_fmt(_duration)}',
            ),
          ),
        ),
      if (osd != null) Center(child: _iconText(osd.icon, osd.text)),
      if (hint != null)
        Align(
          alignment: hint < 0 ? Alignment.centerLeft : Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: _iconText(
              hint < 0 ? Icons.fast_rewind : Icons.fast_forward,
              '${hint < 0 ? '快退' : '快進'} ${hint.abs()} 秒',
            ),
          ),
        ),
      if (rate != null)
        Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 56),
            child: _iconText(Icons.fast_forward, '${_fmtRate(rate)}倍速中'),
          ),
        ),
    ];
  }

  Widget _buildVideo() {
    final Widget child;
    if (_error) {
      child = const Center(
        child: Text(
          '無法播放這個檔案',
          style: TextStyle(color: Colors.white),
        ),
      );
    } else if (_videoController == null) {
      child = const Center(child: CircularProgressIndicator());
    } else {
      final fs = _fullscreen;
      child = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onVideoTap,
        onDoubleTapDown: fs ? (d) => _doubleTapDx = d.localPosition.dx : null,
        onDoubleTap: fs ? _onDoubleTap : null,
        onScaleStart: fs ? _onScaleStart : null,
        onScaleUpdate: fs ? _onScaleUpdate : null,
        onScaleEnd: fs ? _onScaleEnd : null,
        onLongPressStart: fs ? _onLongPressStart : null,
        onLongPressEnd: fs ? (_) => _endLongPress() : null,
        onLongPressCancel: fs ? _endLongPress : null,
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            // Same as the mini player: the video keeps its aspect ratio.
            FittedBox(
              fit: BoxFit.contain,
              child: SimpleVideo(controller: _videoController!),
            ),
            if (!_playing)
              Center(
                child: IconButton(
                  tooltip: '播放',
                  iconSize: 64,
                  color: Colors.white70,
                  icon: const Icon(Icons.play_circle_outline),
                  onPressed: () => _player?.play(),
                ),
              ),
            if (fs) IgnorePointer(child: Stack(children: _buildGestureHints())),
          ],
        ),
      );
    }
    return ColoredBox(
      color: Colors.black,
      child: _fullscreen
          ? LayoutBuilder(
              builder: (context, constraints) {
                _maxWidth = constraints.maxWidth;
                _maxHeight = constraints.maxHeight;
                return child;
              },
            )
          : child,
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        if (_fullscreen)
          IconButton(
            tooltip: '結束全螢幕',
            color: Colors.white,
            icon: const Icon(Icons.arrow_back),
            onPressed: _toggleFullscreen,
          )
        else
          const SizedBox(width: 16),
        Expanded(
          child: Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
        if (!_fullscreen)
          IconButton(
            tooltip: '關閉',
            color: Colors.white,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
      ],
    );
  }

  Widget _buildControls(ColorScheme scheme) {
    final primary = scheme.primary;
    final total = _duration.inSeconds;
    final seekMs = _seekMs;
    final progress =
        (_dragSeconds ??
                (seekMs != null ? seekMs ~/ 1000 : _position.inSeconds))
            .clamp(
              0,
              total > 0 ? total : 0,
            );
    final enabled = total > 0 && !_error;
    return Row(
      children: [
        IconButton(
          tooltip: _playing ? '暫停' : '播放',
          color: Colors.white,
          icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
          onPressed: _error ? null : () => _player?.playOrPause(),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: IgnorePointer(
              ignoring: !enabled,
              child: ProgressBar(
                progress: progress,
                total: total,
                progressBarColor: primary,
                baseBarColor: const Color(0x33FFFFFF),
                bufferedBarColor: primary.withValues(alpha: 0.4),
                thumbColor: primary,
                thumbGlowColor: primary.withAlpha(80),
                barHeight: 3.5,
                thumbRadius: 7,
                thumbGlowRadius: 25,
                onDragStart: (d) => setState(() => _dragSeconds = d.seconds),
                onDragUpdate: (d) => setState(() => _dragSeconds = d.seconds),
                onSeek: (ms) {
                  final to = Duration(milliseconds: ms);
                  _player?.seek(to);
                  setState(() {
                    _position = to;
                    _dragSeconds = null;
                  });
                },
              ),
            ),
          ),
        ),
        Text(
          '${_fmt(Duration(seconds: progress))} / ${_fmt(_duration)}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        IconButton(
          tooltip: _fullscreen ? '結束全螢幕' : '全螢幕',
          color: Colors.white,
          icon: Icon(_fullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
          onPressed: _toggleFullscreen,
        ),
      ],
    );
  }

  Widget _buildFullscreen(ColorScheme scheme) {
    const shade = [Color(0xB3000000), Color(0x00000000)];
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildVideo(),
          if (_showControls || _seekMs != null) ...[
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: shade,
                  ),
                ),
                child: SafeArea(bottom: false, child: _buildHeader()),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: shade,
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: _buildControls(scheme),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      // Back in fullscreen leaves fullscreen first.
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _fullscreen) _toggleFullscreen();
      },
      child: _fullscreen
          ? Dialog.fullscreen(
              backgroundColor: Colors.black,
              child: _buildFullscreen(scheme),
            )
          : Dialog(
              backgroundColor: const Color(0xFF181818),
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildHeader(),
                    AspectRatio(aspectRatio: 16 / 9, child: _buildVideo()),
                    _buildControls(scheme),
                  ],
                ),
              ),
            ),
    );
  }
}
