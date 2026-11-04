import 'package:PiliPlus/models/common/enum_with_label.dart';

enum ArchiveSortTypeApp with EnumWithLabel {
  desc('預設'),
  asc('倒序'),
  ;

  @override
  final String label;
  const ArchiveSortTypeApp(this.label);
}
