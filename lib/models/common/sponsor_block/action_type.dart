enum ActionType {
  skip('跳過'),
  mute('靜音'),
  full('整個影片'),
  poi('精彩時刻'),
  ;

  final String title;
  const ActionType(this.title);
}
