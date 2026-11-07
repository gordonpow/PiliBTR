import 'dart:math' show Random;

import 'package:PiliPlus/http/video.dart';

/// session 建立時快照的影片識別資料（END 一律使用這份，不讀播放器目前欄位）
class MobileHeartbeatMeta {
  const MobileHeartbeatMeta({
    required this.aid,
    required this.cid,
    required this.type,
    required this.epid,
    required this.seasonId,
    required this.subType,
    required this.trackId,
    required this.fromSpmid,
    required this.videoDuration,
  });

  final int aid;
  final int cid;

  /// UGC 3、PGC 4
  final int type;
  final int? epid;
  final int? seasonId;
  final int? subType;
  final String trackId;
  final String fromSpmid;

  /// 秒
  final int videoDuration;
}

class _Session {
  _Session(this.meta, this.id, this.startTs);

  final MobileHeartbeatMeta meta;
  final String id;
  final int startTs;

  /// 以下皆為秒
  double played = 0;
  double paused = 0;
  double actual = 0;
  int lastPos = 0;
  int maxPos = 0;
}

/// App 端心跳 session 狀態與計算。獨立於 web 心跳。
/// START：(aid, cid) 第一次 playing；END：暫停、播放完成、結束 session。
class MobileHeartbeat {
  _Session? _s;
  bool _playing = false;
  final Stopwatch _clock = Stopwatch()..start();
  double _mark = 0;

  static final Random _rnd = Random();

  static String _hex32() {
    final sb = StringBuffer();
    for (var i = 0; i < 32; i++) {
      sb.write(_rnd.nextInt(16).toRadixString(16));
    }
    return sb.toString();
  }

  double get _now => _clock.elapsedMicroseconds / 1e6;

  /// 把上次標記到現在的時間累加進目前狀態（playing 或 paused）
  void _flush(double speed) {
    final s = _s;
    final now = _now;
    final d = now - _mark;
    _mark = now;
    if (s == null || d <= 0) return;
    if (_playing) {
      s
        ..played += d
        ..actual += d * speed;
    } else {
      s.paused += d;
    }
  }

  void _track(int pos) {
    final s = _s;
    if (s == null) return;
    s
      ..lastPos = pos
      ..maxPos = pos > s.maxPos ? pos : s.maxPos;
  }

  /// 追蹤播放位置（只記錄，不送請求）
  void trackPosition(int pos) {
    if (_s != null && _playing) _track(pos);
  }

  /// 倍速改變前呼叫，讓前一段依舊倍速計入
  void beforeSpeedChange(double oldSpeed) {
    if (_s != null && _playing) _flush(oldSpeed);
  }

  Future<void> _send(
    _Session s, {
    required bool isStart,
    required int quality,
  }) {
    final played = isStart ? 0 : s.played.round();
    final paused = isStart ? 0 : s.paused.round();
    final m = s.meta;
    return VideoHttp.heartBeatMobile(
      isStart: isStart,
      session: s.id,
      startTs: s.startTs,
      aid: m.aid,
      cid: m.cid,
      type: m.type,
      epid: m.epid,
      seasonId: m.seasonId,
      subType: m.subType,
      quality: quality,
      totalTime: played + paused,
      pausedTime: paused,
      playedTime: played,
      actualPlayedTime: isStart ? 0 : s.actual.round(),
      videoDuration: m.videoDuration,
      lastProgress: isStart ? 0 : s.lastPos,
      maxProgress: isStart ? 0 : s.maxPos,
      fromSpmid: m.fromSpmid,
      trackId: m.trackId,
    );
  }

  /// 進入 playing。[newMeta] 回傳 null 代表不符合送出條件。
  void onPlaying({
    required double speed,
    required int pos,
    required int quality,
    required MobileHeartbeatMeta? Function() newMeta,
  }) {
    final meta = newMeta();
    if (meta == null) return;
    var s = _s;
    if (s != null && (s.meta.aid != meta.aid || s.meta.cid != meta.cid)) {
      // 換片但舊 session 尚未結束：先結束舊的
      close(speed: speed, pos: pos, quality: quality);
      s = null;
    }
    if (s == null) {
      s = _s = _Session(
        meta,
        _hex32(),
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
      _playing = true;
      _mark = _now;
      _send(s, isStart: true, quality: quality);
      return;
    }
    if (_playing) return;
    _flush(speed); // 累加暫停秒數
    _playing = true;
  }

  /// playing -> paused：送 END，session 保留
  Future<void>? onPaused({
    required double speed,
    required int pos,
    required int quality,
  }) {
    final s = _s;
    if (s == null || !_playing) return null;
    _flush(speed);
    _playing = false;
    _track(pos);
    return _send(s, isStart: false, quality: quality);
  }

  /// 播放完成：播放中才送 END（已暫停時 END 已送過），之後結束 session
  Future<void>? onCompleted({
    required double speed,
    required int pos,
    required int quality,
  }) => close(speed: speed, pos: pos, quality: quality);

  /// 結束 session。播放中會先送 END。
  Future<void>? close({
    required double speed,
    required int pos,
    required int quality,
  }) {
    final s = _s;
    if (s == null) return null;
    Future<void>? res;
    if (_playing) {
      _flush(speed);
      _track(pos);
      res = _send(s, isStart: false, quality: quality);
    }
    _s = null;
    _playing = false;
    return res;
  }
}
