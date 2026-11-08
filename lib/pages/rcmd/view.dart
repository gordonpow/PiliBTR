import 'dart:async';

import 'package:PiliPlus/common/skeleton/video_card_v.dart';
import 'package:PiliPlus/common/sliver_single_child_delegate.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/video_card/swipe_preview.dart';
import 'package:PiliPlus/common/widgets/video_card/video_card_style.dart';
import 'package:PiliPlus/common/widgets/video_card/video_card_v.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/home_tab_type.dart';
import 'package:PiliPlus/models/common/nav_bar_config.dart';
import 'package:PiliPlus/models/model_rec_video_item.dart';
import 'package:PiliPlus/pages/home/controller.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/pages/rcmd/controller.dart';
import 'package:PiliPlus/utils/mobile_observer.dart';
import 'package:PiliPlus/utils/play_url_cache.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart';

class RcmdPage extends StatefulWidget {
  const RcmdPage({super.key});

  @override
  State<RcmdPage> createState() => _RcmdPageState();
}

class _RcmdPageState extends State<RcmdPage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final controller = Get.put(RcmdController());


  Timer? _debounce;
  Worker? _loadWorker;
  Worker? _navWorker;
  bool _appResumed = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    addObserverMobile(this);
    // 清單載入完成（含重新整理）後觸發可見卡片預取，不用等捲動。
    _loadWorker = ever(controller.loadingState, (state) {
      if (state is Success) _scheduleVisiblePrefetch();
    });
    if (Get.isRegistered<MainController>()) {
      _navWorker = ever(
        Get.find<MainController>().selectedIndex,
        (_) => _updatePaused(),
      );
    }
    if (Get.isRegistered<HomeController>()) {
      Get.find<HomeController>().tabController.addListener(_updatePaused);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _loadWorker?.dispose();
    _navWorker?.dispose();
    if (Get.isRegistered<HomeController>()) {
      Get.find<HomeController>().tabController.removeListener(_updatePaused);
    }
    removeObserverMobile(this);
    PlayUrlCache.isPaused = true;
    PlayUrlCache.clearPending();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appResumed = state == AppLifecycleState.resumed;
    _updatePaused();
    if (_appResumed) _scheduleVisiblePrefetch();
  }

  /// 推薦分頁是否正在畫面上：主頁籤為首頁、首頁分頁為推薦、App 在前景。
  bool get _isRcmdVisible {
    if (!_appResumed || !mounted) return false;
    if (Get.isRegistered<MainController>()) {
      final main = Get.find<MainController>();
      final i = main.selectedIndex.value;
      if (i < 0 ||
          i >= main.navigationBars.length ||
          main.navigationBars[i] != NavigationBarType.home) {
        return false;
      }
    }
    if (Get.isRegistered<HomeController>()) {
      final home = Get.find<HomeController>();
      if (home.tabs[home.tabController.index] != HomeTabType.rcmd) {
        return false;
      }
    }
    return true;
  }

  void _updatePaused() {
    PlayUrlCache.isPaused = !_isRcmdVisible;
    if (PlayUrlCache.isPaused) {
      _debounce?.cancel();
      PlayUrlCache.clearPending();
    } else {
      _scheduleVisiblePrefetch();
    }
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    if (n is ScrollStartNotification) {
      _debounce?.cancel();
      PlayUrlCache.clearPending();
    } else if (n is ScrollEndNotification) {
      _scheduleVisiblePrefetch();
    }
    return false;
  }

  void _scheduleVisiblePrefetch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!_isRcmdVisible) {
        PlayUrlCache.isPaused = true;
        return;
      }
      PlayUrlCache.isPaused = false;
      final items = _collectVisible();
      if (items.isNotEmpty) unawaited(PlayUrlCache.prefetchVisible(items));
    });
  }

  /// 走訪 render tree，取畫面內（含部分可見）所有有 bvid、cid 的影片卡片。
  List<(String, int)> _collectVisible() {
    final data = controller.loadingState.value.dataOrNull;
    if (data == null || data.isEmpty || !mounted) return const [];
    final root = context.findRenderObject();
    if (root == null) return const [];
    final grid = _findGrid(root);
    if (grid == null || grid.geometry == null) {
      return const [];
    }
    final c = grid.constraints;
    final top = c.scrollOffset;
    final bottom = top + c.remainingPaintExtent;
    final lastRefreshAt = controller.lastRefreshAt;
    final result = <(String, int)>[];
    var child = grid.firstChild;
    while (child != null) {
      final pd = child.parentData;
      if (pd is SliverMultiBoxAdaptorParentData && child.hasSize) {
        final start = pd.layoutOffset ?? 0;
        final end = start + child.size.height;
        var index = pd.index ?? -1;
        if (end > top && start < bottom && index >= 0) {
          if (lastRefreshAt != null) {
            if (index == lastRefreshAt) index = -1;
            if (index > lastRefreshAt) index -= 1;
          }
          if (index >= 0 && index < data.length) {
            final item = data[index];
            if (item is BaseRcmdVideoItemModel &&
                item.goto == 'av' &&
                item.bvid != null &&
                item.cid != null) {
              result.add((item.bvid!, item.cid!));
            }
          }
        }
      }
      child = grid.childAfter(child);
    }
    return result;
  }

  RenderSliverGrid? _findGrid(RenderObject ro) {
    if (ro is RenderSliverGrid) return ro;
    RenderSliverGrid? found;
    ro.visitChildren((c) => found ??= _findGrid(c));
    return found;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = ColorScheme.of(context);
    return Container(
      clipBehavior: .hardEdge,
      margin: const .symmetric(horizontal: Style.safeSpace),
      decoration: const BoxDecoration(borderRadius: Style.mdRadius),
      child: refreshIndicator(
        onRefresh: controller.onRefresh,
        child: SwipePreviewDetector(
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: CustomScrollView(
              controller: controller.scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const .only(top: Style.cardSpace, bottom: 100),
                  sliver: Obx(
                    () =>
                        _buildBody(colorScheme, controller.loadingState.value),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Same layout as every other video list.
  late final gridDelegate = VideoCardStyle.gridDelegate(context);

  Widget _buildBody(
    ColorScheme colorScheme,
    LoadingState<List<dynamic>?> loadingState,
  ) {
    return switch (loadingState) {
      Loading() => _buildSkeleton,
      Success(:final response) =>
        response != null && response.isNotEmpty
            ? SliverGrid.builder(
                gridDelegate: gridDelegate,
                itemBuilder: (context, index) {
                  if (index == response.length - 1) {
                    controller.onLoadMore();
                  }
                  if (controller.lastRefreshAt != null) {
                    if (controller.lastRefreshAt == index) {
                      return GestureDetector(
                        onTap: () => controller
                          ..animateToTop()
                          ..onRefresh(),
                        child: Card(
                          child: Container(
                            alignment: Alignment.center,
                            padding: const .symmetric(horizontal: 10),
                            child: Text(
                              '上次看到這裡\n點選重新整理',
                              textAlign: .center,
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                    final actualIndex = index > controller.lastRefreshAt!
                        ? index - 1
                        : index;
                    return VideoCardV(
                      videoItem: response[actualIndex],
                      onRemove: () {
                        if (controller.lastRefreshAt != null &&
                            actualIndex < controller.lastRefreshAt!) {
                          controller.lastRefreshAt =
                              controller.lastRefreshAt! - 1;
                        }
                        controller.loadingState
                          ..value.data!.removeAt(actualIndex)
                          ..refresh();
                      },
                    );
                  } else {
                    return VideoCardV(
                      videoItem: response[index],
                      onRemove: () => controller.loadingState
                        ..value.data!.removeAt(index)
                        ..refresh(),
                    );
                  }
                },
                itemCount: controller.lastRefreshAt != null
                    ? response.length + 1
                    : response.length,
              )
            : HttpError(onReload: controller.onReload),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: controller.onReload,
      ),
    };
  }

  Widget get _buildSkeleton => SliverGrid(
    gridDelegate: gridDelegate,
    delegate: const SliverSingleChildDelegate(
      count: 10,
      child: VideoCardVSkeleton(),
    ),
  );
}
