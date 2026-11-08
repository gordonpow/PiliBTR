import 'dart:async';

import 'package:PiliPlus/services/download/btr_config.dart';
import 'package:PiliPlus/services/download/btr_proxy.dart';
import 'package:PiliPlus/utils/speed_format.dart';
import 'package:flutter/material.dart';

/// 播放器上的 CDN 狀態面板，每秒更新一次。
class CdnStatusPanel extends StatefulWidget {
  const CdnStatusPanel({
    super.key,
    required this.videoUrl,
    required this.audioUrl,
    this.cacheSpeed,
  });

  final String? videoUrl;
  final String? audioUrl;

  /// mpv `cache-speed` (bytes per second, as text): the download speed when
  /// BTR does not serve the stream (direct connection).
  final String? Function()? cacheSpeed;

  @override
  State<CdnStatusPanel> createState() => _CdnStatusPanelState();
}

class _CdnStatusPanelState extends State<CdnStatusPanel> {
  Timer? _timer;
  final Map<String, int> _lastServed = {};
  double _totalSpeed = 0;

  /// 目前是否有任何節點正在下載（BTR 時）。
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _sample();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(_sample);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static String? _valid(String? url) =>
      url == null || url.isEmpty ? null : url;

  void _sample() {
    var sum = 0.0;
    var anyBtr = false;
    var downloading = false;
    for (final url in [_valid(widget.videoUrl), _valid(widget.audioUrl)]) {
      if (url == null) continue;
      final stats = BtrProxy.statsFor(url);
      if (stats == null) continue;
      anyBtr = true;
      if (stats.nodes.any((n) => n.inflight > 0)) downloading = true;
      final last = _lastServed[url];
      if (last != null && stats.served >= last) {
        sum += stats.served - last;
      }
      _lastServed[url] = stats.served;
    }
    if (!anyBtr) {
      sum = double.tryParse(widget.cacheSpeed?.call() ?? '') ?? 0;
    }
    _totalSpeed = sum;
    _downloading = !anyBtr || downloading;
  }

  static String _shortHost(String host) => host.replaceFirst(
    RegExp(r'\.(bilivideo\.(com|cn|net)|akamaized\.net)$'),
    '',
  );

  List<Widget> _section(String title, String? url) {
    final texts = <String>[];
    final stats = BtrProxy.statsFor(url!);
    if (stats == null) {
      final host = Uri.tryParse(url)?.host ?? url;
      texts.add('${_shortHost(host)}（直連）');
    } else {
      final nodes = [...stats.nodes]
        ..sort((a, b) => b.speed.compareTo(a.speed));
      for (final n in nodes) {
        final speed = n.speed > 0 ? formatSpeed(n.speed * 1000) : '—';
        texts.add(
          '${_shortHost(n.host)}  $speed'
          '${n.inflight > 0 ? ' ×${n.inflight}' : ''}'
          '${n.banned ? ' 封鎖' : ''}',
        );
      }
    }
    return [
      Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      for (final t in texts) Text(t),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final video = _valid(widget.videoUrl);
    final audio = _valid(widget.audioUrl);
    final head = BtrConfig.playback
        ? 'BTR：${BtrConfig.cdnMode.label}、${BtrConfig.playbackThreads} 線程'
        : 'BTR：關閉';
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.white, fontSize: 11),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(head),
                // 目前下載：這一秒交給播放器的資料量；緩衝足夠時播放器暫停讀取，
                // 會顯示 0，屬正常。節點速度是過去片段測得的平均，不是即時值。
                Text(
                  '目前下載 ${formatSpeed(_totalSpeed)}'
                  '${_totalSpeed == 0 && !_downloading ? '（緩衝足夠，暫停下載）' : ''}',
                ),
                const Text(
                  '節點速度為最近片段測得的平均',
                  style: TextStyle(color: Colors.white60, fontSize: 10),
                ),
                if (video != null) ..._section('影片', video),
                if (audio != null) ..._section('音訊', audio),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
