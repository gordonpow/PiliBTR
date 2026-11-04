enum WebviewMenuItem {
  refresh('重新整理'),
  copy('複製連結'),
  openInBrowser('瀏覽器中開啟'),
  clearCache('清除快取'),
  resetCookie('重新設定Cookie'),
  goBack('返回'),
  ;

  final String title;
  const WebviewMenuItem(this.title);
}
