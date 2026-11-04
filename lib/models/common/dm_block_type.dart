enum DmBlockType {
  keyword('關鍵詞'),
  regex('正則'),
  uid('使用者'),
  ;

  final String label;
  const DmBlockType(this.label);
}
