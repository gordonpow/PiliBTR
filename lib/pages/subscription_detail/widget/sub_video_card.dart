import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/image/image_save.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/stat/stat.dart';
import 'package:PiliPlus/common/widgets/video_card/card_preview.dart';
import 'package:PiliPlus/common/widgets/video_card/vertical_video_card_frame.dart';
import 'package:PiliPlus/common/widgets/video_card/video_preview.dart';
import 'package:PiliPlus/http/search.dart';
import 'package:PiliPlus/models/common/badge_type.dart';
import 'package:PiliPlus/models/common/stat_type.dart';
import 'package:PiliPlus/models_new/sub/sub_detail/media.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart';

// 收藏视频卡片 - 水平布局
class SubVideoCardH extends StatelessWidget {
  final SubDetailItemModel videoItem;
  final int? searchType;

  /// Vertical layout (cover above the title), the same as the home card.
  final bool vertical;

  const SubVideoCardH({
    super.key,
    required this.videoItem,
    this.searchType,
    this.vertical = false,
  });

  @override
  Widget build(BuildContext context) {
    void onLongPress() => imageSaveDialog(
      title: videoItem.title,
      cover: videoItem.cover,
      bvid: videoItem.bvid,
    );
    final preview = CardPreview(
      item: videoItem,
      canPreview: videoItem.bvid != null,
      bvid: videoItem.bvid ?? '',
      cid: null,
    );
    if (vertical) {
      final theme = Theme.of(context);
      final textTheme = theme.textTheme;
      return VerticalVideoCardFrame(
        cover: _cover(preview, overlay: false),
        title: Text(
          videoItem.title!,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: VerticalVideoCardFrame.titleStyle.copyWith(
            fontSize: textTheme.bodyMedium?.fontSize,
          ),
        ),
        stats: Row(
          spacing: 8,
          children: [
            StatWidget(
              type: StatType.play,
              value: videoItem.cntInfo?.play,
            ),
            StatWidget(
              type: StatType.danmaku,
              value: videoItem.cntInfo?.danmaku,
            ),
          ],
        ),
        footer: Text(
          DateFormatUtils.dateFormat(videoItem.pubtime),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        onTap: () => _onTap(preview.take()),
        onLongPress: onLongPress,
        onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
        preview: preview,
      );
    }
    return preview.wrapTarget(
      Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => _onTap(preview.take()),
          onTapDown: preview.onTapDown,
          onLongPress: preview.longPressOr(onLongPress),
          onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Style.safeSpace,
              vertical: 5,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: Style.aspectRatio,
                  child: _cover(preview),
                ),
                const SizedBox(width: 10),
                content(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onTap(PreviewProgress? preview) async {
    final res = preview == null
        ? await SearchHttp.ab2cWithDimension(bvid: videoItem.bvid)
        : null;
    final cid = preview?.cid ?? res?.cid;
    if (cid != null) {
      PageUtils.toVideoPage(
        bvid: videoItem.bvid,
        cid: cid,
        cover: videoItem.cover,
        title: videoItem.title,
        dimension: res?.dimension,
        progress: preview?.ms,
      );
    }
  }

  Widget _cover(CardPreview preview, {bool overlay = true}) {
    return LayoutBuilder(
      builder: (context, boxConstraints) {
        double maxWidth = boxConstraints.maxWidth;
        double maxHeight = boxConstraints.maxHeight;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            NetworkImgLayer(
              src: videoItem.cover,
              width: maxWidth,
              height: maxHeight,
            ),
            PBadge(
              text: DurationUtils.formatDuration(videoItem.duration),
              right: 6.0,
              bottom: 6.0,
              type: PBadgeType.gray,
            ),
            if (overlay) preview.overlay(radius: Style.mdRadius),
          ],
        );
      },
    );
  }

  Widget content(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              videoItem.title!,
              textAlign: TextAlign.start,
              style: const TextStyle(
                letterSpacing: 0.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            DateFormatUtils.dateFormat(videoItem.pubtime),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            spacing: 8,
            children: [
              StatWidget(
                type: StatType.play,
                value: videoItem.cntInfo?.play,
              ),
              StatWidget(
                type: StatType.danmaku,
                value: videoItem.cntInfo?.danmaku,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
