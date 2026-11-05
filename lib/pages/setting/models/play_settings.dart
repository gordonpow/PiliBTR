import 'dart:io' show Platform;

import 'package:PiliPlus/common/widgets/custom_icon.dart';
import 'package:PiliPlus/common/widgets/image_grid/image_grid_view.dart';
import 'package:PiliPlus/models/common/audio_normalization.dart';
import 'package:PiliPlus/models/common/super_chat_type.dart';
import 'package:PiliPlus/models/common/super_resolution_type.dart';
import 'package:PiliPlus/models/common/video/subtitle_pref_type.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/pages/setting/pages/fullscreen_sc.dart';
import 'package:PiliPlus/pages/setting/widgets/select_dialog.dart';
import 'package:PiliPlus/pages/setting/widgets/slider_dialog.dart';
import 'package:PiliPlus/plugin/pl_player/models/bottom_progress_behavior.dart';
import 'package:PiliPlus/plugin/pl_player/models/fullscreen_mode.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_repeat.dart';
import 'package:PiliPlus/plugin/pl_player/mini_player.dart';
import 'package:PiliPlus/services/service_locator.dart';
import 'package:PiliPlus/utils/android/android_helper.dart';
import 'package:PiliPlus/utils/desktop/window_controller.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:PiliPlus/utils/ios/pip_helper.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart';

List<SettingsModel> get playSettings => [
  NormalModel(
    onTap: (context, setState) => Get.toNamed('/playSpeedSet'),
    leading: const Icon(Icons.speed_outlined),
    title: '倍速設定',
    subtitle: '設定影片播放速度',
  ),
  if (kDebugMode || Platform.isAndroid)
    NormalModel(
      onTap: _showAngleDegreesDialog,
      leading: const Icon(MdiIcons.angleAcute),
      title: '傾斜角度閾值',
      getSubtitle: () => '當前:「${Pref.angleDegrees}°」',
    ),
  if (kDebugMode || Platform.isAndroid)
    NormalModel(
      title: '音量均衡',
      leading: const Icon(Icons.multitrack_audio),
      getSubtitle: () {
        final audioNormalization = AudioNormalization.getTitleFromConfig(
          Pref.audioNormalization,
        );
        String fallback = Pref.fallbackNormalization;
        if (fallback == '0') {
          fallback = '';
        } else {
          fallback =
              '，無引數時:「${AudioNormalization.getTitleFromConfig(fallback)}」';
        }
        return '當前:「$audioNormalization」$fallback';
      },
      onTap: audioNormalization,
    ),
  NormalModel(
    title: '超解析度',
    leading: const Icon(Icons.stay_current_landscape_outlined),
    getSubtitle: () =>
        '當前:「${Pref.superResolutionType.label}」\n預設設定對番劇生效, 其他影片預設關閉\n超解析度需要啟用硬體解碼, 若啟用硬體解碼後仍然不生效, 嘗試切換硬體解碼器為 auto-copy',
    onTap: _showSuperResolutionDialog,
  ),
  const SwitchModel(
    title: '自動播放',
    subtitle: '進入詳情頁自動播放',
    leading: Icon(Icons.motion_photos_auto_outlined),
    setKey: SettingBoxKey.autoPlayEnable,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '全屏顯示鎖定按鈕',
    leading: Icon(Icons.lock_outline),
    setKey: SettingBoxKey.showFsLockBtn,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '全屏顯示截圖按鈕',
    leading: Icon(Icons.photo_camera_outlined),
    setKey: SettingBoxKey.showFsScreenshotBtn,
    defaultVal: true,
  ),
  SwitchModel(
    title: '全屏顯示電池電量',
    leading: const Icon(Icons.battery_3_bar),
    setKey: SettingBoxKey.showBatteryLevel,
    defaultVal: PlatformUtils.isMobile,
  ),
  const SwitchModel(
    title: '雙擊快退/快進',
    subtitle: '左側雙擊快退/右側雙擊快進，關閉則雙擊均為暫停/播放',
    leading: Icon(Icons.touch_app_outlined),
    setKey: SettingBoxKey.enableQuickDouble,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '左右側滑動調節亮度/音量',
    leading: Icon(MdiIcons.tuneVerticalVariant),
    setKey: SettingBoxKey.enableSlideVolumeBrightness,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '滾輪調節音量',
    leading: Icon(Icons.mouse_outlined),
    setKey: SettingBoxKey.enableScrollVolume,
    defaultVal: true,
  ),
  if (Platform.isAndroid)
    const SwitchModel(
      title: '調節系統亮度',
      leading: Icon(Icons.brightness_6_outlined),
      setKey: SettingBoxKey.setSystemBrightness,
      defaultVal: false,
    ),
  const SwitchModel(
    title: '中間滑動進入/退出全屏',
    leading: Icon(MdiIcons.panVertical),
    setKey: SettingBoxKey.enableSlideFS,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '提前初始化播放器',
    subtitle: '相對減少手動播放載入時間',
    leading: Icon(Icons.play_circle_outlined),
    setKey: SettingBoxKey.preInitPlayer,
    defaultVal: false,
  ),
  const SwitchModel(
    title: '滑動跳轉預覽影片縮圖',
    leading: Icon(Icons.preview_outlined),
    setKey: SettingBoxKey.showSeekPreview,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '顯示高能進度條',
    subtitle: '高能進度條反應了在時域上，單位時間內彈幕傳送量的變化趨勢',
    leading: Icon(Icons.show_chart),
    setKey: SettingBoxKey.showDmChart,
    defaultVal: false,
  ),
  const SwitchModel(
    title: '啟用雙指縮小影片',
    leading: Icon(Icons.pinch),
    setKey: SettingBoxKey.enableShrinkVideoSize,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '啟用拖拽字幕調整底部邊距',
    leading: Icon(MdiIcons.dragVariant),
    setKey: SettingBoxKey.enableDragSubtitle,
    defaultVal: false,
  ),
  const SwitchModel(
    title: '影片頁顯示相關影片',
    leading: Icon(MdiIcons.motionPlayOutline),
    setKey: SettingBoxKey.showRelatedVideo,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '預設展開影片簡介',
    leading: Icon(Icons.expand_more),
    setKey: SettingBoxKey.alwaysExpandIntroPanel,
    defaultVal: false,
  ),
  const SwitchModel(
    title: '橫屏自動展開影片簡介',
    leading: Icon(Icons.expand_more),
    setKey: SettingBoxKey.expandIntroPanelH,
    defaultVal: false,
  ),
  SwitchModel(
    title: '橫屏分P/合集列表顯示在Tab欄',
    leading: const Icon(Icons.format_list_numbered_rtl_sharp),
    setKey: SettingBoxKey.horizontalSeasonPanel,
    defaultVal: Pref.horizontalScreen,
  ),
  SwitchModel(
    title: '橫屏播放頁在側欄開啟UP主頁',
    leading: const Icon(Icons.account_circle_outlined),
    setKey: SettingBoxKey.horizontalMemberPage,
    defaultVal: Pref.horizontalScreen,
  ),
  SwitchModel(
    title: '橫屏在側欄開啟圖片預覽',
    leading: const Icon(Icons.photo_outlined),
    setKey: SettingBoxKey.horizontalPreview,
    defaultVal: false,
    onChanged: (value) => ImageGridView.horizontalPreview = value,
  ),
  const SwitchModel(
    title: '顯示影片警告/爭議資訊',
    leading: Icon(Icons.warning_amber_rounded),
    setKey: SettingBoxKey.showArgueMsg,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '顯示影片分段資訊',
    leading: Icon(CustomIcons.view_headline_rotate_90),
    setKey: SettingBoxKey.showViewPoints,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '顯示繼續播放分P提示',
    leading: Icon(Icons.local_parking),
    setKey: SettingBoxKey.continuePlayingPart,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '分P/合集：倒序播放從首集開始播放',
    subtitle: '開啟則自動切換為倒序首集，否則保持當前集',
    leading: Icon(MdiIcons.sort),
    setKey: SettingBoxKey.reverseFromFirst,
    defaultVal: true,
  ),
  if (kDebugMode || PlatformUtils.isMobile)
    NormalModel(
      title: '播放器音量',
      leading: const Icon(Icons.volume_up),
      getSubtitle: () => '當前:「${Pref.playerVolume.toStringAsFixed(0)}%」',
      onTap: showPlayerVolumeDialog,
    )
  else
    NormalModel(
      title: '最高音量',
      leading: const Icon(Icons.volume_up),
      getSubtitle: () => '當前:「${(Pref.maxVolume * 100).toStringAsFixed(0)}%」',
      onTap: _showMaxVolumeDialog,
    ),
  getVideoFilterSelectModel(
    title: '雙擊快進/快退時長',
    suffix: 's',
    key: SettingBoxKey.fastForBackwardDuration,
    values: [5, 10, 15],
    defaultValue: 10,
    isFilter: false,
  ),
  const SwitchModel(
    title: '滑動快進/快退使用相對時長',
    leading: Icon(Icons.swap_horiz_outlined),
    setKey: SettingBoxKey.useRelativeSlide,
    defaultVal: false,
  ),
  getVideoFilterSelectModel(
    title: '滑動快進/快退時長',
    subtitle: '從播放器一端滑到另一端的快進/快退時長',
    suffix: Pref.useRelativeSlide ? '%' : 's',
    key: SettingBoxKey.sliderDuration,
    values: [25, 50, 90, 100],
    defaultValue: 90,
    isFilter: false,
  ),
  NormalModel(
    title: '自動啟用字幕',
    leading: const Icon(Icons.closed_caption_outlined),
    getSubtitle: () => '當前選擇偏好：${Pref.subtitlePreferenceV2.desc}',
    onTap: _showSubtitleDialog,
  ),
  if (PlatformUtils.isDesktop)
    SwitchModel(
      title: '最小化時暫停/還原時播放',
      leading: const Icon(Icons.pause_circle_outline),
      setKey: SettingBoxKey.pauseOnMinimize,
      defaultVal: false,
      onChanged: (value) => WindowController.instance.pauseOnMinimize = value,
    ),
  const SwitchModel(
    title: '啟用鍵盤控制',
    leading: Icon(Icons.keyboard_alt_outlined),
    setKey: SettingBoxKey.keyboardControl,
    defaultVal: true,
  ),
  PopupModel(
    title: 'SuperChat (醒目留言) 顯示型別',
    leading: const Icon(Icons.live_tv),
    value: () => Pref.superChatType,
    items: SuperChatType.values,
    onSelected: (value, setState) => GStorage.setting
        .put(SettingBoxKey.superChatType, value.index)
        .whenComplete(setState),
  ),
  NormalModel(
    title: '全屏 SuperChat 設定',
    subtitle: '全屏 SuperChat (醒目留言) 大小、不透明度、縮放設定',
    leading: const Icon(Icons.open_in_full),
    onTap: (_, _) => Get.to(const FullScreenSc()),
  ),
  const SwitchModel(
    title: '豎屏擴大展示',
    subtitle: '小屏豎屏影片寬高比由16:9擴大至1:1（不支援收起）；橫屏適配時，擴大至9:16',
    leading: Icon(Icons.expand_outlined),
    setKey: SettingBoxKey.enableVerticalExpand,
    defaultVal: false,
  ),
  const SwitchModel(
    title: '自動全屏',
    subtitle: '影片開始播放時進入全屏',
    leading: Icon(Icons.fullscreen_outlined),
    setKey: SettingBoxKey.enableAutoEnter,
    defaultVal: false,
  ),
  const SwitchModel(
    title: '自動退出全屏',
    subtitle: '影片結束播放時退出全屏',
    leading: Icon(Icons.fullscreen_exit_outlined),
    setKey: SettingBoxKey.enableAutoExit,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '延長播放控制元件顯示時間',
    subtitle: '開啟後延長至30秒，便於螢幕閱讀器滑動切換控制元件焦點',
    leading: Icon(Icons.timer_outlined),
    setKey: SettingBoxKey.enableLongShowControl,
    defaultVal: false,
  ),
  if (PlatformUtils.isMobile)
    const SwitchModel(
      title: '背景播放',
      subtitle: '進入背景時繼續播放',
      leading: Icon(Icons.motion_photos_pause_outlined),
      setKey: SettingBoxKey.continuePlayInBackground,
      defaultVal: false,
    ),
  const SwitchModel(
    title: '返回時縮小為小視窗',
    subtitle: '離開影片頁時，在 App 內以小視窗繼續播放（類似 YouTube）',
    leading: Icon(Icons.picture_in_picture_alt_outlined),
    setKey: SettingBoxKey.miniPlayerOnBack,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '斜下滑縮小為小視窗',
    subtitle: '在影片上往左下或右下滑動，縮小為小視窗繼續播放',
    leading: Icon(Icons.south_west),
    setKey: SettingBoxKey.miniPlayerOnSwipe,
    defaultVal: true,
  ),
  NormalModel(
    title: '小視窗大小',
    leading: const Icon(Icons.aspect_ratio),
    getSubtitle: () => '當前:「${MiniPlayer.sizeLabels[MiniPlayer.sizeIndex]}」',
    onTap: _showMiniPlayerSizeDialog,
  ),
  if ((Platform.isAndroid && PiliAndroidHelper.isPipAvailable) ||
      (Platform.isIOS && IOSPipHelper.isAvailable))
    SwitchModel(
      title: '背景畫中畫',
      subtitle: '進入背景時以小窗形式（PiP）播放',
      leading: const Icon(Icons.picture_in_picture_outlined),
      setKey: SettingBoxKey.autoPiP,
      defaultVal: false,
      onChanged: Platform.isAndroid
          ? (val) {
              if (val && !videoPlayerServiceHandler!.enableBackgroundPlay) {
                SmartDialog.showToast('建議開啟背景音訊服務');
              }
            }
          : null,
    ),
  // PiP on iOS only shows the video frames, without danmaku.
  if (Platform.isAndroid)
    const SwitchModel(
      title: '畫中畫不載入彈幕',
      subtitle: '當彈幕開關開啟時，小窗遮蔽彈幕以獲得較好的體驗',
      leading: Icon(CustomIcons.dm_off),
      setKey: SettingBoxKey.pipNoDanmaku,
      defaultVal: false,
    ),
  const SwitchModel(
    title: '全屏手勢反向',
    subtitle: '預設播放器中部向上滑動進入全屏，向下退出\n開啟後向下全屏，向上退出',
    leading: Icon(Icons.swap_vert),
    setKey: SettingBoxKey.fullScreenGestureReverse,
    defaultVal: false,
  ),
  const SwitchModel(
    title: '全屏展示點贊/投幣/收藏等操作按鈕',
    leading: Icon(MdiIcons.dotsHorizontalCircleOutline),
    setKey: SettingBoxKey.showFSActionItem,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '觀看人數',
    subtitle: '展示同時在看人數',
    leading: Icon(Icons.people_outlined),
    setKey: SettingBoxKey.enableOnlineTotal,
    defaultVal: false,
  ),
  NormalModel(
    title: '預設全屏方向',
    leading: const Icon(Icons.open_with_outlined),
    getSubtitle: () => '當前全屏方向：${Pref.fullScreenMode.desc}',
    onTap: _showFullScreenModeDialog,
  ),
  PopupModel(
    title: '底部進度條展示',
    leading: const Icon(Icons.border_bottom_outlined),
    value: () => Pref.btmProgressBehavior,
    items: BtmProgressBehavior.values,
    onSelected: (value, setState) => GStorage.setting
        .put(SettingBoxKey.btmProgressBehavior, value.index)
        .whenComplete(setState),
  ),
  if (PlatformUtils.isMobile)
    SwitchModel(
      title: '背景音訊服務',
      subtitle: '避免畫中畫沒有播放暫停功能',
      leading: const Icon(Icons.volume_up_outlined),
      setKey: SettingBoxKey.enableBackgroundPlay,
      defaultVal: true,
      onChanged: (value) =>
          videoPlayerServiceHandler!.enableBackgroundPlay = value,
    ),
  PopupModel(
    title: '播放順序',
    leading: const Icon(Icons.repeat),
    value: () => Pref.playRepeat,
    items: PlayRepeat.values,
    onSelected: (value, setState) => GStorage.video
        .put(VideoBoxKey.playRepeat, value.index)
        .whenComplete(setState),
  ),
  const SwitchModel(
    title: '播放器設定僅對當前生效',
    subtitle: '彈幕、字幕及部分設定中沒有的設定除外',
    leading: Icon(Icons.video_settings_outlined),
    setKey: SettingBoxKey.tempPlayerConf,
    defaultVal: false,
  ),
];

Future<void> _showMiniPlayerSizeDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<int>(
    context: context,
    builder: (context) => SelectDialog<int>(
      title: '小視窗大小',
      value: MiniPlayer.sizeIndex,
      values: MiniPlayer.sizeLabels.indexed.toList(),
    ),
  );
  if (res != null) {
    await GStorage.setting.put(SettingBoxKey.miniPlayerSize, res);
    setState();
  }
}

Future<void> _showSubtitleDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<SubtitlePrefType>(
    context: context,
    builder: (context) => SelectDialog<SubtitlePrefType>(
      title: '字幕選擇偏好',
      value: Pref.subtitlePreferenceV2,
      values: SubtitlePrefType.values.map((e) => (e, e.desc)).toList(),
    ),
  );
  if (res != null) {
    await GStorage.setting.put(
      SettingBoxKey.subtitlePreferenceV2,
      res.index,
    );
    setState();
  }
}

Future<void> _showFullScreenModeDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<FullScreenMode>(
    context: context,
    builder: (context) => SelectDialog<FullScreenMode>(
      title: '預設全屏方向',
      value: Pref.fullScreenMode,
      values: FullScreenMode.values.map((e) => (e, e.desc)).toList(),
    ),
  );
  if (res != null) {
    await GStorage.setting.put(SettingBoxKey.fullScreenMode, res.index);
    setState();
  }
}

Future<void> _showAngleDegreesDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<double>(
    context: context,
    builder: (context) => SliderDialog(
      title: const Text('傾斜角度閾值'),
      min: 10.0,
      max: 90.0,
      divisions: 90,
      precise: 0,
      value: Pref.angleDegrees.toDouble(),
      suffix: '°',
    ),
  );
  if (res != null) {
    await GStorage.setting.put(SettingBoxKey.angleDegrees, res.toInt());
    setState();
  }
}

Future<void> showPlayerVolumeDialog(
  BuildContext context,
  VoidCallback setState, {
  ValueChanged<double>? onChanged,
}) {
  return showVolumeDialog(
    context,
    title: const Text('播放器音量'),
    value: Pref.playerVolume,
    onChanged: (value) => GStorage.setting
        .put(SettingBoxKey.playerVolume, value)
        .whenComplete(() {
          setState();
          onChanged?.call(value);
        }),
  );
}

Future<void> _showMaxVolumeDialog(
  BuildContext context,
  VoidCallback setState,
) {
  return showVolumeDialog(
    context,
    title: const Text('最高音量'),
    value: Pref.maxVolume * 100,
    onChanged: (rawValue) {
      final maxVolume = (rawValue / 100).toPrecision(2);
      if (Pref.desktopVolume > maxVolume) {
        GStorage.setting.put(SettingBoxKey.desktopVolume, maxVolume);
      }
      GStorage.setting
          .put(SettingBoxKey.maxVolume, maxVolume)
          .whenComplete(setState);
    },
  );
}

const kMinVolume = 100.0;
const kMaxVolume = 300.0;

Future<void> showVolumeDialog(
  BuildContext context, {
  required Widget title,
  required double value,
  required ValueChanged<double> onChanged,
}) async {
  final res = await showDialog<double>(
    context: context,
    builder: (context) => SliderDialog(
      title: title,
      min: kMinVolume,
      max: kMaxVolume,
      divisions: 40,
      precise: 0,
      value: value,
      suffix: '%',
    ),
  );
  if (res != null) {
    onChanged(res);
  }
}

Future<void> _showSuperResolutionDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<SuperResolutionType>(
    context: context,
    builder: (context) => SelectDialog<SuperResolutionType>(
      title: '超解析度',
      value: Pref.superResolutionType,
      values: SuperResolutionType.values.map((e) => (e, e.label)).toList(),
    ),
  );
  if (res != null) {
    await GStorage.setting.put(
      SettingBoxKey.superResolutionType,
      res.index,
    );
    setState();
  }
}

Future<void> audioNormalization(
  BuildContext context,
  VoidCallback setState, {
  bool fallback = false,
}) async {
  final key = fallback
      ? SettingBoxKey.fallbackNormalization
      : SettingBoxKey.audioNormalization;
  final res = await showDialog<String>(
    context: context,
    builder: (context) {
      String audioNormalization = fallback
          ? Pref.fallbackNormalization
          : Pref.audioNormalization;
      Set<String> values = {
        '0',
        '1',
        if (!fallback) '2',
        audioNormalization,
        '3',
      };
      return SelectDialog<String>(
        title: fallback ? '伺服器無loudnorm配置時使用' : '音量均衡',
        toggleable: true,
        value: audioNormalization,
        values: values
            .map(
              (e) => (
                e,
                switch (e) {
                  '0' => AudioNormalization.disable.title,
                  '1' => AudioNormalization.dynaudnorm.title,
                  '2' => AudioNormalization.loudnorm.title,
                  '3' => AudioNormalization.custom.title,
                  _ => e,
                },
              ),
            )
            .toList(),
      );
    },
  );
  if (res != null && context.mounted) {
    if (res == '3') {
      String param = '';
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('自定義引數'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 16,
            children: [
              const Text('等同於 --lavfi-complex="[aid1] 引數 [ao]"'),
              TextField(
                autofocus: true,
                onChanged: (value) => param = value,
              ),
            ],
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
              onPressed: () {
                Get.back();
                GStorage.setting.put(key, param);
                if (!fallback &&
                    AudioNormalization.loudnormRegExp.hasMatch(param)) {
                  audioNormalization(context, setState, fallback: true);
                }
                setState();
              },
              child: const Text('確定'),
            ),
          ],
        ),
      );
    } else {
      GStorage.setting.put(key, res);
      if (res == '2') {
        audioNormalization(context, setState, fallback: true);
      }
      setState();
    }
  }
}
