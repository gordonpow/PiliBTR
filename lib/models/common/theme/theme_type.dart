import 'package:PiliPlus/models/common/enum_with_label.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart';

enum ThemeType implements EnumWithLabel {
  light('淺色'),
  dark('深色'),
  system('跟隨系統'),
  ;

  @override
  final String label;
  const ThemeType(this.label);

  ThemeMode get toThemeMode => switch (this) {
    ThemeType.light => ThemeMode.light,
    ThemeType.dark => ThemeMode.dark,
    ThemeType.system => ThemeMode.system,
  };

  Icon get icon => switch (this) {
    ThemeType.light => const Icon(MdiIcons.weatherSunny),
    ThemeType.dark => const Icon(MdiIcons.weatherNight),
    ThemeType.system => const Icon(MdiIcons.themeLightDark),
  };
}
