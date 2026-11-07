import 'dart:async';

import 'package:PiliPlus/http/browser_ua.dart';
import 'package:PiliPlus/http/constants.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/common/video/video_type.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:PiliPlus/models_new/story/story_item.dart';
import 'package:PiliPlus/pages/common/common_intro_controller.dart'
    show FavMixin;
import 'package:PiliPlus/pages/video/introduction/ugc/widgets/triple_mixin.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/services/download/btr_proxy.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart' show ValueNotifier, kDebugMode, debugPrint;
import 'package:flutter/widgets.dart' show Curves, PageController;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 單部豎屏影片的互動狀態（按讚、投幣、收藏、關注與統計數字）。
///
/// 不是 UgcIntroController（它只能在影片頁使用）：只實作 [TripleMixin] 與
/// [FavMixin] 需要的部分，讓收藏面板（PageUtils.showFavBottomSheet）可以直接使用。
class ReelsItemCtr extends GetxController
    with GetSingleTickerProviderStateMixin, TripleMixin, FavMixin {
  ReelsItemCtr(this.item)
    : ownerName = Rxn(item.ownerName),
      ownerFace = Rxn(item.ownerFace),
      desc = Rxn(item.desc),
      ownerMid = item.ownerMid,
      followed = item.followed.obs,
      like = item.like.obs,
      coin = item.coin.obs,
      fav = item.favorite.obs,
      reply = item.reply.obs,
      share = item.share.obs,
      danmaku = item.danmaku.obs {
    hasLike.value = item.hasLiked;
    coinNum.value = item.coined;
    hasFav.value = item.hasFaved;
  }

  final StoryItem item;
  int ownerMid;
  final Rxn<String> ownerName;
  final Rxn<String> ownerFace;
  final Rxn<String> desc;
  final RxBool followed;
  final RxInt like;
  final RxInt coin;
  final RxInt fav;
  final RxInt reply;
  final RxInt share;
  final RxInt danmaku;

  int? _copyright;

  @override
  bool get isLogin => Accounts.main.isLogin;

  /// 沒有版權資訊時保守視為轉載（最多投 1 幣）。
  @override
  int get copyright => _copyright ?? item.copyright ?? 2;

  @override
  (Object, int) get getFavRidType => (item.aid, 2);

  @override
  void updateFavCount(int count) => fav.value += count;

  bool _isProcessing = false;
  bool _detailLoaded = false;

  /// 登入時取得真實的按讚、投幣、收藏、關注狀態；
  /// 以影片頁種子開啟的項目沒有 UP 主與統計，一併補齊。
  Future<void> loadDetail() async {
    if (_detailLoaded) return;
    _detailLoaded = true;
    if (item.ownerName == null) {
      final res = await VideoHttp.videoIntro(bvid: item.bvid);
      if (res case Success(:final response)) {
        ownerMid = response.owner?.mid ?? ownerMid;
        ownerName.value = response.owner?.name;
        ownerFace.value = response.owner?.face;
        desc.value = response.desc;
        _copyright = response.copyright;
        if (response.stat case final stat?) {
          like.value = stat.like;
          coin.value = stat.coin.toInt();
          fav.value = stat.favorite;
          reply.value = stat.reply ?? 0;
          share.value = stat.share ?? 0;
          danmaku.value = stat.danmaku ?? 0;
        }
      }
    }
    if (isLogin) {
      final res = await VideoHttp.videoRelation(bvid: item.bvid);
      if (res case Success(:final response)) {
        hasLike.value = response.like ?? hasLike.value;
        coinNum.value = response.coin ?? coinNum.value;
        hasFav.value = response.favorite ?? hasFav.value;
        followed.value = response.attention ?? followed.value;
      }
    }
  }

  @override
  Future<void> actionLikeVideo() async {
    if (!isLogin) {
      SmartDialog.showToast('帳號未登入');
      return;
    }
    if (_isProcessing) return;
    _isProcessing = true;
    try {
      final newVal = !hasLike.value;
      final res = await VideoHttp.likeVideo(bvid: item.bvid, type: newVal);
      if (res case Success(:final response)) {
        SmartDialog.showToast(newVal ? response : '取消贊');
        like.value += newVal ? 1 : -1;
        hasLike.value = newVal;
      } else {
        res.toast();
      }
    } finally {
      _isProcessing = false;
    }
  }

  @override
  Future<void> onPayCoin(int coin, bool coinWithLike) async {
    final res = await VideoHttp.coinVideo(
      bvid: item.bvid,
      multiply: coin,
      selectLike: coinWithLike ? 1 : 0,
    );
    if (res.isSuccess) {
      SmartDialog.showToast('投幣成功');
      coinNum.value += coin;
      GlobalData().afterCoin(coin);
      this.coin.value += coin;
      if (coinWithLike && !hasLike.value) {
        like.value++;
        hasLike.value = true;
      }
    } else {
      res.toast();
    }
  }

  @override
  Future<void> actionTriple() async {
    if (!isLogin) {
      SmartDialog.showToast('帳號未登入');
      return;
    }
    final res = await VideoHttp.ugcTriple(bvid: item.bvid);
    if (res case Success(:final response)) {
      if (response.like == true && !hasLike.value) {
        like.value++;
        hasLike.value = true;
      }
      if (response.coin == true && !hasCoin) {
        coin.value += response.multiply ?? 1;
        coinNum.value = response.multiply ?? 1;
      }
      if (response.fav == true && !hasFav.value) {
        fav.value++;
        hasFav.value = true;
      }
      SmartDialog.showToast('三連成功');
    } else {
      res.toast();
    }
  }

  /// 關注或取消關注 UP 主。
  Future<void> actionFollow() async {
    if (!isLogin) {
      SmartDialog.showToast('帳號未登入');
      return;
    }
    if (ownerMid == 0 || _isProcessing) return;
    _isProcessing = true;
    try {
      final follow = !followed.value;
      final res = await VideoHttp.relationMod(
        mid: ownerMid,
        act: follow ? 1 : 2,
        reSrc: 11,
      );
      if (res.isSuccess) {
        followed.value = follow;
        SmartDialog.showToast(follow ? '關注成功' : '已取消關注');
      } else {
        res.toast();
      }
    } finally {
      _isProcessing = false;
    }
  }
}

/// 豎屏影片的播放網址。
typedef ReelsSource = ({String media, int cid});

/// 豎屏頁的控制器：影片清單、分頁載入，以及自己持有的 media_kit 播放器
/// （不使用 [PlPlayerController]，不影響影片頁、小視窗與 PiP）。
class ReelsController extends GetxController {
  ReelsController({this.seed});

  /// 種子影片：`{aid, bvid, cid, title, cover, progress(ms)}`
  final Map? seed;

  final items = <StoryItem>[].obs;
  final index = 0.obs;

  /// 第一次載入中（沒有任何影片時顯示轉圈）
  final loading = true.obs;
  final loadingMore = false.obs;

  /// 沒有影片時的錯誤訊息；null 表示沒有錯誤
  final error = RxnString();

  int displayId = 0;
  final Set<int> seen = {};

  /// 單次載入最多連續呼叫的次數（一頁沒有豎屏影片時再抓）
  static const _maxCalls = 5;

  final pageController = PageController();

  /// 有種子影片時，第一部開始播放的位置
  Duration? _startAt;

  @override
  void onInit() {
    super.onInit();
    final seed = this.seed;
    if (seed != null && seed['aid'] != null && seed['bvid'] != null) {
      final item = seed['item'] as StoryItem? ??
          StoryItem(
        aid: seed['aid'] as int,
        bvid: seed['bvid'] as String,
        cid: seed['cid'] as int,
        title: seed['title'] as String? ?? '',
        cover: seed['cover'] as String?,
        isVertical: true,
      );
      items.add(item);
      seen.add(item.aid);
      final progress = seed['progress'];
      if (progress is int && progress > 0) {
        _startAt = Duration(milliseconds: progress);
      }
      loading.value = false;
    }
    loadMore();
  }

  final Map<int, ReelsItemCtr> _itemCtrs = {};

  ReelsItemCtr itemCtr(StoryItem item) =>
      _itemCtrs[item.aid] ??= ReelsItemCtr(item);

  Future<void> loadMore() async {
    if (loadingMore.value) return;
    loadingMore.value = true;
    try {
      for (var call = 0; call < _maxCalls; call++) {
        final res = await VideoHttp.storyFeed(
          aid: items.isEmpty ? null : items.last.aid,
          displayId: ++displayId,
        );
        if (isClosed) return;
        if (res case Success(:final response)) {
          final added = <StoryItem>[];
          for (final i in response) {
            if (!i.isVertical || !seen.add(i.aid)) continue;
            added.add(i);
          }
          if (added.isNotEmpty) {
            items.addAll(added);
            error.value = null;
            break;
          }
        } else {
          if (items.isEmpty) {
            error.value = res is Error ? res.errMsg : null;
            error.value ??= '載入失敗';
          }
          break;
        }
      }
    } finally {
      loading.value = false;
      loadingMore.value = false;
    }
  }

  /// 重試（沒有影片時的按鈕）
  Future<void> retry() {
    error.value = null;
    loading.value = true;
    return loadMore();
  }

  // ---------------- 播放 ----------------

  Player? _player;
  Future<void>? _creating;

  /// 目前的播放器畫面（建立後不變）
  final videoController = Rxn<VideoController>();

  /// 目前是否允許播放（分頁可見、頁面在最上層、App 在前景）
  bool _active = false;

  /// 使用者點一下暫停
  final userPaused = false.obs;

  /// 播放中（只計算目前這部影片）
  final playing = false.obs;

  /// 第一個畫面出現後才蓋掉封面
  final firstFrame = false.obs;

  /// 目前影片的播放失敗訊息
  final playError = RxnString();

  final position = ValueNotifier(Duration.zero);
  final duration = ValueNotifier(Duration.zero);

  final List<StreamSubscription> _subs = [];
  int _gen = 0;
  int _playingIndex = -1;
  String? _media;
  bool _opened = false;

  bool get isActive => _active;

  Duration get currentPosition => position.value;

  bool get _isMine {
    if (!_opened) return false;
    final playlist = _player?.state.playlist;
    if (playlist == null || playlist.medias.isEmpty) return false;
    return playlist.medias[playlist.index.clamp(0, playlist.medias.length - 1)]
            .uri ==
        _media;
  }

  Future<void> _ensurePlayer() => _creating ??= _createPlayer();

  Future<void> _createPlayer() async {
    final player = await Player.create(
      configuration: const PlayerConfiguration(
        logLevel: kDebugMode ? .warn : .error,
        options: {
          'cache-pause-initial': 'no',
          'demuxer-max-bytes': '32MiB',
          'demuxer-readahead-secs': '15',
        },
      ),
    );
    try {
      final controller = await VideoController.create(player);
      if (isClosed) {
        // 建立播放器期間頁面已關閉：直接釋放，避免洩漏
        player.dispose();
        return;
      }
      player
        ..setMediaHeader(userAgent: BrowserUa.pc, referer: HttpString.baseUrl)
        ..setPlaylistMode(.none);
      _player = player;
      _subs
        ..add(
          player.stream.playing.listen((v) {
            if (_isMine) playing.value = v;
          }),
        )
        ..add(
          player.stream.position.listen((p) {
            if (!_isMine) return;
            if (!firstFrame.value && p > Duration.zero) {
              firstFrame.value = true;
            }
            position.value = p;
          }),
        )
        ..add(
          player.stream.completed.listen((done) {
            if (done && _isMine) _onCompleted();
          }),
        )
        ..add(
          player.stream.duration.listen((d) {
            if (_isMine) duration.value = d;
          }),
        );
      videoController.value = controller;
    } catch (_) {
      player.dispose();
      _creating = null;
      rethrow;
    }
  }

  /// 播放網址快取（預先載入下一部）
  final Map<int, Future<ReelsSource?>> _sources = {};
  final Map<int, String> _sourceErrors = {};

  Future<ReelsSource?> _source(StoryItem item) =>
      _sources[item.aid] ??= _fetchSource(item)..then((v) {
        if (v == null) _sources.remove(item.aid);
      });

  Future<ReelsSource?> _fetchSource(StoryItem item) async {
    try {
      final res = await VideoHttp.videoUrl(
        bvid: item.bvid,
        cid: item.cid,
        qn: Pref.defaultVideoQa,
        tryLook: false,
        videoType: VideoType.ugc,
      );
      switch (res) {
        case Success(:final response):
          final dash = response.dash;
          if (dash != null) {
            final video = _pickVideo(dash);
            if (video != null) {
              final audio = _pickAudio(dash);
              final v = await BtrProxy.wrap(video);
              final a = audio == null ? null : await BtrProxy.wrap(audio);
              final media = a == null
                  ? v
                  : 'edl://!no_chapters;%${v.length}%$v;'
                        '!new_stream;!no_chapters;%${a.length}%$a';
              return (media: media, cid: item.cid);
            }
          }
          final url = response.durl?.firstOrNull?.playUrls.firstOrNull;
          if (url != null) {
            return (media: await BtrProxy.wrap(url), cid: item.cid);
          }
          _sourceErrors[item.aid] = '無法取得播放網址';
        case Error(:final errMsg):
          _sourceErrors[item.aid] = errMsg ?? '無法取得播放網址';
        default:
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Reels source: $e');
      _sourceErrors[item.aid] = '無法取得播放網址';
    }
    return null;
  }

  /// 不高於設定畫質的最高畫質，優先 H.264（所有裝置都能解碼）。
  String? _pickVideo(Dash dash) {
    final videos = dash.video;
    if (videos == null || videos.isEmpty) return null;
    final avc = videos.where((v) => v.codecid == 7).toList();
    final list = (avc.isNotEmpty ? avc : List.of(videos))
      ..sort((a, b) => a.id.compareTo(b.id));
    final max = Pref.defaultVideoQa;
    final item = list.lastWhere((v) => v.id <= max, orElse: () => list.first);
    return item.baseUrl;
  }

  String? _pickAudio(Dash dash) {
    final audios = dash.audio;
    if (audios == null || audios.isEmpty) return null;
    final list = List.of(audios)
      ..sort((a, b) => (b.bandWidth ?? 0).compareTo(a.bandWidth ?? 0));
    return list.first.baseUrl;
  }

  /// 頁面切換（PageView.onPageChanged）
  void onPageChanged(int i) {
    index.value = i;
    if (items.length - i <= 3) loadMore();
    if (_active) _startItem(i);
  }

  /// 設定是否允許播放。允許時開始或繼續播放目前影片；不允許時暫停。
  void setActive(bool active) {
    if (_active == active) return;
    _active = active;
    if (active) {
      // 只讓一個播放器出聲：暫停影片頁（含小視窗）的播放器
      PlPlayerController.pauseIfExists();
      if (items.isEmpty) return;
      final i = index.value.clamp(0, items.length - 1);
      if (_playingIndex == i && _opened) {
        if (!userPaused.value) _player?.play();
      } else {
        _startItem(i);
      }
    } else {
      _player?.pause();
    }
  }

  Future<void> _startItem(int i) async {
    if (i < 0 || i >= items.length) return;
    final gen = ++_gen;
    final item = items[i];
    _playingIndex = i;
    _opened = false;
    _media = null;
    userPaused.value = false;
    playing.value = false;
    firstFrame.value = false;
    playError.value = null;
    position.value = Duration.zero;
    duration.value = Duration.zero;
    itemCtr(item).loadDetail();
    try {
      await _ensurePlayer();
      if (gen != _gen) return;
      _player!.stop();
      final source = await _source(item);
      if (gen != _gen) return;
      // 預先取得下一部的網址
      if (i + 1 < items.length) _source(items[i + 1]);
      if (source == null) {
        _fail(gen, i, _sourceErrors[item.aid] ?? '無法播放此影片');
        return;
      }
      final start = _startAt;
      _startAt = null;
      final media = Media(source.media, start: start);
      _media = media.uri;
      await _player!.open(media, play: _active);
      if (gen != _gen) return;
      // open 期間被設為不可播放（切走分頁）時，補一次暫停
      if (!_active) _player!.pause();
      _opened = true;
      playing.value = _player!.state.playing;
      duration.value = _player!.state.duration;
    } catch (e) {
      if (kDebugMode) debugPrint('Reels play: $e');
      if (gen == _gen) _fail(gen, i, '播放失敗');
    }
  }

  /// 播放完成：直接接下一部；沒有下一部時重播目前這部並載入更多。
  void _onCompleted() {
    if (!_active) return;
    final i = _playingIndex;
    if (i + 1 < items.length && pageController.hasClients) {
      pageController.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      loadMore();
      _player?.seek(Duration.zero);
      _player?.play();
    }
  }

  /// 顯示錯誤，稍後自動跳到下一部。
  void _fail(int gen, int i, String msg) {
    playError.value = msg;
    SmartDialog.showToast(msg);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (isClosed || gen != _gen || !_active) return;
      if (i + 1 < items.length && pageController.hasClients) {
        pageController.nextPage(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      } else if (i + 1 >= items.length) {
        loadMore();
      }
    });
  }

  /// 點一下暫停或繼續
  void togglePlay() {
    final player = _player;
    if (player == null || !_isMine) return;
    if (player.state.playing) {
      userPaused.value = true;
      player.pause();
    } else {
      userPaused.value = false;
      player.play();
    }
  }

  void seekTo(Duration position) {
    if (_isMine) _player?.seek(position);
  }

  @override
  void onClose() {
    _gen++;
    _active = false;
    for (final sub in _subs) {
      sub.cancel();
    }
    _player?.dispose();
    _player = null;
    for (final c in _itemCtrs.values) {
      c.onClose();
    }
    pageController.dispose();
    position.dispose();
    duration.dispose();
    super.onClose();
  }
}
