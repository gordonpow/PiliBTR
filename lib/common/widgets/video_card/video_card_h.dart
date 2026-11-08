import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/content_text.dart';
import 'package:PiliPlus/common/widgets/image/image_save.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/progress_bar/video_progress_indicator.dart';
import 'package:PiliPlus/common/widgets/stat/stat.dart';
import 'package:PiliPlus/common/widgets/video_card/card_preview.dart';
import 'package:PiliPlus/common/widgets/video_card/vertical_video_card_frame.dart';
import 'package:PiliPlus/common/widgets/video_card/video_card_v.dart';
import 'package:PiliPlus/common/widgets/video_card/video_preview.dart';
import 'package:PiliPlus/common/widgets/video_popup_menu.dart';
import 'package:PiliPlus/http/search.dart';
import 'package:PiliPlus/models/horizontal_video_model.dart';
import 'package:PiliPlus/models_new/video/video_detail/dimension.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart';
import 'package:flutter/widgets.dart' as flutter show Text;

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

  /// Custom tap. When it opens the video it should continue from the
  /// preview: use [VideoPreview.takeProgress] with the bvid.
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

  /// A normal video (not a course, live, or bangumi) with a bvid.
  static bool canPreviewItem(HorizontalVideoModel item) =>
      item.bvid != null &&
      item.isPugv != true &&
      item.isLive != true &&
      item.redirectUrl?.isNotEmpty != true;

  CardPreview get _preview => CardPreview(
    item: videoItem,
    canPreview: canPreviewItem(videoItem),
    aid: videoItem.aid,
    bvid: videoItem.bvid ?? '',
    cid: videoItem.cid,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _preview;
    if (vertical) return _buildVertical(theme, preview);
    return preview.wrapTarget(
      Material(
        type: .transparency,
        child: Stack(
          clipBehavior: .none,
          children: [
            InkWell(
              onTapDown: preview.onTapDown,
              onLongPress: () => preview.longPress(onLongPress),
              onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
              onTap:
                  onTap ?? () => pushVideoH(videoItem, preview: preview.take()),
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
                      child: _buildCover(theme, preview),
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
      ),
    );
  }

  Widget _buildVertical(ThemeData theme, CardPreview preview) {
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;
    final titleList = videoItem.titleList;
    final titleStyle = VerticalVideoCardFrame.titleStyle.copyWith(
      fontSize: textTheme.bodyMedium!.fontSize,
    );
    final Widget title = ContentTextBuilder(
      text: videoItem.title,
      builder: (context, shown, translated) {
        // The search highlight is dropped for a translated title.
        if (!translated && titleList != null && titleList.isNotEmpty) {
          return Text.rich(
            maxLines: 2,
            overflow: .ellipsis,
            TextSpan(
              children: titleList
                  .map(
                    (e) => TextSpan(
                      text: e.text,
                      style: VerticalVideoCardFrame.titleStyle.copyWith(
                        fontSize: textTheme.bodyMedium!.fontSize,
                        color: e.isEm
                            ? colorScheme.primary
                            : colorScheme.onSurface,
                      ),
                    ),
                  )
                  .toList(),
            ),
          );
        }
        if (translated) {
          return flutter.Text(
            shown!,
            maxLines: 2,
            overflow: .ellipsis,
            style: titleStyle,
          );
        }
        return Text(
          videoItem.title,
          maxLines: 2,
          overflow: .ellipsis,
          style: titleStyle,
        );
      },
    );
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
      cover: _buildCover(theme, preview),
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
      onTap: onTap ?? () => pushVideoH(videoItem, preview: preview.take()),
      onLongPress: onLongPress,
      onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
      preview: preview,
    );
  }

  Widget _buildCover(ThemeData theme, CardPreview preview) {
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
            // The vertical frame adds its own overlay.
            if (!vertical) preview.overlay(radius: Style.mdRadius),
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
          Expanded(
            child: ContentTextBuilder(
              text: videoItem.title,
              builder: (context, shown, translated) {
                if (!translated && videoItem.titleList?.isNotEmpty == true) {
                  return Text.rich(
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
                  );
                }
                final style = TextStyle(
                  fontSize: theme.textTheme.bodyMedium!.fontSize,
                  height: 1.42,
                  letterSpacing: 0.3,
                );
                if (translated) {
                  return flutter.Text(
                    shown!,
                    textAlign: .start,
                    style: style,
                    maxLines: 2,
                    overflow: .ellipsis,
                  );
                }
                return Text(
                  videoItem.title,
                  textAlign: .start,
                  style: style,
                  maxLines: 2,
                  overflow: .ellipsis,
                );
              },
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

/// [preview]: cid and position of the card preview: the video page
/// continues from there.
Future<void> pushVideoH(
  HorizontalVideoModel videoItem, {
  PreviewProgress? preview,
}) async {
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

  int? cid = preview?.cid ?? videoItem.cid;
  Dimension? dimension = cid == videoItem.cid ? videoItem.dimension : null;
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
      progress: preview?.ms,
    );
  }
}
