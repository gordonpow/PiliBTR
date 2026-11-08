import 'dart:io' show Platform;

import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/common/account_type.dart';
import 'package:PiliPlus/models/common/video/video_type.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
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

  /// tap-down 預取：用影片頁相同的參數請求並存入快取。
  static Future<void> prefetch({required String bvid, required int cid}) async {
    try {
      await get(bvid: bvid, cid: cid, params: await defaultParams());
    } catch (e) {
      if (kDebugMode) debugPrint('PlayUrlCache prefetch: $e');
    }
  }

  // ---- 可見卡片預取（首頁推薦）----

  static const _visibleConcurrency = 2;
  static const _backoffDuration = Duration(minutes: 5);

  /// 頁面不可見或 App 進背景時為 true：不再排程新的可見卡片預取。
  static bool isPaused = false;

  static DateTime? _backoffUntil;
  static int _active = 0;
  static final _pending = <String, (String, int)>{};
  static final _inFlight = <String>{};

  static bool get _inBackoff {
    final until = _backoffUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  /// 預取可見卡片的 playurl：併發 2、去重、412 退避；tap-down 的 [prefetch] 不受影響。
  static Future<void> prefetchVisible(List<(String bvid, int cid)> items) async {
    if (isPaused || _inBackoff) return;
    final PlayUrlParams params;
    try {
      params = await defaultParams();
    } catch (_) {
      return;
    }
    if (isPaused || _inBackoff) return;
    final now = DateTime.now();
    for (final (bvid, cid) in items) {
      final key = _key(bvid, cid);
      final cached = _entries[key];
      // 參數不同（例如 Wi-Fi／行動網路切換）的快取影片頁用不到，要重新預取。
      if (cached != null &&
          now.difference(cached.time) < _ttl &&
          cached.params == params) {
        continue;
      }
      if (_inFlight.contains(key)) continue;
      _pending[key] = (bvid, cid);
    }
    _pumpVisible();
  }

  /// 開始捲動時清空尚未發出的佇列（已發出的請求不取消）。
  static void clearPending() => _pending.clear();

  static void _pumpVisible() {
    while (_active < _visibleConcurrency &&
        _pending.isNotEmpty &&
        !isPaused &&
        !_inBackoff) {
      final key = _pending.keys.first;
      final (bvid, cid) = _pending.remove(key)!;
      _active++;
      _inFlight.add(key);
      _runVisible(key, bvid, cid);
    }
  }

  static Future<void> _runVisible(String key, String bvid, int cid) async {
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
    } catch (e) {
      if (kDebugMode) debugPrint('PlayUrlCache visible prefetch: $e');
    } finally {
      _active--;
      _inFlight.remove(key);
      _pumpVisible();
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
    if (kDebugMode) debugPrint('PlayUrlCache backoff until $until');
  }

  /// 帳號切換或登出時清空。
  static void clear() {
    _entries.clear();
    _pending.clear();
  }
}
