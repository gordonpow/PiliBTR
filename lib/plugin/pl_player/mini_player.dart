import 'dart:async';
import 'dart:math' as math;

import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:PiliPlus/services/service_locator.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
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

  static bool get active => _entry != null;

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
    final entry = _entry = OverlayEntry(
      builder: (_) => _MiniPlayerView(ctr: ctr),
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
  const _MiniPlayerView({required this.ctr});

  final PlPlayerController ctr;

  @override
  State<_MiniPlayerView> createState() => _MiniPlayerViewState();
}

class _MiniPlayerViewState extends State<_MiniPlayerView> {
  late bool _playing = widget.ctr.playerStatus.isPlaying;
  Offset? _offset;

  @override
  void initState() {
    super.initState();
    widget.ctr.addStatusLister(_onStatus);
  }

  @override
  void dispose() {
    widget.ctr.removeStatusLister(_onStatus);
    super.dispose();
  }

  void _onStatus(PlayerStatus status) {
    if (mounted) setState(() => _playing = status.isPlaying);
  }

  void _seekBy(int seconds) {
    final ms = widget.ctr.positionInMilliseconds + seconds * 1000;
    widget.ctr.seekTo(Duration(milliseconds: math.max(0, ms)));
  }

  @override
  Widget build(BuildContext context) {
    final videoController = widget.ctr.videoController;
    if (videoController == null) return const SizedBox.shrink();
    final media = MediaQuery.of(context);
    final size = media.size;
    final width = math.min(size.shortestSide * 0.55, 320.0);
    final height = width * 9 / 16 + 40;
    // Default place: bottom right, above the navigation bar.
    final maxX = size.width - width - 8;
    final maxY = size.height - height - media.padding.bottom - 8;
    final offset = _offset ?? Offset(maxX, maxY - 80);
    final theme = Theme.of(context);

    return Positioned(
      left: offset.dx.clamp(8, math.max(8, maxX)),
      top: offset.dy.clamp(media.padding.top + 8, math.max(8, maxY)),
      width: width,
      height: height,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() => _offset = offset + d.delta),
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
                height: 40,
                child: IconTheme(
                  data: theme.iconTheme.copyWith(color: Colors.white),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
                        icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
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
            ],
          ),
        ),
      ),
    );
  }
}
