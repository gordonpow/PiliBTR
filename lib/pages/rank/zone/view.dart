import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/video_card/video_card_h.dart';
import 'package:PiliPlus/common/widgets/video_card/video_card_style.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/model_hot_video_item.dart';
import 'package:PiliPlus/pages/rank/zone/controller.dart';
import 'package:PiliPlus/pages/rank/zone/widget/pgc_rank_item.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:get/get.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart';

class ZonePage extends StatefulWidget {
  const ZonePage({super.key, this.rid, this.seasonType});

  final int? rid;
  final int? seasonType;

  @override
  State<ZonePage> createState() => _ZonePageState();
}

class _ZonePageState extends State<ZonePage>
    with AutomaticKeepAliveClientMixin, GridMixin, VideoGridMixin {
  late final ZoneController controller;

  @override
  void initState() {
    controller = Get.put(
      ZoneController(rid: widget.rid, seasonType: widget.seasonType),
      tag: '${widget.rid}${widget.seasonType}',
    );
    super.initState();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return refreshIndicator(
      onRefresh: controller.onRefresh,
      child: CustomScrollView(
        controller: controller.scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.only(top: 7, bottom: 100),
            sliver: Obx(() => _buildBody(controller.loadingState.value)),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(LoadingState<List<dynamic>?> loadingState) {
    return switch (loadingState) {
      Loading() =>
        widget.seasonType == null
            ? SliverPadding(
                padding: VideoCardStyle.sidePadding,
                sliver: videoGridSkeleton,
              )
            : gridSkeleton,
      Success(:final response) =>
        response != null && response.isNotEmpty
            ? _buildGrid(response)
            : HttpError(onReload: controller.onReload),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: controller.onReload,
      ),
    };
  }

  Widget _buildGrid(List<dynamic> response) {
    final isVideo = response.first is HotVideoItemModel;
    final grid = SliverGrid.builder(
      gridDelegate: isVideo ? videoGridDelegate : gridDelegate,
      itemBuilder: (context, index) {
        final item = response[index];
        if (item is HotVideoItemModel) {
          return VideoCardH(
            videoItem: item,
            vertical: true,
            onRemove: () => controller.loadingState
              ..value.data!.removeAt(index)
              ..refresh(),
          );
        }
        return PgcRankItem(item: item);
      },
      itemCount: response.length,
    );
    if (!isVideo) return grid;
    return SliverPadding(padding: VideoCardStyle.sidePadding, sliver: grid);
  }
}
