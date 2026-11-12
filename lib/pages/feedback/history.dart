import 'package:PiliPlus/common/widgets/zh_material.dart';
import 'package:PiliPlus/services/feedback_history.dart';
import 'package:PiliPlus/services/feedback_status.dart';
import 'package:PiliPlus/utils/utils.dart';

class FeedbackHistoryPage extends StatefulWidget {
  const FeedbackHistoryPage({super.key});

  @override
  State<FeedbackHistoryPage> createState() => _FeedbackHistoryPageState();
}

class _FeedbackHistoryPageState extends State<FeedbackHistoryPage> {
  late final List<FeedbackRecord> _records = FeedbackHistory.load();
  late Map<String, FeedbackStatus> _statuses = FeedbackStatusService.cached();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final statuses = await FeedbackStatusService.load();
    if (mounted) setState(() => _statuses = statuses);
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _formatTime(DateTime t) =>
      '${t.year}-${_two(t.month)}-${_two(t.day)} '
      '${_two(t.hour)}:${_two(t.minute)}';

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.viewPaddingOf(context);
    final theme = Theme.of(context);
    final outline = theme.colorScheme.outline;
    return Scaffold(
      appBar: AppBar(title: const Text('回報紀錄')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _records.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: 240,
                    child: Center(
                      child: Text('還沒有送出過回報', style: TextStyle(color: outline)),
                    ),
                  ),
                ],
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(
                  left: padding.left + 16,
                  right: padding.right + 16,
                  top: 8,
                  bottom: padding.bottom + 24,
                ),
                itemCount: _records.length,
                separatorBuilder: (_, _) => const Divider(height: 24),
                itemBuilder: (context, index) =>
                    _buildItem(theme, _records[index]),
              ),
      ),
    );
  }

  Widget _buildItem(ThemeData theme, FeedbackRecord record) {
    final outline = theme.colorScheme.outline;
    final status = _statuses[record.id.toUpperCase()];
    final note = status?.note;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            InkWell(
              onTap: () => Utils.copyText(record.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      record.id,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.copy, size: 14, color: outline),
                  ],
                ),
              ),
            ),
            const Spacer(),
            Chip(
              label: Text(status?.kind.label ?? '已送出'),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${_formatTime(record.time)}　${record.category}',
          style: TextStyle(color: outline, fontSize: 13),
        ),
        if (record.summary.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(record.summary),
        ],
        if (note != null) ...[
          const SizedBox(height: 4),
          Text(
            note,
            style: TextStyle(color: theme.colorScheme.primary, fontSize: 13),
          ),
        ],
      ],
    );
  }
}
