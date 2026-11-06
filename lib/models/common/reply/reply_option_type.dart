import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart';

enum ReplyOptionType {
  allow('允許評論'),
  close('關閉評論'),
  choose('精選評論'),
  ;

  final String title;
  const ReplyOptionType(this.title);

  IconData get iconData => switch (this) {
    ReplyOptionType.allow => MdiIcons.commentTextOutline,
    ReplyOptionType.close => MdiIcons.commentOffOutline,
    ReplyOptionType.choose => MdiIcons.commentProcessingOutline,
  };
}
