enum ArticleOrderType {
  totalrank('綜合排序'),
  pubdate('最新發布'),
  click('最多點選'),
  attention('最多喜歡'),
  scores('最多評論'),
  ;

  String get order => name;
  final String label;
  const ArticleOrderType(this.label);
}

enum ArticleZoneType {
  all('全部分區', 0),
  douga('動畫', 2),
  game('遊戲', 1),
  cinephile('影視', 28),
  life('生活', 3),
  interest('興趣', 29),
  novel('輕小說', 16),
  tech('科技', 17),
  note('筆記', 41),
  ;

  final String label;
  final int categoryId;
  const ArticleZoneType(this.label, this.categoryId);
}
