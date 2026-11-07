import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/video_card/video_card_h.dart';
import 'package:PiliPlus/common/widgets/video_card/video_preview.dart';
import 'package:PiliPlus/common/widgets/video_card/video_card_style.dart';
import 'package:PiliPlus/common/widgets/view_sliver_safe_area.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/video/source_type.dart';
import 'package:PiliPlus/models/model_hot_video_item.dart';
import 'package:PiliPlus/pages/popular_precious/controller.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:get/get.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart';

class PopularPreciousPage extends StatefulWidget {
  const PopularPreciousPage({super.key});

  @override
  State<PopularPreciousPage> createState() => _PopularPreciousPageState();
}

class _PopularPreciousPageState extends State<PopularPreciousPage>
    with VideoGridMixin {
  final _controller = Get.put(PopularPreciousController());

  @override
  Widget build(BuildContext context) {
    return SimpleScaffold(
      appBar: AppBar(title: const Text('入站必刷')),
      body: refreshIndicator(
        onRefresh: _controller.onRefresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            ViewSliverSafeArea(
              sliver: Obx(() => _buildBody(_controller.loadingState.value)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(LoadingState<List<HotVideoItemModel>?> value) {
    switch (value) {
      case Loading():
        return SliverPadding(
          padding: VideoCardStyle.sidePadding,
          sliver: videoGridSkeleton,
        );
      case Success<List<HotVideoItemModel>?>(:final response):
        return SliverPadding(
          padding: VideoCardStyle.sidePadding,
          sliver: SliverGrid.builder(
            gridDelegate: videoGridDelegate,
            itemCount: response!.length,
            itemBuilder: (context, index) {
              final item = response[index];
              return VideoCardH(
                videoItem: item,
                vertical: true,
                onTap: () {
                  final preview = VideoPreview.takeProgress(item.bvid ?? '');
                  PageUtils.toVideoPage(
                    bvid: item.bvid,
                    cid: preview?.cid ?? item.cid!,
                    progress: preview?.ms,
                    dimension: item.dimension,
                    extraArguments: {
                      'sourceType': SourceType.playlist,
                      'favTitle': '入站必刷',
                      'mediaId': _controller.mediaId,
                      'desc': true,
                      'oid': item.aid,
                      'isContinuePlaying': index != 0,
                    },
                  );
                },
              );
            },
          ),
        );
      case Error(:final errMsg):
        return HttpError(
          errMsg: errMsg,
          onReload: _controller.onReload,
        );
    }
  }
}
