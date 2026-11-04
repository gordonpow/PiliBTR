import 'package:PiliPlus/models/common/enum_with_label.dart';

enum BtmProgressBehavior implements EnumWithLabel {
  alwaysShow('始終展示'),
  alwaysHide('始終隱藏'),
  onlyShowFullScreen('僅全屏時展示'),
  onlyHideFullScreen('僅全屏時隱藏'),
  ;

  @override
  final String label;
  const BtmProgressBehavior(this.label);
}
