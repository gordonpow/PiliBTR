import 'package:PiliPlus/models/dynamics/result.dart' show ModuleBlocked;
import 'package:PiliPlus/pages/article/widgets/opus_content.dart'
    show moduleBlockedItem;
import 'package:PiliPlus/common/widgets/zh_material.dart';

Widget blockedItem(
  BuildContext context, {
  required ThemeData theme,
  required ModuleBlocked blocked,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 1),
    child: moduleBlockedItem(context, theme.colorScheme, blocked),
  );
}
