import 'package:PiliPlus/common/skeleton/video_card_v.dart';
import 'package:PiliPlus/common/sliver_single_child_delegate.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart';

/// Layout of the vertical video cards (cover above the title). The home
/// page and all other video lists use it, so the cards have the same size
/// everywhere. The width comes from the "video card width" setting, or the
/// user sets a fixed number of columns (one for portrait, one for
/// landscape).
abstract final class VideoCardStyle {
  /// Left and right space of a video grid.
  static const EdgeInsets sidePadding = EdgeInsets.symmetric(
    horizontal: Style.safeSpace,
  );

  static SliverGridDelegate gridDelegate(BuildContext context) =>
      SliverGridDelegateWithExtentAndRatio(
        mainAxisSpacing: Style.cardSpace,
        crossAxisSpacing: Style.cardSpace,
        maxCrossAxisExtent: Pref.recommendCardWidth,
        childAspectRatio: Style.aspectRatio,
        mainAxisExtent: MediaQuery.textScalerOf(context).scale(90),
        fixedCrossAxisCount: fixedColumns,
      );

  /// Columns set by the user for the current window shape (portrait or
  /// landscape), or 0 for automatic.
  static int fixedColumns() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return 0;
    final size = views.first.physicalSize;
    return size.width > size.height
        ? Pref.videoCardColumnsLandscape
        : Pref.videoCardColumnsPortrait;
  }
}

/// Grid delegate and loading skeleton for a page with a video grid.
mixin VideoGridMixin<T extends StatefulWidget> on State<T> {
  late final SliverGridDelegate videoGridDelegate = VideoCardStyle.gridDelegate(
    context,
  );

  Widget get videoGridSkeleton => SliverGrid(
    gridDelegate: videoGridDelegate,
    delegate: const SliverSingleChildDelegate(
      count: 10,
      child: VideoCardVSkeleton(),
    ),
  );
}
