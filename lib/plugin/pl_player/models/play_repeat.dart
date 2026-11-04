import 'package:PiliPlus/models/common/enum_with_label.dart';

enum PlayRepeat implements EnumWithLabel {
  pause('播完暫停'),
  listOrder('順序播放'),
  singleCycle('單個迴圈'),
  listCycle('列表迴圈'),
  autoPlayRelated('自動連播'),
  ;

  @override
  final String label;
  const PlayRepeat(this.label);
}
