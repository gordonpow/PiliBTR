import 'package:PiliPlus/common/widgets/zh_material.dart' show Alignment;

enum UserInfoType {
  fan('粉絲', .centerLeft),
  follow('關注', .center),
  like('獲贊', .centerRight),
  ;

  final String title;
  final Alignment alignment;

  const UserInfoType(this.title, this.alignment);
}
