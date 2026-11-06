import 'package:PiliPlus/common/widgets/zh_material.dart';
import 'package:PiliPlus/models/common/video/cdn_type.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:PiliPlus/pages/setting/widgets/btr_settings_dialog.dart';
import 'package:PiliPlus/pages/setting/widgets/select_dialog.dart';
import 'package:PiliPlus/services/download/btr_config.dart';
import 'package:PiliPlus/utils/cdn_choice.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/video_utils.dart';

/// CDN settings: BTR (multi-CDN) or one CDN node, each with a switch.
/// Only one is on. Tapping a row opens its own settings.
class CdnSettingsDialog extends StatefulWidget {
  const CdnSettingsDialog({super.key, this.sample});

  /// A stream of the current video, for the CDN speed test.
  final BaseItem? sample;

  @override
  State<CdnSettingsDialog> createState() => _CdnSettingsDialogState();
}

class _CdnSettingsDialogState extends State<CdnSettingsDialog> {
  Future<void> _setBtr(bool on) async {
    if (await setBtrPlayback(on) && mounted) setState(() {});
  }

  Future<void> _openBtr() async {
    await showDialog<bool>(
      context: context,
      builder: (context) => const BtrSettingsDialog(),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openNodes() async {
    final res = await showDialog<CDNService>(
      context: context,
      builder: (context) => CdnSelectDialog(sample: widget.sample),
    );
    if (res != null) {
      VideoUtils.cdnService = res;
      await GStorage.setting.put(SettingBoxKey.CDNService, res.name);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final btr = BtrConfig.playback;
    final threads = BtrConfig.autoThreads ? '自動' : '${BtrConfig.threads}';
    return AlertDialog(
      title: const Text('CDN 設定'),
      contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('線程撕裂者（多 CDN 加速）'),
            subtitle: Text(
              'CDN：${BtrConfig.cdnMode.label}，執行緒數：$threads，'
              '下載加速：${BtrConfig.enable ? '開' : '關'}',
            ),
            trailing: Switch(value: btr, onChanged: _setBtr),
            onTap: _openBtr,
          ),
          ListTile(
            title: const Text('CDN 節點'),
            subtitle: Text(
              '${VideoUtils.cdnService.desc}，部分 CDN 可能失效，如無法播放請嘗試切換',
            ),
            trailing: Switch(value: !btr, onChanged: (v) => _setBtr(!v)),
            onTap: _openNodes,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              '兩者只能開啟一個。點選專案可進一步設定。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: const Text('完成'),
        ),
      ],
    );
  }
}
