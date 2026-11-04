enum RankType {
  all('全站', rid: 0),
  anime('番劇', seasonType: 1),
  guochuang('國創', seasonType: 4),
  douga('動畫', rid: 1005),
  music('音樂', rid: 1003),
  dance('舞蹈', rid: 1004),
  game('遊戲', rid: 1008),
  knowledge('知識', rid: 1010),
  tech('科技', rid: 1012),
  sports('運動', rid: 1018),
  car('汽車', rid: 1013),
  food('美食', rid: 1020),
  animal('動物', rid: 1024),
  kichiku('鬼畜', rid: 1007),
  fashion('時尚', rid: 1014),
  ent('娛樂', rid: 1002),
  cinephile('影視', rid: 1001),
  documentary('記錄', seasonType: 3),
  movie('電影', seasonType: 2),
  tv('劇集', seasonType: 5),
  variety('綜藝', seasonType: 7),
  ;

  final String label;
  final int? rid;
  final int? seasonType;
  const RankType(this.label, {this.rid, this.seasonType});
}
