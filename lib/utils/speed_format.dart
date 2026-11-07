import 'dart:collection';

import 'package:PiliPlus/utils/storage_pref.dart';

const speedUnitLabels = ['自動', 'KB/s', 'MB/s', 'Mbps'];

const _kb = 1024;
const _mb = 1024 * 1024;

/// 依 [Pref.speedUnit] 格式化網速（輸入單位：bytes/s）。
String formatSpeed(num bytesPerSec) {
  final v = (bytesPerSec.isNaN || bytesPerSec.isNegative)
      ? 0.0
      : bytesPerSec.toDouble();
  switch (Pref.speedUnit) {
    case 1:
      return '${(v / _kb).toStringAsFixed(0)} KB/s';
    case 2:
      return '${(v / _mb).toStringAsFixed(2)} MB/s';
    case 3:
      return '${(v * 8 / 1e6).toStringAsFixed(1)} Mbps';
    default:
      if (v >= _mb) return '${(v / _mb).toStringAsFixed(1)} MB/s';
      return '${(v / _kb).toStringAsFixed(0)} KB/s';
  }
}

/// 以最近約 2 秒的累計位元組樣本估算即時網速。
class SpeedMeter {
  static const _window = Duration(seconds: 2);

  final Stopwatch _clock = Stopwatch()..start();
  final Queue<(Duration, int)> _samples = Queue();

  void update(int totalBytes) {
    final now = _clock.elapsed;
    if (_samples.isNotEmpty && totalBytes < _samples.last.$2) {
      _samples.clear();
    }
    _samples.add((now, totalBytes));
    while (_samples.length > 2 && now - _samples.first.$1 > _window) {
      _samples.removeFirst();
    }
  }

  void reset() => _samples.clear();

  double get bytesPerSec {
    if (_samples.length < 2) return 0;
    final first = _samples.first;
    final last = _samples.last;
    final us = (last.$1 - first.$1).inMicroseconds;
    if (us <= 0) return 0;
    final bytes = last.$2 - first.$2;
    if (bytes < 0) return 0;
    return bytes * 1e6 / us;
  }
}
