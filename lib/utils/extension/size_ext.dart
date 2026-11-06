import 'dart:ui' show Size;

import 'package:PiliPlus/common/widgets/zh_widgets.dart' show Orientation;

extension SizeExt on Size {
  bool get isPortrait => width < 600 || height >= width;

  Orientation get orientation => height > width ? .portrait : .landscape;
}
