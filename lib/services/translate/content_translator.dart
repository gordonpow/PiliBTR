import 'dart:async';

import 'package:PiliPlus/services/translate/translator.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart';

/// Queue priority of a content translation request.
enum ContentPriority {
  /// Titles, badges, tags: what the user sees first.
  high,

  /// Comments, dynamics, descriptions.
  low,
}

/// A per-sentence notifier. It leaves [ContentTranslator] when its last
/// listener goes away, so notifiers of recycled list items do not pile up.
class _SentenceNotifier extends ValueNotifier<String?> {
  _SentenceNotifier(this.text, super.value);

  final String text;

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      ContentTranslator._release(this);
    }
  }
}

/// Translates server content (titles, comments, ...) to English with the
/// offline model, through one global queue:
///
/// - requests made within 100 ms form one batch (at most 16 sentences);
/// - only one batch is sent to ML Kit at a time;
/// - the newest request is translated first (LIFO), high priority first;
/// - each priority keeps a bounded queue (300 / 150), the oldest is dropped;
/// - results are cached in [Translator]'s LRU cache and announced to the
///   listeners of that sentence only.
abstract final class ContentTranslator {
  static const _batchDelay = Duration(milliseconds: 100);
  static const _batchSize = 16;
  static const _highLimit = 300;
  static const _lowLimit = 150;
  static const _failedRetry = Duration(seconds: 60);

  // ---- Enabled switch ----

  static bool _compute() =>
      Translator.isEnglishMode &&
      Pref.translateContent &&
      Translator.offlineSupported;

  static ValueNotifier<bool>? _enabled;

  /// English mode, the setting is on and the offline model is supported.
  static ValueListenable<bool> get enabled =>
      _enabled ??= ValueNotifier(_compute());

  static bool get isEnabled => enabled.value;

  /// Call after the setting or the language changed.
  static void refreshEnabled() {
    _failed.clear();
    _enabled?.value = _compute();
  }

  // ---- Queue ----

  static final _high = <String>{};
  static final _low = <String>{};
  static final _inFlight = <String>{};
  // Texts that could not be translated (model missing, ...), each with the
  // time it may be retried.
  static final _failed = <String, DateTime>{};
  static final _notifiers = <String, _SentenceNotifier>{};
  static Timer? _timer;
  static bool _running = false;

  static bool needsTranslation(String? text) =>
      text != null && text.isNotEmpty && Translator.needsTranslation(text);

  /// The cached translation, or null.
  static String? cached(String text) => Translator.cached(text);

  /// A listenable of the translation of [text] (null until translated).
  /// It only fires for this sentence.
  static ValueListenable<String?> listen(String text) =>
      _notifiers[text] ??= _SentenceNotifier(text, cached(text));

  static void _release(_SentenceNotifier n) {
    if (identical(_notifiers[n.text], n)) _notifiers.remove(n.text);
  }

  /// The translation when cached, otherwise [text] (and a request is queued).
  /// Wrap the user of the result in a `ContentTextBuilder` to get updates.
  static String textOf(
    String text, {
    ContentPriority priority = ContentPriority.high,
  }) {
    if (!isEnabled || !needsTranslation(text)) return text;
    final c = cached(text);
    if (c != null) return c;
    request(text, priority: priority);
    return text;
  }

  /// Queues [text] for translation.
  static void request(
    String text, {
    ContentPriority priority = ContentPriority.high,
  }) {
    if (!isEnabled || !needsTranslation(text)) return;
    if (cached(text) != null || _inFlight.contains(text)) return;
    final until = _failed[text];
    if (until != null) {
      if (DateTime.now().isBefore(until)) return;
      _failed.remove(text);
    }
    final high = priority == ContentPriority.high;
    final q = high ? _high : _low;
    (high ? _low : _high).remove(text);
    // The newest request goes to the end (translated first).
    q
      ..remove(text)
      ..add(text);
    final limit = high ? _highLimit : _lowLimit;
    while (q.length > limit) {
      q.remove(q.first);
    }
    _schedule();
  }

  static void _schedule() {
    if (_running || (_timer?.isActive ?? false)) return;
    _timer = Timer(_batchDelay, _run);
  }

  static List<String> _takeBatch() {
    final q = _high.isNotEmpty ? _high : _low;
    final batch = <String>[];
    while (batch.length < _batchSize && q.isNotEmpty) {
      final t = q.last;
      q.remove(t);
      batch.add(t);
    }
    return batch;
  }

  static Future<void> _run() async {
    if (_running) return;
    _running = true;
    try {
      while (_high.isNotEmpty || _low.isNotEmpty) {
        if (!isEnabled) {
          _high.clear();
          _low.clear();
          break;
        }
        final batch = _takeBatch();
        _inFlight.addAll(batch);
        List<String> res;
        try {
          res = await Translator.translateBatch(batch);
        } catch (e) {
          if (kDebugMode) debugPrint('content translate failed: $e');
          res = batch;
        }
        for (var i = 0; i < batch.length; i++) {
          final t = batch[i];
          _inFlight.remove(t);
          final r = i < res.length ? res[i] : t;
          if (r == t) {
            _failed[t] = DateTime.now().add(_failedRetry);
          } else {
            _notifiers[t]?.value = r;
          }
        }
        // Let requests made meanwhile merge into the next batch.
        if (_high.isNotEmpty || _low.isNotEmpty) {
          await Future<void>.delayed(_batchDelay);
        }
      }
    } finally {
      _running = false;
    }
  }
}
