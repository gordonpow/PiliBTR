import 'package:PiliPlus/utils/storage_pref.dart';

enum MemberTabType {
  def('預設'),
  home('主頁'),
  dynamic('動態'),
  contribute('投稿'),
  favorite('收藏'),
  bangumi('番劇'),
  cheese('課堂'),
  shop('小店'),
  ;

  static bool showMemberShop = Pref.showMemberShop;

  static bool contains(String type) {
    if (type == shop.name && !showMemberShop) {
      return false;
    }
    for (final e in MemberTabType.values) {
      if (e.name == type) {
        return true;
      }
    }
    return false;
  }

  final String title;
  const MemberTabType(this.title);
}
