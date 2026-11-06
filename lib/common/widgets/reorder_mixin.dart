import 'package:PiliPlus/common/widgets/zh_material.dart';

mixin ReorderMixin<T extends StatefulWidget> on State<T> {
  late ColorScheme scheme;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    scheme = ColorScheme.of(context);
  }

  Widget proxyDecorator(Widget child, _, _) {
    return ColoredBox(
      color: scheme.onInverseSurface,
      child: child,
    );
  }
}
