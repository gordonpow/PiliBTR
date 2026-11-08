import 'dart:collection';

import 'package:PiliPlus/services/translate/translator.dart';

/// Background (offline) translation queue for danmaku. Results land in the
/// [Translator] cache; callers read them with [Translator.cached] and never
/// wait.
class TranslateQueue {
  TranslateQueue({this.maxPending, this.batchSize = 12, this.positionMs});

  /// Max pending texts. With [positionMs] new texts are ignored when full
  /// (the caller feeds nearest first); otherwise the oldest are dropped.
  final int? maxPending;
  final int batchSize;

  /// Current playback position. When set, the nearest upcoming texts are
  /// translated first and already-played ones are dropped. When null the
  /// queue is FIFO.
  final int Function()? positionMs;

  /// text -> time in ms (insertion ordered).
  final LinkedHashMap<String, int> _jobs = LinkedHashMap();
  bool _running = false;
  bool _disposed = false;

  int get length => _jobs.length;

  void add(String text, [int timeMs = 0]) {
    if (_disposed ||
        !Translator.needsTranslation(text) ||
        Translator.cached(text) != null) {
      return;
    }
    final old = _jobs[text];
    if (old != null) {
      if (timeMs < old) _jobs[text] = timeMs;
      return;
    }
    final cap = maxPending;
    if (cap != null && _jobs.length >= cap) {
      if (positionMs != null) return;
      _jobs.remove(_jobs.keys.first);
    }
    _jobs[text] = timeMs;
    _run();
  }

  /// Picks the [batchSize] nearest upcoming texts in one linear pass (no
  /// full sort) and drops the ones already played.
  List<String> _takeBatch() {
    final pos = positionMs;
    if (pos == null) {
      final b = _jobs.keys.take(batchSize).toList();
      for (final k in b) {
        _jobs.remove(k);
      }
      return b;
    }
    final now = pos();
    final played = <String>[];
    final best = <MapEntry<String, int>>[]; // ascending by time
    for (final e in _jobs.entries) {
      if (e.value < now - 1000) {
        played.add(e.key);
        continue;
      }
      if (best.length == batchSize && e.value >= best.last.value) continue;
      var i = best.length;
      while (i > 0 && best[i - 1].value > e.value) {
        i--;
      }
      best.insert(i, e);
      if (best.length > batchSize) best.removeLast();
    }
    final batch = [for (final e in best) e.key];
    for (final k in [...played, ...batch]) {
      _jobs.remove(k);
    }
    return batch;
  }

  Future<void> _run() async {
    if (_running) return;
    _running = true;
    try {
      while (!_disposed && _jobs.isNotEmpty) {
        // Model not ready: pause but keep the jobs; the next add retries.
        if (!await Translator.isOfflineReady()) break;
        if (_disposed) break;
        final batch = _takeBatch();
        if (batch.isEmpty) continue;
        try {
          await Translator.translateBatch(batch);
        } catch (_) {}
      }
    } finally {
      _running = false;
    }
  }

  void dispose() {
    _disposed = true;
    _jobs.clear();
  }
}
