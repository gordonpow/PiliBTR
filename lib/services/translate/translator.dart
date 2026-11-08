import 'dart:collection';
import 'dart:io' show Platform;

import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

/// Subtitle translation service. The index is stored in
/// `SettingBoxKey.translateService`.
enum TranslateService {
  offline('離線模型'),
  deepl('DeepL'),
  google('Google Cloud');

  const TranslateService(this.label);
  final String label;
}

enum ModelStatus { unsupported, notDownloaded, downloaded }

/// Result of [Translator.ensureModel].
typedef ModelResult = ({bool ok, String? error});

/// Chinese to English translation: on-device ML Kit (Android only), plus
/// DeepL / Google Cloud Translation for subtitles.
///
/// Every failure returns the original text, so callers can always display
/// the result.
abstract final class Translator {
  /// English UI mode (`Pref.appLanguage == 3`).
  static bool get isEnglishMode => Pref.appLanguage == 3;

  static bool get offlineSupported => Platform.isAndroid;

  /// Danmaku are translated with the offline model only.
  static bool get danmakuEnabled =>
      isEnglishMode && Pref.translateDanmaku && offlineSupported;

  static TranslateService get service {
    final i = Pref.translateService;
    final s = TranslateService.values[i >= 0 && i < 3 ? i : 0];
    // No offline model off Android: use the online service that has a key.
    if (s == TranslateService.offline && !offlineSupported) {
      if (deeplApiKey.isNotEmpty) return TranslateService.deepl;
      if (googleApiKey.isNotEmpty) return TranslateService.google;
    }
    return s;
  }

  /// Services shown in settings (no offline option off Android).
  static List<TranslateService> get availableServices => [
    for (final s in TranslateService.values)
      if (s != TranslateService.offline || offlineSupported) s,
  ];

  static const _deeplKey = 'deepl';
  static const _googleKey = 'google';

  static String get deeplApiKey =>
      GStorage.translateSecrets.get(_deeplKey)?.trim() ?? '';
  static String get googleApiKey =>
      GStorage.translateSecrets.get(_googleKey)?.trim() ?? '';

  static Future<void> setApiKey(TranslateService service, String key) {
    final k = switch (service) {
      TranslateService.deepl => _deeplKey,
      TranslateService.google => _googleKey,
      TranslateService.offline => null,
    };
    if (k == null) return Future.value();
    key = key.trim();
    return key.isEmpty
        ? GStorage.translateSecrets.delete(k)
        : GStorage.translateSecrets.put(k, key);
  }

  /// A key is present for the selected online service.
  static bool get onlineConfigured => switch (service) {
    TranslateService.deepl => deeplApiKey.isNotEmpty,
    TranslateService.google => googleApiKey.isNotEmpty,
    TranslateService.offline => false,
  };

  static const modelUnavailableMessage =
      '離線模型無法使用，可在 播放 › 字幕 › 翻譯服務 填入 DeepL 或 Google Cloud 金鑰';

  static final _cjk = RegExp(r'[㐀-鿿]');

  static bool needsTranslation(String text) => _cjk.hasMatch(text);

  // ---- LRU cache (key: original text) ----

  static const _cacheLimit = 5000;
  static final LinkedHashMap<String, String> _cache = LinkedHashMap();

  /// Cached translation, or null.
  static String? cached(String text) {
    final v = _cache.remove(text);
    if (v != null) _cache[text] = v;
    return v;
  }

  static void _put(String text, String translated) {
    _cache.remove(text);
    _cache[text] = translated;
    if (_cache.length > _cacheLimit) {
      _cache.remove(_cache.keys.first);
    }
  }

  // ---- Public API ----

  /// Translates [texts]; items that fail (or do not need translation) are
  /// returned unchanged. With [online] and a configured key the online
  /// service is used first, then the offline model.
  static Future<List<String>> translateBatch(
    List<String> texts, {
    bool online = false,
  }) async {
    final result = List<String>.of(texts);
    final todo = <String>{};
    for (var i = 0; i < texts.length; i++) {
      final t = texts[i];
      if (!needsTranslation(t)) continue;
      final c = cached(t);
      if (c != null) {
        result[i] = c;
      } else {
        todo.add(t);
      }
    }
    if (todo.isEmpty) return result;

    final done = <String, String>{};
    var remaining = todo.toList();

    if (online && onlineConfigured) {
      remaining = await _translateOnline(remaining, done);
    }
    if (remaining.isNotEmpty) {
      await _translateOffline(remaining, done);
    }

    done.forEach(_put);
    for (var i = 0; i < texts.length; i++) {
      if (done[texts[i]] case final v?) result[i] = v;
    }
    return result;
  }

  // ---- Online ----

  static Dio? _dio;
  // Own Dio: no bilibili base url, cookies or account interceptors.
  static Dio get _client => _dio ??= Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  /// Returns the texts that failed.
  static Future<List<String>> _translateOnline(
    List<String> texts,
    Map<String, String> out,
  ) async {
    final failed = <String>[];
    final isDeepl = service == TranslateService.deepl;
    final size = isDeepl ? 50 : 128;
    for (var i = 0; i < texts.length; i += size) {
      final end = i + size > texts.length ? texts.length : i + size;
      final chunk = texts.sublist(i, end);
      try {
        final res = isDeepl ? await _deepl(chunk) : await _google(chunk);
        if (res.length != chunk.length) throw StateError('length mismatch');
        for (var j = 0; j < chunk.length; j++) {
          if (res[j].isNotEmpty) {
            out[chunk[j]] = res[j];
          } else {
            failed.add(chunk[j]);
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('online translate failed: $e');
        failed.addAll(chunk);
      }
    }
    return failed;
  }

  static Future<List<String>> _deepl(List<String> chunk) async {
    final key = deeplApiKey;
    final host = key.endsWith(':fx') ? 'api-free.deepl.com' : 'api.deepl.com';
    final res = await _client.post(
      'https://$host/v2/translate',
      data: {
        'text': chunk,
        'source_lang': 'ZH',
        'target_lang': 'EN-US',
      },
      options: Options(headers: {'Authorization': 'DeepL-Auth-Key $key'}),
    );
    return (res.data['translations'] as List)
        .map((e) => e['text'] as String)
        .toList();
  }

  static Future<List<String>> _google(List<String> chunk) async {
    final res = await _client.post(
      'https://translation.googleapis.com/language/translate/v2',
      // Key in a header, not the URL: DioException prints the URI.
      options: Options(headers: {'X-goog-api-key': googleApiKey}),
      data: {'q': chunk, 'source': 'zh', 'target': 'en', 'format': 'text'},
    );
    return (res.data['data']['translations'] as List)
        .map((e) => _unescapeHtml(e['translatedText'] as String))
        .toList();
  }

  static String _unescapeHtml(String s) => s
      .replaceAll('&#39;', "'")
      .replaceAll('&quot;', '"')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');

  // ---- Offline (ML Kit, Android only) ----

  static const _zh = 'zh';
  static const _en = 'en';

  static OnDeviceTranslatorModelManager? _manager;
  static OnDeviceTranslatorModelManager get _modelManager =>
      _manager ??= OnDeviceTranslatorModelManager();
  static OnDeviceTranslator? _translator;

  static bool _modelReady = false;
  static DateTime? _lastCheck;

  /// Last error from [ensureModel], for display.
  static String? lastModelError;

  /// Whether the offline model is usable now. A negative answer is cached
  /// for 30 seconds so repeated callers do not hammer the platform channel.
  static Future<bool> isOfflineReady() async {
    if (!offlineSupported) return false;
    if (_modelReady) return true;
    final last = _lastCheck;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 30)) {
      return false;
    }
    _lastCheck = DateTime.now();
    _modelReady = await _bothDownloaded();
    return _modelReady;
  }

  // Tail of the offline queue: ML Kit runs one batch at a time, even when
  // the content queue and the danmaku queue both call in.
  static Future<void> _offlineChain = Future<void>.value();

  static Future<void> _translateOffline(
    List<String> texts,
    Map<String, String> out,
  ) {
    final run = _offlineChain.then((_) => _translateOfflineLocked(texts, out));
    // An error must not break the chain for later callers.
    _offlineChain = run.catchError((Object _) {});
    return run;
  }

  static Future<void> _translateOfflineLocked(
    List<String> texts,
    Map<String, String> out,
  ) async {
    if (!await isOfflineReady()) return;
    final t = _translator ??= OnDeviceTranslator(
      sourceLanguage: TranslateLanguage.chinese,
      targetLanguage: TranslateLanguage.english,
    );
    for (final text in texts) {
      try {
        final r = (await t.translateText(text)).trim();
        if (r.isNotEmpty) out[text] = r;
      } catch (e) {
        if (kDebugMode) debugPrint('offline translate failed: $e');
      }
    }
  }

  /// zh to en needs both the zh and the en model.
  static Future<bool> _bothDownloaded() async {
    try {
      return await _modelManager.isModelDownloaded(_zh) &&
          await _modelManager.isModelDownloaded(_en);
    } catch (_) {
      return false;
    }
  }

  static Future<ModelStatus> modelStatus() async {
    if (!offlineSupported) return ModelStatus.unsupported;
    final ok = await _bothDownloaded();
    _modelReady = ok;
    return ok ? ModelStatus.downloaded : ModelStatus.notDownloaded;
  }

  /// Downloads the zh and en models when missing. The plugin reports no
  /// progress, so callers only get the final result. This is also the entry
  /// point to call when the user switches to English.
  static Future<ModelResult> ensureModel() async {
    if (!offlineSupported) {
      return (ok: false, error: '此平台不支援離線翻譯');
    }
    try {
      final zh = await _modelManager.downloadModel(
        _zh,
        isWifiRequired: false,
      );
      final en = await _modelManager.downloadModel(
        _en,
        isWifiRequired: false,
      );
      if (zh && en) {
        _modelReady = true;
        lastModelError = null;
        return (ok: true, error: null);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('model download failed: $e');
    }
    _modelReady = false;
    _lastCheck = DateTime.now();
    lastModelError = modelUnavailableMessage;
    return (ok: false, error: modelUnavailableMessage);
  }

  static Future<bool> deleteModel() async {
    if (!offlineSupported) return false;
    try {
      await _translator?.close();
      _translator = null;
      final ok = await _modelManager.deleteModel(_zh);
      // The built-in English model may not be deletable; ignore errors.
      try {
        await _modelManager.deleteModel(_en);
      } catch (_) {}
      if (ok) _modelReady = false;
      return ok;
    } catch (_) {
      return false;
    }
  }
}
