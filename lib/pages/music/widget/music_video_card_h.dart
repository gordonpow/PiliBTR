import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/image/image_save.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/marquee.dart';
import 'package:PiliPlus/common/widgets/stat/stat.dart';
import 'package:PiliPlus/common/widgets/video_card/vertical_video_card_frame.dart';
import 'package:PiliPlus/http/search.dart';
import 'package:PiliPlus/models/common/badge_type.dart';
import 'package:PiliPlus/models/common/stat_type.dart';
import 'package:PiliPlus/models_new/music/bgm_recommend_list.dart';
import 'package:PiliPlus/models_new/video/video_detail/dimension.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart';

class MusicVideoCardH extends StatelessWidget {
  final BgmRecommend videoItem;

  /// Vertical layout (cover above the title), the same as the home card.
  final bool vertical;

  const MusicVideoCardH({
    super.key,
    required this.videoItem,
    this.vertical = false,
  });

  @override
  Widget build(BuildContext context) {
    void onLongPress() => imageSaveDialog(
      title: videoItem.title,
      cover: videoItem.cover,
      bvid: videoItem.bvid,
    );
    if (vertical) {
      final theme = Theme.of(context);
      final textTheme = theme.textTheme;
      return VerticalVideoCardFrame(
        cover: _cover(),
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
              value: videoItem.play,
            ),
            StatWidget(
              type: StatType.danmaku,
              value: videoItem.danmu,
            ),
          ],
        ),
        footer: Text(
          videoItem.upNickName!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        onTap: _onTap,
        onLongPress: onLongPress,
        onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
      );
    }
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: _onTap,
        onLongPress: onLongPress,
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
                child: _cover(),
              ),
              const SizedBox(width: 10),
              content(context),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onTap() async {
    int? cid = videoItem.cid;
    Dimension? dimension;
    if (cid == null) {
      if (await SearchHttp.ab2cWithDimension(bvid: videoItem.bvid)
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

  Widget _cover() {
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
          Row(
            spacing: 8,
            children: [
              StatWidget(
                type: StatType.play,
                value: videoItem.play,
              ),
              StatWidget(
                type: StatType.danmaku,
                value: videoItem.danmu,
              ),
            ],
          ),
          const SizedBox(height: 3),
          NormalMarquee(
            velocity: 25,
            spacing: 30,
            child: Row(
              spacing: 8,
              children: [
                if (videoItem.labelList case final labelList?)
                  for (final label in labelList)
                    PBadge(
                      text: label.name,
                      isStack: false,
                      size: PBadgeSize.small,
                      type: PBadgeType.secondary,
                    ),
                Text(
                  videoItem.upNickName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
