import 'package:PiliPlus/models/common/enum_with_label.dart';

enum SuperResolutionType with EnumWithLabel {
  disable('停用'),
  efficiency('效率'),
  quality('畫質'),
  ;

  @override
  final String label;
  const SuperResolutionType(this.label);
}
