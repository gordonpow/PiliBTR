import 'package:PiliPlus/models/common/enum_with_label.dart';

enum SuperChatType implements EnumWithLabel {
  valid('有效時間內顯示'),
  persist('常駐顯示'),
  disable('不顯示'),
  ;

  @override
  final String label;
  const SuperChatType(this.label);
}
