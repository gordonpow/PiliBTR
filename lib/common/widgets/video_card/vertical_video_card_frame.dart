import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart';

/// The layout of a vertical video card, the same as the home page card
/// ([VideoCardV]): a 16:10 cover with rounded top corners, then the title
/// (two lines), a stats row and a footer row. An optional action (for
/// example the "⋮" menu) sits at the bottom right corner.
///
/// Use it inside a grid from [VideoCardStyle.gridDelegate], which gives
/// every card the same width and height.
class VerticalVideoCardFrame extends StatelessWidget {
  const VerticalVideoCardFrame({
    super.key,
    required this.cover,
    required this.title,
    this.stats,
    this.footer,
    this.action,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
  });

  /// Fills the 16:10 cover area. It gets tight constraints; use a
  /// [LayoutBuilder] for the size.
  final Widget cover;

  /// Usually a [Text] with `maxLines: 2` and [titleStyle].
  final Widget title;

  /// Row under the title (play count, danmaku count, date).
  final Widget? stats;

  /// Last row (UP name, badges). Space is kept on the right for [action].
  final Widget? footer;

  /// A 29 x 29 widget at the bottom right corner, like the "⋮" menu of
  /// the home card.
  final Widget? action;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;

  static const TextStyle titleStyle = TextStyle(height: 1.38);

  static const BorderRadius _radius = BorderRadius.all(Radius.circular(12));

  @override
  Widget build(BuildContext context) {
    final card = Card(
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        onSecondaryTap: onSecondaryTap,
        borderRadius: _radius,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: Style.aspectRatio,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: cover,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: title),
                    ?stats,
                    if (footer case final footer?)
                      Padding(
                        padding: EdgeInsets.only(
                          right: action == null ? 0 : 10,
                        ),
                        child: footer,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (action == null) return card;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: card),
        Positioned(
          right: -5,
          bottom: -2,
          width: 29,
          height: 29,
          child: action!,
        ),
      ],
    );
  }
}
