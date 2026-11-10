import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:PiliPlus/btr_version.dart';
import 'package:PiliPlus/services/logger.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:catcher_2/model/report.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// 回報腳本網址（Google Apps Script 網頁應用程式的 /exec 網址），
/// 與 PiliBTRTV 共用同一支腳本。
const String kReportScriptUrl =
    'https://script.google.com/macros/s/AKfycby0KPazujL8jLRFG-vWegEV0p7lLD45a1hQutsY349tryBc3LgKRolwBc-wAECx8CyB-g/exec';

const String kFeedbackAppName = 'PiliBTR';

/// 回報類型。
enum FeedbackCategory {
  bug('錯誤回報'),
  suggestion('功能建議'),
  other('其他');

  final String label;
  const FeedbackCategory(this.label);
}

/// 送出結果。
class FeedbackResult {
  final bool ok;
  final String id;
  final String message;

  const FeedbackResult.ok(this.id) : ok = true, message = '';
  const FeedbackResult.fail(this.message) : ok = false, id = '';
}

const String kReportIdChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const int kReportMaxBytes = 400 * 1024;
const int kReportHeadBytes = 20 * 1024;
const String kReportTruncMarker = '\n…（中略）…\n';
const String _scriptNotPublic = '送出失敗（腳本未公開）';

/// 產生 6 碼回報編號。
String generateReportId([Random? rng]) {
  final r = rng ?? Random.secure();
  return String.fromCharCodes(
    List.generate(
      6,
      (_) => kReportIdChars.codeUnitAt(r.nextInt(kReportIdChars.length)),
    ),
  );
}

bool _isCont(int b) => (b & 0xC0) == 0x80;

/// 以 UTF-8 位元組數截斷：保留開頭 [headBytes] 與結尾，中間以標記取代。
String truncateReportBytes(
  String report, {
  int maxBytes = kReportMaxBytes,
  int headBytes = kReportHeadBytes,
}) {
  final bytes = utf8.encode(report);
  if (bytes.length <= maxBytes) return report;
  final marker = utf8.encode(kReportTruncMarker);
  var headEnd = min(headBytes, maxBytes - marker.length);
  while (headEnd > 0 && headEnd < bytes.length && _isCont(bytes[headEnd])) {
    headEnd--;
  }
  var tailStart = bytes.length - (maxBytes - headEnd - marker.length);
  while (tailStart < bytes.length && _isCont(bytes[tailStart])) {
    tailStart++;
  }
  return utf8.decode(bytes.sublist(0, headEnd)) +
      kReportTruncMarker +
      utf8.decode(bytes.sublist(tailStart));
}

/// 腳本錯誤碼對應的使用者訊息。
String reportErrorMessage(String code) {
  switch (code) {
    case 'rate':
      return '回報太頻繁，請稍後再試';
    case 'quota':
      return '今日回報已達上限，請明天再試';
    default:
      return '送出失敗（$code）';
  }
}

/// 解析腳本回應 JSON。非 JSON 視為腳本未公開。
FeedbackResult parseScriptResponse(
  String body, {
  required String fallbackId,
}) {
  Object? json;
  try {
    json = jsonDecode(body);
  } catch (_) {
    return const FeedbackResult.fail(_scriptNotPublic);
  }
  if (json is! Map) return const FeedbackResult.fail(_scriptNotPublic);
  if (json['ok'] == true) {
    final id = json['id'];
    return FeedbackResult.ok(id is String && id.isNotEmpty ? id : fallbackId);
  }
  return FeedbackResult.fail(reportErrorMessage('${json['error'] ?? '未知'}'));
}

bool isRedirectStatus(int s) =>
    s == 301 || s == 302 || s == 303 || s == 307 || s == 308;

/// 日誌內容（已格式化）與筆數。
typedef FeedbackLogs = ({String text, int count});

abstract final class FeedbackReport {
  static bool get enabled => kReportScriptUrl.isNotEmpty;

  static String newReportId() => generateReportId();

  /// 16 碼隨機安裝代號，存在 GStorage.setting。
  static String installId() {
    final stored = GStorage.setting.get(SettingBoxKey.feedbackInstallId);
    if (stored is String && stored.length >= 16) return stored;
    final r = Random.secure();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final id = String.fromCharCodes(
      List.generate(16, (_) => chars.codeUnitAt(r.nextInt(chars.length))),
    );
    GStorage.setting.put(SettingBoxKey.feedbackInstallId, id);
    return id;
  }

  /// 回傳 (裝置, 系統)。
  static Future<(String, String)> deviceSummary() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        return (
          '${info.manufacturer} ${info.model}',
          'Android ${info.version.release} (SDK ${info.version.sdkInt})',
        );
      }
    } catch (e) {
      debugPrint('回報：取得裝置資訊失敗 $e');
    }
    return (Platform.operatingSystem, Platform.operatingSystemVersion);
  }

  /// 讀取日誌並轉成可讀文字（由新到舊）；沒有日誌時 count 為 0。
  static Future<FeedbackLogs> readLogs() async {
    try {
      final file = await LoggerUtils.getLogsPath();
      final lines = (await file.readAsLines())
          .where((e) => e.trim().isNotEmpty)
          .toList()
          .reversed;
      final buffer = StringBuffer();
      var count = 0;
      for (final line in lines) {
        count++;
        try {
          final log = Report.fromJson(jsonDecode(line));
          buffer
            ..writeln('[${log.dateTime.toIso8601String()}]')
            ..writeln(log.error);
          final stack = log.stackTrace?.toString();
          if (stack != null && stack.isNotEmpty && stack != 'null') {
            buffer.writeln(stack);
          }
        } catch (_) {
          buffer.writeln(line);
        }
        buffer.writeln();
      }
      return (text: buffer.toString().trimRight(), count: count);
    } catch (e) {
      debugPrint('回報：讀取日誌失敗 $e');
      return (text: '', count: 0);
    }
  }

  static Future<FeedbackResult> send({
    required FeedbackCategory category,
    required String description,
    required bool attachLogs,
  }) async {
    final id = newReportId();
    // 乾淨的 Dio：不帶 bilibili cookie 與攔截器
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 20),
        followRedirects: false,
        validateStatus: (_) => true,
        responseType: ResponseType.plain,
      ),
    );
    try {
      final (device, android) = await deviceSummary();
      final desc = description.trim();
      final buffer = StringBuffer()
        ..writeln('App：$kFeedbackAppName')
        ..writeln('版本：$btrVersion')
        ..writeln('裝置：$device')
        ..writeln('Android：$android')
        ..writeln('時間：${DateTime.now().toIso8601String()}')
        ..writeln('類型：${category.label}')
        ..writeln('描述：${desc.isEmpty ? '（未填寫）' : desc}')
        ..writeln();
      if (attachLogs) {
        final logs = await readLogs();
        buffer
          ..writeln('日誌（${logs.count} 筆，由新到舊）：')
          ..write(logs.count == 0 ? '（無日誌）' : logs.text);
      } else {
        buffer.write('（未附日誌）');
      }
      final payload = jsonEncode({
        'app': kFeedbackAppName,
        'id': id,
        'installId': installId(),
        'category': category.label,
        'version': btrVersion,
        'device': device,
        'android': android,
        'report': truncateReportBytes(buffer.toString()),
      });
      final resp = await dio
          .post<String>(
            kReportScriptUrl,
            data: payload,
            options: Options(
              contentType: 'text/plain;charset=utf-8',
              headers: {'Accept': '*/*'},
            ),
          )
          .timeout(const Duration(seconds: 20));
      final status = resp.statusCode ?? 0;
      if (isRedirectStatus(status)) {
        final loc = resp.headers.value('location');
        if (loc == null || loc.isEmpty) {
          return const FeedbackResult.fail('送出失敗（無回應）');
        }
        // POST 已被腳本收到；echo GET 失敗視為已送出（未收到確認）
        try {
          final r2 = await dio
              .getUri<String>(Uri.parse(kReportScriptUrl).resolve(loc))
              .timeout(const Duration(seconds: 10));
          return parseScriptResponse(r2.data ?? '', fallbackId: id);
        } catch (e) {
          debugPrint('回報：echo GET 失敗 $e');
          return FeedbackResult.ok(id);
        }
      }
      if (status == 200) {
        return parseScriptResponse(resp.data ?? '', fallbackId: id);
      }
      debugPrint('回報：HTTP $status');
      return FeedbackResult.fail('送出失敗（HTTP $status）');
    } on TimeoutException {
      return const FeedbackResult.fail('連線逾時，請稍後再試');
    } on DioException catch (e) {
      return switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout => const FeedbackResult.fail(
          '連線逾時，請稍後再試',
        ),
        _ => const FeedbackResult.fail('無法連線，請確認網路'),
      };
    } catch (e) {
      return FeedbackResult.fail('送出失敗（${e.runtimeType}）');
    } finally {
      dio.close();
    }
  }
}
