import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/content_text.dart';
import 'package:PiliPlus/common/widgets/image/image_save.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/models/search/result.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart';
import 'package:flutter/widgets.dart' as flutter show Text;

class SearchPgcItem extends StatelessWidget {
  const SearchPgcItem({
    super.key,
    required this.item,
  });

  final SearchPgcItemModel item;

  void onLongPress() => showPgcCover(
    title: item.title.map((item) => item.text).join(),
    cover: item.cover,
  );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    const TextStyle style = TextStyle(fontSize: 13);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => PageUtils.viewPgc(seasonId: item.seasonId),
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
              Stack(
                clipBehavior: Clip.none,
                children: [
                  NetworkImgLayer(
                    width: 111,
                    height: 148,
                    src: item.cover,
                  ),
                  PBadge(
                    text: item.seasonTypeName,
                    top: 6.0,
                    right: 6.0,
                    bottom: null,
                    left: null,
                  ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ContentTextBuilder(
                      text: item.title.map((e) => e.text).join(),
                      builder: (context, shown, translated) {
                        // The search highlight is dropped for a translation.
                        if (translated) return flutter.Text(shown!);
                        return Text.rich(
                          TextSpan(
                            children: item.title
                                .map(
                                  (e) => TextSpan(
                                    text: e.text,
                                    style: TextStyle(
                                      color: e.isEm
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurface,
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    Text('評分:${item.mediaScore?['score']}', style: style),
                    Text.rich(
                      style: style,
                      TextSpan(
                        children: [
                          if (item.areas?.isNotEmpty == true)
                            TextSpan(text: '${item.areas!}  ·  '),
                          TextSpan(
                            text: DateFormatUtils.dateFormat(item.pubtime),
                          ),
                        ],
                      ),
                    ),
                    Text.rich(
                      style: style,
                      TextSpan(
                        children: [
                          if (item.styles?.isNotEmpty == true)
                            TextSpan(text: '${item.styles!}  ·  '),
                          if (item.indexShow?.isNotEmpty == true)
                            TextSpan(text: item.indexShow!),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
