import 'package:PiliPlus/models/common/enum_with_label.dart';

enum SkipType implements EnumWithLabel {
  alwaysSkip('總是跳過'),
  skipOnce('跳過一次'),
  skipManually('手動跳過'),
  showOnly('僅顯示'),
  disable('停用'),
  ;

  @override
  final String label;
  const SkipType(this.label);
}
