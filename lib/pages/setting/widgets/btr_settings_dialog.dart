import 'package:PiliPlus/services/download/btr_config.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// Settings for multi-thread download (BTR): CDN mode and thread count.
class BtrSettingsDialog extends StatefulWidget {
  const BtrSettingsDialog({super.key});

  @override
  State<BtrSettingsDialog> createState() => _BtrSettingsDialogState();
}

class _BtrSettingsDialogState extends State<BtrSettingsDialog> {
  late bool _enable;
  late bool _playback;
  late BtrCdnMode _cdnMode;
  late bool _autoThreads;
  late int _threadIndex;
  late final TextEditingController _customCdn;

  @override
  void initState() {
    super.initState();
    _enable = BtrConfig.enable;
    _playback = BtrConfig.playback;
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
    if ((_enable || _playback) &&
        _cdnMode == BtrCdnMode.custom &&
        hosts.isEmpty) {
      SmartDialog.showToast('请至少输入一个 CDN 节点');
      return;
    }
    await GStorage.setting.putAll({
      SettingBoxKey.btrEnable: _enable,
      SettingBoxKey.btrPlayback: _playback,
      SettingBoxKey.btrCdnMode: _cdnMode.index,
      SettingBoxKey.btrCustomCdn: hosts,
      SettingBoxKey.btrAutoThreads: _autoThreads,
      SettingBoxKey.btrThreads: BtrConfig.threadSteps[_threadIndex],
    });
    SmartDialog.showToast('已保存，下一个视频或下载任务生效');
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
      title: const Text('线程撕裂者'),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('播放加速'),
              subtitle: const Text('观看时由多个 CDN 同时缓冲，减少卡顿'),
              value: _playback,
              onChanged: (v) => setState(() => _playback = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('下载加速'),
              subtitle: const Text('离线缓存使用多线程下载'),
              value: _enable,
              onChanged: (v) => setState(() => _enable = v),
            ),
            IgnorePointer(
              ignoring: !_enable && !_playback,
              child: AnimatedOpacity(
                opacity: _enable || _playback ? 1 : 0.4,
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
                          labelText: 'CDN 节点',
                          hintText: '每行一个，例如\nupos-sz-mirrorali.bilivideo.com',
                          helperText:
                              '最多 ${BtrConfig.maxCustomCdn} 个，'
                              '原始地址会一并使用',
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 6),
                      Text(
                        '${(_cdnMode == BtrCdnMode.mainland ? BtrConfig.mainlandHosts : BtrConfig.overseasHosts).length}'
                        ' 个节点轮换使用，连续两次 0 KiB 的节点会被停用',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text('线程', style: labelStyle),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('自动线程数（推荐）'),
                      subtitle: const Text('播放用 8 个线程，下载按文件大小选 4 到 16 个'),
                      value: _autoThreads,
                      onChanged: (v) => setState(() => _autoThreads = v),
                    ),
                    Row(
                      children: [
                        const Text('线程数'),
                        const Spacer(),
                        Text(
                          _autoThreads ? '自动' : '${steps[_threadIndex]}',
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
                          '线程过多可能被 CDN 限流，建议 8 到 32',
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
        TextButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}
