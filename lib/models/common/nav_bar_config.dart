import 'package:PiliPlus/common/widgets/custom_icon.dart';
import 'package:PiliPlus/models/common/enum_with_label.dart';
import 'package:PiliPlus/pages/dynamics/view.dart';
import 'package:PiliPlus/pages/home/view.dart';
import 'package:PiliPlus/pages/mine/view.dart';
import 'package:PiliPlus/pages/whisper/view.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart';

// The index of each value is saved in the navBarSort and defaultHomePage
// settings: add new values at the end, and set the order in
// [defaultOrder].
enum NavigationBarType implements EnumWithLabel {
  home(
    '首頁',
    Icon(Icons.home_outlined),
    Icon(Icons.home_rounded),
    HomePage(),
  ),
  dynamics(
    '關注',
    Icon(CustomIcons.motion_photos_on_outlined),
    Icon(CustomIcons.motion_photos_on),
    DynamicsPage(),
  ),
  mine(
    '我的',
    Icon(Icons.tv_outlined),
    Icon(Icons.tv_rounded),
    MinePage(),
  ),
  message(
    '訊息',
    Icon(Icons.chat_bubble_outline_rounded),
    Icon(Icons.chat_bubble_rounded),
    _MessageNavPage(),
  ),
  ;

  @override
  final String label;
  final Icon icon;
  final Icon selectIcon;
  final Widget page;

  const NavigationBarType(this.label, this.icon, this.selectIcon, this.page);

  /// Order of the bottom bar when the user did not sort it.
  static const defaultOrder = [home, dynamics, message, mine];
}

/// The message page as a tab of the main page. The main page already
/// adds the status bar padding, so the app bar must not add it again.
class _MessageNavPage extends StatelessWidget {
  const _MessageNavPage();

  @override
  Widget build(BuildContext context) => MediaQuery.removePadding(
    context: context,
    removeTop: true,
    child: const WhisperPage(),
  );
}
