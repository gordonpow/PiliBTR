// Multi-CDN acceleration for playback ("BTR", thread ripper).
//
// The player (mpv) reads media through a local HTTP proxy. For each Range
// request from the player, the proxy splits the range into pieces and
// fetches them in parallel from several Bilibili CDN nodes. Pieces are
// returned to the player in order, as soon as the next piece is complete.
// Behaviour is modelled on Bilibili-thread-ripper-desktop (MIT,
// https://github.com/MrTangLuyao/Bilibili-thread-ripper-desktop).

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/services/download/btr_cdn.dart'
    show BtrHostStats, BtrNode, BtrNodePool, btrDio, btrProbeDio;
import 'package:PiliPlus/services/download/btr_config.dart';
import 'package:PiliPlus/utils/extension/string_ext.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

abstract final class BtrProxy {
  static HttpServer? _server;
  static Future<HttpServer>? _starting;

  static final Map<String, _BtrSource> _sources = {};
  static final Map<String, String> _idByUrl = {};
  static int _seq = 0;

  /// Clears cached sources so a changed CDN mode applies to the same video.
  /// The server stays up and in-flight requests are not affected.
  static void reset() {
    _sources.clear();
    _idByUrl.clear();
  }

  /// Max number of media URLs kept. Older ones are removed first.
  static const int _maxSources = 32;

  static final _mediaHost = RegExp(
    r'(?:^|\.)(?:bilivideo\.(?:com|cn|net)|akamaized\.net)$',
  );
  static final _mediaPath = RegExp(r'\.(?:m4s|mp4|flv)$');

  static bool isEligible(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        _mediaHost.hasMatch(uri.host) &&
        _mediaPath.hasMatch(uri.path);
  }

  /// Returns a local proxy URL for [url] when playback acceleration is
  /// enabled and [url] is a Bilibili media file. Otherwise returns [url].
  static Future<String> wrap(String url) async {
    if (!BtrConfig.playback || !isEligible(url)) return url;
    try {
      final server = await _ensureServer();
      final src = url.http2https;
      final id = _idFor(src);
      final ext = _mediaPath.firstMatch(Uri.parse(src).path)?.group(0) ?? '';
      return 'http://127.0.0.1:${server.port}/btr/$id$ext';
    } catch (e) {
      if (kDebugMode) debugPrint('BTR: proxy unavailable: $e');
      return url;
    }
  }

  /// Id of the source for [src] (already `http2https`). Creates it when new.
  /// [wrap] and [warm] use the same key, so a warmed URL is the one served.
  static String _idFor(String src) {
    var id = _idByUrl[src];
    if (id == null) {
      id = (++_seq).toString();
      _idByUrl[src] = id;
      _sources[id] = _BtrSource(src);
      while (_sources.length > _maxSources) {
        final oldest = _sources.keys.first;
        _idByUrl.remove(_sources.remove(oldest)!.url);
      }
    }
    return id;
  }

  /// Sources that hold warm bytes, oldest first.
  static final List<_BtrSource> _warmed = [];
  static const int _maxWarmed = 4;

  /// Starts to download the first [bytes] of [url] into memory, so the player
  /// gets them at once when it opens the same URL. The bytes are readable
  /// while they download. Only once per URL; the bytes are released after 30 s
  /// without use (the source and its id stay, so the player URL stays valid).
  static void warm(String url, {int bytes = 512 * 1024}) {
    if (!BtrConfig.playback || !isEligible(url)) return;
    final src = url.http2https;
    final id = _idFor(src);
    final source = _sources[id]!;
    if (source.hasWarm) return;
    if (kDebugMode) debugPrint('BTR: warm start $id');
    source.startWarm(bytes, onRelease: () => _warmed.remove(source));
    _warmed.add(source);
    while (_warmed.length > _maxWarmed) {
      _warmed.removeAt(0).evictWarm();
    }
  }

  static final Map<String, DateTime> _preconnectedAt = {};
  static const _preconnectEvery = Duration(seconds: 60);

  /// Opens a connection to the CDN host of [url] with a `bytes=0-0` request
  /// (the connection stays idle in the BTR client for 60 s). Once per host in
  /// 60 s. It does not touch the failure statistics.
  static void preconnect(String url) {
    if (!BtrConfig.playback || !isEligible(url)) return;
    final src = url.http2https;
    final host = Uri.parse(src).host;
    final now = DateTime.now();
    final last = _preconnectedAt[host];
    if (last != null && now.difference(last) < _preconnectEvery) return;
    _preconnectedAt[host] = now;
    if (kDebugMode) debugPrint('BTR: preconnect $host');
    btrProbeDio
        .get<ResponseBody>(
          src,
          options: Options(
            headers: {..._defaultHeaders, 'range': 'bytes=0-0'},
            responseType: ResponseType.stream,
          ),
        )
        .then(
          (r) => r.data?.stream.drain<void>().catchError((_) {}),
          onError: (Object _) => null,
        )
        .ignore();
  }

  /// Bytes served to the player and CDN nodes for [originalUrl], or null when
  /// that URL is not proxied.
  static ({int served, List<BtrNode> nodes})? statsFor(String originalUrl) {
    final id = _idByUrl[originalUrl.http2https];
    final source = id == null ? null : _sources[id];
    if (source == null) return null;
    return (served: source.served, nodes: source.pool.nodes);
  }

  static Future<HttpServer> _ensureServer() {
    if (_server case final server?) return Future.value(server);
    return _starting ??= HttpServer.bind(InternetAddress.loopbackIPv4, 0).then(
      (server) {
        _server = server;
        server.listen(_handle, onError: (_) {});
        if (kDebugMode) debugPrint('BTR: proxy on port ${server.port}');
        return server;
      },
      onError: (Object e) {
        _starting = null;
        throw e;
      },
    );
  }

  static Future<void> _handle(HttpRequest req) async {
    final segments = req.uri.pathSegments;
    final id = segments.length == 2 && segments[0] == 'btr'
        ? segments[1].split('.').first
        : null;
    final source = id == null ? null : _sources[id];
    if (source == null) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close().catchError((_) {});
      return;
    }
    try {
      await source.serve(req);
    } catch (e) {
      if (kDebugMode) debugPrint('BTR: serve error: $e');
    } finally {
      // Every path ends with a closed response (closing twice is harmless).
      try {
        await req.response.close();
      } catch (_) {}
    }
  }
}

const Map<String, String> _defaultHeaders = {
  'user-agent': 'Mozilla/5.0',
  'referer': 'https://www.bilibili.com/',
  'accept-encoding': 'identity',
};

/// Head bytes of a media file, filled by `BtrProxy.warm`. They can be read
/// while they download: [received] grows and [notify] wakes the waiters.
class _Warm {
  _Warm(this.target, this.onRelease) : buffer = Uint8List(target);

  /// Requested size. The real size is smaller when the file is smaller.
  final int target;
  final void Function() onRelease;

  /// Null after release.
  Uint8List? buffer;

  /// Bytes 0..received-1 of [buffer] are valid and never change again.
  int received = 0;

  /// True when the download ended (done, failed or released).
  bool done = false;

  /// Serve requests that are reading the buffer now.
  int users = 0;

  Timer? _timer;
  Completer<void> _tick = Completer<void>();

  /// Completes at the next change of [received] or [done].
  Future<void> get next => _tick.future;

  void notify() {
    final old = _tick;
    _tick = Completer<void>();
    old.complete();
  }

  static const _idle = Duration(seconds: 30);

  /// Releases the bytes after 30 s without use. Does nothing while a serve
  /// request reads them.
  void armRelease() {
    _timer?.cancel();
    _timer = Timer(_idle, () {
      if (users == 0) release();
    });
  }

  /// Set when the LRU dropped this buffer while a serve was reading it.
  bool evicted = false;

  /// LRU eviction: frees the bytes now, or when the last reader is done.
  void evict() {
    if (users == 0) {
      release();
    } else {
      evicted = true;
    }
  }

  void release() {
    _timer?.cancel();
    if (buffer == null) return;
    buffer = null;
    done = true;
    onRelease();
    notify();
  }
}

class _BtrSource {
  _BtrSource(this.url) : pool = BtrNodePool(url);

  final String url;
  final BtrNodePool pool;

  /// Bytes written to the player's responses.
  int served = 0;

  static const _firstPiece = 128 * 1024;
  static const _maxWindowBytes = 64 * 1024 * 1024;
  static const _pieceAttempts = 6;

  /// After a failed probe the source goes direct for this long.
  static const _probeRetryAfter = Duration(seconds: 30);
  static const _headTimeout = Duration(seconds: 2);
  /// 預熱（tap-down）在背景進行，播放器沒有在等它；首 byte 逾時比開頭片段寬鬆，
  /// 避免 CDN 首 byte 需 1.5～2.5 秒時被提早取消（模擬器實測 11 次取消皆為此原因）。
  static const _warmTimeout = Duration(seconds: 5);

  /// No first byte after this long: the same range also goes to a second node.
  static const _hedgeDelay = Duration(milliseconds: 800);
  static const _headSwitches = 2;
  static const _probeTimeout = Duration(seconds: 4);

  int? _total;
  DateTime? _probeFailedAt;
  Future<void>? _probing;
  String _contentType = 'video/mp4';
  Map<String, String>? _headersOrNull;
  Map<String, String> get _headers => _headersOrNull ?? _defaultHeaders;

  _Warm? _warm;
  bool get hasWarm => _warm != null;

  void startWarm(int bytes, {required void Function() onRelease}) {
    final w = _warm = _Warm(bytes, onRelease)..armRelease();
    _runWarm(w).catchError((Object _) {}).whenComplete(() {
      w
        ..done = true
        ..notify();
    });
  }

  void evictWarm() => _warm?.evict();

  /// Downloads 0..target-1 from one node (one more node after a failure) into
  /// the warm buffer. The first byte must arrive within 2 s.
  Future<void> _runWarm(_Warm w) async {
    await _ensureProbed();
    final total = _total;
    if (total == null) return;
    final len = math.min(w.target, total);
    final tried = <BtrNode>{};
    for (int attempt = 0; attempt < 2; attempt++) {
      if (w.buffer == null) return;
      final node = pool.pickHead(exclude: tried);
      if (node == null) return;
      tried.add(node);
      final token = CancelToken();
      final watch = Stopwatch()..start();
      int got = 0;
      bool gotFirst = false;
      final timer = Timer(_warmTimeout, () {
        if (!gotFirst && !token.isCancelled) token.cancel();
      });
      try {
        final response = await btrDio.get<ResponseBody>(
          node.url,
          options: Options(
            headers: {..._headers, 'range': 'bytes=${w.received}-${len - 1}'},
            responseType: ResponseType.stream,
          ),
          cancelToken: token,
        );
        if (response.statusCode != 206 ||
            !_startsAt(response.data!, w.received)) {
          await response.data?.stream.drain<void>().catchError((_) {});
          throw Exception('bad response ${response.statusCode}');
        }
        await for (final data in response.data!.stream) {
          gotFirst = true;
          timer.cancel();
          final buffer = w.buffer;
          if (buffer == null) {
            token.cancel();
            break;
          }
          final n = math.min(data.length, len - w.received);
          buffer.setRange(w.received, w.received + n, data);
          w.received += n;
          got += n;
          w.notify();
          if (w.received >= len) break;
        }
        final released = w.buffer == null;
        final complete = w.received >= len;
        pool.report(
          node,
          bytes: got,
          elapsed: watch.elapsed,
          cancelled: released,
          failed: !complete,
        );
        if (complete || released) return;
      } catch (e) {
        final released = w.buffer == null;
        pool.report(
          node,
          bytes: got,
          elapsed: watch.elapsed,
          cancelled: released,
          slow: !gotFirst && token.isCancelled && !released,
          failed: true,
        );
        if (released) return;
        if (kDebugMode) debugPrint('BTR: warm failed on ${node.host}: $e');
      } finally {
        timer.cancel();
      }
    }
  }

  static final _rangeRegex = RegExp(r'bytes=(\d*)-(\d*)');

  Future<void> serve(HttpRequest req) async {
    _headersOrNull ??= {
      'user-agent': req.headers.value('user-agent') ?? 'Mozilla/5.0',
      'referer': req.headers.value('referer') ?? 'https://www.bilibili.com/',
      'accept-encoding': 'identity',
    };
    await _ensureProbed();

    final total = _total;
    final range = req.headers.value('range');
    if (total == null) {
      return _passthrough(req.response, range, head: req.method == 'HEAD');
    }

    int start = 0;
    int end = total - 1;
    if (range != null) {
      final m = _rangeRegex.firstMatch(range);
      if (m != null) {
        final a = m.group(1)!;
        final b = m.group(2)!;
        if (a.isEmpty && b.isNotEmpty) {
          start = math.max(0, total - int.parse(b));
        } else {
          if (a.isNotEmpty) start = int.parse(a);
          if (b.isNotEmpty) end = math.min(int.parse(b), total - 1);
        }
      }
    }

    final res = req.response;
    if (start >= total || start > end) {
      res
        ..statusCode = HttpStatus.requestedRangeNotSatisfiable
        ..headers.set('content-range', 'bytes */$total');
      await res.close();
      return;
    }

    res
      ..statusCode = range == null ? HttpStatus.ok : HttpStatus.partialContent
      ..contentLength = end - start + 1
      ..headers.set('content-type', _contentType)
      ..headers.set('accept-ranges', 'bytes');
    if (range != null) {
      res.headers.set('content-range', 'bytes $start-$end/$total');
    }
    if (req.method == 'HEAD') {
      await res.close();
      return;
    }

    await _Pump(this, res, start, end, range).run();
  }

  /// True when a 206 response starts at [from] (a missing header is accepted).
  static bool _startsAt(ResponseBody response, int from) {
    final value = response.headers['content-range']?.firstOrNull;
    if (value == null) return true;
    final m = RegExp(r'bytes\s+(\d+)-').firstMatch(value);
    return m != null && int.parse(m.group(1)!) == from;
  }

  /// Probes once. A failed probe is sticky for [_probeRetryAfter] only.
  Future<void> _ensureProbed() {
    if (_total != null) return Future.value();
    final failedAt = _probeFailedAt;
    if (failedAt != null &&
        DateTime.now().difference(failedAt) < _probeRetryAfter) {
      return Future.value();
    }
    return _probing ??= _probe().whenComplete(() => _probing = null);
  }

  /// Sends `bytes=0-0` to up to 3 nodes at the same time and uses the first
  /// 206 answer with a `content-range`. The other requests are cancelled.
  Future<void> _probe() async {
    final candidates = pool.probeNodes();
    final completer = Completer<({int total, String? type})?>();
    final tokens = [for (final _ in candidates) CancelToken()];
    var pending = candidates.length;

    Future<void> probeOne(BtrNode node, CancelToken token) async {
      try {
        final response = await btrProbeDio.get<ResponseBody>(
          node.url,
          options: Options(
            headers: {..._headers, 'range': 'bytes=0-0'},
            responseType: ResponseType.stream,
          ),
          cancelToken: token,
        );
        await response.data?.stream.drain<void>().catchError((_) {});
        final contentRange = response.headers.value('content-range');
        final slash = contentRange?.lastIndexOf('/') ?? -1;
        final total = response.statusCode == 206 && slash != -1
            ? int.tryParse(contentRange!.substring(slash + 1).trim())
            : null;
        if (total == null) {
          pool.recordHostFailure(node);
        } else {
          BtrHostStats.recordSuccess(node.host);
          if (!completer.isCompleted) {
            completer.complete((
              total: total,
              type: response.headers.value('content-type'),
            ));
          }
        }
      } catch (e) {
        // A request cancelled because another node won is not a failure.
        if (!token.isCancelled) {
          pool.recordHostFailure(node);
          if (kDebugMode) debugPrint('BTR: probe failed ${node.host}: $e');
        }
      } finally {
        if (--pending == 0 && !completer.isCompleted) completer.complete(null);
      }
    }

    for (var i = 0; i < candidates.length; i++) {
      probeOne(candidates[i], tokens[i]);
    }
    // Bounded wait: a stuck probe counts as failed, so the request goes
    // direct instead of waiting for ever.
    final result = await completer.future.timeout(
      _probeTimeout,
      onTimeout: () => null,
    );
    for (final t in tokens) {
      if (!t.isCancelled) t.cancel();
    }
    if (result != null) {
      _total = result.total;
      _contentType = result.type ?? _contentType;
      _probeFailedAt = null;
    } else {
      _probeFailedAt = DateTime.now();
    }
    if (kDebugMode) {
      debugPrint(
        'BTR: play ${Uri.parse(url).pathSegments.last} '
        'host=${Uri.parse(url).host} os=${Uri.parse(url).queryParameters['os']} '
        'total=$_total '
        'nodes=${pool.nodes.length} threads=${BtrConfig.playbackThreads}',
      );
    }
  }

  /// Fetches bytes [start]..[end] (inclusive). Moves to another node when a
  /// request fails or stalls, and keeps the bytes already received.
  Future<Uint8List> fetchPiece(int start, int end, CancelToken cancel) async {
    final length = end - start + 1;
    final builder = BytesBuilder(copy: false);
    Object? lastError;
    for (int attempt = 0; attempt < _pieceAttempts; attempt++) {
      if (cancel.isCancelled) throw 'cancelled';
      final node = pool.pick();
      final from = start + builder.length;
      final watch = Stopwatch()..start();
      int got = 0;
      try {
        final response = await btrDio.get<ResponseBody>(
          node.url,
          options: Options(
            headers: {..._headers, 'range': 'bytes=$from-$end'},
            responseType: ResponseType.stream,
          ),
          cancelToken: cancel,
        );
        if (response.statusCode != 206 || !_startsAt(response.data!, from)) {
          await response.data?.stream.drain<void>().catchError((_) {});
          throw Exception('bad response ${response.statusCode}');
        }
        await for (final data in response.data!.stream) {
          final remain = length - builder.length;
          final bytes = data.length > remain ? data.sublist(0, remain) : data;
          builder.add(bytes);
          got += bytes.length;
          if (builder.length >= length) break;
        }
        final complete = builder.length >= length;
        pool.report(
          node,
          bytes: got,
          elapsed: watch.elapsed,
          failed: !complete,
        );
        if (complete) return builder.takeBytes();
        lastError = Exception('connection closed early');
      } catch (e) {
        pool.report(
          node,
          bytes: got,
          elapsed: watch.elapsed,
          cancelled: cancel.isCancelled,
          failed: true,
        );
        if (cancel.isCancelled) rethrow;
        lastError = e;
        if (kDebugMode) {
          debugPrint('BTR: piece $start retry on ${node.host}: $e');
        }
      }
      await Future.delayed(Duration(milliseconds: 150 * (attempt + 1)));
    }
    throw lastError ?? Exception('BTR: piece failed');
  }

  /// Pipes [range] from the original URL with one connection.
  Future<void> _passthrough(
    HttpResponse res,
    String? range, {
    bool head = false,
  }) async {
    // Cancel the upstream request when the player disconnects (seek, stop).
    final token = CancelToken();
    res.done.then((_) => token.cancel(), onError: (_) => token.cancel());
    final response = await Request.http11Dio.get<ResponseBody>(
      url,
      options: Options(
        headers: {..._headers, 'range': ?range},
        responseType: ResponseType.stream,
        validateStatus: (_) => true,
      ),
      cancelToken: token,
    );
    res.statusCode = response.statusCode ?? HttpStatus.badGateway;
    for (final key in const [
      'content-type',
      'content-length',
      'content-range',
      'accept-ranges',
    ]) {
      if (response.headers.value(key) case final value?) {
        res.headers.set(key, value);
      }
    }
    if (head) {
      await response.data?.stream.drain<void>().catchError((_) {});
      await res.close();
      return;
    }
    await res.addStream(
      response.data!.stream.map((c) {
        served += c.length;
        return c;
      }),
    );
    await res.close();
  }

  /// Pipes [start]..[end] from the original URL into an open response.
  Future<void> pipeRemaining(
    HttpResponse res,
    int start,
    int end, {
    CancelToken? cancelToken,
    void Function()? onWrite,
  }) async {
    final response = await Request.http11Dio.get<ResponseBody>(
      url,
      options: Options(
        headers: {..._headers, 'range': 'bytes=$start-$end'},
        responseType: ResponseType.stream,
      ),
      cancelToken: cancelToken,
    );
    if (response.statusCode != 206) {
      throw Exception('fallback status ${response.statusCode}');
    }
    await res.addStream(
      response.data!.stream.map((c) {
        served += c.length;
        onWrite?.call();
        return c;
      }),
    );
  }
}

/// One piece of a player request. It can run a second copy on another node
/// (hedge) when it blocks the player for too long.
class _Piece {
  _Piece(this.source, this.start, this.end) {
    // ignore(): a piece that fails after the player disconnects is not
    // awaited; do not report it as an unhandled error.
    _primary = source.fetchPiece(start, end, _token)..ignore();
  }

  final _BtrSource source;
  final int start;
  final int end;
  final _watch = Stopwatch()..start();
  final _token = CancelToken();
  CancelToken? _hedgeToken;
  late final Future<Uint8List> _primary;

  Duration get age => _watch.elapsed;

  /// Waits for the piece. When it is not done after [hedgeAfter] (counted
  /// from the piece start), a copy runs on another node and the first one to
  /// finish is used.
  Future<Uint8List> result(Duration hedgeAfter) {
    final completer = Completer<Uint8List>();
    int running = 1;
    int failed = 0;

    void onValue(Uint8List value) {
      if (completer.isCompleted) return;
      completer.complete(value);
      cancel();
    }

    void onError(Object e) {
      if (++failed >= running && !completer.isCompleted) {
        completer.completeError(e);
      }
    }

    _primary.then(onValue, onError: onError);

    final wait = hedgeAfter - age;
    final timer = Timer(wait.isNegative ? Duration.zero : wait, () {
      if (completer.isCompleted || _token.isCancelled) return;
      running++;
      if (kDebugMode) debugPrint('BTR: hedge piece $start');
      final token = _hedgeToken = CancelToken();
      source.fetchPiece(start, end, token).then(onValue, onError: onError);
    });
    return completer.future.whenComplete(timer.cancel);
  }

  void cancel() {
    if (!_token.isCancelled) _token.cancel();
    if (_hedgeToken case final t? when !t.isCancelled) t.cancel();
  }
}

/// One head request to one node. [first] completes with the first chunk (or
/// an error); [next] reads the following chunks of the same response.
class _HeadReq {
  _HeadReq(this.source, this.node, int from, int headEnd) : _from = from {
    first = _open(headEnd)..ignore();
  }

  final _BtrSource source;
  final BtrNode node;
  final int _from;
  final token = CancelToken();
  final watch = Stopwatch()..start();
  StreamIterator<Uint8List>? _it;
  late final Future<Uint8List> first;

  /// Error of the request before any chunk arrived.
  Object? error;

  Future<Uint8List> _open(int headEnd) async {
    final response = await btrDio.get<ResponseBody>(
      node.url,
      options: Options(
        headers: {
          ...source._headers,
          'range': 'bytes=$_from-$headEnd',
        },
        responseType: ResponseType.stream,
      ),
      cancelToken: token,
    );
    if (response.statusCode != 206 ||
        !_BtrSource._startsAt(response.data!, _from)) {
      await response.data?.stream.drain<void>().catchError((_) {});
      throw Exception('bad response ${response.statusCode}');
    }
    final it = _it = StreamIterator(response.data!.stream);
    if (!await it.moveNext()) throw Exception('empty response');
    return it.current;
  }

  /// The next chunk, or null at the end of the response.
  Future<Uint8List?> next() async {
    final it = _it!;
    return await it.moveNext() ? it.current : null;
  }

  /// Cancels the request and closes the connection.
  void cancel() {
    if (!token.isCancelled) token.cancel();
    _it?.cancel().catchError((_) {});
  }
}

/// Serves one player request: streams the head piece from one node, keeps up
/// to `threads` later pieces in flight and writes them to the player in order.
class _Pump {
  _Pump(this.source, this.res, this.start, this.end, this.range);

  final _BtrSource source;
  final HttpResponse res;
  final int start;
  final int end;
  final String? range;

  final _queue = Queue<_Piece>();
  late int _next = start;
  bool _closed = false;

  /// True once any body byte was written. Response headers go out with the
  /// first write, so before that a failure can still use `_passthrough`.
  bool _wrote = false;

  /// Next byte (absolute offset) the player has not received yet. Every
  /// `res.add` advances it by exactly the bytes added, so switching nodes
  /// never repeats or skips a byte.
  late int _position = start;

  /// Head requests in flight (primary and hedge). `_stop` cancels them.
  final _heads = <_HeadReq>[];
  final _fallbackToken = CancelToken();

  /// Moving average of the time a piece needs, in ms.
  double _pieceMs = 0;

  /// Like BTR: hedge after 1.5x the usual piece time, within limits.
  Duration get _hedgeAfter => Duration(
    milliseconds: _pieceMs == 0
        ? 1500
        : (_pieceMs * 1.5).round().clamp(700, 2500),
  );

  Future<void> run() async {
    try {
      await _run();
    } finally {
      _stop();
      try {
        await res.close();
      } catch (_) {}
    }
  }

  Future<void> _run() async {
    res.done.then((_) => _stop(), onError: (_) => _stop());

    final threads = BtrConfig.playbackThreads;
    final pieceSize = (threads > 32 ? 256 : 512) * 1024;
    final window = math.min(
      threads,
      _BtrSource._maxWindowBytes ~/ pieceSize,
    );

    void fill() {
      while (!_closed && _queue.length < window && _next <= end) {
        final s = _next;
        final e = math.min(s + pieceSize - 1, end);
        _next = e + 1;
        _queue.add(_Piece(source, s, e));
      }
    }

    try {
      // Bytes from a warm-up (tap-down) go out first; the head piece and the
      // later pieces continue from `_position`.
      await _serveWarm();
      if (_closed || _position > end) return;
      // The head piece is streamed below; later pieces start downloading now.
      final headEnd = math.min(_position + _BtrSource._firstPiece - 1, end);
      _next = headEnd + 1;
      fill();
      final headDone = await _streamHead(headEnd);
      if (_closed) return;
      if (!headDone) {
        // Head failed on every node: continue with one connection.
        await _fallback('head piece failed');
        return;
      }
      while (_queue.isNotEmpty && !_closed) {
        final head = _queue.first;
        assert(head.start == _position, 'BTR: position mismatch');
        final Uint8List bytes;
        try {
          bytes = await head.result(_hedgeAfter);
        } catch (e) {
          if (_closed) return;
          // Every node failed for this piece: continue with one connection.
          await _fallback('$e');
          return;
        }
        _queue.removeFirst();
        if (_closed) return;
        final ms = head.age.inMilliseconds.toDouble();
        _pieceMs = _pieceMs == 0 ? ms : _pieceMs * 0.8 + ms * 0.2;
        res.add(bytes);
        _wrote = true;
        source.served += bytes.length;
        _position += bytes.length;
        fill();
        await res.flush();
      }
    } catch (_) {
      // Player closed the connection (seek or stop), or the fallback failed.
      final retryDirect = !_closed && !_wrote;
      _stop();
      if (retryDirect) {
        // No byte was sent yet, so the headers can still change.
        try {
          await source._passthrough(res, range);
        } catch (_) {}
      }
    }
  }

  /// Pipes the rest of the request from the original URL.
  Future<void> _fallback(String reason) async {
    if (kDebugMode) {
      debugPrint('BTR: fallback to original URL at $_position: $reason');
    }
    _cancelAll();
    _queue.clear();
    await source.pipeRemaining(
      res,
      _position,
      end,
      cancelToken: _fallbackToken,
      onWrite: () => _wrote = true,
    );
  }

  /// Writes the warm-up bytes (see `BtrProxy.warm`) that cover [_position].
  /// When the warm download is still running, waits for its data instead of
  /// asking the CDN for the same range. Stops when the warm range is written,
  /// the warm download failed or its bytes were released; the normal flow then
  /// continues from [_position]. `_position` moves only by the bytes added.
  Future<void> _serveWarm() async {
    final w = source._warm;
    if (w == null || _position >= w.target) return;
    w.users++;
    var hit = 0;
    try {
      while (!_closed && _position <= end) {
        final buffer = w.buffer;
        if (buffer == null) break;
        if (_position < w.received) {
          final to = math.min(w.received, end + 1);
          final slice = Uint8List.sublistView(buffer, _position, to);
          try {
            // The first write also sends the response headers.
            res.add(slice);
            _wrote = true;
            await res.flush();
          } catch (_) {
            _stop();
            break;
          }
          source.served += slice.length;
          _position += slice.length;
          hit += slice.length;
        } else if (w.done || _position >= w.target) {
          break;
        } else {
          await w.next;
        }
      }
    } finally {
      w.users--;
      if (w.users == 0 && w.buffer != null) {
        if (w.evicted) {
          w.release();
        } else {
          w.armRelease();
        }
      }
    }
    if (hit > 0 && kDebugMode) debugPrint('BTR: warm hit $hit bytes');
  }

  /// Streams [_position]..[headEnd] to the player. Node A starts; when it
  /// sends no byte for 0.8 s, node B gets the same range (hedge) and the first
  /// one with data wins. Both silent for 2 s: the next nodes are used (at most
  /// 2 switches). After a failure it continues from [_position] on another
  /// node. Returns false when no node could finish the head piece.
  Future<bool> _streamHead(int headEnd) async {
    final tried = <BtrNode>{};
    for (int attempt = 0; attempt <= _BtrSource._headSwitches; attempt++) {
      if (_closed) return true;
      final node = source.pool.pickHead(exclude: tried);
      if (node == null) break;
      tried.add(node);
      if (attempt > 0 && kDebugMode) {
        debugPrint('BTR: head switch to ${node.host} at $_position');
      }
      final winner = await _raceHead(node, tried, headEnd);
      if (_closed) return true;
      if (winner == null) continue;
      await _pipeHead(winner, headEnd);
      if (_closed || _position > headEnd) return true;
    }
    return _position > headEnd;
  }

  /// Races head requests from [_position] and returns the one that got the
  /// first chunk (null when none did). Nothing is written to the player here,
  /// so `_position` and the write source stay single. Every request except
  /// the winner is cancelled and reported; a lost race or a cancel is not a
  /// node failure.
  Future<_HeadReq?> _raceHead(
    BtrNode node,
    Set<BtrNode> tried,
    int headEnd,
  ) async {
    final reqs = <_HeadReq>[];
    final chosen = Completer<_HeadReq?>();
    var pending = 0;

    void launch(BtrNode n) {
      final r = _HeadReq(source, n, _position, headEnd);
      reqs.add(r);
      _heads.add(r);
      pending++;
      r.first.then(
        (_) {
          if (!chosen.isCompleted) chosen.complete(r);
        },
        onError: (Object e) {
          r.error = e;
          if (--pending == 0 && !chosen.isCompleted) chosen.complete(null);
        },
      );
    }

    launch(node);
    final hedgeTimer = Timer(_BtrSource._hedgeDelay, () {
      if (chosen.isCompleted || _closed) return;
      final second = source.pool.pickHead(exclude: tried);
      if (second == null) return;
      tried.add(second);
      if (kDebugMode) {
        debugPrint('BTR: hedge start ${second.host} at $_position');
      }
      launch(second);
    });
    final silentTimer = Timer(_BtrSource._headTimeout, () {
      if (!chosen.isCompleted) chosen.complete(null);
    });
    final winner = await chosen.future;
    hedgeTimer.cancel();
    silentTimer.cancel();

    final stopped = _closed;
    for (final r in reqs) {
      if (identical(r, winner)) continue;
      final genuine = r.error != null && !stopped;
      r.cancel();
      _heads.remove(r);
      source.pool.report(
        r.node,
        bytes: 0,
        elapsed: r.watch.elapsed,
        failed: genuine,
        // Slow only when nobody won and this request itself waited for the
        // whole head timeout (a hedge started later is not slow). A loser
        // when a winner exists is only cancelled.
        slow:
            !genuine &&
            !stopped &&
            winner == null &&
            r.watch.elapsed >=
                _BtrSource._headTimeout - const Duration(milliseconds: 100),
        cancelled: stopped || (!genuine && winner != null),
      );
      if (genuine && kDebugMode) {
        debugPrint(
          'BTR: head failed on ${r.node.host} after '
          '${r.watch.elapsedMilliseconds} ms: ${r.error}',
        );
      }
    }
    if (winner == null) {
      if (!stopped && kDebugMode) {
        debugPrint('BTR: head no first byte at $_position');
      }
      return null;
    }
    if (stopped) {
      winner.cancel();
      _heads.remove(winner);
      source.pool.report(
        winner.node,
        bytes: 0,
        elapsed: winner.watch.elapsed,
        cancelled: true,
      );
      return null;
    }
    if (kDebugMode) {
      debugPrint(
        'BTR: head first byte ${winner.watch.elapsedMilliseconds} ms '
        'host=${winner.node.host}',
      );
      if (!identical(winner, reqs.first)) {
        debugPrint('BTR: hedge win ${winner.node.host}');
      }
    }
    return winner;
  }

  /// Writes the winner's stream to the player until [headEnd] and reports it.
  Future<void> _pipeHead(_HeadReq r, int headEnd) async {
    int got = 0;
    var reported = false;
    try {
      var chunk = await r.first;
      while (true) {
        final remain = headEnd - _position + 1;
        final bytes = chunk.length > remain ? chunk.sublist(0, remain) : chunk;
        try {
          // The first write also sends the response headers.
          res.add(bytes);
          _wrote = true;
          await res.flush();
        } catch (_) {
          // Player gone: not a node failure.
          _stop();
          reported = true;
          source.pool.report(
            r.node,
            bytes: got,
            elapsed: r.watch.elapsed,
            cancelled: true,
          );
          return;
        }
        source.served += bytes.length;
        _position += bytes.length;
        got += bytes.length;
        if (_position > headEnd) break;
        final next = await r.next();
        if (next == null) break;
        chunk = next;
      }
      reported = true;
      source.pool.report(
        r.node,
        bytes: got,
        elapsed: r.watch.elapsed,
        failed: _position <= headEnd,
      );
    } catch (e) {
      // Cancelled by _stop (seek or stop) is not a node failure.
      final stopped = _closed;
      if (!reported) {
        reported = true;
        source.pool.report(
          r.node,
          bytes: got,
          elapsed: r.watch.elapsed,
          cancelled: stopped,
          failed: true,
        );
      }
      if (!stopped && kDebugMode) {
        debugPrint(
          'BTR: head failed on ${r.node.host} '
          'after ${r.watch.elapsedMilliseconds} ms: $e',
        );
      }
    } finally {
      r.cancel();
      _heads.remove(r);
    }
  }

  void _cancelAll() {
    if (!_fallbackToken.isCancelled && _closed) _fallbackToken.cancel();
    for (final r in _heads.toList()) {
      r.cancel();
    }
    for (final piece in _queue) {
      piece.cancel();
    }
  }

  void _stop() {
    if (_closed) return;
    _closed = true;
    _cancelAll();
  }
}
