enum UserOrderType {
  def('預設排序', 0, ''),
  fansDesc('粉絲數由高到低', 0, 'fans'),
  fansAsc('粉絲數由低到高', 1, 'fans'),
  levelDesc('Lv等級由高到低', 0, 'level'),
  levelAsc('Lv等級由低到高', 1, 'level'),
  ;

  final String label;
  final int orderSort;
  final String order;
  const UserOrderType(this.label, this.orderSort, this.order);
}

enum UserType {
  all('全部使用者'),
  up('UP主'),
  common('普通使用者'),
  verified('認證使用者'),
  ;

  final String label;
  const UserType(this.label);
}
