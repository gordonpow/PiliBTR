import 'package:PiliPlus/utils/bili_colors.dart';
import 'package:material_ui/material_ui.dart';

enum BadgeType {
  none(),
  vip('大會員'),
  person('認證個人', BiliColors.yellow),
  institution('認證機構', Colors.lightBlueAccent),
  ;

  final String? desc;
  final Color? color;
  const BadgeType([this.desc, this.color]);
}
