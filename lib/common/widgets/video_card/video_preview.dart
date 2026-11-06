import 'dart:async';

import 'package:PiliPlus/grpc/dm.dart';
import 'package:PiliPlus/http/browser_ua.dart';
import 'package:PiliPlus/http/constants.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/search.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:PiliPlus/models_new/video/video_play_info/subtitle.dart';
import 'package:PiliPlus/services/download/btr_proxy.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart' hide Subtitle;
import 'package:media_kit_video/media_kit_video.dart';

/// Streams of a preview: video, optional audio, and the cid.
typedef PreviewSource = ({String video, String? audio, int cid});

/// Long press on a video card: the card plays a low quality preview of the
/// video in place of its cover, muted at the start. Only one card plays at
/// a time.
abstract final class VideoPreview {
  /// Setting: long press on a home video card shows a preview.
  static bool get enabled =>
      GStorage.setting.get(SettingBoxKey.videoCardPreview, defaultValue: true);

  /// Setting: show CC subtitles in the preview. The CC button on the
  /// preview changes it.
  static bool get subtitle => GStorage.setting.get(
    SettingBoxKey.videoPreviewSubtitle,
    defaultValue: true,
  );

  static set subtitle(bool value) =>
      GStorage.setting.put(SettingBoxKey.videoPreviewSubtitle, value);

  /// The item of the card that plays a preview, or null.
  static final active = ValueNotifier<Object?>(null);

  static void start(Object item) => active.value = item;

  static void stop([Object? item]) {
    if (item == null || active.value == item) active.value = null;
  }

  /// One player for all previews. Creating and disposing an mpv player
  /// and its video texture for every card drops frames while the list
  /// scrolls, so the player stays and only the media changes.
  static Future<(Player, VideoController)>? _shared;

  /// The preview that uses the shared player now. A new card starts
  /// (initState) before the old card goes away (dispose), so only the
  /// owner may stop the player.
  static Object? _owner;
  static Timer? _idleTimer;

  /// The shared player is disposed after this time without a preview.
  static const _idleTime = Duration(seconds: 30);

  static Future<(Player, VideoController)> _acquire(Object owner) {
    _idleTimer?.cancel();
    final hadOwner = _owner != null;
    _owner = owner;
    final shared = _shared;
    if (shared != null) {
      // Stop the media of the previous card at once.
      if (hadOwner) shared.then((p) => p.$1.stop()).ignore();
      return shared;
    }
    final created = _createPlayer();
    _shared = created;
    // A failed player is not kept: the next preview tries again.
    created.then(
      (_) {},
      onError: (Object _) {
        if (_shared == created) _shared = null;
      },
    );
    return created;
  }

  static void _release(Object owner) {
    if (_owner != owner) return;
    _owner = null;
    _shared?.then((p) => p.$1.stop()).ignore();
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleTime, () {
      if (_owner != null) return;
      final shared = _shared;
      _shared = null;
      shared?.then((p) => p.$1.dispose()).ignore();
    });
  }

  static Future<(Player, VideoController)> _createPlayer() async {
    final player = await Player.create(
      configuration: const PlayerConfiguration(
        logLevel: .error,
        options: {
          // Start as soon as possible, and keep little data.
          'cache-pause-initial': 'no',
          'demuxer-max-bytes': '16MiB',
          'demuxer-readahead-secs': '10',
        },
      ),
    );
    try {
      final controller = await VideoController.create(player);
      player
        ..setMediaHeader(userAgent: BrowserUa.pc, referer: HttpString.baseUrl)
        ..setPlaylistMode(.single);
      return (player, controller);
    } catch (e) {
      player.dispose();
      rethrow;
    }
  }

  /// Place of the playing preview: its bvid, cid and position.
  static ({String bvid, int cid, int ms})? _progress;

  /// Returns the cid and position (milliseconds) of the preview of [bvid]
  /// if it plays, so the video page can continue from there.
  static ({int cid, int ms})? progressOf(String bvid) {
    final p = _progress;
    if (p == null || p.bvid != bvid) return null;
    return (cid: p.cid, ms: p.ms);
  }

  /// Recent source requests by bvid. The play URLs expire after some time,
  /// so an entry is used only while it is new.
  static final _sources =
      <String, ({DateTime time, Future<PreviewSource?> future})>{};
  static const _maxSources = 6;
  static const _sourceTtl = Duration(minutes: 5);

  /// Starts to get the streams early (for example, when the finger touches
  /// the card), so the preview starts faster after a long press.
  static void prefetch({int? aid, required String bvid, int? cid}) {
    if (enabled) source(aid: aid, bvid: bvid, cid: cid);
  }

  /// Streams for the preview of [bvid] (about 480P).
  static Future<PreviewSource?> source({
    int? aid,
    required String bvid,
    int? cid,
  }) {
    final now = DateTime.now();
    final cached = _sources[bvid];
    if (cached != null && now.difference(cached.time) < _sourceTtl) {
      return cached.future;
    }
    final future = _fetchSource(aid: aid, bvid: bvid, cid: cid);
    _sources
      ..remove(bvid)
      ..[bvid] = (time: now, future: future);
    while (_sources.length > _maxSources) {
      _sources.remove(_sources.keys.first);
    }
    // Do not keep a failure.
    future.then((value) {
      if (value == null && _sources[bvid]?.future == future) {
        _sources.remove(bvid);
      }
    });
    return future;
  }

  static Future<PreviewSource?> _fetchSource({
    int? aid,
    required String bvid,
    int? cid,
  }) async {
    try {
      if (cid == null) {
        if (await SearchHttp.ab2cWithDimension(aid: aid, bvid: bvid)
            case final res?) {
          cid = res.cid;
        }
      }
      if (cid == null) return null;
      final res = await VideoHttp.videoUrl(
        bvid: bvid,
        cid: cid,
        qn: 32,
        tryLook: false,
        videoType: .ugc,
      );
      final dash = switch (res) {
        Success(:final response) => response.dash,
        _ => null,
      };
      if (dash == null) return null;
      final video = _pickVideo(dash);
      if (video == null) return null;
      return (video: video, audio: _pickAudio(dash), cid: cid);
    } catch (e) {
      if (kDebugMode) debugPrint('VideoPreview source: $e');
      return null;
    }
  }

  /// Video stream: about 480P, H.264 when possible (it decodes on all
  /// devices).
  static String? _pickVideo(Dash dash) {
    final videos = dash.video;
    if (videos == null || videos.isEmpty) return null;
    final avc = videos.where((v) => v.codecid == 7).toList();
    final list = (avc.isNotEmpty ? avc : List.of(videos))
      ..sort((a, b) => a.id.compareTo(b.id));
    final item = list.lastWhere((v) => v.id <= 32, orElse: () => list.first);
    return item.baseUrl;
  }

  /// Audio stream with the lowest bit rate.
  static String? _pickAudio(Dash dash) {
    final audios = dash.audio;
    if (audios == null || audios.isEmpty) return null;
    final list = List.of(audios)
      ..sort((a, b) => (a.bandWidth ?? 0).compareTo(b.bandWidth ?? 0));
    return list.first.baseUrl;
  }
}

/// Preview player that fills the cover area of a card.
class InlineVideoPreview extends StatefulWidget {
  const InlineVideoPreview({
    super.key,
    required this.item,
    this.aid,
    required this.bvid,
    this.cid,
  });

  /// The card item (see [VideoPreview.active]).
  final Object item;
  final int? aid;
  final String bvid;
  final int? cid;

  @override
  State<InlineVideoPreview> createState() => _InlineVideoPreviewState();
}

class _InlineVideoPreviewState extends State<InlineVideoPreview>
    with WidgetsBindingObserver {
  Player? _player;
  VideoController? _video;
  bool _muted = true;
  bool _playing = false;

  /// True after the first video frame shows. Until then the cover stays
  /// visible (no black frame).
  bool _firstFrame = false;
  String? _error;
  final List<StreamSubscription> _subs = [];
  bool _disposed = false;

  int? _cid;

  /// True after this card's media opened: earlier position events belong
  /// to the previous card of the shared player.
  bool _opened = false;

  /// Media of this card. Events of the shared player count only while it
  /// plays this media, not a late event of the previous card.
  String? _media;

  bool get _isMine {
    if (!_opened) return false;
    final playlist = _player?.state.playlist;
    if (playlist == null || playlist.medias.isEmpty) return false;
    return playlist.medias[playlist.index.clamp(0, playlist.medias.length - 1)]
            .uri ==
        _media;
  }

  /// Position and subtitle text change many times a second: only the
  /// progress bar and the subtitle rebuild, not the whole preview.
  final _position = ValueNotifier(Duration.zero);
  final _cueText = ValueNotifier<String?>(null);
  Duration _duration = Duration.zero;

  /// Part of the video (0 to 1) while the finger drags the progress bar.
  double? _dragValue;

  /// CC subtitles: on/off, the cues (seconds), and the current text.
  bool _subtitleOn = VideoPreview.subtitle;
  List<({double from, double to, String text})>? _cues;

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
    _position.dispose();
    _cueText.dispose();
    // The player is shared: stop it only if this card still owns it.
    VideoPreview._release(this);
    // The card went away (for example, it scrolled out of the list).
    _stopLater();
    super.dispose();
  }

  void _fail() {
    if (mounted) setState(() => _error = '無法預覽此影片');
  }

  Future<void> _load() async {
    // The player gets ready while the streams load.
    final playerFuture = VideoPreview._acquire(this);
    final source = await VideoPreview.source(
      aid: widget.aid,
      bvid: widget.bvid,
      cid: widget.cid,
    );
    final Player player;
    final VideoController controller;
    try {
      (player, controller) = await playerFuture;
    } catch (e) {
      if (kDebugMode) debugPrint('VideoPreview player: $e');
      return _fail();
    }
    if (_disposed) return;
    _player = player;
    if (source == null) return _fail();
    _cid = source.cid;
    _loadSubtitle(source.cid);
    try {
      player.setVolume(0);
      // BTR: fetch from several CDN nodes in parallel.
      final video = await BtrProxy.wrap(source.video);
      final audio = source.audio == null
          ? null
          : await BtrProxy.wrap(source.audio!);
      if (_disposed) return;
      final media = audio == null
          ? video
          : 'edl://!no_chapters;%${video.length}%$video;'
                '!new_stream;!no_chapters;%${audio.length}%$audio';
      _subs
        ..add(
          player.stream.playing.listen((playing) {
            if (_isMine && mounted) setState(() => _playing = playing);
          }),
        )
        ..add(player.stream.position.listen(_onPosition))
        ..add(
          player.stream.duration.listen((duration) {
            if (_isMine && mounted) setState(() => _duration = duration);
          }),
        );
      setState(() => _video = controller);
      final item = Media(media);
      // Compare with the uri as Media keeps it (it can normalize it).
      _media = item.uri;
      await player.open(item);
      if (_disposed) return;
      _opened = true;
    } catch (e) {
      if (kDebugMode) debugPrint('VideoPreview: $e');
      _fail();
    }
  }

  /// Loads the first CC subtitle (Chinese first, AI subtitles last).
  Future<void> _loadSubtitle(int cid) async {
    try {
      List<Subtitle>? subs;
      final res = await VideoHttp.playInfo(bvid: widget.bvid, cid: cid);
      if (res case Success(:final response)) {
        subs = response.subtitle?.subtitles;
      }
      if ((subs == null || subs.isEmpty) && !Accounts.main.isLogin) {
        // Without login, playInfo has no subtitles: use the dm view.
        final aid = widget.aid ?? IdUtils.bv2av(widget.bvid);
        if (await DmGrpc.dmView(aid, cid) case Success(:final response)
            when response.hasSubtitle()) {
          subs = response.subtitle.subtitles
              .map(
                (i) => Subtitle(
                  lan: i.lan,
                  lanDoc: i.lanDoc,
                  subtitleUrl: i.subtitleUrl,
                  isAi: i.type == .AI,
                ),
              )
              .toList();
        }
      }
      if (_disposed || subs == null || subs.isEmpty) return;
      var url = (List.of(subs)..sort()).first.subtitleUrl;
      if (url == null || url.isEmpty) return;
      if (url.startsWith('//')) url = 'https:$url';
      final body = await Request().get(url);
      if (_disposed) return;
      if (body.data?['body'] case List list) {
        final cues = <({double from, double to, String text})>[];
        for (final e in list) {
          if (e case {
            'from': num from,
            'to': num to,
            'content': String text,
          }) {
            cues.add((from: from.toDouble(), to: to.toDouble(), text: text));
          }
        }
        if (cues.isNotEmpty) setState(() => _cues = cues);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('VideoPreview subtitle: $e');
    }
  }

  void _onPosition(Duration position) {
    if (!mounted || !_isMine) return;
    // The shared player renders frames of every card: show the video
    // only after this card's media plays (no frame of the previous card).
    if (!_firstFrame && position > Duration.zero) {
      setState(() => _firstFrame = true);
    }
    String? text;
    final cues = _cues;
    if (_subtitleOn && cues != null) {
      final t = position.inMilliseconds / 1000;
      for (final cue in cues) {
        if (cue.from > t) break;
        if (t < cue.to) {
          text = cue.text;
          break;
        }
      }
    }
    if (_cid case final cid?) {
      VideoPreview._progress = (
        bvid: widget.bvid,
        cid: cid,
        ms: position.inMilliseconds,
      );
    }
    _position.value = position;
    _cueText.value = text;
  }

  void _toggleSubtitle() {
    setState(() => _subtitleOn = !_subtitleOn);
    if (!_subtitleOn) _cueText.value = null;
    VideoPreview.subtitle = _subtitleOn;
  }

  void _toggleMute() {
    final player = _player;
    if (player == null) return;
    setState(() => _muted = !_muted);
    player.setVolume(_muted ? 0 : 100);
  }

  double _valueAt(Offset local, double width) =>
      width <= 0 ? 0 : (local.dx / width).clamp(0.0, 1.0);

  void _seekTo(double value) {
    final ms = (_duration.inMilliseconds * value).round();
    _player?.seek(Duration(milliseconds: ms));
  }

  Widget _progressBar() => ValueListenableBuilder(
    valueListenable: _position,
    builder: (context, position, _) => _progressBarAt(position),
  );

  Widget _progressBarAt(Duration position) {
    final total = _duration.inMilliseconds;
    final value =
        _dragValue ??
        (total > 0 ? (position.inMilliseconds / total).clamp(0.0, 1.0) : 0.0);
    final dragging = _dragValue != null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _seekTo(_valueAt(d.localPosition, width)),
          onHorizontalDragStart: (d) =>
              setState(() => _dragValue = _valueAt(d.localPosition, width)),
          onHorizontalDragUpdate: (d) =>
              setState(() => _dragValue = _valueAt(d.localPosition, width)),
          onHorizontalDragEnd: (_) {
            if (_dragValue case final v?) _seekTo(v);
            setState(() => _dragValue = null);
          },
          onHorizontalDragCancel: () => setState(() => _dragValue = null),
          // A taller touch area than the bar.
          child: SizedBox(
            height: 20,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  SizedBox(
                    height: dragging ? 4 : 3,
                    width: width,
                    child: ColoredBox(
                      color: Colors.white.withValues(alpha: .3),
                    ),
                  ),
                  SizedBox(
                    height: dragging ? 4 : 3,
                    width: width * value,
                    child: const ColoredBox(color: Color(0xFFFB7299)),
                  ),
                  if (dragging)
                    Positioned(
                      left: width * value - 6,
                      top: -4,
                      child: const SizedBox.square(
                        dimension: 12,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color(0xFFFB7299),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
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
        else if (!_firstFrame || !_playing)
          const Center(
            child: SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            ),
          ),
        if (_subtitleOn)
          Positioned(
            left: 8,
            right: 8,
            bottom: 12,
            child: ValueListenableBuilder(
              valueListenable: _cueText,
              builder: (context, cue, _) => cue == null
                  ? const SizedBox.shrink()
                  : Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Text(
                            cue,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        if (video != null && _duration > Duration.zero)
          Positioned(left: 0, right: 0, bottom: 0, child: _progressBar()),
        if (video != null && _cues != null)
          Positioned(
            right: 40,
            top: 2,
            child: IconButton(
              tooltip: _subtitleOn ? '關閉字幕' : '開啟字幕',
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              color: Colors.white,
              style: IconButton.styleFrom(backgroundColor: Colors.black45),
              icon: Icon(
                _subtitleOn
                    ? Icons.closed_caption
                    : Icons.closed_caption_disabled_outlined,
              ),
              onPressed: _toggleSubtitle,
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
