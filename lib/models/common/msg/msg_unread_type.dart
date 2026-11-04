enum MsgUnReadType {
  pm('私信'),
  reply('回覆我的'),
  at('@我'),
  like('收到的贊'),
  sysMsg('系統通知'),
  ;

  final String title;
  const MsgUnReadType(this.title);
}
