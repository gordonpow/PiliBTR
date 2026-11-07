import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/common/widgets/thin_progress_bar.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/pages/video/introduction/pgc/controller.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/controller.dart';
import 'package:PiliPlus/services/download/download_manager.dart';
import 'package:PiliPlus/utils/device_utils.dart';
import 'package:PiliPlus/utils/extension/file_ext.dart';
import 'package:PiliPlus/utils/mp4_mux.dart';
import 'package:PiliPlus/utils/permission_handler.dart';
import 'package:PiliPlus/utils/speed_format.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

/// Stage of the MP4 download.
enum ExportStage {
  downloading('下載中'),
  paused('已暫停'),
  merging('合併中'),
  ;

  final String label;
  const ExportStage(this.label);
}

/// The MP4 download in progress (one at a time).
class ExportTask {
  ExportTask({
    required this.cid,
    required this.bvid,
    required this.title,
    required this.cover,
    required this.videoUrl,
    required this.audioUrl,
    required this.tmpDir,
  });

  final int cid;
  final String bvid;
  final String title;
  final String cover;
  final String videoUrl;
  final String? audioUrl;
  final Directory tmpDir;

  final stage = ExportStage.downloading.obs;

  /// 0 to 1 for the current stage (download or merge).
  final progress = RxnDouble();

  /// Bytes per second while downloading.
  final speed = 0.0.obs;

  bool get hasAudio => audioUrl != null && audioUrl!.isNotEmpty;

  String get videoFile => '${tmpDir.path}/video.m4s';
  String get audioFile => '${tmpDir.path}/audio.m4s';

  /// Received and total bytes of the video (0) and audio (1) stream.
  final received = [0, 0];
  final total = [0, 0];
}

/// A finished MP4 download (kept in [LocalCacheKey.exportRecords]).
class ExportRecord {
  const ExportRecord({
    required this.path,
    required this.title,
    required this.cover,
    required this.bvid,
    required this.cid,
    required this.size,
    required this.time,
  });

  final String path;
  final String title;
  final String cover;
  final String bvid;
  final int cid;
  final int size;

  /// Finish time, milliseconds since epoch.
  final int time;

  Map<String, Object> toJson() => {
    'path': path,
    'title': title,
    'cover': cover,
    'bvid': bvid,
    'cid': cid,
    'size': size,
    'time': time,
  };

  static ExportRecord? fromJson(Object? json) {
    if (json case {
      'path': final String path,
      'title': final String title,
    }) {
      return ExportRecord(
        path: path,
        title: title,
        cover: json['cover'] as String? ?? '',
        bvid: json['bvid'] as String? ?? '',
        cid: json['cid'] as int? ?? 0,
        size: json['size'] as int? ?? 0,
        time: json['time'] as int? ?? 0,
      );
    }
    return null;
  }
}

/// Downloads the playing video as one MP4 file to a folder the user can
/// open (default: the Download folder). Finished files are listed in
/// 我的 → 快取與下載 → 下載 (records in localCache, not synced).
///
/// The video and audio streams are downloaded with [DownloadManager] (BTR
/// multi-thread when it is on) and merged by [Mp4Mux]. The download can be
/// paused and resumed: the parts stay in a temporary folder per cid until
/// the file is done or the user stops it.
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

  /// The download in progress or paused, null when there is none.
  static final current = Rxn<ExportTask>();

  static final _managers = <DownloadManager>[];
  static bool _paused = false;
  static bool _stopped = false;
  static final _meter = SpeedMeter();
  static Timer? _speedTimer;

  /// Downloads the video of [ctr] at the quality that plays now. A paused
  /// or failed earlier download of the same stream goes on from its parts.
  static Future<void> start(VideoDetailController ctr) async {
    if (current.value != null) {
      SmartDialog.showToast('已有影片正在下載，可在「我的 → 快取與下載」管理');
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
    final tmp = Directory(
      '${(await getTemporaryDirectory()).path}/export/${ctr.cid.value}',
    );
    final task = ExportTask(
      cid: ctr.cid.value,
      bvid: ctr.bvid,
      title: title,
      cover: ctr.cover.value,
      videoUrl: videoUrl,
      audioUrl: audioUrl,
      tmpDir: tmp,
    );
    current.value = task;
    try {
      await _prepareTmp(task);
    } catch (e) {
      current.value = null;
      SmartDialog.showToast('下載失敗：$e');
      return;
    }
    _showPanel();
    unawaited(_run(task));
  }

  /// Identity of a stream: the url path without host and query. The same
  /// quality and codec of the same video have the same path on every CDN
  /// node and after the signed link expires.
  static String? _streamKey(String? url) =>
      url == null || url.isEmpty ? null : Uri.tryParse(url)?.path ?? url;

  static File _metaFile(ExportTask t) => File('${t.tmpDir.path}/meta.json');
  static File _doneFile(ExportTask t, int i) =>
      File('${t.tmpDir.path}/${i == 0 ? 'video' : 'audio'}.done');

  /// Keeps the parts of an earlier download of the same streams, else
  /// starts with an empty folder (other quality or codec: the old bytes
  /// would not fit the new stream).
  static Future<void> _prepareTmp(ExportTask t) async {
    final meta = {
      'cid': t.cid,
      'video': _streamKey(t.videoUrl),
      'audio': _streamKey(t.audioUrl),
    };
    var reuse = false;
    final metaFile = _metaFile(t);
    if (metaFile.existsSync()) {
      try {
        final old = jsonDecode(await metaFile.readAsString());
        reuse =
            old is Map &&
            old['cid'] == meta['cid'] &&
            old['video'] == meta['video'] &&
            old['audio'] == meta['audio'];
      } catch (_) {}
    }
    if (!reuse && t.tmpDir.existsSync()) {
      await t.tmpDir.delete(recursive: true);
    }
    await t.tmpDir.create(recursive: true);
    await metaFile.writeAsString(jsonEncode(meta));
  }

  static Future<void> _run(ExportTask t) async {
    _paused = false;
    _stopped = false;
    t.stage.value = .downloading;
    _meter.reset();
    _speedTimer?.cancel();
    _speedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      t.speed.value = _meter.bytesPerSec;
    });
    File? part;
    try {
      void onProgress() {
        final total = t.total[0] + t.total[1];
        final received = t.received[0] + t.received[1];
        if (total > 0) t.progress.value = received / total;
        _meter.update(received);
      }

      Future<void> stream(int i, String url, String file) async {
        final done = _doneFile(t, i);
        if (done.existsSync() && File(file).existsSync()) {
          // Finished before a pause: a range request after the end would
          // add the error body to the file.
          t.received[i] = t.total[i] = File(file).lengthSync();
          onProgress();
          return;
        }
        await _download(url, file, (r, total) {
          t.received[i] = r;
          t.total[i] = total;
          onProgress();
        });
        await done.create();
      }

      await Future.wait([
        stream(0, t.videoUrl, t.videoFile),
        if (t.hasAudio) stream(1, t.audioUrl!, t.audioFile),
      ]);
      _checkStop();
      _speedTimer?.cancel();
      t.speed.value = 0;

      final target = await _targetFile(t.title);
      part = File('${target.path}.part');
      t.stage.value = .merging;
      t.progress.value = 0;
      if (t.hasAudio) {
        await Mp4Mux.merge(
          videoPath: t.videoFile,
          audioPath: t.audioFile,
          outPath: part.path,
          onProgress: (p) => t.progress.value = p,
          isCancelled: () => _stopped,
        );
      } else {
        await File(t.videoFile).copy(part.path);
      }
      _checkStop();
      await part.rename(target.path);
      part = null;
      if (Platform.isAndroid) {
        try {
          await const MethodChannel(
            'pilibtr/update',
          ).invokeMethod('scanFile', {'path': target.path});
        } catch (_) {}
      }
      await _addRecord(
        ExportRecord(
          path: target.path,
          title: t.title,
          cover: t.cover,
          bvid: t.bvid,
          cid: t.cid,
          size: target.lengthSync(),
          time: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      await _finish(t, deleteTmp: true);
      SmartDialog.showToast(
        '已下載到 ${target.path}',
        displayTime: const Duration(seconds: 4),
      );
    } catch (e) {
      _speedTimer?.cancel();
      t.speed.value = 0;
      if (part != null) await part.tryDel();
      if (_paused && !_stopped) {
        // Pause: the managers stopped with an error. Keep the parts.
        t.stage.value = .paused;
        return;
      }
      if (_stopped) {
        await _finish(t, deleteTmp: true);
        SmartDialog.showToast('已停止下載');
      } else {
        // Keep the parts: downloading the same video again goes on.
        await _finish(t, deleteTmp: false);
        if (kDebugMode) debugPrint('video export: $e');
        SmartDialog.showToast(
          e is FileSystemException && e.path != null
              ? '無法寫入 ${e.path}，請在設定中改用 Download 或 Movies 底下的資料夾'
              : '下載失敗，回到影片頁再按一次「下載」可從目前進度繼續',
        );
      }
    } finally {
      _managers.clear();
    }
  }

  static Future<void> _finish(ExportTask t, {required bool deleteTmp}) async {
    _speedTimer?.cancel();
    SmartDialog.dismiss(tag: _tag);
    if (current.value == t) current.value = null;
    if (deleteTmp) {
      try {
        if (t.tmpDir.existsSync()) await t.tmpDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Pauses the download (not while merging). The parts stay.
  static void pause() {
    final t = current.value;
    if (t == null || t.stage.value != .downloading) return;
    _paused = true;
    for (final m in _managers) {
      m.cancel(isDelete: false);
    }
  }

  /// Goes on with a paused download.
  static void resume() {
    final t = current.value;
    if (t == null || t.stage.value != .paused) return;
    if (_expired(t.videoUrl) || (t.hasAudio && _expired(t.audioUrl!))) {
      SmartDialog.showToast('下載連結已過期，回到影片頁再按一次「下載」可從目前進度繼續');
      return;
    }
    unawaited(_run(t));
  }

  /// Stops the download and deletes its parts.
  static void stop() {
    final t = current.value;
    if (t == null) return;
    _stopped = true;
    if (t.stage.value == .paused) {
      _finish(t, deleteTmp: true);
      SmartDialog.showToast('已停止下載');
      return;
    }
    // Downloading: the managers stop with an error; merging: Mp4Mux checks
    // [_stopped]. [_run] then deletes the parts.
    for (final m in _managers) {
      m.cancel(isDelete: true);
    }
  }

  /// Bilibili media links are signed with a `deadline` (unix seconds).
  static bool _expired(String url) {
    final deadline = int.tryParse(
      Uri.tryParse(url)?.queryParameters['deadline'] ?? '',
    );
    if (deadline == null) return false;
    return deadline * 1000 <= DateTime.now().millisecondsSinceEpoch + 60000;
  }

  static void _checkStop() {
    if (_stopped) throw StateError('stopped');
    if (_paused) throw StateError('paused');
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

  // ---------------------------------------------------------------------------
  // Records of finished downloads
  // ---------------------------------------------------------------------------

  static List<Object?> _rawRecords() {
    final list = GStorage.localCache.get(LocalCacheKey.exportRecords);
    return list is List ? list : const [];
  }

  static Future<void> _addRecord(ExportRecord record) {
    final list = [
      record.toJson(),
      ..._rawRecords().where(
        (e) => e is! Map || e['path'] != record.path,
      ),
    ];
    return GStorage.localCache.put(LocalCacheKey.exportRecords, list);
  }

  /// Finished downloads, newest first. Files deleted outside the app are
  /// left out.
  static List<ExportRecord> records() => [
    for (final e in _rawRecords())
      if (ExportRecord.fromJson(e) case final r?)
        if (File(r.path).existsSync()) r,
  ];

  /// Removes the record of [path], and the file if [deleteFile].
  static Future<void> deleteRecord(
    String path, {
    bool deleteFile = true,
  }) async {
    if (deleteFile) await File(path).tryDel();
    await GStorage.localCache.put(
      LocalCacheKey.exportRecords,
      _rawRecords().where((e) => e is! Map || e['path'] != path).toList(),
    );
  }

  // ---------------------------------------------------------------------------

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
  static void _showPanel() {
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
            child: Obx(() {
              final t = current.value;
              if (t == null) return const SizedBox.shrink();
              return ExportTaskTile(task: t, compact: true);
            }),
          ),
        );
      },
    );
  }
}

/// Progress, stage, speed and the pause / resume / stop buttons of [task].
/// Used by the progress card and the 下載 tab.
class ExportTaskTile extends StatelessWidget {
  const ExportTaskTile({super.key, required this.task, this.compact = false});

  final ExportTask task;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Obx(() {
      final stage = task.stage.value;
      final p = task.progress.value;
      final speed = task.speed.value;
      final text = StringBuffer(stage.label);
      if (p != null) text.write(' ${(p * 100).toStringAsFixed(0)}%');
      if (stage == .downloading) text.write('　${formatSpeed(speed)}');
      return Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 6),
                ThinProgressBar(value: p),
                const SizedBox(height: 4),
                Text(
                  text.toString(),
                  style: TextStyle(fontSize: 12, color: colorScheme.outline),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: stage == .paused ? '繼續下載' : '暫停下載',
            onPressed: switch (stage) {
              .downloading => VideoExport.pause,
              .paused => VideoExport.resume,
              .merging => null,
            },
            icon: Icon(
              stage == .paused ? Icons.play_arrow : Icons.pause,
            ),
          ),
          const IconButton(
            tooltip: '停止下載',
            onPressed: VideoExport.stop,
            icon: Icon(Icons.stop),
          ),
        ],
      );
    });
  }
}
