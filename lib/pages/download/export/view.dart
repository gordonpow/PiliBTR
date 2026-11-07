import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/video_popup_player.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart';
import 'package:PiliPlus/services/download/video_export.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:get/get.dart';

/// 「下載」分頁：進行中的 MP4 下載與已完成的檔案
class ExportTab extends StatefulWidget {
  const ExportTab({super.key});

  @override
  State<ExportTab> createState() => _ExportTabState();
}

class _ExportTabState extends State<ExportTab> {
  late List<ExportRecord> _records = VideoExport.records();
  Worker? _worker;

  @override
  void initState() {
    super.initState();
    // 下載完成（current 變成 null）後重新讀取清單
    _worker = ever(VideoExport.current, (task) {
      if (task == null) _refresh();
    });
  }

  @override
  void dispose() {
    _worker?.dispose();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() => _records = VideoExport.records());
  }

  static String _formatTime(int ms) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  Widget _cover(String? src, double width, double height) {
    if (src == null || src.isEmpty) {
      return SizedBox(
        width: width,
        height: height,
        child: const Icon(Icons.movie_outlined),
      );
    }
    return NetworkImgLayer(src: src, width: width, height: height);
  }

  void _showMenu(ExportRecord r) {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        clipBehavior: Clip.hardEdge,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          ListTile(
            dense: true,
            title: const Text('刪除'),
            onTap: () {
              Get.back();
              showConfirmDialog(
                context: this.context,
                title: const Text('刪除這個檔案？'),
                onConfirm: () async {
                  await VideoExport.deleteRecord(r.path);
                  _refresh();
                },
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: Obx(() {
        final task = VideoExport.current.value;
        if (task == null && _records.isEmpty) {
          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    '還沒有下載的影片',
                    style: TextStyle(color: theme.colorScheme.outline),
                  ),
                ),
              ),
            ],
          );
        }
        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (task != null)
              SliverToBoxAdapter(
                child: Card(
                  margin: const EdgeInsets.fromLTRB(
                    Style.safeSpace,
                    8,
                    Style.safeSpace,
                    4,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                    child: Row(
                      spacing: 10,
                      children: [
                        _cover(task.cover, 96, 54),
                        Expanded(child: ExportTaskTile(task: task)),
                      ],
                    ),
                  ),
                ),
              ),
            SliverList.builder(
              itemCount: _records.length,
              itemBuilder: (context, index) {
                final r = _records[index];
                return InkWell(
                  onTap: () => showVideoPopup(
                    context,
                    videoPath: r.path,
                    title: r.title,
                  ),
                  onLongPress: () => _showMenu(r),
                  onSecondaryTap: () => _showMenu(r),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Style.safeSpace,
                      vertical: 6,
                    ),
                    child: Row(
                      spacing: 10,
                      children: [
                        _cover(r.cover, 112, 63),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 4,
                            children: [
                              Text(
                                r.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${r.size.formatSize}　${_formatTime(r.time)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            SliverToBoxAdapter(child: SizedBox(height: bottom + 100)),
          ],
        );
      }),
    );
  }
}
