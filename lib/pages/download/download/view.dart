import 'dart:async';

import 'package:PiliPlus/common/widgets/appbar/appbar.dart';
import 'package:PiliPlus/common/widgets/flutter/pop_scope.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/models_new/download/download_info.dart';
import 'package:PiliPlus/pages/common/multi_select/base.dart';
import 'package:PiliPlus/pages/download/detail/widgets/item.dart';
import 'package:PiliPlus/pages/download/download/controller.dart';
import 'package:PiliPlus/pages/download/download/widgets/page.dart';
import 'package:PiliPlus/pages/download/download/widgets/season.dart';
import 'package:PiliPlus/pages/download/download_action_mixin.dart';
import 'package:PiliPlus/pages/download/export/view.dart';
import 'package:PiliPlus/pages/download/search/view.dart';
import 'package:PiliPlus/services/download/download_service.dart';
import 'package:PiliPlus/utils/extension/iterable_ext.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:collection/collection.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart'
    hide SliverGridDelegateWithMaxCrossAxisExtent;

class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage>
    with
        SingleTickerProviderStateMixin,
        GridMixin,
        BaseDownloadActionMixin<DownloadPage, DownloadSeasonInfo> {
  final _progress = ChangeNotifier();
  late final TabController _tabController;
  final _controller = Get.put(DownloadController());

  @override
  final downloadService = Get.find<DownloadService>();

  @override
  BaseMultiSelectMixin<DownloadSeasonInfo> get multiSelectCtr => _controller;

  @override
  void initState() {
    super.initState();
    final args = Get.arguments;
    final tab = args is Map ? args['tab'] : null;
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: tab is int && tab >= 0 && tab < 2 ? tab : 0,
    )
      ..addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabController.dispose();
    _progress.dispose();
    super.dispose();
  }

  @override
  Future<void> onUpdate(
    Future<bool> Function(BiliDownloadEntryInfo e) toElement,
  ) async {
    if (checkUpdateCount(_controller.checkedCount)) return;

    bool dismiss = false;
    SmartDialog.showLoading(
      onDismiss: () {
        dismiss = true;
        _controller.handleSelect();
      },
    );

    bool isSuccess = true;
    for (final chunk in _controller.allChecked.mapChunked(
      kUpdateConcurrency,
      (season) async {
        bool isSuccess = true;
        for (final chunk in season.pages.mapChunked(
          kUpdateConcurrency,
          (page) async {
            bool isSuccess = true;
            for (final chunk in page.entries.mapChunked(
              kUpdateConcurrency,
              toElement,
            )) {
              final res = await Future.wait(chunk);
              if (res.any((e) => !e)) isSuccess = false;
              if (dismiss) break;
            }
            return isSuccess;
          },
        )) {
          final res = await Future.wait(chunk);
          if (res.any((e) => !e)) isSuccess = false;
          if (dismiss) break;
        }
        return isSuccess;
      },
    )) {
      final res = await Future.wait(chunk);
      if (res.any((e) => !e)) isSuccess = false;
      if (dismiss) break;
    }

    toastUpdateResult(dismiss, isSuccess);
  }

  Future<void> _updateSeasonDm(DownloadSeasonInfo seasonInfo) async {
    if (checkUpdateCount(
      seasonInfo.pages.fold(0, (a, b) => a + b.entries.length),
    )) {
      return;
    }

    bool dismiss = false;
    SmartDialog.showLoading(onDismiss: () => dismiss = true);

    bool isSuccess = true;

    for (final page in seasonInfo.pages) {
      for (final chunk in page.entries.mapChunked(
        kUpdateConcurrency,
        (e) => downloadService.downloadDanmaku(
          entry: e,
          isUpdate: true,
        ),
      )) {
        final res = await Future.wait(chunk);
        if (res.any((e) => !e)) isSuccess = false;
        if (dismiss) break;
      }
    }

    toastUpdateResult(dismiss, isSuccess);
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.viewPaddingOf(context);
    return Obx(() {
      final enableMultiSelect = _controller.enableMultiSelect.value;
      final isCacheTab = _tabController.index == 0;
      return popScope(
        canPop: !enableMultiSelect,
        onPopInvokedWithResult: (didPop, result) {
          if (enableMultiSelect) {
            _controller.handleSelect();
          }
        },
        child: SimpleScaffold(
          appBar: MultiSelectAppBarWidget(
            ctr: _controller,
            actions: [updateBtn()],
            child: AppBar(
              title: const Text('快取與下載'),
              actions: [
                if (isCacheTab) ...[
                  IconButton(
                    tooltip: '搜尋',
                    onPressed: () async {
                      await downloadService.waitForInitialization;
                      if (!mounted) return;
                      Get.to(DownloadSearchPage(progress: _progress));
                    },
                    icon: const Icon(Icons.search),
                  ),
                  IconButton(
                    tooltip: '多選',
                    onPressed: () {
                      if (enableMultiSelect) {
                        _controller.handleSelect();
                      } else {
                        _controller.enableMultiSelect.value = true;
                      }
                    },
                    icon: const Icon(Icons.edit_note),
                  ),
                ],
                const SizedBox(width: 6),
              ],
            ),
          ),
          body: Padding(
            padding: EdgeInsets.only(left: padding.left, right: padding.right),
            child: Column(
              children: [
                IgnorePointer(
                  ignoring: enableMultiSelect,
                  child: TabBar(
                    controller: _tabController,
                    tabs: const [
                      Tab(text: '快取'),
                      Tab(text: '下載'),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    physics: enableMultiSelect
                        ? const NeverScrollableScrollPhysics()
                        : null,
                    children: [
                      _KeepAlive(
                        child: _buildCacheTab(padding, enableMultiSelect),
                      ),
                      const _KeepAlive(child: ExportTab()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _buildCacheTab(EdgeInsets padding, bool enableMultiSelect) {
    return CustomScrollView(
      slivers: [
        Obx(() {
          final entry =
              downloadService.waitDownloadQueue.firstWhereOrNull(
                (e) => e.cid == downloadService.curCid,
              ) ??
              downloadService.waitDownloadQueue.firstOrNull;
          if (entry != null) {
            return SliverMainAxisGroup(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.only(left: 12, bottom: 7),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      '正在快取 (${downloadService.waitDownloadQueue.length})',
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 110,
                    child: DetailItem(
                      entry: entry,
                      progress: _progress,
                      downloadService: downloadService,
                      showTitle: true,
                      isCurr: true,
                      controller: _controller,
                    ),
                  ),
                ),
              ],
            );
          }
          return const SliverToBoxAdapter();
        }),
        Obx(() {
          if (_controller.seasons.isNotEmpty) {
            return SliverMainAxisGroup(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.only(
                    left: 12,
                    bottom: 7,
                    top: downloadService.waitDownloadQueue.isEmpty ? 0 : 7,
                  ),
                  sliver: const SliverToBoxAdapter(
                    child: Text('已快取影片'),
                  ),
                ),
                SliverGrid.builder(
                  gridDelegate: gridDelegate,
                  itemBuilder: (context, index) {
                    final season = _controller.seasons[index];
                    final seasonInfo = season.seasonInfo;
                    final pages = season.pages;

                    if (seasonInfo != null && pages.length > 1) {
                      return SeasonInfoItem(
                        controller: _controller,
                        downloadService: downloadService,
                        seasonInfo: seasonInfo,
                        season: season,
                        enableMultiSelect: enableMultiSelect,
                        progress: _progress,
                        updateSeasonDm: _updateSeasonDm,
                      );
                    }

                    final page = pages.first;
                    if (pages.length == 1 && page.entries.length == 1) {
                      final entry = page.entries.first;
                      return DetailItem(
                        entry: entry,
                        progress: _progress,
                        downloadService: downloadService,
                        showTitle: true,
                        onDelete: () {
                          downloadService.deleteDownload(
                            entry: entry,
                            removeList: true,
                          );
                          GStorage.watchProgress.delete(
                            entry.cid.toString(),
                          );
                        },
                        checked: season.checked,
                        onSelect: (_) => _controller.onSelect(season),
                        controller: _controller,
                      );
                    }

                    return PageInfoItem(
                      controller: _controller,
                      downloadService: downloadService,
                      seasonInfo: season,
                      pageInfo: page,
                      enableMultiSelect: enableMultiSelect,
                      progress: _progress,
                      updatePageDm: updatePageDm,
                    );
                  },
                  itemCount: _controller.seasons.length,
                ),
              ],
            );
          }
          if (downloadService.waitDownloadQueue.isNotEmpty) {
            return const SliverToBoxAdapter();
          }
          return const HttpError();
        }),
        SliverToBoxAdapter(
          child: SizedBox(height: padding.bottom + 100),
        ),
      ],
    );
  }
}

class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
