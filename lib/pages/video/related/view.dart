import 'package:PiliPlus/common/skeleton/video_card_v.dart';
import 'package:PiliPlus/common/sliver_single_child_delegate.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/video_card/video_card_h.dart';
import 'package:PiliPlus/common/widgets/video_card/video_card_style.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/model_hot_video_item.dart';
import 'package:PiliPlus/pages/video/related/controller.dart';
import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:get/get.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart';

class RelatedVideoPanel extends StatefulWidget {
  const RelatedVideoPanel({
    super.key,
    required this.heroTag,
    this.beforeOpen,
    this.sidePane = false,
  });
  final String heroTag;

  /// True when the list is in the side pane of the landscape video page,
  /// which has its own column setting.
  final bool sidePane;

  /// Called before a tapped video opens (for example to close the panel
  /// that shows this list).
  final VoidCallback? beforeOpen;
  @override
  State<RelatedVideoPanel> createState() => _RelatedVideoPanelState();
}

// Vertical cards like the home page (same width and column setting).
class _RelatedVideoPanelState extends State<RelatedVideoPanel> {
  late final RelatedController _relatedController;

  @override
  void initState() {
    super.initState();
    _relatedController = Get.putOrFind(
      RelatedController.new,
      tag: widget.heroTag,
    );
  }

  // The same State moves between the portrait and landscape layouts, so the
  // delegate is built per build() from [RelatedVideoPanel.sidePane].
  SliverGridDelegate _gridDelegate(BuildContext context) =>
      VideoCardStyle.gridDelegate(
        context,
        fixedColumns: widget.sidePane
            ? () => Pref.videoPageRelatedColumns
            : null,
      );

  @override
  Widget build(BuildContext context) {
    final gridDelegate = _gridDelegate(context);
    return SliverPadding(
      padding: VideoCardStyle.sidePadding.add(
        const EdgeInsets.only(top: 7, bottom: 100),
      ),
      sliver: Obx(
        () => _buildBody(_relatedController.loadingState.value, gridDelegate),
      ),
    );
  }

  Widget _buildBody(
    LoadingState<List<HotVideoItemModel>?> loadingState,
    SliverGridDelegate gridDelegate,
  ) {
    return switch (loadingState) {
      Loading() => SliverGrid(
        gridDelegate: gridDelegate,
        delegate: const SliverSingleChildDelegate(
          count: 10,
          child: VideoCardVSkeleton(),
        ),
      ),
      Success(:final response) =>
        response != null && response.isNotEmpty
            ? SliverGrid.builder(
                gridDelegate: gridDelegate,
                itemBuilder: (context, index) {
                  final beforeOpen = widget.beforeOpen;
                  return VideoCardH(
                    videoItem: response[index],
                    vertical: true,
                    onTap: beforeOpen == null
                        ? null
                        : () {
                            beforeOpen();
                            pushVideoH(response[index]);
                          },
                    onRemove: () => _relatedController.loadingState
                      ..value.data!.removeAt(index)
                      ..refresh(),
                  );
                },
                itemCount: response.length,
              )
            : const SliverToBoxAdapter(),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: _relatedController.onReload,
      ),
    };
  }
}
