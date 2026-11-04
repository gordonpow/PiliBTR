enum FollowOrderType {
  def('', '最近關注'),
  attention('attention', '最常訪問'),
  ;

  final String type;
  final String title;

  const FollowOrderType(this.type, this.title);
}
