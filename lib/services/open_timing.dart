import 'package:flutter/foundation.dart' show debugPrint;

/// One video open: times in ms from entering the video page.
class OpenTimingRecord {
  int? playUrlMs;
  bool playUrlCacheHit = false;

  /// player.open 呼叫（含 BtrProxy.wrap）到完成。
  int? openMs;

  /// 這次開檔的 BTR 首 byte。
  int? headMs;
  int? firstFrameMs;

  /// 例：「首幀 820 ms（playurl 40 ms 快取・開檔 300 ms・首 byte 180 ms）」；缺的段落省略。
  String summary() {
    final parts = <String>[
      if (playUrlMs != null)
        'playurl $playUrlMs ms${playUrlCacheHit ? ' 快取' : ''}',
      if (openMs != null) '開檔 $openMs ms',
      if (headMs != null) '首 byte $headMs ms',
    ];
    final first = firstFrameMs != null ? '首幀 $firstFrameMs ms' : '首幀 —';
    return parts.isEmpty ? first : '$first（${parts.join('・')}）';
  }
}

abstract final class OpenTiming {
  /// 測試建置用（`--dart-define=btr.timing=true`）：在 logcat 印出從點卡片
  /// 起算的各階段時間（`OPEN-TIME <ms> <stage>`）。
  static const bool log = bool.fromEnvironment('btr.timing');
  static final Stopwatch _tap = Stopwatch();

  /// 點卡片開影片的瞬間。
  static void markTap() {
    if (!log) return;
    _tap
      ..reset()
      ..start();
    mark('tap');
  }

  static void mark(String stage) {
    if (!log) return;
    if (!_tap.isRunning) _tap.start();
    debugPrint('OPEN-TIME ${_tap.elapsedMilliseconds} $stage');
  }

  /// 首幀後停止，下次沒點卡片（例如連結開啟）時從頁面建立起算。
  static void endTap() {
    if (log) _tap..stop()..reset();
  }

  static const _maxRecent = 20;

  /// 最近一次完成的紀錄與本次啟動最近 20 次首幀（ms）。
  static OpenTimingRecord? last;
  static final List<int> recent = [];

  /// 有 firstFrameMs 才加入 recent（上限 20，先進先出）。
  /// 首幀比開檔時間還短（重用 controller 立即完成）時不加入平均。
  static void finish(OpenTimingRecord r) {
    last = r;
    final ms = r.firstFrameMs;
    if (ms == null || ms < (r.openMs ?? 0)) return;
    recent.add(ms);
    while (recent.length > _maxRecent) {
      recent.removeAt(0);
    }
  }

  static int? get averageMs => recent.isEmpty
      ? null
      : (recent.reduce((a, b) => a + b) / recent.length).round();

  /// 影片頁開檔期間的紀錄與該頁串流的原始 URL；BTR 只在 URL 相符時記首 byte。
  static OpenTimingRecord? pending;
  static Set<String> pendingUrls = {};
}
