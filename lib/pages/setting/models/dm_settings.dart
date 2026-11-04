import 'dart:math' show max;

import 'package:PiliPlus/common/widgets/custom_icon.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:PiliPlus/utils/filtering_text.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart' hide RefreshIndicator;

List<SettingsModel> get dmSettings => [
  const SwitchModel(
    title: '彈幕開關',
    subtitle: '是否展示彈幕',
    leading: Icon(CustomIcons.dm_settings),
    setKey: SettingBoxKey.enableShowDanmaku,
    defaultVal: true,
  ),
  if (PlatformUtils.isMobile)
    const SwitchModel(
      title: '啟用點選彈幕',
      subtitle: '點選彈幕懸停，支援點贊、複製、舉報操作',
      leading: Icon(Icons.touch_app_outlined),
      setKey: SettingBoxKey.enableTapDm,
      defaultVal: true,
    ),
  NormalModel(
    title: '彈幕行高',
    subtitle: '預設1.6',
    leading: const Icon(CustomIcons.dm_settings),
    getTrailing: (theme) => Text(
      Pref.danmakuLineHeight.toString(),
      style: theme.textTheme.titleSmall,
    ),
    onTap: _showDmHeightDialog,
  ),
  const SwitchModel(
    title: '顯示會員彩色彈幕',
    leading: Icon(MdiIcons.gradientHorizontal),
    setKey: SettingBoxKey.showVipDanmaku,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '合併彈幕',
    subtitle: '合併一段時間內獲取到的相同彈幕',
    leading: Icon(Icons.merge),
    setKey: SettingBoxKey.mergeDanmaku,
    defaultVal: false,
  ),
];

void _showDmHeightDialog(BuildContext context, VoidCallback setState) {
  String danmakuLineHeight = Pref.danmakuLineHeight.toString();
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('彈幕行高'),
      content: TextFormField(
        autofocus: true,
        initialValue: danmakuLineHeight,
        keyboardType: const .numberWithOptions(decimal: true),
        onChanged: (value) => danmakuLineHeight = value,
        inputFormatters: FilteringText.decimal,
      ),
      actions: [
        TextButton(
          onPressed: Get.back,
          child: Text(
            '取消',
            style: TextStyle(color: ColorScheme.of(context).outline),
          ),
        ),
        TextButton(
          onPressed: () async {
            try {
              final val = max(
                1.0,
                double.parse(danmakuLineHeight).toPrecision(1),
              );
              Get.back();
              await GStorage.setting.put(SettingBoxKey.danmakuLineHeight, val);
              setState();
            } catch (e) {
              SmartDialog.showToast(e.toString());
            }
          },
          child: const Text('確定'),
        ),
      ],
    ),
  );
}
