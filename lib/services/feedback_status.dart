import 'dart:async';
import 'dart:convert';

import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// 回報處理狀態。
enum FeedbackStatusKind {
  resolved('resolved', '已解決'),
  inProgress('in_progress', '處理中'),
  cannotReproduce('cannot_reproduce', '無法重現');

  final String json;
  final String label;
  const FeedbackStatusKind(this.json, this.label);

  static FeedbackStatusKind? fromJson(Object? v) {
    if (v is! String) return null;
    for (final k in values) {
      if (k.json == v) return k;
    }
    return null;
  }
}

class FeedbackStatus {
  final FeedbackStatusKind kind;
  final String? note;
  const FeedbackStatus(this.kind, [this.note]);
}

/// 狀態檔網址，可用 --dart-define=REPORT_STATUS_URL=... 覆寫。
const String kFeedbackStatusUrl = String.fromEnvironment(
  'REPORT_STATUS_URL',
  defaultValue: 'https://raw.githubusercontent.com/gordonpow/PiliBTR/main/report_status.json',
);

const int _noteMaxRunes = 80;

/// 解析狀態檔；頂層格式不合法回 null，單筆不合法只跳過該筆。
Map<String, FeedbackStatus>? tryDecodeFeedbackStatus(String raw) {
  try {
    final root = jsonDecode(raw);
    if (root is! Map) return null;
    final reports = root['reports'];
    if (reports is! Map) return null;
    final result = <String, FeedbackStatus>{};
    reports.forEach((key, value) {
      if (key is! String || value is! Map) return;
      final kind = FeedbackStatusKind.fromJson(value['status']);
      if (kind == null) return;
      final id = key.trim().toUpperCase();
      if (id.isEmpty) return;
      String? note;
      final n = value['note'];
      if (n is String) {
        final runes = n.trim().runes;
        if (runes.isNotEmpty) {
          note = String.fromCharCodes(runes.take(_noteMaxRunes));
        }
      }
      result[id] = FeedbackStatus(kind, note);
    });
    return result;
  } catch (_) {
    return null;
  }
}

abstract final class FeedbackStatusService {
  /// 取得處理狀態；任何失敗都不拋例外，最差回空 Map。
  static Future<Map<String, FeedbackStatus>> load() async {
    // 乾淨的 Dio：不帶 bilibili cookie 與攔截器
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        validateStatus: (_) => true,
        responseType: ResponseType.plain,
      ),
    );
    try {
      // 加時間戳避開 raw CDN 快取
      final url = Uri.parse(
        '$kFeedbackStatusUrl?t=${DateTime.now().millisecondsSinceEpoch}',
      );
      final res = await dio
          .getUri<String>(url)
          .timeout(const Duration(seconds: 8));
      final code = res.statusCode ?? 0;
      if (code == 200) {
        final body = res.data ?? '';
        final decoded = tryDecodeFeedbackStatus(body);
        if (decoded != null) {
          try {
            await GStorage.setting.put(SettingBoxKey.feedbackStatusCache, body);
          } catch (e) {
            debugPrint('回報狀態：寫入快取失敗 ${e.runtimeType}');
          }
          return decoded;
        }
        debugPrint('回報狀態：格式不合法，改用快取');
      } else if (code == 404) {
        // 狀態檔已刪除，視為空狀態並清除快取
        try {
          await GStorage.setting.delete(SettingBoxKey.feedbackStatusCache);
        } catch (e) {
          debugPrint('回報狀態：清除快取失敗 ${e.runtimeType}');
        }
        return const {};
      } else {
        debugPrint('回報狀態：HTTP $code，改用快取');
      }
    } catch (e) {
      debugPrint('回報狀態：下載失敗 ${e.runtimeType}，改用快取');
    } finally {
      dio.close();
    }
    return cached();
  }

  /// 讀取本機快取的狀態。
  static Map<String, FeedbackStatus> cached() {
    try {
      final raw = GStorage.setting.get(SettingBoxKey.feedbackStatusCache);
      if (raw is String) return tryDecodeFeedbackStatus(raw) ?? const {};
    } catch (e) {
      debugPrint('回報狀態：讀取快取失敗 ${e.runtimeType}');
    }
    return const {};
  }
}
