import 'package:PiliPlus/common/widgets/zh_material.dart';
import 'package:PiliPlus/services/translate/translator.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

/// Masks a key for display, keeping the last 4 characters.
String maskApiKey(String key) {
  if (key.isEmpty) return '未設定';
  final tail = key.length > 4 ? key.substring(key.length - 4) : '';
  return '已設定 ••••$tail';
}

/// Edit an API key. The field is obscured; an empty value clears the key.
Future<bool> showApiKeyDialog(
  BuildContext context,
  TranslateService service,
) async {
  final current = service == TranslateService.deepl
      ? Translator.deeplApiKey
      : Translator.googleApiKey;
  final controller = TextEditingController(text: current);
  final res = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('${service.label} 金鑰'),
      content: TextField(
        controller: controller,
        autofocus: true,
        obscureText: true,
        enableSuggestions: false,
        autocorrect: false,
        decoration: InputDecoration(
          hintText: service == TranslateService.deepl
              ? '貼上 DeepL API 金鑰（免費版以 :fx 結尾）'
              : '貼上 Google Cloud Translation API 金鑰',
          helperText: '金鑰只存在本機，不會被匯出設定',
        ),
      ),
      actions: [
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: Text(
            '取消',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('確定'),
        ),
      ],
    ),
  );
  final text = controller.text;
  controller.dispose();
  if (res == true) {
    await Translator.setApiKey(service, text);
    return true;
  }
  return false;
}

/// Offline model: shows the status, with download and delete actions.
Future<void> showTranslateModelDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _ModelDialog(),
  );
}

class _ModelDialog extends StatefulWidget {
  const _ModelDialog();

  @override
  State<_ModelDialog> createState() => _ModelDialogState();
}

class _ModelDialogState extends State<_ModelDialog> {
  ModelStatus? _status;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final s = await Translator.modelStatus();
    if (mounted) setState(() => _status = s);
  }

  Future<void> _download() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await Translator.ensureModel();
    final s = await Translator.modelStatus();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = s;
      _error = res.ok ? null : res.error;
    });
  }

  Future<void> _delete() async {
    setState(() => _busy = true);
    final ok = await Translator.deleteModel();
    final s = await Translator.modelStatus();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = s;
    });
    if (!ok) SmartDialog.showToast('刪除失敗');
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final text = switch (status) {
      null => '檢查中…',
      ModelStatus.unsupported => '此平台不支援離線翻譯',
      ModelStatus.notDownloaded => '尚未下載',
      ModelStatus.downloaded => '已下載（中文 → 英文）',
    };
    return AlertDialog(
      title: const Text('離線翻譯模型'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text),
          if (_busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        if (status == ModelStatus.downloaded)
          TextButton(
            onPressed: _busy ? null : _delete,
            child: const Text('刪除'),
          ),
        if (status == ModelStatus.notDownloaded)
          TextButton(
            onPressed: _busy ? null : _download,
            child: const Text('下載'),
          ),
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: const Text('關閉'),
        ),
      ],
    );
  }
}
