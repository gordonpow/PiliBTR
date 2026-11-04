import 'package:PiliPlus/models/common/enum_with_label.dart';

enum ReplySortType implements EnumWithLabel {
  time('最新評論', '最新', label: '按時間'),
  hot('最熱評論', '最熱', label: '按熱度'),
  select('精選評論', '精選'),
  ;

  @override
  final String label;
  final String desc;
  final String descShort;
  const ReplySortType(this.desc, this.descShort, {this.label = ''});
}
