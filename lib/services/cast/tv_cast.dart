import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// 投放結果。
enum CastResult {
  ok,
  denied,
  busy,
  tooMany,
  notReady,
  network,
  cancelled,
  error,
}

class TvDevice {
  TvDevice({
    required this.id,
    required this.name,
    required this.host,
    this.port = 3322,
    this.token,
  });

  final String id;
  String name;
  String host;
  int port;
  String? token;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    'token': token,
  };

  static TvDevice? fromJson(Object? m) {
    if (m is! Map) return null;
    final id = m['id'];
    final name = m['name'];
    final host = m['host'];
    final port = m['port'];
    final token = m['token'];
    if (id is! String || name is! String || host is! String) return null;
    return TvDevice(
      id: id,
      name: name,
      host: host,
      port: port is int ? port : 3322,
      token: token is String && token.isNotEmpty ? token : null,
    );
  }
}

class CastPayload {
  const CastPayload({
    this.bvid,
    this.aid,
    this.cid,
    this.epId,
    this.seasonId,
    required this.positionMs,
    this.title,
  });

  final String? bvid;
  final int? aid;
  final int? cid;
  final int? epId;
  final int? seasonId;
  final int positionMs;
  final String? title;
}

abstract final class TvCast {
  static const int defaultPort = 3322;
  static const _app = 'PiliBTRTV';

  // 不帶 cookie、不帶帳號攔截器的專用 Dio。
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 5),
      validateStatus: (_) => true,
    ),
  );

  // 探索用：Dio 的 Options 不能設定連線逾時，不存在的位址會等滿 3 秒，
  // 254 個位址在 3 秒內掃不完，所以另用一個連線逾時 500 ms 的 Dio。
  static final Dio _scanDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(milliseconds: 500),
      receiveTimeout: const Duration(milliseconds: 500),
      validateStatus: (_) => true,
    ),
  );

  // ---- 儲存 ----

  static List<TvDevice> loadKnown() {
    try {
      final raw = GStorage.localCache.get(LocalCacheKey.castTvs);
      if (raw is! List) return [];
      return [
        for (final e in raw) ?TvDevice.fromJson(e),
      ];
    } catch (e) {
      debugPrint('投放：讀取已知電視失敗 $e');
      return [];
    }
  }

  static void _saveKnown(List<TvDevice> list) {
    GStorage.localCache.put(
      LocalCacheKey.castTvs,
      list.map((e) => e.toJson()).toList(),
    );
  }

  /// 新增或更新（以 id 比對）已知電視，保留原有 token。
  static void upsert(TvDevice tv) {
    final list = loadKnown();
    final i = list.indexWhere((e) => e.id == tv.id);
    if (i >= 0) {
      tv.token ??= list[i].token;
      list[i] = tv;
    } else {
      list.add(tv);
    }
    _saveKnown(list);
  }

  /// 更新（或清除）某台電視的 token。
  static void upsertToken(TvDevice tv, String? token) {
    tv.token = token;
    final list = loadKnown();
    final i = list.indexWhere((e) => e.id == tv.id);
    if (i >= 0) {
      list[i].token = token;
    } else {
      list.add(tv);
    }
    _saveKnown(list);
  }

  static String get deviceId {
    final v = GStorage.localCache.get(LocalCacheKey.castDeviceId);
    if (v is String && v.isNotEmpty) return v;
    final id = const Uuid().v4();
    GStorage.localCache.put(LocalCacheKey.castDeviceId, id);
    return id;
  }

  static String? _deviceName;
  static Future<String> getDeviceName() async {
    if (_deviceName case final n?) return n;
    try {
      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        return _deviceName = '${info.manufacturer} ${info.model}';
      }
    } catch (e) {
      debugPrint('投放：取得裝置名稱失敗 $e');
    }
    return _deviceName = Platform.operatingSystem;
  }

  // ---- 探索 ----

  static String _url(String host, int port, String path) =>
      'http://${host.contains(':') ? '[$host]' : host}:$port$path';

  static TvDevice? _parseInfo(Object? data, String host, int port) {
    if (data is! Map || data['app'] != _app) return null;
    final id = data['id'];
    final name = data['name'];
    if (id is! String || id.isEmpty) return null;
    return TvDevice(
      id: id,
      name: name is String && name.isNotEmpty ? name : host,
      host: host,
      port: port,
    );
  }

  static Future<TvDevice?> _info(
    String host,
    int port,
    Duration timeout,
    CancelToken? cancel,
  ) async {
    try {
      final dio = timeout <= const Duration(seconds: 1) ? _scanDio : _dio;
      final res = await dio.get(
        _url(host, port, '/api/cast/info'),
        options: Options(
          sendTimeout: timeout,
          receiveTimeout: timeout,
          responseType: ResponseType.json,
        ),
        cancelToken: cancel,
      );
      if (res.statusCode != 200) return null;
      return _parseInfo(res.data, host, port);
    } catch (_) {
      return null;
    }
  }

  /// 手動輸入或 QR code：3 秒逾時。
  static Future<TvDevice?> probe(String host, int port) async {
    final cancel = CancelToken();
    final timer = Timer(const Duration(seconds: 3), cancel.cancel);
    try {
      return await _info(host, port, const Duration(seconds: 3), cancel);
    } finally {
      timer.cancel();
    }
  }

  static bool _isPrivate(InternetAddress a) {
    final b = a.rawAddress;
    if (b.length != 4) return false;
    return b[0] == 10 ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && b[1] == 168);
  }

  /// 邊找邊回傳；3 秒後結束。
  static Stream<TvDevice> discover() {
    final controller = StreamController<TvDevice>();
    final cancel = CancelToken();
    final seen = <String>{};
    final known = loadKnown();
    var closed = false;

    void found(TvDevice tv) {
      if (closed || !seen.add(tv.id)) return;
      final i = known.indexWhere((e) => e.id == tv.id);
      if (i >= 0) {
        tv.token = known[i].token;
        if (known[i].host != tv.host || known[i].port != tv.port) {
          // 已知電視的 IP 或埠變了，更新
          upsert(tv);
        }
      }
      controller.add(tv);
    }

    Future<void> run() async {
      const timeout = Duration(milliseconds: 500);
      final selfIps = <String>{};
      final subnets = <String>{};
      try {
        for (final itf in await NetworkInterface.list(
          type: InternetAddressType.IPv4,
        )) {
          for (final a in itf.addresses) {
            if (!_isPrivate(a)) continue;
            selfIps.add(a.address);
            subnets.add(a.address.substring(0, a.address.lastIndexOf('.')));
          }
        }
      } catch (e) {
        debugPrint('投放：列出網卡失敗 $e');
      }
      final jobs = <String>[
        for (final s in subnets)
          for (var i = 1; i <= 254; i++)
            if (!selfIps.contains('$s.$i')) '$s.$i',
      ];
      var next = 0;
      Future<void> worker() async {
        while (!closed && next < jobs.length) {
          final ip = jobs[next++];
          final r = await _info(ip, defaultPort, timeout, cancel);
          if (r != null) found(r);
        }
      }

      await Future.wait([
        // 已知電視直接探測（不受 /24 與預設埠限制）
        for (final tv in known)
          _info(tv.host, tv.port, const Duration(seconds: 3), cancel).then((r) {
            if (r != null) found(r);
          }),
        for (var i = 0; i < 64; i++) worker(),
      ]);
    }

    final timer = Timer(const Duration(seconds: 3), () {
      closed = true;
      cancel.cancel();
      if (!controller.isClosed) controller.close();
    });
    controller.onCancel = () {
      closed = true;
      timer.cancel();
      cancel.cancel();
    };
    run();
    return controller.stream;
  }

  // ---- 投放 ----

  /// [onPending]：電視端開始詢問（收到 202）時呼叫。
  static Future<CastResult> play(
    TvDevice tv,
    CastPayload p, {
    CancelToken? cancel,
    VoidCallback? onPending,
  }) async {
    final deviceName = await getDeviceName();
    final deviceId = TvCast.deviceId;
    var token = tv.token;
    var retried = false;
    final options = Options(contentType: Headers.jsonContentType);
    try {
      while (true) {
        final res = await _dio.post(
          _url(tv.host, tv.port, '/api/cast/play'),
          data: {
            'v': 1,
            'deviceId': deviceId,
            'deviceName': deviceName,
            'token': ?token,
            'bvid': p.bvid,
            'aid': p.aid,
            'cid': p.cid,
            'epId': p.epId,
            'seasonId': p.seasonId,
            'positionMs': p.positionMs,
            'title': p.title,
          },
          options: options,
          cancelToken: cancel,
        );
        final data = res.data;
        final reason = data is Map ? data['reason'] : null;
        switch (res.statusCode) {
          case 200:
            return CastResult.ok;
          case 202:
            final reqId = data is Map ? data['reqId'] : null;
            if (reqId is! String) return CastResult.error;
            onPending?.call();
            return await _poll(tv, reqId, cancel);
          case 403:
            if (reason == 'bad_token' && token != null && !retried) {
              retried = true;
              token = null;
              upsertToken(tv, null);
              continue;
            }
            return CastResult.denied;
          case 409:
            return CastResult.busy;
          case 429:
            return CastResult.tooMany;
          case 503:
            return CastResult.notReady;
          default:
            return CastResult.error;
        }
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return CastResult.cancelled;
      return CastResult.network;
    } catch (_) {
      return CastResult.network;
    }
  }

  static Future<CastResult> _poll(
    TvDevice tv,
    String reqId,
    CancelToken? cancel,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 35));
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(seconds: 1));
      if (cancel?.isCancelled ?? false) return CastResult.cancelled;
      final res = await _dio.get(
        _url(tv.host, tv.port, '/api/cast/result'),
        queryParameters: {'id': reqId},
        cancelToken: cancel,
      );
      final data = res.data;
      switch (res.statusCode) {
        case 200:
          if (data is Map && data['pending'] == true) continue;
          if (data is Map && data['ok'] == true) {
            if (data['token'] case final String t when t.isNotEmpty) {
              upsertToken(tv, t);
            }
            return CastResult.ok;
          }
          return CastResult.error;
        case 403:
          return CastResult.denied;
        case 503:
          return CastResult.notReady;
        default:
          return CastResult.error;
      }
    }
    return CastResult.denied;
  }
}
