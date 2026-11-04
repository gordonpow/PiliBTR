const double kScreenRatio = 1.2;

// 全屏模式
enum FullScreenMode {
  // 根据内容自适应
  auto('按影片方向（預設）'),
  // 不改变当前方向
  none('不改變當前方向'),
  // 始终竖屏
  vertical('強制豎屏'),
  // 始终横屏
  horizontal('強制橫屏'),
  // 屏幕长宽比 < kScreenRatio 或为竖屏视频时竖屏，否则横屏
  ratio('螢幕長寬比<$kScreenRatio或為豎屏影片時豎屏，否則橫屏'),
  // 强制重力转屏（仅安卓）
  gravity('忽略系統方向鎖定，強制按重力轉屏（僅安卓）'),
  ;

  final String desc;
  const FullScreenMode(this.desc);
}
