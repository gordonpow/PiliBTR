import 'package:PiliPlus/services/download/btr_config.dart';
import 'package:PiliPlus/services/download/btr_proxy.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart';

/// Settings of BTR (multi-CDN): CDN mode, threads, download acceleration.
/// Playback acceleration is the switch in the CDN settings
/// (cdn_settings_dialog.dart).
class BtrSettingsDialog extends StatefulWidget {
  const BtrSettingsDialog({super.key});

  @override
  State<BtrSettingsDialog> createState() => _BtrSettingsDialogState();
}

class _BtrSettingsDialogState extends State<BtrSettingsDialog> {
  late bool _enable;
  late BtrCdnMode _cdnMode;
  late bool _autoThreads;
  late int _threadIndex;
  late final TextEditingController _customCdn;

  @override
  void initState() {
    super.initState();
    _enable = BtrConfig.enable;
    _cdnMode = BtrConfig.cdnMode;
    _autoThreads = BtrConfig.autoThreads;
    final threads = BtrConfig.threads;
    _threadIndex = BtrConfig.threadSteps.indexWhere((e) => e >= threads);
    if (_threadIndex == -1) _threadIndex = BtrConfig.threadSteps.length - 1;
    _customCdn = TextEditingController(text: BtrConfig.customCdn.join('\n'));
  }

  @override
  void dispose() {
    _customCdn.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final hosts = BtrConfig.parseHosts(_customCdn.text);
    if ((_enable || BtrConfig.playback) &&
        _cdnMode == BtrCdnMode.custom &&
        hosts.isEmpty) {
      SmartDialog.showToast('請至少輸入一個 CDN 節點');
      return;
    }
    await GStorage.setting.putAll({
      SettingBoxKey.btrEnable: _enable,
      SettingBoxKey.btrCdnMode: _cdnMode.index,
      SettingBoxKey.btrCustomCdn: hosts,
      SettingBoxKey.btrAutoThreads: _autoThreads,
      SettingBoxKey.btrThreads: BtrConfig.threadSteps[_threadIndex],
    });
    // Forget proxy sources built with the old node list.
    BtrProxy.reset();
    SmartDialog.showToast('已儲存，下一個影片或下載任務生效');
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final labelStyle = theme.textTheme.titleSmall?.copyWith(
      color: colorScheme.primary,
    );
    const steps = BtrConfig.threadSteps;

    return AlertDialog(
      title: const Text('線程撕裂者'),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('下載加速'),
              subtitle: const Text('離線快取使用多執行緒下載'),
              value: _enable,
              onChanged: (v) => setState(() => _enable = v),
            ),
            IgnorePointer(
              ignoring: !_enable && !BtrConfig.playback,
              child: AnimatedOpacity(
                opacity: _enable || BtrConfig.playback ? 1 : 0.4,
                duration: const Duration(milliseconds: 150),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Text('CDN 模式', style: labelStyle),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<BtrCdnMode>(
                        showSelectedIcon: false,
                        segments: [
                          for (final e in BtrCdnMode.values)
                            ButtonSegment(value: e, label: Text(e.label)),
                        ],
                        selected: {_cdnMode},
                        onSelectionChanged: (v) =>
                            setState(() => _cdnMode = v.first),
                      ),
                    ),
                    if (_cdnMode == BtrCdnMode.custom) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _customCdn,
                        minLines: 3,
                        maxLines: 6,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                          labelText: 'CDN 節點',
                          hintText: '每行一個，例如\nupos-sz-mirrorali.bilivideo.com',
                          helperText:
                              '最多 ${BtrConfig.maxCustomCdn} 個，'
                              '原始地址會一併使用',
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 6),
                      Text(
                        '${(_cdnMode == BtrCdnMode.mainland ? BtrConfig.mainlandHosts : BtrConfig.overseasHosts).length}'
                        ' 個節點輪換使用，連續兩次 0 KiB 的節點會被停用',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text('執行緒', style: labelStyle),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('自動執行緒數（推薦）'),
                      subtitle: const Text('播放用 8 個執行緒，下載按檔案大小選 4 到 16 個'),
                      value: _autoThreads,
                      onChanged: (v) => setState(() => _autoThreads = v),
                    ),
                    Row(
                      children: [
                        const Text('執行緒數'),
                        const Spacer(),
                        Text(
                          _autoThreads ? '自動' : '${steps[_threadIndex]}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: _threadIndex.toDouble(),
                      min: 0,
                      max: (steps.length - 1).toDouble(),
                      divisions: steps.length - 1,
                      label: '${steps[_threadIndex]}',
                      onChanged: _autoThreads
                          ? null
                          : (v) => setState(() => _threadIndex = v.round()),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (final s in steps)
                            Text(
                              '$s',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.outline,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (!_autoThreads && steps[_threadIndex] > 32)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '執行緒過多可能被 CDN 限流，建議 8 到 32',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: Text('取消', style: TextStyle(color: colorScheme.outline)),
        ),
        TextButton(onPressed: _save, child: const Text('儲存')),
      ],
    );
  }
}
