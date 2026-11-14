import 'dart:async';
import 'dart:io' show Platform;

import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:nm/nm.dart';

abstract final class ConnectivityUtils {
  /// Result of the last check. A check through the platform channel takes
  /// 15-190 ms, and opening a video waits for it: on mobile the result is
  /// kept up to date by the connectivity change events, so it is read
  /// without a check. Before the first event, a result younger than [_ttl]
  /// is reused.
  static bool? _last;
  static DateTime _lastAt = DateTime(0);
  static const _ttl = Duration(seconds: 5);

  /// True after a connectivity event: [_last] follows the changes.
  static bool _live = false;
  // Kept for the whole app life.
  // ignore: cancel_subscriptions
  static StreamSubscription<List<ConnectivityResult>>? _sub;

  static Future<bool> get isWiFi async {
    _listen();
    final last = _last;
    if (last != null && (_live || DateTime.now().difference(_lastAt) < _ttl)) {
      return last;
    }
    final res = await _check();
    _last = res;
    _lastAt = DateTime.now();
    return res;
  }

  static void _listen() {
    if (_sub != null || !PlatformUtils.isMobile) return;
    try {
      _sub = Connectivity().onConnectivityChanged.listen(
        (result) {
          _last = result.contains(ConnectivityResult.wifi);
          _lastAt = DateTime.now();
          _live = true;
        },
        onError: (Object _) => _live = false,
      );
    } catch (_) {}
  }

  static Future<bool> _check() async {
    try {
      if (Platform.isLinux) {
        final client = NetworkManagerClient();
        try {
          await client.connect();
          return switch (client.metered) {
            NetworkManagerMetered.yes ||
            NetworkManagerMetered.guessYes => false,
            _ => true,
          };
        } finally {
          await client.close();
        }
      }
      return PlatformUtils.isMobile &&
          (await Connectivity().checkConnectivity()).contains(
            ConnectivityResult.wifi,
          );
    } catch (_) {
      return true;
    }
  }
}
