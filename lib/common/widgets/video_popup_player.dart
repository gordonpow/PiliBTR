import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:io' show File;

import 'package:PiliPlus/common/widgets/zh_material.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/mini_player.dart';
import 'package:PiliPlus/plugin/pl_player/utils/fullscreen.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

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
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double? _dragValue;

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
      final player = await Player.create();
      final controller = await VideoController.create(player);
      if (!mounted || _disposed) {
        player.dispose();
        return;
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
    _player?.dispose();
    if (_fullscreen) showSystemBar();
    super.dispose();
  }

  void _toggleFullscreen() {
    setState(() => _fullscreen = !_fullscreen);
    if (_fullscreen) {
      hideSystemBar();
    } else {
      showSystemBar();
    }
  }

  static String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = two(d.inMinutes.remainder(60));
    final s = two(d.inSeconds.remainder(60));
    return h > 0 ? '$h:$m:$s' : '$m:$s';
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
      child = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _player?.playOrPause(),
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
              const Icon(
                Icons.play_circle_outline,
                size: 64,
                color: Colors.white70,
              ),
          ],
        ),
      );
    }
    return ColoredBox(color: Colors.black, child: child);
  }

  Widget _buildControls() {
    final maxMs = _duration.inMilliseconds.toDouble();
    final curMs = (_dragValue ?? _position.inMilliseconds.toDouble()).clamp(
      0.0,
      maxMs > 0 ? maxMs : 1.0,
    );
    return Row(
      children: [
        IconButton(
          tooltip: _playing ? '暫停' : '播放',
          icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
          onPressed: _error ? null : () => _player?.playOrPause(),
        ),
        Text(
          '${_fmt(Duration(milliseconds: curMs.toInt()))} / ${_fmt(_duration)}',
          style: const TextStyle(fontSize: 12),
        ),
        Expanded(
          child: Slider(
            value: curMs,
            max: maxMs > 0 ? maxMs : 1.0,
            onChanged: maxMs > 0 && !_error
                ? (v) => setState(() => _dragValue = v)
                : null,
            onChangeEnd: (v) {
              _player?.seek(Duration(milliseconds: v.toInt()));
              setState(() {
                _position = Duration(milliseconds: v.toInt());
                _dragValue = null;
              });
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final header = Row(
      children: [
        Expanded(
          child: Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        IconButton(
          tooltip: _fullscreen ? '結束全螢幕' : '全螢幕',
          icon: Icon(_fullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
          onPressed: _toggleFullscreen,
        ),
        IconButton(
          tooltip: '關閉',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );

    return Dialog(
      insetPadding: _fullscreen
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: _fullscreen
          ? const RoundedRectangleBorder()
          : RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: _fullscreen
            ? BoxConstraints.tight(MediaQuery.sizeOf(context))
            : const BoxConstraints(maxWidth: 800),
        child: Column(
          mainAxisSize: _fullscreen ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 4),
              child: header,
            ),
            if (_fullscreen)
              Expanded(child: _buildVideo())
            else
              AspectRatio(aspectRatio: 16 / 9, child: _buildVideo()),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildControls(),
            ),
          ],
        ),
      ),
    );
  }
}
