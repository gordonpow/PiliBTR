import 'dart:convert';

import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter/foundation.dart';

/// 一筆本機回報紀錄。
class FeedbackRecord {
  final String id;
  final DateTime time;
  final String category;
  final String summary;

  const FeedbackRecord({
    required this.id,
    required this.time,
    required this.category,
    required this.summary,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'time': time.toIso8601String(),
    'category': category,
    'summary': summary,
  };
}

const int kFeedbackHistoryMax = 20;
const int kFeedbackSummaryMaxRunes = 60;

/// 解析回報紀錄 JSON；格式錯誤回傳空清單，略過壞掉的項目。
List<FeedbackRecord> decodeFeedbackHistory(Object? raw) {
  if (raw is! String || raw.isEmpty) return [];
  try {
    final json = jsonDecode(raw);
    if (json is! List) return [];
    final out = <FeedbackRecord>[];
    for (final e in json) {
      if (e is! Map) continue;
      final id = e['id'];
      final time = DateTime.tryParse('${e['time']}');
      final cat = e['category'];
      if (id is! String || time == null || cat is! String) continue;
      final summary = e['summary'];
      out.add(
        FeedbackRecord(
          id: id,
          time: time,
          category: cat,
          summary: summary is String ? summary : '',
        ),
      );
    }
    return out;
  } catch (_) {
    return [];
  }
}

/// 把新紀錄放到最前面並只保留最新 [kFeedbackHistoryMax] 筆。
String encodeFeedbackHistory(
  FeedbackRecord record,
  List<FeedbackRecord> existing,
) {
  final list = [record, ...existing].take(kFeedbackHistoryMax).toList();
  return jsonEncode(list.map((e) => e.toJson()).toList());
}

/// 取描述前 [kFeedbackSummaryMaxRunes] 字，換行壓成空白。
String summarizeDescription(String description) {
  final text = description.trim().replaceAll(RegExp(r'\s+'), ' ');
  final runes = text.runes;
  if (runes.length <= kFeedbackSummaryMaxRunes) return text;
  return String.fromCharCodes(runes.take(kFeedbackSummaryMaxRunes));
}

abstract final class FeedbackHistory {
  static List<FeedbackRecord> load() {
    try {
      return decodeFeedbackHistory(
        GStorage.setting.get(SettingBoxKey.feedbackHistory),
      );
    } catch (_) {
      return [];
    }
  }

  static Future<void> add({
    required String id,
    required String category,
    required String description,
    DateTime? time,
  }) async {
    try {
      final rec = FeedbackRecord(
        id: id,
        time: time ?? DateTime.now(),
        category: category,
        summary: summarizeDescription(description),
      );
      await GStorage.setting.put(
        SettingBoxKey.feedbackHistory,
        encodeFeedbackHistory(rec, load()),
      );
    } catch (e) {
      debugPrint('回報：儲存紀錄失敗 $e');
    }
  }
}
