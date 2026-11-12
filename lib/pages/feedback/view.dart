import 'package:PiliPlus/common/widgets/zh_material.dart';
import 'package:PiliPlus/services/feedback_report.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:get/get.dart';

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final _controller = TextEditingController();
  FeedbackCategory _category = FeedbackCategory.bug;
  bool _attachLogs = true;
  bool _sending = false;
  int? _logCount;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    FeedbackReport.readLogs().then((logs) {
      if (mounted) setState(() => _logCount = logs.count);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSend =>
      !_sending && (_controller.text.trim().isNotEmpty || _attachLogs);

  String get _logSubtitle {
    final count = _logCount;
    if (count == null) return '讀取中…';
    return count == 0 ? '目前沒有日誌' : '共 $count 筆日誌';
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    final result = await FeedbackReport.send(
      category: _category,
      description: _controller.text,
      attachLogs: _attachLogs,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (result.ok) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('已送出'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('感謝你的回報，回報編號：'),
              const SizedBox(height: 8),
              SelectableText(
                result.id,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Utils.copyText(result.id),
              child: const Text('複製編號'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('確定'),
            ),
          ],
        ),
      );
      if (mounted) Get.back();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.viewPaddingOf(context);
    final outline = ColorScheme.of(context).outline;
    return Scaffold(
      appBar: AppBar(
        title: const Text('回報錯誤／建議'),
        actions: [
          IconButton(
            tooltip: '回報紀錄',
            icon: const Icon(Icons.history),
            onPressed: () => Get.toNamed('/feedbackHistory'),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.only(
          left: padding.left + 16,
          right: padding.right + 16,
          top: 8,
          bottom: padding.bottom + 24,
        ),
        children: [
          const Text('類型'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: FeedbackCategory.values
                .map(
                  (e) => ChoiceChip(
                    label: Text(e.label),
                    selected: _category == e,
                    onSelected: _sending
                        ? null
                        : (_) => setState(() => _category = e),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            enabled: !_sending,
            minLines: 5,
            maxLines: 10,
            maxLength: 2000,
            decoration: const InputDecoration(
              labelText: '描述（選填）',
              hintText: '請描述遇到的問題或想要的功能',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('附上錯誤日誌'),
            subtitle: Text(_logSubtitle),
            value: _attachLogs,
            onChanged: _sending ? null : (v) => setState(() => _attachLogs = v),
          ),
          const SizedBox(height: 4),
          Text(
            '內容會寄給開發者，包含 App 版本與裝置型號。',
            style: TextStyle(color: outline, fontSize: 13),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _canSend ? _send : null,
            icon: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
            label: Text(_sending ? '送出中…' : '送出'),
          ),
        ],
      ),
    );
  }
}
