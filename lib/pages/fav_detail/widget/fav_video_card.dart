import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/button/icon_button.dart';
import 'package:PiliPlus/common/widgets/image/image_save.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/select_mask.dart';
import 'package:PiliPlus/common/widgets/stat/stat.dart';
import 'package:PiliPlus/common/widgets/video_card/vertical_video_card_frame.dart';
import 'package:PiliPlus/grpc/bilibili/app/listener/v1.pbenum.dart'
    show PlaylistSource;
import 'package:PiliPlus/models/common/badge_type.dart';
import 'package:PiliPlus/models/common/stat_type.dart';
import 'package:PiliPlus/models_new/fav/fav_detail/media.dart';
import 'package:PiliPlus/pages/audio/view.dart';
import 'package:PiliPlus/pages/fav_detail/controller.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:get/get.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart';

// 收藏视频卡片 - 水平布局
class FavVideoCardH extends StatelessWidget {
  final FavDetailItemModel item;
  final int? index;
  final BaseFavController? ctr;

  /// Use the vertical layout (the same as the home card).
  final bool vertical;

  const FavVideoCardH({
    super.key,
    required this.item,
    this.index,
    this.ctr,
    this.vertical = false,
  }) : assert(ctr == null || index != null);

  bool get isSort => ctr == null;

  void _onTap() {
    // 0/4/16/...: 正常；9: up自己删除；1: 其他原因删除
    if (const [1, 9].contains(item.attr)) {
      Get.toNamed('/member?mid=${item.upper?.mid}');
      return;
    }

    switch (item.type) {
      case 12:
        AudioPage.toAudioPage(
          oid: item.id!,
          itemType: 3,
          from: PlaylistSource.AUDIO_CARD,
        );
        break;
      case 24:
        PageUtils.viewPgc(
          seasonId: item.ogv!.seasonId,
          epId: item.id,
        );
        break;
      default:
        ctr!.onViewFav(item, index);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = !isSort && ctr!.isOwner;
    late final enableMultiSelect = ctr?.enableMultiSelect.value ?? false;
    final colorScheme = ColorScheme.of(context);

    final onLongPress = isSort || enableMultiSelect
        ? null
        : isOwner && !enableMultiSelect
        ? () {
            ctr!
              ..enableMultiSelect.value = true
              ..onSelect(item);
          }
        : () => imageSaveDialog(
            title: item.title,
            cover: item.cover,
            bvid: item.bvid,
          );
    final onTap = isSort
        ? null
        : enableMultiSelect
        ? () => ctr!.onSelect(item)
        : _onTap;

    if (vertical) {
      final textTheme = TextTheme.of(context);
      return VerticalVideoCardFrame(
        cover: _cover(colorScheme),
        title: Text(
          item.title!,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: VerticalVideoCardFrame.titleStyle.copyWith(
            fontSize: textTheme.bodyMedium!.fontSize,
          ),
        ),
        stats: _verticalStats(textTheme, colorScheme),
        footer: Text(
          item.upper?.name ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: textTheme.labelMedium!.fontSize,
            color: colorScheme.outline,
          ),
        ),
        action: isOwner ? _cancelFavButton(context, colorScheme, 29, 17) : null,
        onTap: onTap,
        onLongPress: onLongPress,
        onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
      );
    }

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
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
                child: _cover(colorScheme),
              ),
              const SizedBox(width: 10),
              content(context, colorScheme, isOwner),
            ],
          ),
        ),
      ),
    );
  }

  // Cover with badges and the multi-select mask, shared by both layouts.
  Widget _cover(ColorScheme colorScheme) {
    return LayoutBuilder(
      builder: (context, boxConstraints) {
        double maxWidth = boxConstraints.maxWidth;
        double maxHeight = boxConstraints.maxHeight;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            NetworkImgLayer(
              src: item.cover,
              width: maxWidth,
              height: maxHeight,
            ),
            PBadge(
              text: DurationUtils.formatDuration(item.duration),
              right: 6.0,
              bottom: 6.0,
              type: PBadgeType.gray,
            ),
            if (item.type == 12)
              const PBadge(
                text: '音訊',
                top: 6.0,
                right: 6.0,
                type: PBadgeType.gray,
              )
            else
              PBadge(
                text: item.ogv?.typeName,
                top: 6.0,
                right: 6.0,
                bottom: null,
                left: null,
              ),
            if (!isSort)
              Positioned.fill(
                child: selectMask(
                  colorScheme,
                  item.checked,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _verticalStats(TextTheme textTheme, ColorScheme colorScheme) {
    return Row(
      children: [
        // In a narrow card the counts shrink instead of running into the
        // date.
        Expanded(
          child: FittedBox(
            fit: .scaleDown,
            alignment: .centerLeft,
            child: Row(
              children: [
                StatWidget(
                  type: StatType.play,
                  value: item.cntInfo?.play,
                ),
                if (item.type != 24) ...[
                  const SizedBox(width: 4),
                  StatWidget(
                    type: StatType.danmaku,
                    value: item.cntInfo?.danmaku,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          DateFormatUtils.dateFormat(item.favTime),
          maxLines: 1,
          style: TextStyle(
            fontSize: textTheme.labelSmall!.fontSize,
            color: colorScheme.outline.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(width: 2),
      ],
    );
  }

  Widget _cancelFavButton(
    BuildContext context,
    ColorScheme colorScheme,
    double size,
    double iconSize,
  ) {
    return iconButton(
      size: size,
      iconSize: iconSize,
      icon: const Icon(Icons.clear),
      tooltip: '取消收藏',
      iconColor: colorScheme.outline,
      onPressed: () => showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('提示'),
          content: const Text('要取消收藏嗎?'),
          actions: [
            TextButton(
              onPressed: Get.back,
              child: Text(
                '取消',
                style: TextStyle(color: colorScheme.outline),
              ),
            ),
            TextButton(
              onPressed: () {
                Get.back();
                ctr!.onCancelFav(index!, item.id!, item.type!);
              },
              child: const Text('確定取消'),
            ),
          ],
        ),
      ),
    );
  }

  Widget content(BuildContext context, ColorScheme colorScheme, bool isOwner) {
    return Expanded(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            spacing: 3,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title!,
                textAlign: TextAlign.start,
                style: const TextStyle(
                  letterSpacing: 0.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (item.type == 24 && item.intro?.isNotEmpty == true)
                Text(
                  item.intro!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.outline,
                  ),
                ),
              const Spacer(),
              Text(
                '${DateFormatUtils.dateFormat(item.favTime)} ${item.upper?.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  height: 1,
                  fontSize: 12,
                  color: colorScheme.outline,
                ),
              ),
              if (item.type != 24)
                Row(
                  spacing: 8,
                  children: [
                    StatWidget(
                      type: StatType.play,
                      value: item.cntInfo?.play,
                    ),
                    StatWidget(
                      type: StatType.danmaku,
                      value: item.cntInfo?.danmaku,
                    ),
                  ],
                ),
            ],
          ),
          if (isOwner)
            Positioned(
              right: 0,
              bottom: -8,
              child: _cancelFavButton(context, colorScheme, 36, 18),
            ),
        ],
      ),
    );
  }
}
