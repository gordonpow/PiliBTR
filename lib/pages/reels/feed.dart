import 'package:PiliPlus/common/skeleton/video_card_v.dart';
import 'package:PiliPlus/common/sliver_single_child_delegate.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/image/image_save.dart';
import 'package:PiliPlus/common/widgets/video_card/card_preview.dart';
import 'package:PiliPlus/common/widgets/video_card/video_card_style.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models_new/story/story_item.dart';
import 'package:PiliPlus/pages/common/common_controller.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/num_utils.dart';
import 'package:get/get.dart';

/// 首頁「豎屏」分頁的清單：和推薦一樣是影片卡片，點進去才開啟豎屏模式。
class ReelsFeedController extends GetxController with ScrollOrRefreshMixin {
  final items = <StoryItem>[].obs;
  final loading = true.obs;
  final RxnString error = RxnString();
  @override
  final scrollController = ScrollController();

  int _displayId = 0;
  Set<int> _seen = {};
  bool _busy = false;

  static const _maxCalls = 5;

  @override
  void onInit() {
    super.onInit();
    load(refresh: true);
  }

  Future<void> load({bool refresh = false}) async {
    if (_busy) return;
    _busy = true;
    final oldSeen = _seen;
    var ok = !refresh;
    if (refresh) {
      _displayId = 0;
      _seen = {};
    }
    try {
      for (var call = 0; call < _maxCalls; call++) {
        final res = await VideoHttp.storyFeed(
          aid: refresh || items.isEmpty ? null : items.last.aid,
          displayId: ++_displayId,
        );
        if (isClosed) return;
        if (res case Success(:final response)) {
          final added = response
              .where((i) => i.isVertical && _seen.add(i.aid))
              .toList();
          if (added.isNotEmpty) {
            if (refresh) {
              items.assignAll(added);
            } else {
              items.addAll(added);
            }
            error.value = null;
            ok = true;
            break;
          }
        } else {
          if (items.isEmpty) {
            error.value = (res is Error ? res.errMsg : null) ?? '載入失敗';
          }
          break;
        }
      }
    } finally {
      // 重新整理沒有拿到新影片時，保留原清單與去重集合
      if (!ok) _seen = oldSeen;
      loading.value = false;
      _busy = false;
    }
  }

  @override
  Future<void> onRefresh() => load(refresh: true);

  Future<void> onReload() {
    loading.value = true;
    error.value = null;
    return load(refresh: true);
  }

  @override
  void onClose() {
    scrollController.dispose();
    super.onClose();
  }
}

class ReelsFeedPage extends StatefulWidget {
  const ReelsFeedPage({super.key});

  @override
  State<ReelsFeedPage> createState() => _ReelsFeedPageState();
}

class _ReelsFeedPageState extends State<ReelsFeedPage>
    with AutomaticKeepAliveClientMixin {
  final controller = Get.put(ReelsFeedController());

  @override
  bool get wantKeepAlive => true;

  late final gridDelegate = VideoCardStyle.gridDelegate(context);

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Container(
      clipBehavior: .hardEdge,
      margin: const .symmetric(horizontal: Style.safeSpace),
      decoration: const BoxDecoration(borderRadius: Style.mdRadius),
      child: refreshIndicator(
        onRefresh: controller.onRefresh,
        child: CustomScrollView(
          controller: controller.scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const .only(top: Style.cardSpace, bottom: 100),
              sliver: Obx(_buildBody),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final items = controller.items;
    if (items.isEmpty) {
      if (controller.loading.value) {
        return SliverGrid(
          gridDelegate: gridDelegate,
          delegate: const SliverSingleChildDelegate(
            count: 10,
            child: VideoCardVSkeleton(),
          ),
        );
      }
      return HttpError(
        errMsg: controller.error.value ?? '暫時沒有豎屏影片',
        onReload: controller.onReload,
      );
    }
    return SliverGrid.builder(
      gridDelegate: gridDelegate,
      itemCount: items.length,
      itemBuilder: (context, index) {
        if (index == items.length - 1) controller.load();
        return _ReelsCard(item: items[index]);
      },
    );
  }
}

class _ReelsCard extends StatelessWidget {
  const _ReelsCard({required this.item});

  final StoryItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final subStyle = TextStyle(fontSize: 12, color: colorScheme.outline);
    final preview = CardPreview(
      item: item,
      aid: item.aid,
      bvid: item.bvid,
      cid: item.cid,
    );
    void onMore() => imageSaveDialog(
      title: item.title,
      cover: item.cover,
      bvid: item.bvid,
    );
    return preview.wrapTarget(
      Card(
      clipBehavior: Clip.hardEdge,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTapDown: preview.onTapDown,
        onLongPress: () => preview.longPress(onMore),
        onTap: () {
          final progress = preview.take();
          Get.toNamed(
            '/reels',
            arguments: {
              'aid': item.aid,
              'bvid': item.bvid,
              'cid': item.cid,
              'title': item.title,
              'cover': item.cover,
              'item': item,
              if (progress != null && progress.ms > 0) 'progress': progress.ms,
            },
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: Style.aspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  LayoutBuilder(
                    builder: (context, c) => NetworkImgLayer(
                      src: item.cover,
                      width: c.maxWidth,
                      height: c.maxHeight,
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        child: Text(
                          DurationUtils.formatDuration(item.duration),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ),
                  preview.overlay(),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 5, 6, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                    const Spacer(),
                    Text(
                      '${item.ownerName ?? ''} · ${NumUtils.numFormat(item.view)}播放',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: subStyle,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
