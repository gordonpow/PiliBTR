import 'package:PiliPlus/btr_version.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/update.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// Update settings: automatic or manual check, and the new version with
/// its release notes and an install button.
class UpdatePage extends StatefulWidget {
  const UpdatePage({super.key});

  @override
  State<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends State<UpdatePage> {
  bool _auto = Pref.autoUpdate;

  void _setAuto(bool value) {
    setState(() => _auto = value);
    GStorage.setting.put(SettingBoxKey.autoUpdate, value);
    if (value) Update.check();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final padding = MediaQuery.viewPaddingOf(context);
    return SimpleScaffold(
      appBar: AppBar(title: const Text('更新')),
      body: ListView(
        padding: EdgeInsets.only(bottom: padding.bottom + 24),
        children: [
          ListTile(
            leading: const Icon(Icons.autorenew),
            title: const Text('自動檢查更新'),
            subtitle: const Text(
              '每次開啟 App 時在背景檢查，有新版本時在「我的」與「設定」顯示紅點。'
              '關閉後只在手動檢查時更新',
            ),
            trailing: Switch(value: _auto, onChanged: _setAuto),
            onTap: () => _setAuto(!_auto),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('目前版本'),
            trailing: Text(
              btrVersion,
              style: TextStyle(color: colorScheme.outline),
            ),
          ),
          Obx(
            () => ListTile(
              leading: const Icon(Icons.system_update_alt),
              title: const Text('檢查更新'),
              enabled: !Update.checking.value,
              trailing: Update.checking.value
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              onTap: () => Update.check(silent: false),
            ),
          ),
          Obx(() {
            final info = Update.available.value;
            if (info == null) return const SizedBox.shrink();
            return _newVersion(theme, info);
          }),
        ],
      ),
    );
  }

  Widget _newVersion(ThemeData theme, UpdateInfo info) {
    final colorScheme = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: Badge(
              smallSize: 8,
              child: Icon(Icons.new_releases_outlined, color: colorScheme.primary),
            ),
            title: Text('發現新版本 ${info.tag}'),
            subtitle: const Text('確認後下載並開啟系統安裝程式'),
          ),
          // Collapsed by default: the release notes can be long.
          ExpansionTile(
            title: const Text('更新內容'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                _notes(info.body),
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Obx(() {
              final progress = Update.progress.value;
              if (progress != null) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LinearProgressIndicator(value: progress),
                    const SizedBox(height: 6),
                    Text(
                      '下載中 ${(progress * 100).toStringAsFixed(0)}%',
                      style: TextStyle(color: colorScheme.outline),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  TextButton(
                    onPressed: () => PageUtils.launchURL(info.htmlUrl),
                    child: const Text('在 GitHub 檢視'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => _confirmInstall(info),
                    child: const Text('下載並安裝'),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  /// The change list of the release notes as plain text: the part under
  /// the first heading (the download table and notes are left out), with
  /// the Markdown marks removed.
  static String _notes(String body) {
    final lines = body.split(RegExp(r'\r?\n'));
    final start = lines.indexWhere((e) => e.startsWith('## '));
    Iterable<String> part = lines;
    if (start != -1) {
      final rest = lines.skip(start + 1).toList();
      final end = rest.indexWhere((e) => e.startsWith('## '));
      part = end == -1 ? rest : rest.take(end);
    }
    final text = part
        .map(
          (e) => e
              .replaceAll('**', '')
              .replaceAll('`', '')
              .replaceFirst(RegExp(r'^\s*[-*] '), '• '),
        )
        .join('\n')
        .trim();
    return text.isEmpty ? '（沒有說明）' : text;
  }

  Future<void> _confirmInstall(UpdateInfo info) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('安裝 ${info.tag}？'),
        content: const Text('將下載安裝檔，完成後開啟系統安裝程式。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('安裝'),
          ),
        ],
      ),
    );
    if (ok == true) Update.downloadAndInstall(info);
  }
}
