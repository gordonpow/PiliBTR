// Settings for the multi-thread downloader ("BTR", thread ripper).
// Behaviour is modelled on Bilibili-thread-ripper-desktop (MIT,
// https://github.com/MrTangLuyao/Bilibili-thread-ripper-desktop).

import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';

enum BtrCdnMode {
  mainland('大陸'),
  overseas('海外'),
  custom('自定義'),
  ;

  final String label;
  const BtrCdnMode(this.label);
}

abstract final class BtrConfig {
  /// Selectable thread counts for the slider.
  static const List<int> threadSteps = [4, 8, 16, 32, 64, 128];

  /// Max number of custom CDN hosts.
  static const int maxCustomCdn = 32;

  static const int defaultThreads = 16;

  // Host lists from BTR (shared/cdn-resolver.js).
  static const List<String> mainlandHosts = [
    'upos-sz-mirrorali.bilivideo.com',
    'upos-sz-mirrorhw.bilivideo.com',
    'upos-sz-mirrorbos.bilivideo.com',
    'upos-sz-mirror08c.bilivideo.com',
    'upos-sz-mirrorbd.bilivideo.com',
    'upos-sz-mirror14b.bilivideo.com',
    'upos-sz-estgoss.bilivideo.com',
    'upos-sz-mirrorcos.bilivideo.com',
    'upos-sz-mirrorcoso1.bilivideo.com',
  ];

  static const List<String> overseasHosts = [
    'upos-sz-mirrorcosov.bilivideo.com',
    'upos-sz-mirroraliov.bilivideo.com',
    'cn-hk-eq-01-01.bilivideo.com',
    'cn-hk-eq-01-03.bilivideo.com',
  ];

  /// Multi-thread offline download.
  static bool get enable =>
      GStorage.setting.get(SettingBoxKey.btrEnable, defaultValue: true);

  /// Multi-CDN parallel fetch while watching (local proxy for the player).
  static bool get playback =>
      GStorage.setting.get(SettingBoxKey.btrPlayback, defaultValue: true);

  /// Threads per player request. Auto uses 8, the BTR default.
  static int get playbackThreads => autoThreads ? 8 : threads;

  static BtrCdnMode get cdnMode {
    final int index = GStorage.setting.get(
      SettingBoxKey.btrCdnMode,
      defaultValue: BtrCdnMode.mainland.index,
    );
    return BtrCdnMode.values[index.clamp(0, BtrCdnMode.values.length - 1)];
  }

  static List<String> get customCdn {
    final List? list = GStorage.setting.get(SettingBoxKey.btrCustomCdn);
    return list?.cast<String>() ?? const [];
  }

  static bool get autoThreads =>
      GStorage.setting.get(SettingBoxKey.btrAutoThreads, defaultValue: true);

  static int get threads {
    final int value = GStorage.setting.get(
      SettingBoxKey.btrThreads,
      defaultValue: defaultThreads,
    );
    return value.clamp(threadSteps.first, threadSteps.last);
  }

  /// CDN hosts used for the current mode.
  static List<String> get hosts => switch (cdnMode) {
    BtrCdnMode.mainland => mainlandHosts,
    BtrCdnMode.overseas => overseasHosts,
    BtrCdnMode.custom => customCdn,
  };

  /// Parses user input (one host or URL per line, or comma separated)
  /// into a clean host list.
  static List<String> parseHosts(String input) {
    final result = <String>[];
    for (var item in input.split(RegExp(r'[\s,，]+'))) {
      item = item.trim();
      if (item.isEmpty) continue;
      final host = item.contains('://')
          ? Uri.tryParse(item)?.host
          : Uri.tryParse('https://$item')?.host;
      if (host != null && host.isNotEmpty && !result.contains(host)) {
        result.add(host);
        if (result.length >= maxCustomCdn) break;
      }
    }
    return result;
  }

  /// Thread count for a file of [totalBytes].
  static int threadsFor(int totalBytes) {
    if (!autoThreads) return threads;
    // Auto: about one thread per 4 MiB, between 4 and 16.
    const mb4 = 4 * 1024 * 1024;
    return (totalBytes ~/ mb4).clamp(4, 16);
  }
}
