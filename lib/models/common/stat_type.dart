import 'package:material_ui/material_ui.dart' show IconData, Icons;

enum StatType {
  view(Icons.remove_red_eye_outlined, '觀看'),
  danmaku(Icons.subtitles_outlined, '彈幕'),
  like(Icons.thumb_up_outlined, '點贊'),
  reply(Icons.comment_outlined, '評論'),
  follow(Icons.favorite_border, '關注'),
  play(Icons.play_circle_outlined, '播放'),
  listen(Icons.headset_outlined, '播放'),
  ;

  final IconData iconData;
  final String label;
  const StatType(this.iconData, this.label);
}
