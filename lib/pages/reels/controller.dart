import 'dart:async';
import 'dart:io' show Platform;

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
import 'package:PiliPlus/utils/connectivity_utils.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
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
/// [expire] 為網址過期時間（毫秒 epoch，0 表示未知）。
typedef ReelsSource = ({String media, int cid, bool preload, int expire});

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

  /// 允許的最高畫質（依 Wi-Fi／行動網路設定），先用預設值，查完網路後更新。
  int _maxQa = Pref.defaultVideoQa;
  Future<void> _qaReady = Future.value();

  Future<void> _initQa() async {
    if (!(PlatformUtils.isMobile || Platform.isLinux)) return;
    try {
      final isWiFi = await ConnectivityUtils.isWiFi;
      _maxQa = isWiFi ? Pref.defaultVideoQa : Pref.defaultVideoQaCellular;
    } catch (_) {
      // 判斷失敗：保留預設值
    }
  }

  @override
  void onInit() {
    super.onInit();
    _qaReady = _initQa();
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
            // 原本是最後一部而沒有預載時，補預載
            if (_opened) _preloadAhead(_playingIndex);
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

  /// 播放器數量。
  static const _poolSize = 4;

  /// 播放器槽位：一個正在播放（[_cur]），其餘靜音暫停預載後面幾部。
  final List<_Slot> _slots = [];
  int _cur = 0;
  Future<void>? _creating;

  /// 目前槽位的播放器畫面（換槽位時更新）
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

  /// 世代計數：每次換片加一，過時的非同步開啟一律丟棄。
  int _gen = 0;
  int _playingIndex = -1;
  bool _opened = false;

  /// 使用 `player_preload` 失敗過的影片（改用 videoUrl）
  final Set<int> _noPreload = {};

  /// 解碼失敗過的影片（改只選 H.264）
  final Set<int> _avcOnly = {};

  bool get isActive => _active;

  Duration get currentPosition => position.value;

  _Slot? get _curSlot => _slots.length == _poolSize ? _slots[_cur] : null;

  /// 非目前槽位中載入（或載入中）[aid] 的槽位
  _Slot? _slotFor(int aid) {
    final cur = _curSlot;
    for (final s in _slots) {
      if (!identical(s, cur) && s.aid == aid) return s;
    }
    return null;
  }

  /// 丟棄槽位：停止播放並釋放解碼器與快取。
  void _discard(_Slot slot) {
    slot.player
      ..pause()
      ..setVolume(0)
      ..stop();
    slot.reset();
  }

  Player? get _player => _curSlot?.player;

  /// 只處理目前槽位、且已開啟完成的事件（預載槽位的事件一律忽略）
  bool _isMine(_Slot slot) {
    if (!identical(slot, _curSlot) || !_opened || slot.media == null) {
      return false;
    }
    final playlist = slot.player.state.playlist;
    if (playlist.medias.isEmpty) return false;
    return playlist.medias[playlist.index.clamp(0, playlist.medias.length - 1)]
            .uri ==
        slot.media;
  }

  Future<void> _ensurePlayers() => _creating ??= _createPlayers();

  Future<void> _createPlayers() async {
    Object? err;
    StackTrace? st;
    final results = await Future.wait(
      List.generate(_poolSize, (_) async {
        try {
          return await _createSlot();
        } catch (e, s) {
          err ??= e;
          st ??= s;
          return null;
        }
      }),
    );
    final created = results.whereType<_Slot>().toList();
    if (err != null || created.length != _poolSize || isClosed) {
      // 失敗或建立期間頁面已關閉：已建立的全部釋放，避免洩漏
      for (final s in created) {
        s.dispose();
      }
      if (err != null) {
        _creating = null;
        await Future<void>.error(err!, st);
      }
      return;
    }
    _slots.addAll(created);
    _cur = 0;
    videoController.value = _slots[0].video;
    for (var n = 1; n < _slots.length; n++) {
      _slots[n].player.setVolume(0);
    }
  }

  Future<_Slot?> _createSlot() async {
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
        player.dispose();
        return null;
      }
      player
        ..setMediaHeader(userAgent: BrowserUa.pc, referer: HttpString.baseUrl)
        ..setPlaylistMode(.none);
      final slot = _Slot(player, controller);
      slot.subs
        ..add(
          player.stream.playing.listen((v) {
            if (_isMine(slot)) playing.value = v;
          }),
        )
        ..add(
          player.stream.position.listen((p) {
            if (!_isMine(slot)) return;
            if (!firstFrame.value && p > Duration.zero) {
              firstFrame.value = true;
            }
            position.value = p;
          }),
        )
        ..add(
          player.stream.completed.listen((done) {
            if (done && _isMine(slot)) _onCompleted();
          }),
        )
        ..add(
          player.stream.duration.listen((d) {
            if (_isMine(slot)) duration.value = d;
          }),
        )
        ..add(player.stream.error.listen((_) => _onSlotError(slot)));
      return slot;
    } catch (_) {
      player.dispose();
      rethrow;
    }
  }

  /// 開啟失敗：`player_preload` 來源改用 videoUrl；否則改只選 H.264。
  /// 各重試一次（每部），從出錯前的位置繼續。
  void _onSlotError(_Slot slot) {
    final aid = slot.aid;
    if (isClosed || aid == null || slot.media == null) return;
    if (slot.fromPreload) {
      if (!_noPreload.add(aid)) return;
    } else if (!_avcOnly.add(aid)) {
      return;
    }
    _sources.remove(aid);
    slot.fromPreload = false;
    if (identical(slot, _curSlot)) {
      final i = _playingIndex;
      if (i >= 0 && i < items.length && items[i].aid == aid) {
        // 從出錯前的位置繼續，不要跳回開頭
        final pos = slot.player.state.position;
        if (pos > Duration.zero) _startAt = pos;
        _startItem(i);
      }
    } else {
      // 預載槽位：丟棄，之後重新預載或換到該頁時走一般開啟流程
      _discard(slot);
    }
  }

  /// 播放網址快取（預先載入下一部）
  final Map<int, Future<ReelsSource?>> _sources = {};
  final Map<int, String> _sourceErrors = {};

  Future<ReelsSource?> _source(StoryItem item) async {
    final aid = item.aid;
    var f = _sources[aid];
    if (f != null) {
      final v = await f;
      final left = v == null || v.expire <= 0
          ? 1 << 30
          : v.expire - DateTime.now().millisecondsSinceEpoch;
      if (left >= 60000) {
        if (kDebugMode && v != null) debugPrint('[reels] source hit aid=$aid');
        return v;
      }
      // 快取的網址快過期：重新取得
      if (identical(_sources[aid], f)) _sources.remove(aid);
    }
    if (kDebugMode) debugPrint('[reels] source fetch aid=$aid');
    f = _sources[aid] ??= _fetchSource(item)..then((v) {
      if (v == null) _sources.remove(aid);
    });
    return f;
  }

  /// 影片網址的 `deadline` 查詢參數（秒）轉毫秒；沒有時回傳 0。
  int _deadlineMs(String? url) {
    final d = int.tryParse(
      Uri.tryParse(url ?? '')?.queryParameters['deadline'] ?? '',
    );
    return d == null || d <= 0 ? 0 : d * 1000;
  }

  /// 組成 mpv 的播放來源（影音分離時用 EDL 合併）。
  Future<String> _compose(String video, String? audio) async {
    final v = await BtrProxy.wrap(video);
    if (audio == null) return v;
    final a = await BtrProxy.wrap(audio);
    return 'edl://!no_chapters;%${v.length}%$v;'
        '!new_stream;!no_chapters;%${a.length}%$a';
  }

  /// story feed 的 `player_preload`：沒過期（離過期超過 60 秒）才使用。
  Future<ReelsSource?> _preloadSource(StoryItem item) async {
    final p = item.playerPreload;
    if (p == null || _noPreload.contains(item.aid)) return null;
    try {
      final dashJson = p['dash'];
      if (dashJson is! Map<String, dynamic>) return null;
      final cid = p['cid'];
      if (cid is num && cid.toInt() != item.cid) return null;
      final dash = Dash.fromJson(dashJson, null);
      final picked = _pickVideo(dash, avcOnly: _avcOnly.contains(item.aid));
      final video = picked?.baseUrl;
      if (picked == null || video == null) return null;
      // 選到的畫質低於允許值（上限 1080P）時改走 videoUrl 取得更高畫質
      if (picked.id < (_maxQa < 80 ? _maxQa : 80)) return null;
      var expire = p['expire_time'] is num
          ? (p['expire_time'] as num).toInt()
          : 0;
      if (expire <= 0) expire = _deadlineMs(video) ~/ 1000;
      if (expire <= 0) return null;
      final left = expire * 1000 - DateTime.now().millisecondsSinceEpoch;
      if (left < 60000) return null;
      final media = await _compose(video, _pickAudio(dash));
      return (
        media: media,
        cid: item.cid,
        preload: true,
        expire: expire * 1000,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Reels preload source: $e');
      return null;
    }
  }

  Future<ReelsSource?> _fetchSource(StoryItem item) async {
    await _qaReady;
    if (await _preloadSource(item) case final pre?) return pre;
    try {
      final res = await VideoHttp.videoUrl(
        bvid: item.bvid,
        cid: item.cid,
        qn: _maxQa,
        tryLook: false,
        videoType: VideoType.ugc,
      );
      switch (res) {
        case Success(:final response):
          final dash = response.dash;
          if (dash != null) {
            final video = _pickVideo(
              dash,
              avcOnly: _avcOnly.contains(item.aid),
            )?.baseUrl;
            if (video != null) {
              final media = await _compose(video, _pickAudio(dash));
              return (
                media: media,
                cid: item.cid,
                preload: false,
                expire: _deadlineMs(video),
              );
            }
          }
          final url = response.durl?.firstOrNull?.playUrls.firstOrNull;
          if (url != null) {
            return (
              media: await BtrProxy.wrap(url),
              cid: item.cid,
              preload: false,
              expire: _deadlineMs(url),
            );
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

  /// 不高於 [_maxQa] 的最高畫質（全部編碼一起比）。
  /// 同畫質依 AVC → HEVC → AV1 → 其他，同編碼取碼率最高；
  /// [avcOnly] 時只選 AVC（沒有 AVC 才退回全部）。
  VideoItem? _pickVideo(Dash dash, {bool avcOnly = false}) {
    var list = dash.video;
    if (list == null || list.isEmpty) return null;
    if (avcOnly) {
      final avc = list.where((v) => v.codecid == 7).toList();
      if (avc.isNotEmpty) list = avc;
    }
    var cands = list.where((v) => v.id <= _maxQa).toList();
    if (cands.isEmpty) {
      // 沒有符合的：取最低畫質
      final minId = list.map((v) => v.id).reduce((a, b) => a < b ? a : b);
      cands = list.where((v) => v.id == minId).toList();
    }
    int rank(VideoItem v) => switch (v.codecid) {
      7 => 0,
      12 => 1,
      13 => 2,
      _ => 3,
    };
    cands.sort((a, b) {
      final c = b.id.compareTo(a.id);
      if (c != 0) return c;
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      return (b.bandWidth ?? 0).compareTo(a.bandWidth ?? 0);
    });
    return cands.first;
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
    // 要預取後面 6 部的網址，剩不到 6 部就先載入更多
    if (items.length - i <= 6) loadMore();
    if (_active) _startItem(i);
  }

  /// 設定是否允許播放。允許時開始或繼續播放目前影片；不允許時所有播放器都暫停。
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
      for (final s in _slots) {
        s.player.pause();
      }
    }
  }

  Future<void> _startItem(int i) async {
    if (i < 0 || i >= items.length) return;
    final gen = ++_gen;
    final item = items[i];
    _playingIndex = i;
    _opened = false;
    userPaused.value = false;
    playing.value = false;
    firstFrame.value = false;
    playError.value = null;
    position.value = Duration.zero;
    duration.value = Duration.zero;
    itemCtr(item).loadDetail();
    try {
      await _ensurePlayers();
      if (gen != _gen || isClosed) return;

      // 丟棄不屬於「目前＋後面 3 部」的非目前槽位（往回滑、跳頁都以新的 i 為準）
      final keep = <int>{item.aid};
      for (var k = 1; k <= 3; k++) {
        if (i + k < items.length) keep.add(items[i + k].aid);
      }
      final cur = _curSlot!;
      for (final s in _slots) {
        if (identical(s, cur)) continue;
        if (s.aid != null && !keep.contains(s.aid)) _discard(s);
      }

      var slot = cur;
      final target = _slotFor(item.aid);
      if (target != null) {
        // 預載槽位就是這部（通常是往下一部）：交換槽位，直接播放
        final old = slot;
        _cur = _slots.indexOf(target);
        _discard(old);
        slot = target;
        if (kDebugMode) debugPrint('[reels] swap aid=${item.aid}');
        videoController.value = slot.video;
        if (slot.opening case final f?) await f;
        if (gen != _gen || isClosed) return;
        if (slot.opened && slot.aid == item.aid) {
          slot.player.setVolume(100);
          final start = _startAt;
          _startAt = null;
          if (start != null) slot.player.seek(start);
          if (_active) {
            slot.player.play();
          } else {
            slot.player.pause();
          }
          _opened = true;
          playing.value = slot.player.state.playing;
          duration.value = slot.player.state.duration;
          _preloadAhead(i);
          return;
        }
        // 預載失敗：在這個槽位走一般開啟
      }

      slot
        ..reset()
        ..aid = item.aid;
      final tok = slot.token;
      if (kDebugMode) {
        debugPrint(
          '[reels] open aid=${item.aid} slot=${_slots.indexOf(slot)} play',
        );
      }
      slot.player
        ..setVolume(100)
        ..stop();
      final source = await _source(item);
      if (gen != _gen || tok != slot.token) return;
      if (source == null) {
        slot.aid = null;
        _fail(gen, i, _sourceErrors[item.aid] ?? '無法播放此影片');
        return;
      }
      final start = _startAt;
      _startAt = null;
      final media = Media(source.media, start: start);
      slot
        ..fromPreload = source.preload
        ..media = media.uri;
      await slot.player.open(media, play: _active);
      if (gen != _gen || tok != slot.token) return;
      // open 期間被設為不可播放（切走分頁）時，補一次暫停
      if (!_active) slot.player.pause();
      slot.opened = true;
      _opened = true;
      playing.value = slot.player.state.playing;
      duration.value = slot.player.state.duration;
      _preloadAhead(i);
    } catch (e) {
      if (kDebugMode) debugPrint('Reels play: $e');
      if (gen == _gen) _fail(gen, i, '播放失敗');
    }
  }

  /// 在非目前槽位靜音暫停預載 items[i+1..i+3]，並預取 items[i+4..i+6] 的網址。
  void _preloadAhead(int i) {
    if (isClosed || _slots.length != _poolSize) return;
    final cur = _curSlot;
    final targets = <StoryItem>[
      for (var k = 1; k <= 3; k++)
        if (i + k < items.length) items[i + k],
    ];
    final targetAids = targets.map((e) => e.aid).toSet();
    // 保留已載目標的槽位；其餘非目前槽位丟棄後當作空槽位
    final free = <_Slot>[];
    for (final s in _slots) {
      if (identical(s, cur)) continue;
      if (s.aid != null && targetAids.contains(s.aid)) continue;
      if (s.aid != null) _discard(s);
      free.add(s);
    }
    for (final item in targets) {
      if (_slotFor(item.aid) != null) continue;
      if (free.isEmpty) break;
      final slot = free.removeAt(0);
      // 級聯依序執行：reset() 之後 token 才是新值
      slot
        ..reset()
        ..aid = item.aid
        ..opening = _openPreload(slot, slot.token, item);
    }
    for (var k = 4; k <= 6; k++) {
      if (i + k < items.length) _source(items[i + k]);
    }
  }

  Future<void> _openPreload(_Slot slot, int tok, StoryItem item) async {
    try {
      slot.player
        ..setVolume(0)
        ..pause();
      final source = await _source(item);
      if (isClosed || tok != slot.token) return;
      if (source == null) {
        slot.aid = null;
        return;
      }
      final media = Media(source.media);
      slot
        ..fromPreload = source.preload
        ..media = media.uri;
      if (kDebugMode) {
        debugPrint(
          '[reels] open aid=${item.aid} slot=${_slots.indexOf(slot)} preload',
        );
      }
      await slot.player.open(media, play: false);
      if (isClosed || tok != slot.token) return;
      slot.player
        ..setVolume(0)
        ..pause();
      slot.opened = true;
    } catch (e) {
      if (kDebugMode) debugPrint('Reels preload: $e');
      if (!isClosed && tok == slot.token) slot.reset();
    }
  }

  /// 播完成：直接接下一部（走預載換槽位）；沒有下一部時重播目前這部並載入更多。
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
    // 自動跳下一部前先預載，避免冷啟
    _preloadAhead(i);
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
    final slot = _curSlot;
    if (slot == null || !_isMine(slot)) return;
    if (slot.player.state.playing) {
      userPaused.value = true;
      slot.player.pause();
    } else {
      userPaused.value = false;
      slot.player.play();
    }
  }

  void seekTo(Duration position) {
    final slot = _curSlot;
    if (slot != null && _isMine(slot)) slot.player.seek(position);
  }

  @override
  void onClose() {
    _gen++;
    _active = false;
    for (final s in _slots) {
      s.dispose();
    }
    _slots.clear();
    for (final c in _itemCtrs.values) {
      c.onClose();
    }
    pageController.dispose();
    position.dispose();
    duration.dispose();
    super.onClose();
  }
}

/// 一個播放器槽位（目前播放或預載）。
class _Slot {
  _Slot(this.player, this.video);

  final Player player;
  final VideoController video;
  final List<StreamSubscription> subs = [];

  /// 這個槽位載入（或載入中）的影片
  int? aid;
  String? media;

  /// 已開啟完成
  bool opened = false;

  /// 來源來自 `player_preload`（失敗時要改用 videoUrl 重試）
  bool fromPreload = false;

  /// 預載開啟中的 Future（不會丟例外）
  Future<void>? opening;

  /// 槽位被重新指派時加一，讓過時的非同步開啟丟棄
  int token = 0;

  void reset() {
    token++;
    aid = null;
    media = null;
    opened = false;
    fromPreload = false;
    opening = null;
  }

  void dispose() {
    token++;
    for (final sub in subs) {
      sub.cancel();
    }
    subs.clear();
    player.dispose();
  }
}
