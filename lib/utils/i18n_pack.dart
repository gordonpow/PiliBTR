import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, visibleForTesting;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// A template of the language pack, for example `{0}分鐘前` -> `{0} min ago`.
/// The Chinese key becomes an anchored [RegExp]; each `{n}` is `(.+?)`.
class I18nTemplate {
  I18nTemplate._(this.regex, this.groupNumbers, this.english, this.zhLength);

  final RegExp regex;

  /// The `{n}` number of each capture group, in order of appearance.
  final List<int> groupNumbers;
  final String english;

  /// Length of the Chinese part without placeholders. Longer goes first.
  final int zhLength;

  static final _placeholder = RegExp(r'\{(\d+)\}');

  /// Returns null when the template cannot be matched safely: two
  /// placeholders side by side, no Chinese part, or a Chinese part with
  /// fewer than 2 characters.
  static I18nTemplate? tryParse(String zh, String english) {
    final buf = StringBuffer('^');
    final numbers = <int>[];
    var last = 0;
    var zhLength = 0;
    var prevWasPlaceholder = false;
    for (final m in _placeholder.allMatches(zh)) {
      final literal = zh.substring(last, m.start);
      if (literal.isEmpty && prevWasPlaceholder) return null;
      buf
        ..write(RegExp.escape(literal))
        ..write('(.+?)');
      zhLength += literal.length;
      numbers.add(int.parse(m.group(1)!));
      prevWasPlaceholder = true;
      last = m.end;
    }
    final tail = zh.substring(last);
    buf
      ..write(RegExp.escape(tail))
      ..write(r'$');
    zhLength += tail.length;
    if (numbers.isEmpty || zhLength < 2) return null;
    return I18nTemplate._(
      RegExp(buf.toString(), dotAll: true),
      numbers,
      english,
      zhLength,
    );
  }

  /// English text with the captured fragments put in, or null if no match.
  String? apply(String text, String Function(String fragment) lookup) {
    final m = regex.firstMatch(text);
    if (m == null) return null;
    final fragments = <int, String>{};
    for (var i = 0; i < groupNumbers.length; i++) {
      fragments[groupNumbers[i]] = lookup(m.group(i + 1)!);
    }
    return english.replaceAllMapped(
      _placeholder,
      (p) => fragments[int.parse(p.group(1)!)] ?? p.group(0)!,
    );
  }
}

/// The English UI language pack (`i18n/en.json` of the repo). It is
/// downloaded when the user picks English and read from the app documents
/// folder at start. [translate] is called by `ZhConvert.convert`.
abstract final class I18nPack {
  static const url =
      'https://raw.githubusercontent.com/gordonpow/PiliBTR/main/i18n/en.json';
  static const _checkInterval = Duration(days: 7);
  static const _cacheSize = 4096;
  static const _cacheMaxLength = 200;

  static Map<String, String> _strings = const {};
  static List<I18nTemplate> _templates = const [];
  static String _version = '';

  // Map literals keep insertion order, which makes this an LRU cache.
  static final _cache = <String, String>{};

  static final _cjk = RegExp(r'[㐀-鿿豈-﫿]');

  /// Version of the loaded pack, empty when none is loaded.
  static String get version => _version;
  static bool get isLoaded => _strings.isNotEmpty || _templates.isNotEmpty;

  static Future<File> _file(String name) async {
    final dir = Directory(
      path.join((await getApplicationDocumentsDirectory()).path, 'i18n'),
    );
    if (!dir.existsSync()) await dir.create(recursive: true);
    return File(path.join(dir.path, name));
  }

  /// Reads the saved pack into memory. Never throws: on any error the
  /// pack stays empty and the UI stays in Traditional Chinese.
  static Future<void> load() async {
    try {
      final file = await _file('en.json');
      if (!file.existsSync()) return;
      final json = jsonDecode(await file.readAsString());
      if (json is Map<String, dynamic>) loadJson(json);
    } catch (e) {
      if (kDebugMode) debugPrint('I18nPack.load: $e');
    }
  }

  /// Loads the saved pack and returns true if it has strings.
  static Future<bool> loadValid() async {
    await load();
    return _strings.isNotEmpty;
  }

  /// Puts a decoded pack into memory.
  @visibleForTesting
  static void loadJson(Map<String, dynamic> json) {
    final strings = _stringMap(json['strings']);
    final templates = buildTemplates(_stringMap(json['templates']));
    _strings = strings;
    _templates = templates;
    _version = json['version']?.toString() ?? '';
    _cache.clear();
  }

  @visibleForTesting
  static void clear() {
    _strings = const {};
    _templates = const [];
    _version = '';
    _cache.clear();
  }

  static Map<String, String> _stringMap(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final e in raw.entries)
        if (e.key is String &&
            e.value is String &&
            (e.value as String).isNotEmpty)
          e.key as String: e.value as String,
    };
  }

  /// Turns the template map into regexps, longest Chinese part first.
  @visibleForTesting
  static List<I18nTemplate> buildTemplates(Map<String, String> templates) {
    final list = <I18nTemplate>[];
    for (final e in templates.entries) {
      final t = I18nTemplate.tryParse(e.key, e.value);
      if (t != null) list.add(t);
    }
    list.sort((a, b) => b.zhLength.compareTo(a.zhLength));
    return list;
  }

  /// English text for [s], or [s] when the pack has none.
  static String translate(String s) {
    if (s.isEmpty || !isLoaded) return s;
    final exact = _strings[s];
    if (exact != null) return exact;
    if (!_cjk.hasMatch(s)) return s;
    final cacheable = s.length <= _cacheMaxLength;
    if (cacheable) {
      final hit = _cache.remove(s);
      if (hit != null) {
        _cache[s] = hit;
        return hit;
      }
    }
    final result = _templateTranslate(s, 0);
    if (cacheable) {
      if (_cache.length >= _cacheSize) _cache.remove(_cache.keys.first);
      _cache[s] = result;
    }
    return result;
  }

  static String _templateTranslate(String s, int depth) {
    for (final t in _templates) {
      final out = t.apply(s, (fragment) {
        // Captured fragment can be a fixed string: 進入 / 退出.
        final hit = _strings[fragment];
        if (hit != null) return hit;
        if (depth < 2 && _cjk.hasMatch(fragment)) {
          return _templateTranslate(fragment, depth + 1);
        }
        return fragment;
      });
      if (out != null) return out;
    }
    return s;
  }

  // ---- download and update ----

  static Dio _newDio() => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      responseType: ResponseType.plain,
    ),
  );

  /// Downloads the pack and saves it. Returns the pack version. Throws on
  /// a network error or an invalid pack. Does not load it into memory.
  static Future<String> download({
    void Function(int received, int total)? onProgress,
  }) async {
    final res = await _newDio().get<String>(
      url,
      onReceiveProgress: onProgress,
    );
    final body = res.data;
    if (body == null) throw const FormatException('empty language pack');
    final json = jsonDecode(body);
    if (json is! Map<String, dynamic> ||
        json['strings'] is! Map ||
        (json['strings'] as Map).isEmpty) {
      throw const FormatException('invalid language pack');
    }
    final file = await _file('en.json');
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(body);
    // Windows cannot rename over an existing file.
    if (file.existsSync()) await file.delete();
    await tmp.rename(file.path);
    await _saveCheckTime();
    return json['version']?.toString() ?? '';
  }

  static Future<void> _saveCheckTime() async {
    try {
      final meta = await _file('meta.json');
      await meta.writeAsString(
        jsonEncode({'lastCheck': DateTime.now().millisecondsSinceEpoch}),
      );
    } catch (_) {}
  }

  static Future<int> _lastCheck() async {
    try {
      final meta = await _file('meta.json');
      if (!meta.existsSync()) return 0;
      final json = jsonDecode(await meta.readAsString());
      return json is Map ? (json['lastCheck'] as int? ?? 0) : 0;
    } catch (_) {
      return 0;
    }
  }

  /// Downloads the pack when its version differs from the loaded one.
  /// Returns true if a new version was saved (used at next start). Throws
  /// on error.
  static Future<bool> checkUpdate() async {
    final old = _version;
    final latest = await download();
    return latest != old;
  }

  /// English mode only: check in the background when the last check is
  /// more than 7 days ago. Errors are ignored.
  static Future<void> maybeUpdateInBackground() async {
    try {
      final last = DateTime.fromMillisecondsSinceEpoch(await _lastCheck());
      if (DateTime.now().difference(last) < _checkInterval) return;
      await checkUpdate();
    } catch (e) {
      if (kDebugMode) debugPrint('I18nPack update: $e');
    }
  }
}
