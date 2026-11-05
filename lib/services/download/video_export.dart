import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/pages/video/introduction/pgc/controller.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/controller.dart';
import 'package:PiliPlus/services/download/download_manager.dart';
import 'package:PiliPlus/utils/device_utils.dart';
import 'package:PiliPlus/utils/mp4_mux.dart';
import 'package:PiliPlus/utils/permission_handler.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

/// Downloads the playing video as one MP4 file to a folder the user can
/// open (default: the Download folder). Unlike the offline cache, the file
/// is not managed by the app.
///
/// The video and audio streams are downloaded with [DownloadManager] (BTR
/// multi-thread when it is on) and merged by [Mp4Mux].
abstract final class VideoExport {
  static const _tag = 'videoExport';

  static String get defaultDir {
    if (Platform.isAndroid) return '/storage/emulated/0/Download';
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    return home == null ? '.' : '$home${Platform.pathSeparator}Downloads';
  }

  static String get dir => Pref.exportPath ?? defaultDir;

  static set dir(String? value) => value == null || value == defaultDir
      ? GStorage.setting.delete(SettingBoxKey.exportPath)
      : GStorage.setting.put(SettingBoxKey.exportPath, value);

  static bool _running = false;
  static bool _cancelled = false;
  static final _managers = <DownloadManager>[];
  static final _stage = '準備中'.obs;
  static final _progress = RxnDouble();

  /// Downloads the video of [ctr] at the quality that plays now.
  static Future<void> start(VideoDetailController ctr) async {
    if (_running) {
      SmartDialog.showToast('已有影片正在下載');
      return;
    }
    if (ctr.isFileSource) {
      SmartDialog.showToast('離線影片不需要下載');
      return;
    }
    final videoUrl = ctr.videoUrl;
    final audioUrl = ctr.audioUrl;
    if (videoUrl == null || videoUrl.isEmpty) {
      SmartDialog.showToast('影片尚未載入，請稍後再試');
      return;
    }
    if (!await _requestPermission()) return;

    final title =
        _title(ctr) ?? (ctr.bvid.isEmpty ? '${ctr.cid.value}' : ctr.bvid);
    _running = true;
    _cancelled = false;
    _stage.value = '下載中';
    _progress.value = 0;
    _showPanel(title);

    final tmp = Directory(
      '${(await getTemporaryDirectory()).path}/export/${ctr.cid.value}',
    );
    try {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
      await tmp.create(recursive: true);
      final hasAudio = audioUrl != null && audioUrl.isNotEmpty;
      final videoFile = '${tmp.path}/video.m4s';
      final audioFile = '${tmp.path}/audio.m4s';

      final received = [0, 0], total = [0, 0];
      void onProgress() {
        final t = total[0] + total[1];
        if (t > 0) _progress.value = (received[0] + received[1]) / t;
      }

      await Future.wait([
        _download(videoUrl, videoFile, (r, t) {
          received[0] = r;
          total[0] = t;
          onProgress();
        }),
        if (hasAudio)
          _download(audioUrl, audioFile, (r, t) {
            received[1] = r;
            total[1] = t;
            onProgress();
          }),
      ]);
      _checkCancel();

      final target = await _targetFile(title);
      final part = File('${target.path}.part');
      if (hasAudio) {
        _stage.value = '合併中';
        _progress.value = 0;
        await Mp4Mux.merge(
          videoPath: videoFile,
          audioPath: audioFile,
          outPath: part.path,
          onProgress: (p) => _progress.value = p,
          isCancelled: () => _cancelled,
        );
      } else {
        await File(videoFile).copy(part.path);
      }
      await part.rename(target.path);
      if (Platform.isAndroid) {
        try {
          await const MethodChannel(
            'pilibtr/update',
          ).invokeMethod('scanFile', {'path': target.path});
        } catch (_) {}
      }
      SmartDialog.dismiss(tag: _tag);
      SmartDialog.showToast(
        '已下載到 ${target.path}',
        displayTime: const Duration(seconds: 4),
      );
    } catch (e) {
      SmartDialog.dismiss(tag: _tag);
      if (_cancelled) {
        SmartDialog.showToast('已取消下載');
      } else {
        if (kDebugMode) debugPrint('video export: $e');
        SmartDialog.showToast(
          e is FileSystemException && e.path != null
              ? '無法寫入 ${e.path}，請在設定中改用 Download 或 Movies 底下的資料夾'
              : '下載失敗：$e',
        );
      }
    } finally {
      _managers.clear();
      _running = false;
      _progress.value = null;
      try {
        if (tmp.existsSync()) await tmp.delete(recursive: true);
      } catch (_) {}
    }
  }

  static void cancel() {
    _cancelled = true;
    for (final m in _managers) {
      m.cancel(isDelete: true);
    }
  }

  static void _checkCancel() {
    if (_cancelled) throw StateError('cancelled');
  }

  static Future<void> _download(
    String url,
    String path,
    void Function(int received, int total) onProgress,
  ) {
    final done = Completer<void>();
    final manager = DownloadManager(
      url: url,
      path: path,
      onReceiveProgress: onProgress,
      onDone: ([error]) {
        if (done.isCompleted) return;
        if (error != null) {
          done.completeError(error);
        } else {
          done.complete();
        }
      },
    );
    _managers.add(manager);
    return done.future;
  }

  static Future<bool> _requestPermission() async {
    // Android 11 and later: files in Download need no permission.
    if (!Platform.isAndroid || DeviceUtils.sdkInt > 29) return true;
    final status = await Permission.storage.request();
    if (status.isGranted) return true;
    SmartDialog.showToast('需要儲存權限才能下載到手機');
    return false;
  }

  static String? _title(VideoDetailController ctr) {
    try {
      return ctr.isUgc
          ? Get.find<UgcIntroController>(
              tag: ctr.heroTag,
            ).videoDetail.value.title
          : Get.find<PgcIntroController>(
              tag: ctr.heroTag,
            ).videoDetail.value.title;
    } catch (_) {
      return null;
    }
  }

  /// A free file name in [dir] for [title].
  static Future<File> _targetFile(String title) async {
    final folder = Directory(dir);
    if (!folder.existsSync()) await folder.create(recursive: true);
    var name = title.replaceAll(RegExp(r'[\\/:*?"<>|\r\n\t]'), '_').trim();
    if (name.isEmpty) name = 'video';
    // Count characters, not UTF-16 units: an emoji must not be cut.
    final chars = name.runes.toList();
    if (chars.length > 80) name = String.fromCharCodes(chars.take(80));
    var file = File('${folder.path}${Platform.pathSeparator}$name.mp4');
    for (var i = 2; file.existsSync(); i++) {
      file = File('${folder.path}${Platform.pathSeparator}$name ($i).mp4');
    }
    return file;
  }

  /// Progress card at the bottom of the screen. Touches go through to the
  /// page, so the user can keep watching.
  static void _showPanel(String title) {
    SmartDialog.show(
      tag: _tag,
      alignment: Alignment.bottomCenter,
      usePenetrate: true,
      maskColor: Colors.transparent,
      clickMaskDismiss: false,
      backType: SmartBackType.ignore,
      builder: (context) {
        final colorScheme = ColorScheme.of(context);
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
            constraints: const BoxConstraints(maxWidth: 480),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: const BorderRadius.all(Radius.circular(12)),
              boxShadow: const [
                BoxShadow(blurRadius: 8, color: Color(0x33000000)),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 6),
                      Obx(() {
                        final p = _progress.value;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LinearProgressIndicator(value: p),
                            const SizedBox(height: 4),
                            Text(
                              p == null
                                  ? _stage.value
                                  : '${_stage.value} ${(p * 100).toStringAsFixed(0)}%',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.outline,
                              ),
                            ),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
                const IconButton(
                  tooltip: '取消下載',
                  onPressed: cancel,
                  icon: Icon(Icons.close),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
