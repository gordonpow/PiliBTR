enum AccountType {
  main('主賬號'),
  heartbeat('記錄觀看'),
  recommend('推薦'),
  video('影片取流'),
  ;

  final String title;
  const AccountType(this.title);
}
