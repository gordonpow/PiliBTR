import 'dart:convert' show utf8;
import 'dart:math' show Random;

import 'package:PiliPlus/models/common/account_type.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:crypto/crypto.dart' show md5;

/// App 端請求用的裝置指紋與 session id。
/// 每次啟動 App 第一次讀取時計算，之後固定（快取在記憶體）。
abstract final class DeviceFp {
  static final Random _random = Random.secure();

  static String _randomHex(int length) {
    final sb = StringBuffer();
    for (var i = 0; i < length; i++) {
      sb.write(_random.nextInt(16).toRadixString(16));
    }
    return sb.toString();
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _generate() {
    final buvid = Accounts.get(AccountType.recommend).buvid;
    // md5(buvid + model + radio)，32 字元小寫 hex
    final source = md5.convert(utf8.encode('${buvid}android')).toString();
    final now = DateTime.now();
    final ts =
        '${now.year.toString().padLeft(4, '0')}${_two(now.month)}'
        '${_two(now.day)}${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';
    final s = source + ts + _randomHex(16);
    // 每 2 字元當 hex 數值相加後 mod 256 作為檢查碼
    var sum = 0;
    for (var i = 0; i < s.length; i += 2) {
      sum += int.parse(s.substring(i, i + 2), radix: 16);
    }
    return s + (sum % 256).toRadixString(16).padLeft(2, '0');
  }

  static final String fpLocal = _generate();

  static String get fpRemote => fpLocal;

  static final String sessionId = _randomHex(8);
}
