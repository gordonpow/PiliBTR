import 'dart:io';
import 'dart:math' as math;

import 'package:PiliPlus/common/widgets/color_palette.dart';
import 'package:PiliPlus/common/widgets/custom_toast.dart';
import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/common/widgets/emote_tooltip.dart'
    show enableEmoteTooltip;
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/pendant_avatar.dart';
import 'package:PiliPlus/common/widgets/scale_app.dart';
import 'package:PiliPlus/common/widgets/scroll_physics.dart'
    show kSpringDescription;
import 'package:PiliPlus/common/widgets/stateful_builder.dart';
import 'package:PiliPlus/models/common/bar_hide_type.dart';
import 'package:PiliPlus/models/common/dynamic/dynamic_badge_mode.dart';
import 'package:PiliPlus/models/common/dynamic/up_panel_position.dart';
import 'package:PiliPlus/models/common/home_tab_type.dart';
import 'package:PiliPlus/models/common/member/tab_type.dart';
import 'package:PiliPlus/models/common/mine_tab_type.dart';
import 'package:PiliPlus/models/common/msg/msg_unread_type.dart';
import 'package:PiliPlus/models/common/nav_bar_config.dart';
import 'package:PiliPlus/models/common/theme/theme_color_type.dart';
import 'package:PiliPlus/models/common/theme/theme_type.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/pages/mine/controller.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/pages/setting/slide_color_picker.dart';
import 'package:PiliPlus/pages/setting/widgets/dual_slider_dialog.dart';
import 'package:PiliPlus/pages/setting/widgets/multi_select_dialog.dart';
import 'package:PiliPlus/pages/setting/widgets/ordered_multi_select_dialog.dart';
import 'package:PiliPlus/pages/setting/widgets/select_dialog.dart';
import 'package:PiliPlus/pages/setting/widgets/slider_dialog.dart';
import 'package:PiliPlus/plugin/pl_player/utils/fullscreen.dart';
import 'package:PiliPlus/utils/extension/file_ext.dart';
import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:PiliPlus/utils/extension/theme_ext.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/theme_utils.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart' hide StatefulBuilder;
import 'package:path/path.dart' as path;

List<SettingsModel> get styleSettings => [
  if (PlatformUtils.isDesktop) ...[
    const SwitchModel(
      title: '顯示視窗標題欄',
      leading: Icon(Icons.window),
      setKey: SettingBoxKey.showWindowTitleBar,
      defaultVal: true,
      needReboot: true,
    ),
    const SwitchModel(
      title: '顯示托盤圖示',
      leading: Icon(Icons.donut_large_rounded),
      setKey: SettingBoxKey.showTrayIcon,
      defaultVal: true,
      needReboot: true,
    ),
  ],
  if (Platform.isLinux) _useSSDModel(),
  SwitchModel(
    title: '橫屏適配',
    subtitle: '啟用橫屏佈局與邏輯，平板、摺疊屏等可開啟；建議全屏方向設為【不改變當前方向】',
    leading: const Icon(Icons.phonelink_outlined),
    setKey: SettingBoxKey.horizontalScreen,
    defaultVal: Pref.horizontalScreen,
    onChanged: _onHorizontalScreenChanged,
  ),
  const SwitchModel(
    title: '改用側邊欄',
    subtitle: '開啟後底欄與頂欄被替換，且相關設定失效',
    leading: Icon(Icons.chrome_reader_mode_outlined),
    setKey: SettingBoxKey.useSideBar,
    defaultVal: false,
    needReboot: true,
  ),
  const SwitchModel(
    title: '隱藏側邊欄文字',
    subtitle: '僅顯示圖示，減少側邊欄佔用寬度',
    leading: Icon(Icons.label_off_outlined),
    setKey: SettingBoxKey.hideSideBarLabel,
    defaultVal: false,
    needReboot: true,
  ),
  NormalModel(
    title: 'App字型設定',
    subtitle: '點選設定',
    leading: const Icon(Icons.text_fields),
    onTap: (context, setState) => Get.toNamed('/fontSetting'),
  ),
  NormalModel(
    title: '介面縮放',
    getSubtitle: () => '當前縮放比例：${Pref.uiScale.toStringAsFixed(2)}',
    leading: const Icon(Icons.zoom_in_outlined),
    onTap: _showUiScaleDialog,
  ),
  const SwitchModel(
    title: '首頁切換頁面動畫',
    leading: Icon(Icons.home_outlined),
    setKey: SettingBoxKey.mainTabBarView,
    defaultVal: false,
    needReboot: true,
  ),
  NormalModel(
    title: '頁面過渡動畫',
    leading: const Icon(Icons.animation),
    getSubtitle: () => '當前：${Pref.pageTransition.name}',
    onTap: _showTransitionDialog,
  ),
  const SwitchModel(
    title: '最佳化平板導航欄',
    leading: Icon(Icons.auto_fix_high),
    setKey: SettingBoxKey.optTabletNav,
    defaultVal: true,
    needReboot: true,
  ),
  const SwitchModel(
    title: '懸浮底欄',
    leading: Icon(MdiIcons.soundbar),
    setKey: SettingBoxKey.floatingNavBar,
    defaultVal: false,
    needReboot: true,
  ),
  SwitchModel(
    title: '顯示粉絲勳章',
    leading: const Icon(MdiIcons.medalOutline),
    setKey: SettingBoxKey.showMedal,
    defaultVal: true,
    onChanged: (value) => GlobalData().showMedal = value,
  ),
  SwitchModel(
    title: '展示頭像/評論/動態裝飾',
    leading: const Icon(MdiIcons.stickerCircleOutline),
    setKey: SettingBoxKey.showDecorate,
    defaultVal: true,
    onChanged: (value) => PendantAvatar.showDecorate = value,
  ),
  SwitchModel(
    title: '點選表情顯示 Tooltip',
    leading: const Icon(Icons.emoji_emotions_outlined),
    setKey: SettingBoxKey.enableEmoteTooltip,
    defaultVal: false,
    onChanged: (value) => enableEmoteTooltip = value,
  ),
  NormalModel(
    leading: const Icon(Icons.calendar_view_week_outlined),
    title: '列表寬度（dp）限制',
    getSubtitle: () =>
        '當前: 影片卡片${Pref.recommendCardWidth.toInt()}dp 其他列表${Pref.smallCardWidth.toInt()}dp，螢幕寬度:${MediaQuery.widthOf(Get.context!).toPrecision(2)}dp。寬度越小列數越多。',
    onTap: _showCardWidthDialog,
  ),
  const SwitchModel(
    title: '播放頁移除安全邊距',
    leading: Icon(Icons.fit_screen_outlined),
    setKey: SettingBoxKey.removeSafeArea,
    defaultVal: false,
  ),
  const SwitchModel(
    title: '影片播放頁使用深色主題',
    leading: Icon(Icons.dark_mode_outlined),
    setKey: SettingBoxKey.darkVideoPage,
    defaultVal: false,
  ),
  SwitchModel(
    title: '動態頁啟用瀑布流',
    subtitle: '關閉會顯示為單列',
    leading: const Icon(Icons.view_array_outlined),
    setKey: SettingBoxKey.dynamicsWaterfallFlow,
    defaultVal: Pref.horizontalScreen,
    needReboot: true,
  ),
  PopupModel(
    title: '動態頁UP主顯示位置',
    leading: const Icon(Icons.person_outlined),
    value: () => Pref.upPanelPosition,
    items: UpPanelPosition.values,
    onSelected: (value, setState) {
      GStorage.setting
          .put(SettingBoxKey.upPanelPosition, value.index)
          .whenComplete(setState);
      SmartDialog.showToast('重啟生效');
    },
  ),
  const SwitchModel(
    title: '動態頁顯示所有已關注UP主',
    leading: Icon(Icons.people_alt_outlined),
    setKey: SettingBoxKey.dynamicsShowAllFollowedUp,
    defaultVal: false,
    needReboot: true,
  ),
  const SwitchModel(
    title: '動態頁展開正在直播UP列表',
    leading: Icon(Icons.live_tv),
    setKey: SettingBoxKey.expandDynLivePanel,
    defaultVal: false,
    needReboot: true,
  ),
  PopupModel(
    title: '動態未讀標記',
    leading: const Icon(Icons.motion_photos_on_outlined),
    value: () => Pref.dynamicBadgeType,
    items: DynamicBadgeMode.values,
    onSelected: _setDynBadge,
  ),
  PopupModel(
    title: '訊息未讀標記',
    leading: const Icon(MdiIcons.bellBadgeOutline),
    value: () => Pref.msgBadgeMode,
    items: DynamicBadgeMode.values,
    onSelected: _setMsgBadge,
  ),
  NormalModel(
    onTap: _showMsgUnReadDialog,
    title: '訊息未讀型別',
    leading: const Icon(MdiIcons.bellCogOutline),
    getSubtitle: () =>
        '當前訊息型別：${Pref.msgUnReadTypeV2.map((item) => item.title).join('、')}',
  ),
  PopupModel(
    title: '頂/底欄收起型別',
    leading: const Icon(MdiIcons.arrowExpandVertical),
    value: () => Pref.barHideType,
    items: BarHideType.values,
    onSelected: (value, setState) {
      GStorage.setting
          .put(SettingBoxKey.barHideType, value.index)
          .whenComplete(setState);
      SmartDialog.showToast('重啟生效');
    },
  ),
  NormalModel(
    title: '使用者頁預設展示TAB',
    leading: const Icon(Icons.tab),
    getSubtitle: () => '當前優先展示「${Pref.memberTab.title}」',
    onTap: _showMemberTabDialog,
  ),
  SwitchModel(
    title: '顯示UP主頁小店TAB',
    leading: const Icon(Icons.shop_outlined),
    setKey: SettingBoxKey.showMemberShop,
    defaultVal: false,
    onChanged: (value) => MemberTabType.showMemberShop = value,
  ),
  SwitchModel(
    title: '首頁頂欄收起',
    subtitle: '首頁列表滑動時，收起頂欄',
    leading: const Icon(Icons.vertical_align_top_outlined),
    setKey: SettingBoxKey.hideTopBar,
    defaultVal: PlatformUtils.isMobile,
    needReboot: true,
  ),
  NormalModel(
    onTap: (context, setState) => _showQualityDialog(
      context: context,
      title: const Text('圖片質量'),
      initValue: Pref.picQuality,
      onChanged: (picQuality) async {
        GlobalData().imgQuality = picQuality;
        await GStorage.setting.put(SettingBoxKey.defaultPicQa, picQuality);
        setState();
      },
    ),
    title: '圖片質量',
    subtitle: '選擇合適的圖片清晰度，上限100%',
    leading: const Icon(Icons.image_outlined),
    getTrailing: (theme) => Text(
      '${Pref.picQuality}%',
      style: theme.textTheme.titleSmall,
    ),
  ),
  NormalModel(
    onTap: (context, setState) => _showQualityDialog(
      context: context,
      title: const Text('檢視大圖質量'),
      initValue: Pref.previewQ,
      onChanged: (picQuality) async {
        await GStorage.setting.put(SettingBoxKey.previewQuality, picQuality);
        setState();
      },
    ),
    title: '檢視大圖質量',
    subtitle: '選擇合適的圖片清晰度，上限100%',
    leading: const Icon(Icons.image_outlined),
    getTrailing: (theme) => Text(
      '${Pref.previewQ}%',
      style: theme.textTheme.titleSmall,
    ),
  ),
  NormalModel(
    onTap: _showReduceColorDialog,
    title: '深色下圖片顏色疊加',
    subtitle: '顯示顏色=圖片原色x所選顏色，大圖檢視不受影響',
    leading: const Icon(Icons.format_color_fill_outlined),
    getTrailing: (theme) => Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: Pref.reduceLuxColor ?? Colors.white,
        shape: BoxShape.circle,
      ),
    ),
  ),
  NormalModel(
    leading: const Icon(Icons.opacity_outlined),
    title: '氣泡提示不透明度',
    subtitle: '自定義氣泡提示(Toast)不透明度',
    getTrailing: (theme) => Text(
      CustomToast.toastOpacity.toStringAsFixed(1),
      style: theme.textTheme.titleSmall,
    ),
    onTap: _showToastDialog,
  ),
  PopupModel(
    leading: const Icon(Icons.flashlight_on_outlined),
    title: '主題模式',
    value: () => Pref.themeType,
    items: ThemeType.values,
    onSelected: _setThemeType,
  ),
  SwitchModel(
    leading: const Icon(Icons.invert_colors),
    title: '純黑主題',
    setKey: SettingBoxKey.isPureBlackTheme,
    defaultVal: false,
    onChanged: (value) {
      if (ThemeUtils.isDarkMode || Pref.darkVideoPage) {
        Get.updateMyAppTheme();
      }
    },
  ),
  NormalModel(
    onTap: (context, setState) => Get.toNamed('/colorSetting'),
    leading: const Icon(Icons.color_lens_outlined),
    title: '應用主題',
    getSubtitle: () => '當前主題：${Pref.dynamicColor ? '動態取色' : '指定顏色'}',
    getTrailing: _themeTrailing,
  ),
  NormalModel(
    onTap: _showMineTabsDialog,
    title: '我的頁卡片',
    leading: const Icon(Icons.person_outline),
    getSubtitle: () =>
        '當前顯示：${Pref.mineTabs.map((item) => item.label).join('、')}',
  ),
  PopupModel(
    leading: const Icon(Icons.home_outlined),
    title: '預設啟動頁',
    value: () => Pref.defaultHomePage,
    items: NavigationBarType.values,
    onSelected: (value, setState) {
      GStorage.setting
          .put(SettingBoxKey.defaultHomePage, value.index)
          .whenComplete(setState);
      SmartDialog.showToast('重啟生效');
    },
  ),
  const NormalModel(
    title: '滑動動畫彈簧引數',
    leading: Icon(Icons.chrome_reader_mode_outlined),
    onTap: _showSpringDialog,
  ),
  NormalModel(
    onTap: (context, setState) => Get.toNamed(
      '/barSetting',
      arguments: {
        'key': SettingBoxKey.tabBarSort,
        'defaultBars': HomeTabType.values,
        'title': '首頁標籤頁',
      },
    ),
    title: '首頁標籤頁',
    subtitle: '刪除或調換首頁標籤頁',
    leading: const Icon(Icons.toc_outlined),
  ),
  NormalModel(
    onTap: (context, setState) => Get.toNamed(
      '/barSetting',
      arguments: {
        'key': SettingBoxKey.navBarSort,
        'defaultBars': NavigationBarType.defaultOrder,
        'title': 'Navbar',
      },
    ),
    title: 'Navbar編輯',
    subtitle: '刪除或調換Navbar',
    leading: const Icon(Icons.toc_outlined),
  ),
  SwitchModel(
    title: '返回時直接退出',
    subtitle: '開啟後在主頁任意tab按返回鍵都直接退出，關閉則先回到Navbar的第一個tab',
    leading: const Icon(Icons.exit_to_app_outlined),
    setKey: SettingBoxKey.directExitOnBack,
    defaultVal: false,
    onChanged: (value) => Get.find<MainController>().directExitOnBack = value,
  ),
  if (Platform.isAndroid)
    NormalModel(
      onTap: (context, setState) => Get.toNamed('/displayModeSetting'),
      title: '螢幕幀率',
      leading: const Icon(Icons.autofps_select_outlined),
    ),
];

void _showQualityDialog({
  required BuildContext context,
  required Widget title,
  required int initValue,
  required ValueChanged<int> onChanged,
}) {
  showDialog<double>(
    context: context,
    builder: (context) => SliderDialog(
      value: initValue.toDouble(),
      title: title,
      min: 10,
      max: 100,
      divisions: 9,
      suffix: '%',
      precise: 0,
    ),
  ).then((result) {
    if (result != null) {
      SmartDialog.showToast('設定成功');
      onChanged(result.toInt());
    }
  });
}

void _showUiScaleDialog(
  BuildContext context,
  VoidCallback setState,
) {
  const minUiScale = 0.5;
  const maxUiScale = 2.0;

  double uiScale = Pref.uiScale;
  final textController = TextEditingController(
    text: uiScale.toStringAsFixed(2),
  );

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('介面縮放'),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      content: StatefulBuilder(
        onDispose: textController.dispose,
        builder: (context, setDialogState) => Column(
          spacing: 20,
          mainAxisSize: MainAxisSize.min,
          children: [
            Slider(
              padding: .zero,
              value: uiScale,
              min: minUiScale,
              max: maxUiScale,
              secondaryTrackValue: 1.0,
              divisions: ((maxUiScale - minUiScale) * 20).toInt(),
              label: textController.text,
              onChanged: (value) => setDialogState(() {
                uiScale = value.toPrecision(2);
                textController.text = uiScale.toStringAsFixed(2);
              }),
            ),
            TextFormField(
              controller: textController,
              keyboardType: const .numberWithOptions(decimal: true),
              inputFormatters: [
                LengthLimitingTextInputFormatter(4),
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]+')),
              ],
              decoration: const InputDecoration(
                labelText: '縮放比例',
                hintText: '0.50 - 2.00',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                final parsed = double.tryParse(value);
                if (parsed != null &&
                    parsed >= minUiScale &&
                    parsed <= maxUiScale) {
                  setDialogState(() {
                    uiScale = parsed;
                  });
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            GStorage.setting.delete(SettingBoxKey.uiScale).whenComplete(() {
              setState();
              Get.appUpdate();
              ScaledWidgetsFlutterBinding.instance.scaleFactor = 1.0;
            });
          },
          child: const Text('重置'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            '取消',
            style: TextStyle(color: ColorScheme.of(context).outline),
          ),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            GStorage.setting.put(SettingBoxKey.uiScale, uiScale).whenComplete(
              () {
                setState();
                Get.appUpdate();
                ScaledWidgetsFlutterBinding.instance.scaleFactor = uiScale;
              },
            );
          },
          child: const Text('確定'),
        ),
      ],
    ),
  );
}

void _showSpringDialog(BuildContext context, _) {
  final List<String> springDescription = Pref.springDescription
      .map((i) => i.toString())
      .toList(growable: false);
  bool physicalMode = true;

  void physical2Duration() {
    final mass = double.parse(springDescription[0]);
    final stiffness = double.parse(springDescription[1]);
    final damping = double.parse(springDescription[2]);

    final duration = math.sqrt(4 * math.pi * math.pi * mass / stiffness);
    final dampingRatio = damping / (2.0 * math.sqrt(mass * stiffness));
    final bounce = dampingRatio < 1.0
        ? 1.0 - dampingRatio
        : 1.0 / dampingRatio - 1;

    springDescription[0] = duration.toString();
    springDescription[1] = bounce.toString();
  }

  /// from [SpringDescription.withDurationAndBounce] but with higher precision
  void duration2Physical() {
    final duration = double.parse(springDescription[0]);
    final bounce = double.parse(springDescription[1]).clamp(-1.0, 1.0);

    final stiffness = 4 * math.pi * math.pi / math.pow(duration, 2);
    final dampingRatio = bounce > 0 ? 1.0 - bounce : 1.0 / (bounce + 1);
    final damping = 2 * math.sqrt(stiffness) * dampingRatio;

    springDescription[0] = '1';
    springDescription[1] = stiffness.toString();
    springDescription[2] = damping.toString();
  }

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(
        mainAxisAlignment: .spaceBetween,
        children: [
          const Text('彈簧引數'),
          TextButton(
            style: TextButton.styleFrom(
              visualDensity: .compact,
              tapTargetSize: .shrinkWrap,
            ),
            onPressed: () {
              try {
                if (physicalMode) {
                  physical2Duration();
                } else {
                  duration2Physical();
                }
                physicalMode = !physicalMode;
                (context as Element).markNeedsBuild();
              } catch (e) {
                SmartDialog.showToast(e.toString());
              }
            },
            child: Text(physicalMode ? '滑動時間' : '物理引數'),
          ),
        ],
      ),
      content: Column(
        key: ValueKey(physicalMode),
        mainAxisSize: .min,
        children: List.generate(
          physicalMode ? 3 : 2,
          (index) => TextFormField(
            autofocus: index == 0,
            initialValue: springDescription[index],
            keyboardType: .numberWithOptions(
              signed: !physicalMode && index == 1,
              decimal: true,
            ),
            onChanged: (value) => springDescription[index] = value,
            inputFormatters: [
              !physicalMode && index == 1
                  ? FilteringTextInputFormatter.allow(RegExp(r'[-\d\.]+'))
                  : FilteringTextInputFormatter.allow(RegExp(r'[\d\.]+')),
            ],
            decoration: InputDecoration(
              labelText: (physicalMode
                  ? const ['mass', 'stiffness', 'damping']
                  : const ['duration', 'bounce'])[index],
              suffixText: !physicalMode && index == 0 ? 's' : null,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Get.back();
            GStorage.setting.delete(SettingBoxKey.springDescription);
            SmartDialog.showToast('重置成功，重啟生效');
          },
          child: const Text('重置'),
        ),
        TextButton(
          onPressed: Get.back,
          child: Text(
            '取消',
            style: TextStyle(color: ColorScheme.of(context).outline),
          ),
        ),
        TextButton(
          onPressed: () {
            try {
              if (!physicalMode) {
                duration2Physical();
              }
              final res = springDescription.map(double.parse).toList();
              Get.back();
              GStorage.setting.put(SettingBoxKey.springDescription, res);
              kSpringDescription = SpringDescription(
                mass: res[0],
                stiffness: res[1],
                damping: res[2],
              );
              SmartDialog.showToast('設定成功');
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

Future<void> _showTransitionDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<Transition>(
    context: context,
    builder: (context) => SelectDialog<Transition>(
      title: '頁面過渡動畫',
      value: Pref.pageTransition,
      values: Transition.values.map((e) => (e, e.name)).toList(),
    ),
  );
  if (res != null) {
    Get.rootController.defaultTransition = res;
    await GStorage.setting.put(SettingBoxKey.pageTransition, res.index);
    setState();
  }
}

Future<void> _showCardWidthDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<(double, double)>(
    context: context,
    builder: (context) => DualSliderDialog(
      title: const Text('列表最大列寬度'),
      value1: Pref.recommendCardWidth,
      value2: Pref.smallCardWidth,
      description1: const Text('影片卡片（首頁與影片列表，預設 300dp）'),
      description2: const Text('其他列表（直播、番劇、歷史、稍後再看等，預設 240dp）'),
      min: 150.0,
      max: 500.0,
      divisions: 35,
      suffix: 'dp',
    ),
  );
  if (res != null) {
    await GStorage.setting.putAll({
      SettingBoxKey.recommendCardWidth: res.$1,
      SettingBoxKey.smallCardWidth: res.$2,
    });
    SmartDialog.showToast('重啟生效');
    setState();
  }
}

void _setDynBadge(DynamicBadgeMode value, VoidCallback setState) {
  final mainController = Get.find<MainController>()..dynamicBadgeMode = value;
  if (value != DynamicBadgeMode.hidden) mainController.getUnreadDynamic();
  GStorage.setting
      .put(SettingBoxKey.dynamicBadgeMode, value.index)
      .whenComplete(setState);
}

void _setMsgBadge(DynamicBadgeMode value, VoidCallback setState) {
  final mainController = Get.find<MainController>()..msgBadgeMode = value;
  if (value != DynamicBadgeMode.hidden) {
    mainController.queryUnreadMsg(true);
  } else {
    mainController.clearUnreadMsg();
  }
  GStorage.setting
      .put(SettingBoxKey.msgBadgeMode, value.index)
      .whenComplete(setState);
}

Future<void> _showMsgUnReadDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<Set<MsgUnReadType>>(
    context: context,
    builder: (context) => MultiSelectDialog<MsgUnReadType>(
      title: '訊息未讀型別',
      initValues: Pref.msgUnReadTypeV2,
      values: {for (final i in MsgUnReadType.values) i: i.title},
    ),
  );
  if (res != null) {
    final mainController = Get.find<MainController>()..msgUnReadTypes = res;
    if (mainController.msgBadgeMode != DynamicBadgeMode.hidden) {
      mainController.queryUnreadMsg();
    }
    await GStorage.setting.put(
      SettingBoxKey.msgUnReadTypeV2,
      res.map((item) => item.index).toList()..sort(),
    );
    SmartDialog.showToast('設定成功');
    setState();
  }
}

void _showReduceColorDialog(
  BuildContext context,
  VoidCallback setState,
) {
  final reduceLuxColor = Pref.reduceLuxColor;
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      clipBehavior: Clip.hardEdge,
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
      title: const Text('Color Picker'),
      content: SlideColorPicker(
        color: reduceLuxColor ?? Colors.white,
        onChanged: (Color? color) {
          if (color != null && color != reduceLuxColor) {
            if (color == Colors.white) {
              NetworkImgLayer.reduceLuxColor = null;
              GStorage.setting.delete(SettingBoxKey.reduceLuxColor);
              SmartDialog.showToast('設定成功');
              setState();
            } else {
              void onConfirm() {
                NetworkImgLayer.reduceLuxColor = color;
                GStorage.setting.put(
                  SettingBoxKey.reduceLuxColor,
                  color.toARGB32(),
                );
                SmartDialog.showToast('設定成功');
                setState();
              }

              if (color.computeLuminance() < 0.2) {
                showConfirmDialog(
                  context: context,
                  title: Text(
                    '確認使用#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6)}？',
                  ),
                  content: const Text('所選顏色過於昏暗，可能會影響圖片觀看'),
                  onConfirm: onConfirm,
                );
              } else {
                onConfirm();
              }
            }
          }
        },
      ),
    ),
  );
}

Future<void> _showToastDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<double>(
    context: context,
    builder: (context) => SliderDialog(
      title: const Text('Toast不透明度'),
      value: CustomToast.toastOpacity,
      min: 0.0,
      max: 1.0,
      divisions: 10,
    ),
  );
  if (res != null) {
    CustomToast.toastOpacity = res;
    await GStorage.setting.put(SettingBoxKey.defaultToastOp, res);
    SmartDialog.showToast('設定成功');
    setState();
  }
}

void _setThemeType(ThemeType value, VoidCallback setState) {
  try {
    Get.find<MineController>().themeType.value = value;
  } catch (_) {}
  GStorage.setting.put(SettingBoxKey.themeMode, value.index);
  Get.changeThemeMode(ThemeUtils.themeMode = value.toThemeMode);
  setState();
}

NormalModel _useSSDModel() {
  final file = File(path.join(appSupportDirPath, 'use_ssd'));
  void onChanged(BuildContext context, VoidCallback setState) {
    (file.existsSync() ? file.tryDel() : file.create()).whenComplete(setState);
  }

  return NormalModel(
    title: '使用SSD（Server-Side Decoration）',
    leading: const Icon(Icons.web_asset),
    onTap: onChanged,
    getTrailing: (theme) => Builder(
      builder: (context) => Transform.scale(
        scale: 0.8,
        alignment: .centerRight,
        child: Switch(
          value: file.existsSync(),
          onChanged: (_) =>
              onChanged(context, (context as Element).markNeedsBuild),
        ),
      ),
    ),
  );
}

Widget _themeTrailing(ThemeData theme) {
  if (Pref.dynamicColor) {
    return Icon(Icons.color_lens_rounded, color: theme.colorScheme.primary);
  }
  final customColor = Pref.customColor;
  final color =
      colorThemeTypes.elementAtOrNull(customColor)?.color ?? Color(customColor);
  return SizedBox.square(
    dimension: 20,
    child: ColorPalette(
      colorScheme: color.asColorSchemeSeed(
        Pref.schemeVariant,
        theme.brightness,
      ),
      selected: false,
      showBgColor: false,
    ),
  );
}

void _onHorizontalScreenChanged(bool value) {
  if (value) {
    fullMode();
  } else {
    portraitUpMode();
  }
}

Future<void> _showMineTabsDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<List<MineTabType>>(
    context: context,
    builder: (context) => OrderedMultiSelectDialog<MineTabType>(
      title: const Text('我的頁卡片'),
      initValues: Pref.mineTabs,
      values: {for (final i in MineTabType.values) i: i.label},
    ),
  );
  if (res != null) {
    await GStorage.setting.put(
      SettingBoxKey.mineTabs,
      res.map((item) => item.index).toList(),
    );
    SmartDialog.showToast('重啟生效');
    setState();
  }
}

Future<void> _showMemberTabDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<MemberTabType>(
    context: context,
    builder: (context) => SelectDialog<MemberTabType>(
      title: '使用者頁預設展示TAB',
      value: Pref.memberTab,
      values: MemberTabType.values.map((e) => (e, e.title)).toList(),
    ),
  );
  if (res != null) {
    await GStorage.setting.put(SettingBoxKey.memberTab, res.index);
    setState();
  }
}
