import 'package:PiliPlus/services/translate/translator.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

abstract final class NumUtils {
  static final _numRegExp = RegExp(r'([\d\.]+)([千万亿萬億]|[KkMmBb](?![A-Za-z]))?');

  static final _chineseUnit = RegExp(r'[千万萬亿億]');

  static int _getUnit(String? unit) {
    switch (unit) {
      case '千':
        return 1000;
      case '万' || '萬':
        return 10000;
      case '亿' || '億':
        return 100000000;
      case 'K' || 'k':
        return 1000;
      case 'M' || 'm':
        return 1000000;
      case 'B' || 'b':
        return 1000000000;
      default:
        return 1;
    }
  }

  static int parseNum(String numberStr) {
    if (numberStr == '-') return 0;
    try {
      final match = _numRegExp.firstMatch(numberStr)!;
      var number = double.parse(match.group(1)!);
      number *= _getUnit(match.group(2));
      return number.toInt();
    } catch (e) {
      if (kDebugMode) debugPrint('parse failed: "$numberStr" : $e');
      return 0;
    }
  }

  static String numFormat(dynamic number) {
    if (number == null) {
      return '0';
    }
    if (number is String) {
      number = int.tryParse(number) ?? number;
      if (number is String) {
        // A display string such as "15万": parse it, then format it again.
        if (Translator.isEnglishMode && _chineseUnit.hasMatch(number)) {
          number = parseNum(number);
        } else {
          return number;
        }
      }
    }

    String format(first, second) {
      double result = ((number / first) as double).toPrecision(1);
      int intRes = result.toInt();
      if (result == intRes) {
        return '$intRes$second';
      } else {
        return '$result$second';
      }
    }

    if (Translator.isEnglishMode) {
      if (number >= 1000000000) {
        return format(1000000000, 'B');
      } else if (number >= 1000000) {
        return format(1000000, 'M');
      } else if (number >= 1000) {
        return format(1000, 'K');
      }
      return number.toString();
    }

    if (number >= 100000000) {
      return format(100000000, '億');
    } else if (number >= 10000) {
      return format(10000, '萬');
    } else {
      return number.toString();
    }
  }

  static String formatPositiveDecimal(int number) {
    if (number < 1000) return number.toString();

    final numStr = number.toString();
    final length = numStr.length;
    final sb = StringBuffer();

    int firstLength = length % 3;
    if (firstLength == 0) firstLength = 3;

    sb.write(numStr.substring(0, firstLength));
    for (int i = firstLength; i < length; i += 3) {
      sb
        ..write(',')
        ..write(numStr.substring(i, i + 3));
    }

    return sb.toString();
  }
}
