import 'package:PiliPlus/common/widgets/zh_material.dart';
import 'package:PiliPlus/pages/common/publish/publish_route.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/pages/video/related/view.dart';
import 'package:get/get.dart';

/// Shows the related videos of the video page [heroTag] in a panel that
/// slides up from the bottom of the fullscreen player (swipe up on the
/// center zone). The video keeps playing above it. Swipe the panel down,
/// or tap the video above it, to close it.
///
/// A tapped video closes the panel and opens a new video page above. The
/// player is shared, so the new page is in fullscreen too.
Future<void>? showFullscreenRecommendPanel(
  BuildContext context, {
  required String heroTag,
}) {
  final navigator = Get.key.currentState;
  if (navigator == null || !context.mounted) return null;
  _videoCtr(heroTag)?.cancelUpNext();
  // The video page route: the panel route is popped when the panel closes,
  // and the main player resumes only while the video page is current.
  final pageRoute = Get.routing.route;
  return navigator.push(
    PublishRoute(
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) =>
          _RecommendPanel(heroTag: heroTag, pageRoute: pageRoute),
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          SlideTransition(
            position: animation.drive(
              Tween<Offset>(
                begin: const Offset(0.0, 1.0),
                end: Offset.zero,
              ).chain(CurveTween(curve: Curves.easeOutCubic)),
            ),
            child: child,
          ),
      settings: RouteSettings(arguments: Get.arguments),
    ),
  );
}

VideoDetailController? _videoCtr(String heroTag) =>
    Get.isRegistered<VideoDetailController>(tag: heroTag)
    ? Get.find<VideoDetailController>(tag: heroTag)
    : null;

class _RecommendPanel extends StatelessWidget {
  const _RecommendPanel({required this.heroTag, this.pageRoute});

  final String heroTag;
  final Route<dynamic>? pageRoute;

  /// Height of the panel as a part of the screen height.
  static const double _heightFactor = 0.6;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.bottomCenter,
      child: FractionallySizedBox(
        heightFactor: _heightFactor,
        widthFactor: 1,
        child: GestureDetector(
          // Swipe down on the handle area closes the panel.
          onVerticalDragEnd: (details) {
            if ((details.primaryVelocity ?? 0) > 200) {
              Navigator.of(context).pop();
            }
          },
          child: Material(
            color: theme.colorScheme.surface.withValues(alpha: 0.97),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(16),
            ),
            clipBehavior: Clip.antiAlias,
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.outline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        Text('相關推薦', style: theme.textTheme.titleMedium),
                        const Spacer(),
                        IconButton(
                          tooltip: '關閉',
                          icon: const Icon(Icons.keyboard_arrow_down),
                          onPressed: Navigator.of(context).pop,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification is ScrollUpdateNotification &&
                            notification.dragDetails != null) {
                          _videoCtr(heroTag)?.cancelUpNext();
                        }
                        return false;
                      },
                      child: CustomScrollView(
                        slivers: [
                          RelatedVideoPanel(
                            heroTag: heroTag,
                            resumeRoute: pageRoute,
                            // Close the panel first: the new page opens in
                            // fullscreen and the panel must not stay on the
                            // old page.
                            beforeOpen: Navigator.of(context).pop,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
