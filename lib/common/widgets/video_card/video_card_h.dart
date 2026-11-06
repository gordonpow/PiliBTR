import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/image/image_save.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/progress_bar/video_progress_indicator.dart';
import 'package:PiliPlus/common/widgets/stat/stat.dart';
import 'package:PiliPlus/common/widgets/video_card/vertical_video_card_frame.dart';
import 'package:PiliPlus/common/widgets/video_card/video_card_v.dart';
import 'package:PiliPlus/common/widgets/video_popup_menu.dart';
import 'package:PiliPlus/http/search.dart';
import 'package:PiliPlus/models/horizontal_video_model.dart';
import 'package:PiliPlus/models_new/video/video_detail/dimension.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart';

// 视频卡片 - 水平布局
class VideoCardH extends StatelessWidget {
  const VideoCardH({
    super.key,
    required this.videoItem,
    this.onTap,
    this.onViewLater,
    this.onRemove,
    this.vertical = false,
  });
  final HorizontalVideoModel videoItem;
  final VoidCallback? onTap;
  final ValueChanged<int>? onViewLater;
  final VoidCallback? onRemove;

  /// Vertical layout (cover above the title), like the home page card.
  final bool vertical;

  void onLongPress() => imageSaveDialog(
    bvid: videoItem.bvid,
    title: videoItem.title,
    cover: videoItem.cover,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (vertical) return _buildVertical(theme);
    return Material(
      type: .transparency,
      child: Stack(
        clipBehavior: .none,
        children: [
          InkWell(
            onLongPress: onLongPress,
            onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
            onTap: onTap ?? () => pushVideoH(videoItem),
            child: Padding(
              padding: const .symmetric(
                horizontal: Style.safeSpace,
                vertical: 5,
              ),
              child: Row(
                crossAxisAlignment: .start,
                children: [
                  AspectRatio(
                    aspectRatio: Style.aspectRatio,
                    child: _buildCover(theme),
                  ),
                  const SizedBox(width: 10),
                  content(theme),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 12,
            width: 29,
            height: 29,
            child: VideoPopupMenu(
              iconSize: 17,
              videoItem: videoItem,
              onRemove: onRemove,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVertical(ThemeData theme) {
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;
    final titleList = videoItem.titleList;
    final Widget title;
    if (titleList != null && titleList.isNotEmpty) {
      title = Text.rich(
        maxLines: 2,
        overflow: .ellipsis,
        TextSpan(
          children: titleList
              .map(
                (e) => TextSpan(
                  text: e.text,
                  style: VerticalVideoCardFrame.titleStyle.copyWith(
                    fontSize: textTheme.bodyMedium!.fontSize,
                    color: e.isEm ? colorScheme.primary : colorScheme.onSurface,
                  ),
                ),
              )
              .toList(),
        ),
      );
    } else {
      title = Text(
        videoItem.title,
        maxLines: 2,
        overflow: .ellipsis,
        style: VerticalVideoCardFrame.titleStyle.copyWith(
          fontSize: textTheme.bodyMedium!.fontSize,
        ),
      );
    }
    // Live items have no play count: keep the stats size, hide the content.
    final stats = Row(
      children: [
        // In a narrow card the counts shrink instead of running into the
        // date.
        Expanded(
          child: FittedBox(
            fit: .scaleDown,
            alignment: .centerLeft,
            child: Visibility.maintain(
              visible: videoItem.isLive != true,
              child: Row(
                spacing: 4,
                children: [
                  StatWidget(type: .play, value: videoItem.stat.view),
                  StatWidget(type: .danmaku, value: videoItem.stat.danmu),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          DateFormatUtils.dateFormat(
            videoItem.pubdate,
            short: VideoCardV.shortFormat,
            long: VideoCardV.longFormat,
          ),
          maxLines: 1,
          style: TextStyle(
            fontSize: textTheme.labelSmall!.fontSize,
            color: colorScheme.outline.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(width: 2),
      ],
    );
    return VerticalVideoCardFrame(
      cover: _buildCover(theme),
      title: title,
      stats: stats,
      footer: Text(
        videoItem.owner.name.toString(),
        maxLines: 1,
        overflow: .ellipsis,
        style: TextStyle(
          height: 1.5,
          fontSize: textTheme.labelMedium!.fontSize,
          color: colorScheme.outline,
        ),
      ),
      action: VideoPopupMenu(
        iconSize: 17,
        videoItem: videoItem,
        onRemove: onRemove,
      ),
      onTap: onTap ?? () => pushVideoH(videoItem),
      onLongPress: onLongPress,
      onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
    );
  }

  Widget _buildCover(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, boxConstraints) {
        final double maxWidth = boxConstraints.maxWidth;
        final double maxHeight = boxConstraints.maxHeight;

        final progress = videoItem.progress;

        return Stack(
          clipBehavior: .none,
          children: [
            NetworkImgLayer(
              src: videoItem.cover,
              width: maxWidth,
              height: maxHeight,
              borderRadius: vertical ? .zero : Style.mdRadius,
            ),
            if (videoItem.badge case final badge?)
              PBadge(
                text: badge,
                top: 6.0,
                right: 6.0,
                type: switch (badge) {
                  '充電專屬' => .error,
                  _ => .primary,
                },
              ),
            if (progress != null && progress != 0) ...[
              PBadge(
                text: progress == -1
                    ? '已看完'
                    : '${DurationUtils.formatDuration(progress)}/${DurationUtils.formatDuration(videoItem.duration)}',
                right: 6,
                bottom: 8,
                type: .gray,
              ),
              Positioned(
                left: 0,
                bottom: 0,
                right: 0,
                child: VideoProgressIndicator(
                  color: theme.colorScheme.primary,
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  progress: progress == -1 ? 1 : progress / videoItem.duration,
                ),
              ),
            ] else if (videoItem.duration > 0)
              PBadge(
                text: DurationUtils.formatDuration(
                  videoItem.duration,
                ),
                right: 6.0,
                bottom: 6.0,
                type: .gray,
              ),
          ],
        );
      },
    );
  }

  Widget content(ThemeData theme) {
    String pubdate = DateFormatUtils.dateFormat(videoItem.pubdate!);
    if (pubdate != '') pubdate += '  ';
    return Expanded(
      child: Column(
        crossAxisAlignment: .start,
        children: [
          if (videoItem.titleList?.isNotEmpty == true)
            Expanded(
              child: Text.rich(
                overflow: .ellipsis,
                maxLines: 2,
                TextSpan(
                  children: videoItem.titleList!
                      .map(
                        (e) => TextSpan(
                          text: e.text,
                          style: TextStyle(
                            fontSize: theme.textTheme.bodyMedium!.fontSize,
                            height: 1.42,
                            letterSpacing: 0.3,
                            color: e.isEm
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            )
          else
            Expanded(
              child: Text(
                videoItem.title,
                textAlign: .start,
                style: TextStyle(
                  fontSize: theme.textTheme.bodyMedium!.fontSize,
                  height: 1.42,
                  letterSpacing: 0.3,
                ),
                maxLines: 2,
                overflow: .ellipsis,
              ),
            ),
          Text(
            "$pubdate${videoItem.owner.name}",
            maxLines: 1,
            style: TextStyle(
              fontSize: 12,
              height: 1,
              color: theme.colorScheme.outline,
              overflow: .ellipsis,
            ),
          ),
          if (videoItem.isLive != true) ...[
            const SizedBox(height: 3),
            // Scale down in narrow cards instead of overflowing.
            FittedBox(
              fit: .scaleDown,
              alignment: .centerLeft,
              child: Row(
                spacing: 8,
                children: [
                  StatWidget(
                    type: .play,
                    value: videoItem.stat.view,
                  ),
                  StatWidget(
                    type: .danmaku,
                    value: videoItem.stat.danmu,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> pushVideoH(HorizontalVideoModel videoItem) async {
  if (videoItem.isPugv ?? false) {
    PageUtils.viewPugv(seasonId: videoItem.seasonId);
    return;
  }

  if (videoItem.isLive ?? false) {
    if (videoItem.roomId case final roomId?) {
      PageUtils.toLiveRoom(roomId);
    }
    return;
  }

  if (videoItem.redirectUrl?.isNotEmpty == true &&
      PageUtils.viewPgcFromUri(videoItem.redirectUrl!)) {
    return;
  }

  int? cid = videoItem.cid;
  Dimension? dimension = videoItem.dimension;
  if (cid == null) {
    if (await SearchHttp.ab2cWithDimension(
          aid: videoItem.aid,
          bvid: videoItem.bvid,
        )
        case final res?) {
      cid = res.cid;
      dimension = res.dimension;
    }
  }
  if (cid != null) {
    PageUtils.toVideoPage(
      bvid: videoItem.bvid,
      cid: cid,
      cover: videoItem.cover,
      title: videoItem.title,
      dimension: dimension,
    );
  }
}
