import 'dart:io' show HttpClient;

import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/services/download/btr_config.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

/// BTR's own adapter. `Dio.clone()` shares the adapter of the source client,
/// so changing the idle timeout on that one would affect the whole app. This
/// adapter keeps idle connections for 60 s, so a connection made by
/// `BtrProxy.preconnect` is still usable when the player starts. It is shared
/// by [btrDio] and [btrProbeDio] (one connection pool). Proxy settings follow
/// `Request._createPool`.
final IOHttpClientAdapter _btrAdapter = IOHttpClientAdapter(
  createHttpClient: () {
    final client = HttpClient()
      ..idleTimeout = const Duration(seconds: 60)
      ..autoUncompress = false;
    if (Pref.enableSystemProxy) {
      final host = Pref.systemProxyHost;
      final port = int.tryParse(Pref.systemProxyPort);
      if (port != null && host.isNotEmpty) {
        client
          ..findProxy = ((_) => 'PROXY $host:$port')
          ..badCertificateCallback = (cert, host, port) => true;
      }
    }
    return client;
  },
);

/// HTTP client for BTR requests: short connect timeout so a dead node is
/// left quickly, and a stall timeout between data chunks.
final Dio btrDio = Request.http11Dio.clone(
  httpClientAdapter: _btrAdapter,
  options: Request.http11Dio.options.copyWith(
    connectTimeout: const Duration(seconds: 4),
    receiveTimeout: const Duration(seconds: 5),
  ),
);

/// Probe client: 3 s connect and 3 s receive timeout, so a dead node does not
/// delay playback start.
final Dio btrProbeDio = Request.http11Dio.clone(
  httpClientAdapter: _btrAdapter,
  options: Request.http11Dio.options.copyWith(
    connectTimeout: const Duration(seconds: 3),
    receiveTimeout: const Duration(seconds: 3),
  ),
);

/// Process-wide host statistics, shared by every media file so a new video
/// does not retry a host that is known to be bad.
abstract final class BtrHostStats {
  /// Consecutive failures that ban a host.
  static const int banAfter = 2;
  static const Duration banDuration = Duration(minutes: 10);

  static final Map<String, _HostStat> _stats = {};

  static bool isBanned(String host) {
    final stat = _stats[host];
    if (stat == null) return false;
    final until = stat.bannedUntil;
    if (until == null) return false;
    if (DateTime.now().isBefore(until)) return true;
    // Ban expired: give the host a clean start.
    stat
      ..bannedUntil = null
      ..failures = 0;
    return false;
  }

  /// Speed EMA in bytes per millisecond. 0 = unknown.
  static double speedOf(String host) => _stats[host]?.speed ?? 0;

  /// Updates the speed EMA only; does not touch the failure count.
  static void addSpeed(String host, double speed) {
    if (speed <= 0) return;
    final stat = _stats.putIfAbsent(host, _HostStat.new);
    stat.speed = stat.speed == 0 ? speed : stat.speed * 0.7 + speed * 0.3;
  }

  /// A request that ended well: resets the consecutive failures.
  static void recordSuccess(String host, {double? speed}) {
    _stats.putIfAbsent(host, _HostStat.new).failures = 0;
    if (speed != null) addSpeed(host, speed);
  }

  /// Lowers the speed only (for example a slow first byte). Not a failure.
  static void recordSlow(String host) {
    final stat = _stats[host];
    if (stat != null) stat.speed *= 0.5;
  }

  /// A failed request. The same host counts at most once per second, so a
  /// network blip that fails many parallel pieces at once is one failure.
  /// [canBan] is false for the original URL host, which stays usable.
  static void recordFailure(String host, {bool canBan = true}) {
    final stat = _stats.putIfAbsent(host, _HostStat.new);
    final now = DateTime.now();
    final last = stat.lastFailureAt;
    if (last != null && now.difference(last) < const Duration(seconds: 1)) {
      return;
    }
    stat
      ..lastFailureAt = now
      ..speed *= 0.5;
    if (!canBan) return;
    if (++stat.failures >= banAfter && stat.bannedUntil == null) {
      stat.bannedUntil = DateTime.now().add(banDuration);
      if (kDebugMode) debugPrint('BTR: host banned 10 min $host');
    }
  }
}

class _HostStat {
  int failures = 0;
  DateTime? lastFailureAt;
  DateTime? bannedUntil;
  double speed = 0;
}

/// One CDN address for a media file.
class BtrNode {
  final String url;
  late final String host = Uri.tryParse(url)?.host ?? url;

  int strikes = 0;
  bool banned = false;
  int inflight = 0;

  /// Total bytes received from this node.
  int bytes = 0;

  /// Measured speed in bytes per millisecond (moving average). 0 = unknown.
  double speed = 0;

  BtrNode(this.url);
}

/// CDN nodes for one media file, with the BTR rules:
/// - a node that returns 0 bytes [strikeLimit] times in a row is banned for
///   this file; when every node is banned, all nodes are used again;
/// - requests go to nodes by measured speed and current load; a node slower
///   than 1/12 of the fastest one is skipped.
class BtrNodePool {
  BtrNodePool(String url) : nodes = _build(url);

  /// Fixed number of hosts a probe tries at the same time.
  static const int probeCount = 3;

  static const int strikeLimit = 2;

  /// Times per-file bans may be cleared again before [pick] uses the original
  /// URL only.
  static const int maxResets = 3;

  static final _mediaHost = RegExp(
    r'\.(?:bilivideo\.(?:com|cn|net)|akamaized\.net)$',
  );

  final List<BtrNode> nodes;
  int _turn = 0;
  int _resets = 0;

  static List<BtrNode> _build(String url) {
    final urls = <String>[url];
    final uri = Uri.tryParse(url);
    // Like BTR swapOrdinaryHost: the URL moves to another host and keeps its
    // path and query (with the signature). Relay URLs (mcdn host,
    // /v1/resource/ path, os=mcdn) stay on their host. Akamai never is a
    // target, because its URLs use their own signature.
    if (uri != null &&
        _mediaHost.hasMatch(uri.host) &&
        !uri.host.contains('mcdn') &&
        uri.path.contains('/upgcxcode/') &&
        !uri.path.contains('/v1/resource/') &&
        uri.queryParameters['os'] != 'mcdn') {
      for (final host in BtrConfig.hosts) {
        if (host != uri.host && !host.contains('akamai')) {
          urls.add(uri.replace(host: host).toString());
        }
      }
    }
    final nodes = [for (final u in urls) BtrNode(u)];
    // Use the process-wide statistics: start with known speeds and order
    // mirrors from fast to slow; the original URL stays first. Banned hosts
    // are kept and filtered at use time, so they return when the ban ends.
    final original = nodes.first;
    final mirrors = nodes.skip(1).toList();
    for (final n in [original, ...mirrors]) {
      n.speed = BtrHostStats.speedOf(n.host);
    }
    final order = {for (var i = 0; i < mirrors.length; i++) mirrors[i]: i};
    mirrors.sort((a, b) {
      final c = b.speed.compareTo(a.speed);
      return c != 0 ? c : order[a]!.compareTo(order[b]!);
    });
    return [original, ...mirrors];
  }

  /// Records a failure for [node] host. The original URL host is never
  /// banned.
  void recordHostFailure(BtrNode node) =>
      BtrHostStats.recordFailure(node.host, canBan: node != nodes.first);

  bool _isUsable(BtrNode n) => !n.banned && !BtrHostStats.isBanned(n.host);

  /// Up to [probeCount] nodes for a probe: known fast ones first. Uses the
  /// original URL when every node is banned.
  List<BtrNode> probeNodes() {
    final usable = nodes.where(_isUsable).toList();
    if (usable.isEmpty) return [nodes.first];
    final known = usable.where((n) => n.speed > 0).toList()
      ..sort((a, b) => b.speed.compareTo(a.speed));
    return [
      ...known,
      ...usable.where((n) => n.speed == 0),
    ].take(probeCount).toList();
  }

  /// Node for the streamed head piece: the fastest usable node that is not in
  /// [exclude]; the original URL when there are no statistics. Returns null
  /// when nothing is left (the first call never returns null). Call [report]
  /// when the request ends.
  BtrNode? pickHead({Set<BtrNode> exclude = const {}}) {
    final usable = nodes
        .where((n) => !exclude.contains(n) && _isUsable(n))
        .toList();
    BtrNode? node;
    if (usable.isNotEmpty) {
      final known = usable.where((n) => n.speed > 0).toList();
      if (known.isNotEmpty) {
        node = known.reduce((a, b) => a.speed >= b.speed ? a : b);
      } else {
        node = usable.contains(nodes.first) ? nodes.first : usable.first;
      }
    } else if (exclude.isEmpty) {
      node = nodes.first;
    }
    node?.inflight++;
    return node;
  }

  /// Selects a node for one request and counts it as in flight.
  /// Call [report] when the request ends.
  BtrNode pick() {
    var usable = nodes.where(_isUsable).toList();
    if (usable.isEmpty && ++_resets <= maxResets) {
      // Give nodes banned only for this file another chance. Hosts banned
      // process-wide stay banned until their ban expires.
      for (final n in nodes) {
        n
          ..banned = false
          ..strikes = 0;
      }
      usable = nodes.where(_isUsable).toList();
    }
    if (usable.isEmpty) {
      // Every node is banned: use the original URL instead of failing.
      if (kDebugMode) debugPrint('BTR: all nodes banned, using original URL');
      return nodes.first..inflight += 1;
    }

    BtrNode node;
    // Try each node once before measured speeds decide.
    final untested = usable.where((n) => n.speed == 0 && n.inflight == 0);
    if (untested.isNotEmpty) {
      node = untested.elementAt(_turn++ % untested.length);
    } else {
      final top = usable.fold<double>(0, (m, n) => n.speed > m ? n.speed : m);
      var candidates = usable.where((n) => n.speed >= top / 12).toList();
      if (candidates.isEmpty) candidates = usable;
      // Highest speed per request in flight; unknown speed counts as top.
      node = candidates.reduce(
        (a, b) =>
            ((a.speed == 0 ? top : a.speed) / (a.inflight + 1)) >=
                ((b.speed == 0 ? top : b.speed) / (b.inflight + 1))
            ? a
            : b,
      );
    }
    node.inflight++;
    return node;
  }

  /// Reports the end of a request on [node]: [bytes] received in [elapsed].
  /// For a cancelled request pass `cancelled: true`; it does not count as a
  /// strike.
  void report(
    BtrNode node, {
    required int bytes,
    Duration? elapsed,
    bool cancelled = false,
    bool failed = false,
    bool slow = false,
  }) {
    if (node.inflight > 0) node.inflight--;
    if (bytes > 0) node.bytes += bytes;
    if (bytes >= 64 * 1024 && elapsed != null) {
      final sample = bytes / (elapsed.inMilliseconds + 1);
      node.speed = node.speed == 0 ? sample : node.speed * 0.7 + sample * 0.3;
      BtrHostStats.addSpeed(node.host, sample);
    }
    if (cancelled) return;
    if (slow) {
      // First-byte timeout: lowers the speed, but is not a failure.
      node.speed *= 0.5;
      BtrHostStats.recordSlow(node.host);
      return;
    }
    // [failed]: the request broke or ended early, even if some bytes came.
    if (bytes > 0 && !failed) {
      node.strikes = 0;
      _resets = 0;
      BtrHostStats.recordSuccess(node.host);
      return;
    }
    // A failed request also lowers the measured speed.
    node.speed *= 0.5;
    recordHostFailure(node);
    if (++node.strikes >= strikeLimit && !node.banned) {
      node.banned = true;
      if (kDebugMode) debugPrint('BTR: node banned ${node.host}');
    }
  }
}
