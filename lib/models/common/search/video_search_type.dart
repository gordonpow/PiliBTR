enum VideoPubTimeType {
  all('不限'),
  day('最近一天'),
  week('最近一週'),
  halfYear('最近半年'),
  ;

  final String label;
  const VideoPubTimeType(this.label);
}

enum VideoDurationType {
  all('全部時長'),
  tenMins('0-10分鐘'),
  halfHour('10-30分鐘'),
  hour('30-60分鐘'),
  hourPlus('60分鐘+'),
  ;

  final String label;
  const VideoDurationType(this.label);
}

enum VideoZoneType {
  all('全部'),
  douga('動畫', tids: 1),
  anime('番劇', tids: 13),
  guochuang('國創', tids: 167),
  music('音樂', tids: 3),
  dance('舞蹈', tids: 129),
  game('遊戲', tids: 4),
  knowledge('知識', tids: 36),
  tech('科技', tids: 188),
  sports('運動', tids: 234),
  car('汽車', tids: 223),
  life('生活', tids: 160),
  food('美食', tids: 221),
  animal('動物', tids: 217),
  kichiku('鬼畜', tids: 119),
  fashion('時尚', tids: 115),
  info('資訊', tids: 202),
  ent('娛樂', tids: 5),
  cinephile('影視', tids: 181),
  documentary('記錄', tids: 177),
  movie('電影', tids: 23),
  tv('電視', tids: 11),
  ;

  final String label;
  final int? tids;
  const VideoZoneType(this.label, {this.tids});
}

// 搜索类型为视频、专栏及相簿时
enum ArchiveFilterType {
  totalrank('預設排序'),
  click('播放多'),
  pubdate('新發布'),
  dm('彈幕多'),
  stow('收藏多'),
  scores('評論多'),
  ;

  // 专栏
  // attention('最多喜欢'),

  final String desc;
  const ArchiveFilterType(this.desc);
}
