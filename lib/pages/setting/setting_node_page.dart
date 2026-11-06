import 'package:PiliPlus/common/widgets/flutter/list_tile.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart' hide ListTile;
import 'package:PiliPlus/pages/setting/models/setting_tree.dart';
import 'package:get/get.dart';

/// Page of a settings tree node: the sub nodes of a category, or the items
/// of a group.
class SettingNodePage extends StatelessWidget {
  const SettingNodePage({
    super.key,
    required this.node,
    this.showAppBar = true,
    this.onOpen,
  });

  final SettingNode node;
  final bool showAppBar;
  final ValueChanged<SettingNode>? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final padding = MediaQuery.viewPaddingOf(context);
    final Widget body;
    if (node.isGroup) {
      final items = node.items;
      body = ListView.builder(
        key: ValueKey(node.id),
        padding: EdgeInsets.only(
          left: showAppBar ? padding.left : 0,
          right: showAppBar ? padding.right : 0,
          bottom: padding.bottom + 100,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) => items[index].widget,
      );
    } else {
      final titleStyle = theme.textTheme.titleMedium!;
      final subTitleStyle = theme.textTheme.labelMedium!.copyWith(
        color: theme.colorScheme.outline,
      );
      body = ListView(
        key: ValueKey(node.id),
        padding: EdgeInsets.only(
          left: showAppBar ? padding.left : 0,
          right: showAppBar ? padding.right : 0,
          bottom: padding.bottom + 100,
        ),
        children: [
          for (final child in node.children)
            ListTile(
              onTap: () => onOpen != null
                  ? onOpen!(child)
                  // Same page type as this one: GetX would drop it as a
                  // duplicate route without preventDuplicates: false.
                  : Get.to(
                      () => SettingNodePage(node: child),
                      preventDuplicates: false,
                    ),
              leading: Icon(child.icon),
              title: Text(child.title, style: titleStyle),
              subtitle: child.subtitle == null
                  ? null
                  : Text(child.subtitle!, style: subTitleStyle),
            ),
        ],
      );
    }
    return SimpleScaffold(
      appBar: showAppBar ? AppBar(title: Text(node.title)) : null,
      body: body,
    );
  }
}
