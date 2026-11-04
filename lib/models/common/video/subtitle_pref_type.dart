enum SubtitlePrefType {
  off('預設不顯示字幕'),
  on('優先選擇非自動生成(ai)字幕'),
  withoutAi('跳過自動生成(ai)字幕，選擇第一個可用字幕'),
  auto('靜音時等同第二項，非靜音時等同第三項'),
  ;

  final String desc;
  const SubtitlePrefType(this.desc);
}
