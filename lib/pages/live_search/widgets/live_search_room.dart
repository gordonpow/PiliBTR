import 'package:PiliPlus/common/widgets/content_text.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/image/image_save.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/video_card/live_preview.dart';
import 'package:PiliPlus/models_new/live/live_search/room_item.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart';

// 视频卡片 - 垂直布局
class LiveCardVSearch extends StatelessWidget {
  final LiveSearchRoomItemModel item;

  const LiveCardVSearch({
    super.key,
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    void onLongPress() => imageSaveDialog(
      title: item.title,
      cover: item.cover,
    );
    final preview = LiveCardPreview(item: item, roomId: item.roomid);
    return preview.wrapTarget(Card(
      child: InkWell(
        onTap: () {
          preview.stop();
          PageUtils.toLiveRoom(item.roomid);
        },
        onLongPress: () => preview.longPress(onLongPress),
        onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
        borderRadius: const .all(.circular(12)),
        child: Column(
          crossAxisAlignment: .start,
          children: [
            AspectRatio(
              aspectRatio: Style.aspectRatio,
              child: LayoutBuilder(
                builder: (context, boxConstraints) {
                  double maxWidth = boxConstraints.maxWidth;
                  double maxHeight = boxConstraints.maxHeight;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      NetworkImgLayer(
                        src: item.cover!,
                        width: maxWidth,
                        height: maxHeight,
                        borderRadius: const .vertical(top: .circular(12)),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: videoStat(),
                      ),
                      preview.overlay(
                        radius: const .vertical(top: .circular(12)),
                      ),
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(5, 8, 5, 4),
              child: ContentText(
                item.title.toString(),
                textAlign: TextAlign.start,
                style: const TextStyle(
                  letterSpacing: 0.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    ));
  }

  Widget videoStat() {
    return Container(
      height: 50,
      padding: const EdgeInsets.only(top: 26, left: 10, right: 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.transparent,
            Colors.black54,
          ],
          tileMode: TileMode.mirror,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            item.name.toString(),
            style: const TextStyle(fontSize: 11, color: Colors.white),
          ),
          if (item.watchedShow?.textLarge case final textLarge?)
            Text(
              textLarge,
              style: const TextStyle(fontSize: 11, color: Colors.white),
            ),
        ],
      ),
    );
  }
}
