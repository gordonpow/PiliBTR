import 'dart:async';

import 'package:PiliPlus/common/widgets/video_card/swipe_preview.dart';
import 'package:PiliPlus/common/widgets/video_card/video_preview.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart';
import 'package:PiliPlus/http/live.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/live/live_room_play_info/codec.dart';
import 'package:PiliPlus/models_new/live/live_room_play_info/data.dart';
import 'package:PiliPlus/utils/video_utils.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:media_kit/media_kit.dart' hide Subtitle;
import 'package:media_kit_video/media_kit_video.dart';

/// Preview behaviour of one live card: the first long press plays the live
/// stream in the cover, the next one runs the old long press action.
/// Uses the shared preview player of [VideoPreview], so a live preview and a
/// video preview never play together.
class LiveCardPreview {
  const LiveCardPreview({required this.item, required this.roomId});

  /// The key of the card (see [VideoPreview.active]).
  final Object item;
  final Object? roomId;

  bool get _on => roomId != null && VideoPreview.enabled;

  /// For `InkWell.onLongPress`: preview first, [second] when it plays.
  void longPress(VoidCallback second) =>
      _on && VideoPreview.active.value != item
      ? VideoPreview.start(item)
      : second();

  /// Stops the preview of this card. Call it when the card opens the room.
  void stop() => VideoPreview.stop(item);

  /// The preview over the cover. Put it in a [Stack] of the cover.
  Widget overlay({BorderRadius? radius}) {
    final roomId = this.roomId;
    if (roomId == null) return const SizedBox.shrink();
    return Positioned.fill(
      child: ValueListenableBuilder(
        valueListenable: VideoPreview.active,
        builder: (context, active, _) {
          if (active != item) return const SizedBox.shrink();
          final preview = LiveInlinePreview(item: item, roomId: roomId);
          return radius == null
              ? preview
              : ClipRRect(borderRadius: radius, child: preview);
        },
      ),
    );
  }

  /// Makes the card a target of the swipe preview.
  Widget wrapTarget(Widget child) => roomId != null
      ? SwipePreviewTarget(item: item, onPrefetch: () {}, child: child)
      : child;
}

/// Live preview that fills the cover area of a card.
class LiveInlinePreview extends StatefulWidget {
  const LiveInlinePreview({
    super.key,
    required this.item,
    required this.roomId,
  });

  /// The card item (see [VideoPreview.active]).
  final Object item;
  final Object roomId;

  @override
  State<LiveInlinePreview> createState() => _LiveInlinePreviewState();
}

class _LiveInlinePreviewState extends State<LiveInlinePreview>
    with WidgetsBindingObserver {
  VideoController? _video;
  Player? _player;
  bool _muted = true;
  bool _firstFrame = false;
  bool _opened = false;
  String? _media;
  String? _error;
  final List<StreamSubscription> _subs = [];
  bool _disposed = false;

  bool get _isMine {
    if (!_opened) return false;
    final playlist = _player?.state.playlist;
    if (playlist == null || playlist.medias.isEmpty) return false;
    return playlist.medias[playlist.index.clamp(0, playlist.medias.length - 1)]
            .uri ==
        _media;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Another page covers this one: stop.
    if (!TickerMode.valuesOf(context).enabled) _stopLater();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _stopLater();
  }

  void _stopLater() {
    // Do not change the notifier during a build.
    scheduleMicrotask(() => VideoPreview.stop(widget.item));
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    for (final sub in _subs) {
      sub.cancel();
    }
    // The player is shared: stop it only if this card still owns it.
    VideoPreview.release(this);
    _stopLater();
    super.dispose();
  }

  void _fail([String message = '無法預覽']) {
    if (mounted) setState(() => _error = message);
  }

  /// H.264 when possible. No BtrProxy: it range-proxies media files and
  /// cannot carry an endless live stream.
  static String? _pickUrl(RoomPlayInfoData data) {
    final streams = data.playurlInfo?.playurl?.stream;
    if (streams == null) return null;
    CodecItem? first;
    for (final s in streams) {
      for (final f in s.format) {
        for (final c in f.codec) {
          if (c.urlInfo.isEmpty) continue;
          first ??= c;
          if (c.codecName == 'avc') return VideoUtils.getLiveCdnUrl(c);
        }
      }
    }
    return first == null ? null : VideoUtils.getLiveCdnUrl(first);
  }

  Future<void> _load() async {
    // The player gets ready while the room info loads.
    final playerFuture = VideoPreview.acquire(this);
    final LoadingState<RoomPlayInfoData> res;
    try {
      // qn 80 is the lowest live quality.
      res = await LiveHttp.liveRoomInfo(roomId: widget.roomId, qn: 80);
    } catch (e) {
      if (kDebugMode) debugPrint('LivePreview info: $e');
      return _fail();
    }
    if (_disposed) return;
    final data = switch (res) {
      Success(:final response) => response,
      _ => null,
    };
    if (data == null) return _fail();
    if (data.liveStatus != 1) return _fail('直播已結束');
    final url = _pickUrl(data);
    if (url == null) return _fail();
    final Player player;
    final VideoController controller;
    try {
      (player, controller) = await playerFuture;
    } catch (e) {
      if (kDebugMode) debugPrint('LivePreview player: $e');
      return _fail();
    }
    if (_disposed) return;
    _player = player;
    try {
      if (mounted) setState(() => _muted = PreviewAudio.muted);
      player.setVolume(_muted ? 0 : 100);
      _subs.add(
        player.stream.position.listen((position) {
          if (!mounted || !_isMine) return;
          if (!_firstFrame && position > Duration.zero) {
            setState(() => _firstFrame = true);
          }
        }),
      );
      // A live stream's position can stay 0: a decoded picture size also
      // means the first frame is there.
      _subs.add(
        player.stream.size.listen((size) {
          if (!mounted || !_isMine) return;
          if (!_firstFrame && size.$1 > 0) {
            setState(() => _firstFrame = true);
          }
        }),
      );
      setState(() => _video = controller);
      final item = Media(url);
      _media = item.uri;
      await player.open(item);
      if (_disposed) return;
      _opened = true;
    } catch (e) {
      if (kDebugMode) debugPrint('LivePreview: $e');
      _fail();
    }
  }

  void _toggleMute() {
    final player = _player;
    if (player == null) return;
    setState(() => _muted = !_muted);
    PreviewAudio.muted = _muted;
    player.setVolume(_muted ? 0 : 100);
  }

  @override
  Widget build(BuildContext context) {
    final video = _video;
    return Stack(
      fit: StackFit.expand,
      children: [
        // The cover (under this widget) shows until the first frame.
        if (video != null && _firstFrame)
          ColoredBox(
            color: Colors.black,
            child: FittedBox(
              fit: BoxFit.contain,
              child: SimpleVideo(controller: video),
            ),
          ),
        if (_error case final error?)
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                child: Text(
                  error,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          )
        else if (!_firstFrame)
          const Center(
            child: SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            ),
          ),
        if (video != null)
          Positioned(
            right: 2,
            top: 2,
            child: IconButton(
              tooltip: _muted ? '開啟聲音' : '靜音',
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              color: Colors.white,
              style: IconButton.styleFrom(backgroundColor: Colors.black45),
              icon: Icon(_muted ? Icons.volume_off : Icons.volume_up),
              onPressed: _toggleMute,
            ),
          ),
      ],
    );
  }
}
