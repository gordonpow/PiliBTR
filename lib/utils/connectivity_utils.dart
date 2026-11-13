import 'dart:io' show Platform;

import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:nm/nm.dart';

abstract final class ConnectivityUtils {
  /// Result of the last check. A check through the platform channel takes
  /// 15-90 ms; opening a video asks right after the card prefetch asked, so
  /// a result younger than [_ttl] is reused.
  static bool? _last;
  static DateTime _lastAt = DateTime(0);
  static const _ttl = Duration(seconds: 5);

  static Future<bool> get isWiFi async {
    final last = _last;
    if (last != null && DateTime.now().difference(_lastAt) < _ttl) {
      return last;
    }
    final res = await _check();
    _last = res;
    _lastAt = DateTime.now();
    return res;
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
