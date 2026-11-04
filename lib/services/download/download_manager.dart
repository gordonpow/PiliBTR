import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/services/download/btr_cdn.dart';
import 'package:PiliPlus/services/download/btr_config.dart';
import 'package:PiliPlus/utils/extension/file_ext.dart';
import 'package:PiliPlus/utils/extension/string_ext.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

/// Downloads one media file.
///
/// When multi-thread download (BTR) is enabled, the file is split into
/// chunks that several workers fetch in parallel with HTTP range requests.
/// Workers rotate over CDN nodes. A node is disabled after two consecutive
/// attempts that receive 0 bytes. When all nodes are disabled, they are
/// enabled again. Progress is kept in a `<path>.btr` sidecar file so a paused
/// or failed download can resume.
///
/// When the server does not support range requests, or BTR is disabled, the
/// file is downloaded with one connection.
class DownloadManager {
  final String url;
  final String path;
  final void Function(int, int)? onReceiveProgress;
  final void Function([Object? error]) onDone;

  DownloadStatus _status = DownloadStatus.downloading;

  DownloadStatus get status => _status;
  final _cancelToken = CancelToken();
  late Future<void> task;

  DownloadManager({
    required this.url,
    required this.path,
    required this.onReceiveProgress,
    required this.onDone,
  }) {
    task = BtrConfig.enable ? _startMulti() : _startSingle();
  }

  File get _metaFile => File('$path.btr');

  static const _headers = {'referer': 'https://www.bilibili.com/'};

  // ---------------------------------------------------------------------------
  // Single connection (original implementation)
  // ---------------------------------------------------------------------------

  Future<void> _startSingle() async {
    int received;

    final file = File(path);

    // A multi-thread download leaves a sparse file. Its length does not
    // match the received bytes, so start again.
    if (_metaFile.existsSync()) {
      await _metaFile.tryDel();
      if (file.existsSync()) {
        await file.tryDel();
      }
    }

    if (file.existsSync()) {
      received = await file.length();
    } else {
      file.createSync(recursive: true);
      received = 0;
    }

    final sink = file.openWrite(
      mode: received == 0 ? FileMode.writeOnly : FileMode.writeOnlyAppend,
    );

    Future<void> onError(Object e, {bool delete = false}) async {
      try {
        await sink.close();
      } catch (_) {}
      if (_status == DownloadStatus.downloading) {
        _status = DownloadStatus.failDownload;
        if (delete && file.existsSync()) {
          await file.tryDel();
        }
      }
      onDone(e);
    }

    Response<ResponseBody> response;
    try {
      response = await Request.http11Dio.get<ResponseBody>(
        url.http2https,
        options: Options(
          headers: {'range': 'bytes=$received-'},
          responseType: ResponseType.stream,
          validateStatus: (status) =>
              status != null &&
              (status == 416 || (status >= 200 && status < 300)),
        ),
        cancelToken: _cancelToken,
      );
    } on DioException catch (e) {
      await onError(e, delete: true);
      return;
    }
    final data = response.data!;
    final contentLength = data.contentLength + received;

    if (received == 0) {
      onReceiveProgress?.call(0, contentLength);
    }

    int? last;
    try {
      await for (final chunk in data.stream) {
        sink.add(chunk);
        received += chunk.length;
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        if (last != now) {
          last = now;
          onReceiveProgress?.call(received, contentLength);
        }
      }
      await sink.close();
      _status = DownloadStatus.completed;
      onDone();
    } catch (e) {
      await onError(e);
      return;
    }
  }

  // ---------------------------------------------------------------------------
  // Multi-thread (BTR)
  // ---------------------------------------------------------------------------

  static const int _minChunk = 512 * 1024;
  static const int _maxChunk = 8 * 1024 * 1024;

  /// Attempts per chunk before the download fails.
  static const int _maxChunkAttempts = 12;

  late final BtrNodePool _pool;

  late final int _total;
  late final int _chunkSize;
  late final int _chunkCount;
  late final Set<int> _done;
  int _received = 0;

  RandomAccessFile? _raf;
  Future<void> _ioQueue = Future.value();
  Object? _fatalError;
  DateTime _lastMetaSave = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _stopped => _cancelToken.isCancelled || _fatalError != null;

  Future<void> _startMulti() async {
    _pool = BtrNodePool(url.http2https);

    // 1. Total size, and check range support.
    int? total;
    try {
      for (final node in _pool.nodes.take(3)) {
        total = await _probe(node.url);
        if (total != null) break;
      }
    } catch (e) {
      if (_cancelToken.isCancelled) {
        onDone(e);
        return;
      }
    }
    if (total == null) {
      if (kDebugMode) debugPrint('BTR: range not supported, single connection');
      return _startSingle();
    }
    _total = total;

    Timer? progressTimer;
    try {
      // 2. Prepare file and resume state.
      final file = File(path);
      if (!file.existsSync()) {
        file.createSync(recursive: true);
      }
      await _loadState(file);

      if (_received == 0) {
        onReceiveProgress?.call(0, _total);
      }

      final raf = _raf = await file.open(mode: FileMode.append);
      if (await raf.length() != _total) {
        await raf.truncate(_total);
      }

      // 3. Download pending chunks.
      final pending = Queue<int>.of([
        for (int i = 0; i < _chunkCount; i++)
          if (!_done.contains(i)) i,
      ]);

      if (pending.isNotEmpty) {
        final threads = math.min(BtrConfig.threadsFor(_total), pending.length);
        if (kDebugMode) {
          debugPrint(
            'BTR: $path total=$_total chunk=$_chunkSize '
            'pending=${pending.length} threads=$threads '
            'nodes=${_pool.nodes.length}',
          );
        }
        progressTimer = Timer.periodic(
          const Duration(seconds: 1),
          (_) => onReceiveProgress?.call(_received, _total),
        );
        await Future.wait([
          for (int i = 0; i < threads; i++) _worker(pending),
        ]);
      }

      await _ioQueue;

      if (_cancelToken.isCancelled || _fatalError != null) {
        throw _fatalError ?? DioException.requestCancelled(
          requestOptions: RequestOptions(path: url),
          reason: 'cancelled',
        );
      }

      // 4. Finish.
      progressTimer?.cancel();
      await raf.flush();
      await raf.close();
      _raf = null;
      await _metaFile.tryDel();
      _status = DownloadStatus.completed;
      onReceiveProgress?.call(_total, _total);
      onDone();
    } catch (e) {
      progressTimer?.cancel();
      await _ioQueue.catchError((_) {});
      try {
        await _raf?.flush();
        await _saveMeta();
      } catch (_) {}
      try {
        await _raf?.close();
      } catch (_) {}
      _raf = null;
      if (_status == DownloadStatus.downloading) {
        _status = DownloadStatus.failDownload;
      }
      if (kDebugMode) debugPrint('BTR: stopped: $e');
      onDone(e);
    }
  }

  /// Returns the total size when [url] supports range requests.
  Future<int?> _probe(String url) async {
    try {
      final response = await Request.http11Dio.get<ResponseBody>(
        url,
        options: Options(
          headers: {..._headers, 'range': 'bytes=0-0'},
          responseType: ResponseType.stream,
        ),
        cancelToken: _cancelToken,
      );
      await response.data?.stream.drain<void>().catchError((_) {});
      if (response.statusCode != 206) return null;
      final range = response.headers.value('content-range');
      if (range == null) return null;
      final slash = range.lastIndexOf('/');
      if (slash == -1) return null;
      return int.tryParse(range.substring(slash + 1).trim());
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      if (kDebugMode) debugPrint('BTR: probe failed $url: $e');
      return null;
    }
  }

  Future<void> _loadState(File file) async {
    // Resume from sidecar.
    if (_metaFile.existsSync()) {
      try {
        final json = jsonDecode(await _metaFile.readAsString()) as Map;
        final chunkSize = json['chunkSize'];
        final done = (json['done'] as List).cast<int>().toSet();
        if (json['total'] == _total && chunkSize is int && chunkSize > 0) {
          _chunkSize = chunkSize;
          _chunkCount = (_total + _chunkSize - 1) ~/ _chunkSize;
          _done = done..removeWhere((i) => i < 0 || i >= _chunkCount);
          _received = _done.fold(0, (sum, i) => sum + _chunkLength(i));
          return;
        }
      } catch (_) {}
      await _metaFile.tryDel();
    }

    final threads = BtrConfig.threadsFor(_total);
    _chunkSize = (_total / (threads * 4)).ceil().clamp(_minChunk, _maxChunk);
    _chunkCount = math.max(1, (_total + _chunkSize - 1) ~/ _chunkSize);
    _done = {};

    // Partial file from the single-connection downloader: the first
    // `length` bytes are valid.
    final length = await file.length();
    if (length > 0 && length <= _total) {
      for (int i = 0; i < _chunkCount; i++) {
        if (i * _chunkSize + _chunkLength(i) <= length) {
          _done.add(i);
        } else {
          break;
        }
      }
    }
    _received = _done.fold(0, (sum, i) => sum + _chunkLength(i));
  }

  int _chunkLength(int index) =>
      math.min(_chunkSize, _total - index * _chunkSize);

  Future<void> _worker(Queue<int> pending) async {
    while (!_stopped && pending.isNotEmpty) {
      final index = pending.removeFirst();
      try {
        await _downloadChunk(index);
        _done.add(index);
        _maybeSaveMeta();
      } catch (e) {
        if (!_cancelToken.isCancelled && _fatalError == null) {
          _fatalError = e;
          _cancelToken.cancel();
        }
        return;
      }
    }
  }

  Future<void> _downloadChunk(int index) async {
    final chunkStart = index * _chunkSize;
    final length = _chunkLength(index);
    int written = 0;

    for (int attempt = 0; ; attempt++) {
      if (_stopped) throw _fatalError ?? 'cancelled';
      final node = _pool.pick();
      final start = chunkStart + written;
      final end = chunkStart + length - 1;
      int got = 0;
      try {
        final response = await Request.http11Dio.get<ResponseBody>(
          node.url,
          options: Options(
            headers: {..._headers, 'range': 'bytes=$start-$end'},
            responseType: ResponseType.stream,
          ),
          cancelToken: _cancelToken,
        );
        if (response.statusCode != 206) {
          await response.data?.stream.drain<void>().catchError((_) {});
          throw Exception('BTR: status ${response.statusCode}');
        }
        await for (final data in response.data!.stream) {
          final remain = length - written;
          final bytes = data.length > remain
              ? data.sublist(0, remain)
              : data;
          await _write(chunkStart + written, bytes);
          written += bytes.length;
          got += bytes.length;
          _received += bytes.length;
          if (written >= length) break;
        }
        if (written >= length) {
          _pool.report(node, bytes: got);
          return;
        }
        throw Exception('BTR: connection closed early');
      } catch (e) {
        if (_cancelToken.isCancelled) rethrow;
        _pool.report(node, bytes: got);
        if (attempt + 1 >= _maxChunkAttempts) rethrow;
        if (kDebugMode) debugPrint('BTR: chunk $index retry: $e');
        await Future.delayed(
          Duration(milliseconds: math.min(3000, 300 * (attempt + 1))),
        );
      }
    }
  }

  /// Serialises file writes. One [RandomAccessFile] does not allow
  /// concurrent operations.
  Future<void> _write(int position, List<int> data) {
    final raf = _raf!;
    final f = _ioQueue.then((_) async {
      await raf.setPosition(position);
      await raf.writeFrom(data);
    });
    _ioQueue = f.catchError((_) {});
    return f;
  }

  void _maybeSaveMeta() {
    final now = DateTime.now();
    if (now.difference(_lastMetaSave).inMilliseconds < 1000) return;
    _lastMetaSave = now;
    final raf = _raf;
    if (raf == null) return;
    // Flush data before recording chunks as done.
    _ioQueue = _ioQueue
        .then((_) => raf.flush())
        .then((_) => _saveMeta())
        .catchError((_) {});
  }

  Future<void> _saveMeta() => _metaFile.writeAsString(
    jsonEncode({
      'total': _total,
      'chunkSize': _chunkSize,
      'done': _done.toList()..sort(),
    }),
    flush: true,
  );

  Future<void> cancel({required bool isDelete}) {
    if (!isDelete && _status == DownloadStatus.downloading) {
      _status = DownloadStatus.pause;
    }
    if (!_cancelToken.isCancelled) {
      _cancelToken.cancel();
    }
    return task;
  }
}
