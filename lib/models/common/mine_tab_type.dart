import 'package:PiliPlus/models/common/enum_with_label.dart';

enum MineTabType implements EnumWithLabel {
  favorite('我的收藏'),
  history('觀看記錄'),
  later('稍後再看'),
  sub('我的訂閱');

  static const Set<MineTabType> kDefault = {.favorite};

  @override
  final String label;

  const MineTabType(this.label);
}
