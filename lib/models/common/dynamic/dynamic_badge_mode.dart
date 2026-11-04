import 'package:PiliPlus/models/common/enum_with_label.dart';

enum DynamicBadgeMode implements EnumWithLabel {
  hidden('隱藏'),
  point('紅點'),
  number('數字'),
  ;

  @override
  final String label;
  const DynamicBadgeMode(this.label);
}
