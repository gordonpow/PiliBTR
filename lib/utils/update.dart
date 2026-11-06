import 'dart:async' show Timer;
import 'dart:io' show Directory, File, Platform;

import 'package:PiliPlus/btr_version.dart';
import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/http/api.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:collection/collection.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

/// A release on GitHub that is newer than this build.
class UpdateInfo {
  const UpdateInfo({
    required this.tag,
    required this.body,
    required this.htmlUrl,
    required this.assets,
  });

  final String tag;
  final String body;
  final String htmlUrl;

  /// Name and download URL of each file of the release.
  final List<({String name, String url})> assets;
}

/// Checks the PiliBTR releases on GitHub. It never shows a dialog by
/// itself: a new version only sets [available], which shows red dots on
/// the "mine" tab, the settings button and the update setting.
abstract final class Update {
  static final available = Rxn<UpdateInfo>();
  static final checking = false.obs;

  /// Download progress from 0 to 1, or null when no download runs.
  static final progress = RxnDouble();

  static const _channel = MethodChannel('pilibtr/update');

  static final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      headers: {
        'accept': 'application/vnd.github+json',
        'user-agent': 'PiliBTR',
      },
    ),
  );

  /// Version numbers of a tag like `v2.2.0-btr.7`.
  static List<int> _parse(String tag) {
    final m = RegExp(r'(\d+)\.(\d+)\.(\d+)(?:-btr\.(\d+))?').firstMatch(tag);
    if (m == null) return const [0, 0, 0, 0];
    return [for (var i = 1; i <= 4; i++) int.tryParse(m[i] ?? '') ?? 0];
  }

  static bool _isNewer(String tag, String current) {
    final a = _parse(tag), b = _parse(current);
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  /// Start time of the last check (automatic or manual).
  static DateTime? _lastCheck;
  static Timer? _timer;

  /// Starts or updates the automatic check. If the last check is older
  /// than [Pref.updateIntervalHours] (or there was no check since the app
  /// started), it checks now. Then it checks again after each interval.
  /// Call it when the app starts, when the app comes back to the
  /// foreground (timers do not run while the app is in the background),
  /// and when the settings change. If [Pref.autoUpdate] is off, it stops.
  static void startAuto() {
    _timer?.cancel();
    _timer = null;
    if (!Pref.autoUpdate) return;
    final interval = Duration(hours: Pref.updateIntervalHours);
    final last = _lastCheck;
    final wait = last == null
        ? Duration.zero
        : last.add(interval).difference(DateTime.now());
    if (wait <= Duration.zero) {
      check();
      _timer = Timer(interval, startAuto);
    } else {
      _timer = Timer(wait, startAuto);
    }
  }

  /// Checks for a new release. With [silent], it shows no message.
  static Future<void> check({bool silent = true}) async {
    if (checking.value) return;
    checking.value = true;
    _lastCheck = DateTime.now();
    try {
      final res = await _dio.get(Api.latestApp);
      final data = res.data;
      if (data is! List) throw const FormatException('no release list');
      final release = data.cast<Map>().firstWhereOrNull(
        (e) => e['draft'] != true && e['prerelease'] != true,
      );
      final tag = release?['tag_name'] as String?;
      if (release == null || tag == null || !_isNewer(tag, btrVersion)) {
        available.value = null;
        _deleteDownloads();
        if (!silent) SmartDialog.showToast('已是最新版本');
        return;
      }
      available.value = UpdateInfo(
        tag: tag,
        body: (release['body'] as String?)?.trim() ?? '',
        htmlUrl:
            release['html_url'] as String? ??
            '${Constants.sourceCodeUrl}/releases/latest',
        assets: [
          for (final Map a in (release['assets'] as List? ?? const []))
            (
              name: a['name'] as String,
              url: a['browser_download_url'] as String,
            ),
        ],
      );
      if (!silent) SmartDialog.showToast('發現新版本 $tag');
    } catch (e) {
      if (kDebugMode) debugPrint('failed to check update: $e');
      if (!silent) SmartDialog.showToast('檢查更新失敗，請檢查網路');
    } finally {
      checking.value = false;
    }
  }

  /// Removes downloaded APKs: this build is up to date, so they are old.
  static Future<void> _deleteDownloads() async {
    try {
      final dir = Directory('${(await getTemporaryDirectory()).path}/update');
      if (dir.existsSync()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  /// Downloads the APK of [info] for this device and opens the system
  /// installer. On other platforms it opens the release page.
  static Future<void> downloadAndInstall(UpdateInfo info) async {
    if (progress.value != null) return;
    if (!Platform.isAndroid) {
      PageUtils.launchURL(info.htmlUrl);
      return;
    }
    final abis = (await DeviceInfoPlugin().androidInfo).supportedAbis;
    ({String name, String url})? asset;
    for (final abi in abis) {
      asset = info.assets.firstWhereOrNull(
        (e) => e.name.contains(abi) && e.name.endsWith('.apk'),
      );
      if (asset != null) break;
    }
    if (asset == null) {
      SmartDialog.showToast('找不到適用此裝置的安裝檔');
      PageUtils.launchURL(info.htmlUrl);
      return;
    }
    // The installer reads the file through the FileProvider path
    // `cache/update/` (android/app/src/main/res/xml/update_paths.xml).
    final dir = Directory('${(await getTemporaryDirectory()).path}/update');
    final file = File('${dir.path}/${asset.name}');
    progress.value = 0;
    try {
      // A complete file stays after a download (for example when the
      // user must first allow installs): use it again.
      if (!file.existsSync()) {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
        dir.createSync(recursive: true);
        final part = '${file.path}.part';
        await _dio.download(
          asset.url,
          part,
          onReceiveProgress: (received, total) {
            if (total > 0) progress.value = received / total;
          },
        );
        File(part).renameSync(file.path);
      }
      progress.value = null;
      final result = await _channel.invokeMethod<String>('installApk', {
        'path': file.path,
      });
      if (result == 'permission') {
        SmartDialog.showToast('請允許 PiliBTR 安裝應用程式，再按一次安裝');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('update download error: $e');
      SmartDialog.showToast('下載更新失敗：$e');
    } finally {
      progress.value = null;
    }
  }
}
