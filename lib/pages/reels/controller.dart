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
typedef ReelsSource = ({String media, int cid, bool preload});

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
            // 原本是最後一部而沒有預載時，補預載
            if (_opened) _preloadNext(_playingIndex);
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

  /// 兩個播放器槽位：一個正在播放（[_cur]），另一個靜音暫停預載下一部。
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

  bool get isActive => _active;

  Duration get currentPosition => position.value;

  _Slot? get _curSlot => _slots.length == 2 ? _slots[_cur] : null;

  _Slot get _otherSlot => _slots[1 - _cur];

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
    final created = <_Slot>[];
    try {
      for (var n = 0; n < 2; n++) {
        final slot = await _createSlot();
        if (slot == null) {
          // 建立期間頁面已關閉：已建立的也釋放，避免洩漏
          for (final s in created) {
            s.dispose();
          }
          return;
        }
        created.add(slot);
      }
    } catch (_) {
      for (final s in created) {
        s.dispose();
      }
      _creating = null;
      rethrow;
    }
    if (isClosed) {
      for (final s in created) {
        s.dispose();
      }
      return;
    }
    _slots.addAll(created);
    _cur = 0;
    videoController.value = _slots[0].video;
    _slots[1].player.setVolume(0);
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

  /// 用 `player_preload` 開啟失敗：清掉快取，改用 videoUrl 重試一次（每部一次）。
  void _onSlotError(_Slot slot) {
    final aid = slot.aid;
    if (isClosed || aid == null || !slot.fromPreload) return;
    if (!_noPreload.add(aid)) return;
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
      // 預載槽位：丟棄，換到該頁時走一般開啟流程
      slot.reset();
    }
  }

  /// 播放網址快取（預先載入下一部）
  final Map<int, Future<ReelsSource?>> _sources = {};
  final Map<int, String> _sourceErrors = {};

  Future<ReelsSource?> _source(StoryItem item) =>
      _sources[item.aid] ??= _fetchSource(item)..then((v) {
        if (v == null) _sources.remove(item.aid);
      });

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
      final video = _pickVideo(dash);
      if (video == null) return null;
      var expire = p['expire_time'] is num
          ? (p['expire_time'] as num).toInt()
          : 0;
      if (expire <= 0) {
        expire =
            int.tryParse(
              Uri.tryParse(video)?.queryParameters['deadline'] ?? '',
            ) ??
            0;
      }
      if (expire <= 0) return null;
      final left = expire * 1000 - DateTime.now().millisecondsSinceEpoch;
      if (left < 60000) return null;
      final media = await _compose(video, _pickAudio(dash));
      return (media: media, cid: item.cid, preload: true);
    } catch (e) {
      if (kDebugMode) debugPrint('Reels preload source: $e');
      return null;
    }
  }

  Future<ReelsSource?> _fetchSource(StoryItem item) async {
    if (await _preloadSource(item) case final pre?) return pre;
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
              final media = await _compose(video, _pickAudio(dash));
              return (media: media, cid: item.cid, preload: false);
            }
          }
          final url = response.durl?.firstOrNull?.playUrls.firstOrNull;
          if (url != null) {
            return (
              media: await BtrProxy.wrap(url),
              cid: item.cid,
              preload: false,
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

  /// 設定是否允許播放。允許時開始或繼續播放目前影片；不允許時兩個播放器都暫停。
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

      var slot = _curSlot!;
      final other = _otherSlot;
      if (other.aid == item.aid) {
        // 預載槽位就是這部（通常是往下一部）：交換槽位，直接播放
        final old = slot;
        _cur = 1 - _cur;
        old
          ..player.pause()
          ..player.setVolume(0)
          ..reset();
        slot = other;
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
          _preloadNext(i);
          return;
        }
        // 預載失敗：在這個槽位走一般開啟
      } else if (other.aid != null) {
        // 預載的不是這部（跳頁、往回）：停掉它，之後重新預載
        other
          ..player.pause()
          ..reset();
      }

      slot
        ..reset()
        ..aid = item.aid;
      final tok = slot.token;
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
      _preloadNext(i);
    } catch (e) {
      if (kDebugMode) debugPrint('Reels play: $e');
      if (gen == _gen) _fail(gen, i, '播放失敗');
    }
  }

  /// 在另一個槽位靜音暫停預載下一部。
  void _preloadNext(int i) {
    if (isClosed || _slots.length != 2) return;
    final n = i + 1;
    if (n >= items.length) return;
    final item = items[n];
    final slot = _otherSlot;
    if (slot.aid == item.aid) return;
    slot
      ..reset()
      ..aid = item.aid;
    final tok = slot.token;
    slot.opening = _openPreload(slot, tok, item);
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
