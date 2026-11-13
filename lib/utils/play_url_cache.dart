import 'dart:io' show Platform;

import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/common/account_type.dart';
import 'package:PiliPlus/models/common/video/video_type.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/services/download/btr_config.dart';
import 'package:PiliPlus/services/download/btr_proxy.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/connectivity_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/play_url_select.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

/// 影片頁 playurl 請求的參數。只有參數完全相同的快取才能重用。
typedef PlayUrlParams = ({int qn, bool tryLook, bool voiceBalance});

/// 共用的 playurl 快取（僅 UGC）：卡片 tap-down 預取與影片頁共用同一份回應。
///
/// key 為 bvid + cid + mid（主帳號與影片帳號）；有效 10 分鐘，最多 30 筆。同時保存進行中的 Future，
/// 影片頁可以等待尚未完成的預取，避免重複請求。
abstract final class PlayUrlCache {
  static const _ttl = Duration(minutes: 10);
  static const _maxEntries = 30;

  static final _entries =
      <
        String,
        ({
          DateTime time,
          PlayUrlParams params,
          Future<LoadingState<PlayUrlModel>> future,
        })
      >{};

  /// playurl 實際使用影片帳號（AccountType.video）的身分，所以 key 同時含
  /// 主帳號與影片帳號的 mid。
  static String _key(String bvid, int cid) =>
      '$bvid|$cid|${Accounts.main.mid}|${Accounts.video.mid}';

  /// 影片頁與預取共用的請求參數：qn 為目標畫質。
  static Future<PlayUrlParams> defaultParams() async {
    var qn = PlPlayerController.instance?.cacheVideoQa;
    if (qn == null) {
      if (PlatformUtils.isMobile || Platform.isLinux) {
        qn = await ConnectivityUtils.isWiFi
            ? Pref.defaultVideoQa
            : Pref.defaultVideoQaCellular;
      } else {
        qn = Pref.defaultVideoQa;
      }
    }
    return (
      qn: qn,
      tryLook: !Accounts.get(AccountType.video).isLogin && Pref.p1080,
      voiceBalance: Platform.isAndroid && Pref.audioNormalization != '0',
    );
  }

  /// 取得 UGC playurl：命中快取（含進行中的請求）就重用，否則請求並存入。
  /// [fromDetail] 為 true 時，命中會印 debug log。
  static Future<LoadingState<PlayUrlModel>> get({
    required String bvid,
    required int cid,
    required PlayUrlParams params,
    bool fromDetail = false,
  }) {
    final key = _key(bvid, cid);
    final now = DateTime.now();
    final cached = _entries[key];
    if (cached != null &&
        now.difference(cached.time) < _ttl &&
        cached.params == params) {
      if (fromDetail && kDebugMode) {
        debugPrint('PlayUrlCache hit bvid=$bvid cid=$cid qn=${params.qn}');
      }
      return cached.future;
    }
    final future = VideoHttp.videoUrl(
      bvid: bvid,
      cid: cid,
      qn: params.qn,
      tryLook: params.tryLook,
      videoType: VideoType.ugc,
      voiceBalance: params.voiceBalance,
    );
    _entries
      ..remove(key)
      ..[key] = (time: now, params: params, future: future);
    while (_entries.length > _maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    // 失敗不保留，下次重新請求。
    future.then(
      (res) {
        if (res is Success<PlayUrlModel>) {
          _completed[future] = res.response;
          // BTR：預先建立 CDN 連線（BTR 關閉時什麼都不做）。
          preconnectStreams(res.response, qn: params.qn).ignore();
        } else if (_entries[key]?.future == future) {
          _entries.remove(key);
        }
      },
      onError: (Object _) {
        if (_entries[key]?.future == future) _entries.remove(key);
      },
    );
    return future;
  }

  /// 已完成（成功）的回應；Future 完成後才有值。
  static final _completed = Expando<PlayUrlModel>('PlayUrlCache.completed');

  /// 快取中已完成且參數相符的 playurl；未完成或沒有則回傳 null（不等待）。
  static PlayUrlModel? completedOf({
    required String bvid,
    required int cid,
    required PlayUrlParams params,
  }) {
    final cached = _entries[_key(bvid, cid)];
    if (cached == null ||
        DateTime.now().difference(cached.time) >= _ttl ||
        cached.params != params) {
      return null;
    }
    return _completed[cached.future];
  }

  /// 是否有可重用的快取（含進行中的請求）；條件同 [get]。
  static bool has({
    required String bvid,
    required int cid,
    required PlayUrlParams params,
  }) {
    final cached = _entries[_key(bvid, cid)];
    return cached != null &&
        DateTime.now().difference(cached.time) < _ttl &&
        cached.params == params;
  }

  /// tap-down 預取：用影片頁相同的參數請求並存入快取。
  static Future<void> prefetch({required String bvid, required int cid}) async {
    try {
      await get(bvid: bvid, cid: cid, params: await defaultParams());
    } catch (e) {
      if (kDebugMode) debugPrint('PlayUrlCache prefetch: $e');
    }
  }

  // ---- 可見卡片預取（首頁推薦）----

  static const _maxPlayUrlOnly = 6;
  static const _warmTimeout = Duration(seconds: 15);
  static const _backoffDuration = Duration(minutes: 5);

  /// 頁面不可見或 App 進背景時為 true：不再排程新的可見卡片預取。
  static bool isPaused = false;

  static DateTime? _backoffUntil;
  static int _active = 0;
  static final _pending = <String, (String, int, bool)>{};
  static final _inFlight = <String>{};

  /// 目前可見卡片的 key -> 順序（越小越前面）。佇列依此排序：可見優先，
  /// 不在畫面上且尚未開始的項目留在佇列但排最後。
  static var _visibleOrder = <String, int>{};

  /// 最近一次收集的可見卡片數；playurl 預取的同時數即為此值（至少 1）。
  static int _visibleLimit = 1;

  /// 設定的同時預載影片數；0 為不限制。
  static int _concurrencyCap = 0;
  static int _warmActive = 0;

  /// 預熱佇列（影片＋音訊開頭）：同時數依設定（0 不限制）、去重。
  static final _warmPending = <String, (String, int)>{};
  static final _warmInFlight = <String>{};

  /// clearPending／clear 時加一（帳號切換、頁面不可見）；捲動開始不會改變它。
  /// playurl 完成時若世代已變，就不再加入預熱佇列。
  static int _generation = 0;

  /// 每次 [prefetchVisible] 加一；較舊的呼叫在 await 後發現有新呼叫就返回。
  static int _callSeq = 0;

  static bool get _inBackoff {
    final until = _backoffUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  /// 預取可見卡片：依設定決定是否預熱開頭。
  /// 預熱開啟（一律，或僅 Wi-Fi 且目前是 Wi-Fi，且 BTR 播放開啟）時處理所有卡片，
  /// 並在 playurl 完成後預熱影片與音訊開頭；否則只預取前 6 張的 playurl。
  /// playurl 同時數為本次可見卡片數、去重、412 退避；預熱不限同時數。
  /// 捲動中會重複呼叫：每次呼叫以「目前可見」取代尚未開始的佇列（playurl 與預熱），
  /// 已開始的不取消；可見項目依畫面順序處理。
  /// tap-down 的 [prefetch] 不受影響。
  static Future<void> prefetchVisible(List<(String bvid, int cid)> items) async {
    if (isPaused || _inBackoff) return;
    final generation = _generation;
    final seq = ++_callSeq;
    final PlayUrlParams params;
    bool warmOn;
    try {
      params = await defaultParams();
      final mode = Pref.visiblePreloadMode;
      warmOn =
          BtrConfig.playback &&
          (mode == 2 || (mode == 1 && await ConnectivityUtils.isWiFi));
    } catch (_) {
      return;
    }
    if (isPaused || _inBackoff || generation != _generation) return;
    if (seq != _callSeq) return;
    if (!warmOn && items.length > _maxPlayUrlOnly) {
      items = items.sublist(0, _maxPlayUrlOnly);
    }
    _visibleOrder = {
      for (var i = 0; i < items.length; i++) _key(items[i].$1, items[i].$2): i,
    };
    _visibleLimit = items.isEmpty ? 1 : items.length;
    final cap = Pref.visiblePreloadConcurrency;
    _concurrencyCap = cap > 0 ? cap : 0;
    if (_concurrencyCap > 0 && _visibleLimit > _concurrencyCap) {
      _visibleLimit = _concurrencyCap;
    }
    if (warmOn) {
      BtrProxy.setWarmCapacity(
        items.length,
        visibleOwners: _visibleOrder.keys.toSet(),
      );
    }
    // 以目前可見取代尚未開始的佇列；已開始的不取消。
    _pending.clear();
    _warmPending.clear();
    final now = DateTime.now();
    for (final (bvid, cid) in items) {
      final key = _key(bvid, cid);
      final cached = _entries[key];
      // 參數不同（例如 Wi-Fi／行動網路切換）的快取影片頁用不到，要重新預取。
      if (cached != null &&
          now.difference(cached.time) < _ttl &&
          cached.params == params) {
        // 快取命中仍要預熱開頭。
        if (warmOn) {
          _enqueueCachedWarm(
            key,
            bvid,
            cid,
            params,
            cached.future,
            seq,
          ).ignore();
        }
        continue;
      }
      if (_inFlight.contains(key)) continue;
      _pending[key] = (bvid, cid, warmOn);
    }
    _pumpVisible();
    _pumpWarm();
  }

  /// 頁面不可見、dispose 時清空尚未發出的佇列（已發出的請求不取消）。
  static void clearPending() {
    _generation++;
    _pending.clear();
    _warmPending.clear();
  }

  static void _pumpVisible() {
    while (_active < _visibleLimit &&
        _pending.isNotEmpty &&
        !isPaused &&
        !_inBackoff) {
      final key = _nextKey(_pending.keys);
      final (bvid, cid, warm) = _pending.remove(key)!;
      _active++;
      _inFlight.add(key);
      _runVisible(key, bvid, cid, warm);
    }
  }

  static Future<void> _runVisible(
    String key,
    String bvid,
    int cid,
    bool warm,
  ) async {
    final generation = _generation;
    try {
      if (kDebugMode) {
        debugPrint('PlayUrlCache visible prefetch bvid=$bvid cid=$cid');
      }
      final res = await get(
        bvid: bvid,
        cid: cid,
        params: await defaultParams(),
      );
      if (res is Error && _isRiskControl(res)) _startBackoff();
      if (warm &&
          res is Success &&
          generation == _generation &&
          _visibleOrder.containsKey(key)) {
        _enqueueWarm(key, bvid, cid);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('PlayUrlCache visible prefetch: $e');
    } finally {
      _active--;
      _inFlight.remove(key);
      _pumpVisible();
      _pumpWarm();
    }
  }

  /// 快取命中的卡片：兩條串流都已預熱（或下載中）就略過，不佔用名額。
  /// 以 BtrProxy 目前狀態判斷，釋放後可重新預熱。
  static Future<void> _enqueueCachedWarm(
    String key,
    String bvid,
    int cid,
    PlayUrlParams params,
    Future<LoadingState<PlayUrlModel>> future,
    int seq,
  ) async {
    final generation = _generation;
    try {
      final data = _completed[future];
      if (data != null && await allStreamsWarm(data, qn: params.qn)) return;
    } catch (_) {}
    if (generation != _generation ||
        seq != _callSeq ||
        isPaused ||
        _inBackoff) {
      return;
    }
    _enqueueWarm(key, bvid, cid);
    _pumpWarm();
  }

  static void _enqueueWarm(String key, String bvid, int cid) {
    if (_warmInFlight.contains(key)) return;
    _warmPending[key] = (bvid, cid);
  }

  /// 佇列中下一個要處理的 key：可見的依畫面順序優先，沒有可見的就取最早加入者。
  static String _nextKey(Iterable<String> keys) {
    String? best;
    var bestOrder = 1 << 30;
    for (final k in keys) {
      final o = _visibleOrder[k];
      if (o != null && o < bestOrder) {
        best = k;
        bestOrder = o;
      }
    }
    return best ?? keys.first;
  }

  static void _pumpWarm() {
    while (_warmPending.isNotEmpty &&
        (_concurrencyCap == 0 || _warmActive < _concurrencyCap) &&
        !isPaused &&
        !_inBackoff) {
      final key = _nextKey(_warmPending.keys);
      final (bvid, cid) = _warmPending.remove(key)!;
      _warmActive++;
      _warmInFlight.add(key);
      _runWarm(key, bvid, cid);
    }
  }

  /// 取得（多半是快取）playurl 後預熱影片與音訊開頭，等兩者下載結束才從進行中移除。
  static Future<void> _runWarm(String key, String bvid, int cid) async {
    try {
      final params = await defaultParams();
      final res = await get(bvid: bvid, cid: cid, params: params);
      if (res is Error && _isRiskControl(res)) _startBackoff();
      if (res is Success<PlayUrlModel>) {
        if (kDebugMode) debugPrint('PlayUrlCache visible warm bvid=$bvid');
        await warmStreams(
          res.response,
          qn: params.qn,
          owner: key,
        ).timeout(_warmTimeout, onTimeout: () {});
      }
    } catch (e) {
      if (kDebugMode) debugPrint('PlayUrlCache visible warm: $e');
    } finally {
      _warmActive--;
      _warmInFlight.remove(key);
      _pumpWarm();
    }
  }

  /// HTTP 412 或 code -412 / -352（風控）。videoUrl 把錯誤轉成文字，所以用字串判斷。
  static bool _isRiskControl(Error err) {
    final code = err.code;
    if (code == -412 || code == -352 || code == 412) return true;
    final msg = err.errMsg;
    if (msg == null) return false;
    return msg.contains('(-412)') ||
        msg.contains('(-352)') ||
        msg.contains('status code of 412');
  }

  static void _startBackoff() {
    final until = DateTime.now().add(_backoffDuration);
    _backoffUntil = until;
    _pending.clear();
    _warmPending.clear();
    if (kDebugMode) debugPrint('PlayUrlCache backoff until $until');
  }

  /// 帳號切換或登出時清空。
  static void clear() {
    _entries.clear();
    _generation++;
    _visibleOrder = {};
    _pending.clear();
    _warmPending.clear();
  }
}
