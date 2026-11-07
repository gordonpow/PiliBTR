import 'package:PiliPlus/common/skeleton/video_card_v.dart';
import 'package:PiliPlus/common/sliver_single_child_delegate.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/video_card/video_card_h.dart';
import 'package:PiliPlus/common/widgets/video_card/video_card_style.dart';
import 'package:PiliPlus/common/widgets/video_card/video_preview.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/model_hot_video_item.dart';
import 'package:PiliPlus/pages/video/related/controller.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
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
    this.resumeRoute,
  });
  final String heroTag;

  /// The route that must be current for the main player to resume after a
  /// preview. Null: the route of this list. A popup panel (it closes before
  /// the player resumes) gives the video page route here.
  final Route<dynamic>? resumeRoute;

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
    VideoPreview.active.addListener(_onPreviewChanged);
  }

  /// True when a preview of this list paused the main player.
  bool _pausedMain = false;
  ModalRoute<dynamic>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  /// The preview of a card here pauses the main player (two sounds at once
  /// are bad); it plays again when the preview stops.
  void _onPreviewChanged() {
    final active = VideoPreview.active.value;
    final mine =
        active != null &&
        (_relatedController.loadingState.value.dataOrNull?.contains(active) ??
            false);
    if (mine) {
      final player = PlPlayerController.instance;
      if (!_pausedMain && (player?.playerStatus.isPlaying ?? false)) {
        _pausedMain = true;
        player!.pause();
      }
    } else {
      _resumeMain();
    }
  }

  void _resumeMain() {
    if (!_pausedMain) return;
    _pausedMain = false;
    final route = widget.resumeRoute ?? _route;
    // A tapped card opens another video page: the old page must stay
    // paused. Look again after the page was pushed.
    Future.delayed(const Duration(milliseconds: 300), () {
      if (route != null && !route.isCurrent) return;
      final player = PlPlayerController.instance;
      if (player != null && player.playerStatus.isPaused) player.play();
    });
  }

  @override
  void dispose() {
    VideoPreview.active.removeListener(_onPreviewChanged);
    _resumeMain();
    super.dispose();
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
                            pushVideoH(
                              response[index],
                              preview: VideoPreview.takeProgress(
                                response[index].bvid ?? '',
                              ),
                            );
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
