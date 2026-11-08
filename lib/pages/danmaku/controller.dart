import 'dart:collection';
import 'dart:io' show File;

import 'package:PiliPlus/grpc/bilibili/community/service/dm/v1.pb.dart';
import 'package:PiliPlus/grpc/dm.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/data_source.dart';
import 'package:PiliPlus/services/translate/translate_queue.dart';
import 'package:PiliPlus/services/translate/translator.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/danmaku_utils.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:dio/dio.dart' show CancelToken;
import 'package:path/path.dart' as path;

class PlDanmakuController {
  PlDanmakuController(
    this._cid,
    this._plPlayerController,
    this._isFileSource,
  ) : _mergeDanmaku = _plPlayerController.mergeDanmaku;

  final int _cid;
  final PlPlayerController _plPlayerController;
  final bool _mergeDanmaku;
  final bool _isFileSource;

  late final _isLogin = Accounts.main.isLogin;

  final Map<int, List<DanmakuElem>> _dmSegMap = HashMap();
  // 已请求的段落标记
  late final Set<int> _requestedSeg = HashSet();

  // English mode: offline translation in the background, nearest to the
  // playback position first. Read results with [Translator.cached].
  late final bool translateEnabled = Translator.danmakuEnabled;
  late final TranslateQueue? _translateQueue = translateEnabled
      ? TranslateQueue(
          maxPending: 500,
          positionMs: () => _plPlayerController.positionInMilliseconds,
        )
      : null;

  // Cancels in-flight segment requests when the page closes, so they do not
  // hold the connection while the next video loads.
  final CancelToken _cancelToken = CancelToken();
  bool _disposed = false;

  // After a failed request, wait before requesting a segment again.
  static const _retryDelay = Duration(seconds: 10);
  DateTime? _retryAfter;

  void dispose() {
    _disposed = true;
    _cancelToken.cancel();
    _translateQueue?.dispose();
    _dmSegMap.clear();
    _requestedSeg.clear();
  }

  Future<void> queryDanmaku(int segmentIndex) async {
    if (_isFileSource) {
      return;
    }
    if (_disposed || _requestedSeg.contains(segmentIndex)) {
      return;
    }
    if (_retryAfter case final retryAfter?
        when DateTime.now().isBefore(retryAfter)) {
      return;
    }
    _requestedSeg.add(segmentIndex);
    final res = await DmGrpc.dmSegMobile(
      cid: _cid,
      segmentIndex: segmentIndex + 1,
      cancelToken: _cancelToken,
    );
    if (_disposed) return;

    if (res case Success(:final response)) {
      _retryAfter = null;
      if (response.state == 1) {
        _plPlayerController.dmState.add(_cid);
      }
      handleDanmaku(response.elems);
    } else {
      _requestedSeg.remove(segmentIndex);
      _retryAfter = DateTime.now().add(_retryDelay);
    }
  }

  void handleDanmaku(List<DanmakuElem> elems) {
    if (elems.isEmpty) return;
    final uniques = HashMap<String, DanmakuElem>();

    final filters = _plPlayerController.filters;
    final shouldFilter = filters.count != 0;
    for (final element in elems) {
      if (_isLogin) {
        element.isSelf = element.midHash == _plPlayerController.midHash;
      }

      if (!element.isSelf) {
        if (_mergeDanmaku) {
          final elem = uniques[element.content];
          if (elem == null) {
            uniques[element.content] = element..count = 1;
          } else {
            elem.count++;
            continue;
          }
        }

        if (shouldFilter && filters.remove(element)) {
          continue;
        }
      }

      final int pos = element.progress ~/ 100; //每0.1秒存储一次
      (_dmSegMap[pos] ??= []).add(element);
    }
  }

  int _lastFeed = -1;

  /// Feeds the filtered / deduped danmaku of the next 2 minutes to the
  /// translation queue (at most every 10 s of playback, and after a seek).
  void _feedTranslate(int progress) {
    final queue = _translateQueue;
    if (queue == null) return;
    if (_lastFeed >= 0 &&
        progress >= _lastFeed &&
        progress < _lastFeed + 10000) {
      return;
    }
    _lastFeed = progress;
    final start = progress ~/ 100;
    for (var i = start; i < start + 1200; i++) {
      if (_dmSegMap[i] case final list?) {
        for (final e in list) {
          if (e.mode != 7) queue.add(e.content, e.progress);
        }
      }
    }
  }

  List<DanmakuElem>? getCurrentDanmaku(int progress) {
    _feedTranslate(progress);
    if (_isFileSource) {
      initFileDmIfNeeded();
    } else {
      final int segmentIndex = DmUtils.calcSegment(progress);
      if (!_requestedSeg.contains(segmentIndex)) {
        queryDanmaku(segmentIndex);
        return null;
      }
    }
    return _dmSegMap[progress ~/ 100];
  }

  bool _fileDmLoaded = false;

  void initFileDmIfNeeded() {
    if (_fileDmLoaded) return;
    _fileDmLoaded = true;
    _initFileDm();
  }

  @pragma('vm:notify-debugger-on-exception')
  Future<void> _initFileDm() async {
    try {
      final file = File(
        path.join(
          (_plPlayerController.dataSource as FileSource).dir,
          PathUtils.danmakuName,
        ),
      );
      if (!file.existsSync()) return;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return;
      final elem = DmSegMobileReply.fromBuffer(bytes).elems;
      handleDanmaku(elem);
    } catch (e, s) {
      Utils.reportError(e, s);
    }
  }
}
