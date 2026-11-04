import 'package:PiliPlus/models/common/enum_with_label.dart';

enum UpPanelPosition implements EnumWithLabel {
  top('頂部'),
  leftFixed('左側常駐'),
  rightFixed('右側常駐'),
  leftDrawer('左側抽屜'),
  rightDrawer('右側抽屜'),
  ;

  @override
  final String label;
  const UpPanelPosition(this.label);
}
