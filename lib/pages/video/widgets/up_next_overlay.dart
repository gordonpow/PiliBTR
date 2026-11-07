import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:get/get.dart';

/// 播放完畢後顯示在播放器右下角的「接下來播放」倒數卡片。
class UpNextOverlay extends StatelessWidget {
  const UpNextOverlay({super.key, required this.controller});

  final VideoDetailController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final seconds = controller.upNextSeconds.value;
      final info = controller.upNextInfo;
      if (seconds == null || info == null) return const SizedBox.shrink();
      return Positioned(
        right: 16,
        bottom: 56,
        child: _Card(
          seconds: seconds,
          title: info.title,
          cover: info.cover,
          onCancel: controller.dismissUpNext,
          onPlay: controller.playUpNextNow,
        ),
      );
    });
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.seconds,
    required this.title,
    required this.cover,
    required this.onCancel,
    required this.onPlay,
  });

  final int seconds;
  final String title;
  final String? cover;
  final VoidCallback onCancel;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    const white = TextStyle(color: Colors.white, fontSize: 13);
    return Container(
      width: 280,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: const BorderRadius.all(Radius.circular(10)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '接下來播放',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SizedBox(
                width: 28,
                height: 28,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: seconds / 5,
                      strokeWidth: 2.5,
                      color: Colors.white,
                      backgroundColor: Colors.white24,
                    ),
                    Text('$seconds', style: white),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NetworkImgLayer(
                src: cover,
                width: 96,
                height: 54,
                borderRadius: const BorderRadius.all(Radius.circular(6)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onCancel,
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
                child: const Text('取消'),
              ),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: onPlay,
                child: const Text('立即播放'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
