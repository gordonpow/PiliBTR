import 'dart:io';

import 'package:PiliPlus/models/common/video/base_quality.dart';
import 'package:PiliPlus/models/common/video/video_decode_type.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/pages/setting/widgets/cdn_settings_dialog.dart';
import 'package:PiliPlus/pages/setting/widgets/ordered_multi_select_dialog.dart';
import 'package:PiliPlus/pages/setting/widgets/select_dialog.dart';
import 'package:PiliPlus/plugin/pl_player/models/audio_output_type.dart';
import 'package:PiliPlus/plugin/pl_player/models/hwdec_type.dart';
import 'package:PiliPlus/utils/cdn_choice.dart';
import 'package:PiliPlus/utils/filtering_text.dart';
import 'package:PiliPlus/utils/speed_format.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/video_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:PiliPlus/common/widgets/zh_material.dart';

List<SettingsModel> get videoSettings => [
  const SwitchModel(
    title: '開啟硬解',
    subtitle: '以較低功耗播放影片，若異常卡死請關閉',
    leading: Icon(Icons.flash_on_outlined),
    setKey: SettingBoxKey.enableHA,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '免登入1080P',
    subtitle: '免登入檢視1080P影片',
    leading: Icon(Icons.hd_outlined),
    setKey: SettingBoxKey.p1080,
    defaultVal: true,
  ),
  NormalModel(
    title: 'B站定向流量支援',
    subtitle: '若套餐含B站定向流量，則會自動使用。可查閱運營商的流量記錄確認。',
    leading: const Icon(Icons.perm_data_setting_outlined),
    getTrailing: (theme) => IgnorePointer(
      child: Transform.scale(
        scale: 0.8,
        alignment: Alignment.centerRight,
        child: Switch(
          value: true,
          onChanged: (_) {},
          thumbIcon: WidgetStateProperty.all(
            const Icon(Icons.lock_outline_rounded),
          ),
        ),
      ),
    ),
  ),
  NormalModel(
    title: 'CDN 設定',
    leading: const Icon(MdiIcons.cloudPlusOutline),
    getSubtitle: () => '當前使用：${cdnChoiceLabel()}，部分 CDN 可能失效，如無法播放請嘗試切換',
    onTap: _showCDNDialog,
  ),
  NormalModel(
    title: '直播 CDN 設定',
    leading: const Icon(MdiIcons.cloudPlusOutline),
    getSubtitle: () => '當前使用：${Pref.liveCdnUrl ?? "預設"}',
    onTap: _showLiveCDNDialog,
  ),
  const SwitchModel(
    title: 'CDN 測速',
    leading: Icon(Icons.speed),
    subtitle: '測速通過模擬載入影片實現，注意流量消耗，結果僅供參考',
    setKey: SettingBoxKey.cdnSpeedTest,
    defaultVal: true,
  ),
  NormalModel(
    title: '網速單位',
    leading: const Icon(Icons.speed),
    getSubtitle: () => '當前：${speedUnitLabels[Pref.speedUnit]}',
    onTap: _showSpeedUnitDialog,
  ),
  SwitchModel(
    title: '音訊不跟隨 CDN 設定',
    subtitle: '直接採用備用 URL，可解決部分影片無聲',
    leading: const Icon(MdiIcons.musicNotePlus),
    setKey: SettingBoxKey.disableAudioCDN,
    defaultVal: false,
    onChanged: (value) => VideoUtils.disableAudioCDN = value,
  ),
  NormalModel(
    title: '預設畫質',
    leading: const Icon(Icons.video_settings_outlined),
    getSubtitle: () =>
        '當前畫質：${VideoQuality.fromCode(Pref.defaultVideoQa).desc}',
    onTap: _showVideoQaDialog,
  ),
  NormalModel(
    title: '蜂窩網路畫質',
    leading: const Icon(Icons.video_settings_outlined),
    getSubtitle: () =>
        '當前畫質：${VideoQuality.fromCode(Pref.defaultVideoQaCellular).desc}',
    onTap: _showVideoCellularQaDialog,
  ),
  NormalModel(
    title: '預設音質',
    leading: const Icon(Icons.music_video_outlined),
    getSubtitle: () =>
        '當前音質：${AudioQuality.fromCode(Pref.defaultAudioQa).desc}',
    onTap: _showAudioQaDialog,
  ),
  NormalModel(
    title: '蜂窩網路音質',
    leading: const Icon(Icons.music_video_outlined),
    getSubtitle: () =>
        '當前音質：${AudioQuality.fromCode(Pref.defaultAudioQaCellular).desc}',
    onTap: _showAudioCellularQaDialog,
  ),
  NormalModel(
    title: '直播預設畫質',
    leading: const Icon(Icons.video_settings_outlined),
    getSubtitle: () => '當前畫質：${LiveQuality.fromCode(Pref.liveQuality).desc}',
    onTap: _showLiveQaDialog,
  ),
  NormalModel(
    title: '蜂窩網路直播預設畫質',
    leading: const Icon(Icons.video_settings_outlined),
    getSubtitle: () =>
        '當前畫質：${LiveQuality.fromCode(Pref.liveQualityCellular).desc}',
    onTap: _showLiveCellularQaDialog,
  ),
  NormalModel(
    title: '首選解碼格式',
    leading: const Icon(Icons.movie_creation_outlined),
    getSubtitle: () =>
        '首選解碼格式：${(Pref.preferCodecs.map((i) => i.name).join(","))}，請根據裝置支援情況與需求調整',
    onTap: _showCodecsDialog,
  ),
  NormalModel(
    title: '蜂窩網路首選解碼格式',
    leading: const Icon(Icons.movie_creation_outlined),
    getSubtitle: () =>
        '首選解碼格式：${(Pref.preferCodecsCellular.map((i) => i.name).join(","))}，請根據裝置支援情況與需求調整',
    onTap: _showCellularCodecsDialog,
  ),
  if (kDebugMode || Platform.isAndroid)
    NormalModel(
      title: '音訊輸出裝置',
      leading: const Icon(Icons.speaker_outlined),
      getSubtitle: () => '當前：${Pref.audioOutput}',
      onTap: _showAudioOutputDialog,
    ),
  NormalModel(
    title: '緩衝大小',
    leading: const Icon(Icons.storage_outlined),
    getSubtitle: () =>
        '當前：${Pref.bufferSize}MB。點播影片的前向和後向緩衝區大小（此選項即mpv的--demuxer-max-bytes，--demuxer-max-back-bytes）。直播流請設定下方的直播緩衝大小',
    onTap: _showBufferSizeDialog,
  ),
  NormalModel(
    title: '緩衝時長',
    leading: const Icon(Icons.av_timer),
    getSubtitle: () =>
        '當前：${Pref.bufferSec}s。點播影片的實際緩衝為大小與時長二者的最小值（此選項即mpv的--cache-secs）。直播流該選項無效，請設定下方的直播緩衝時長',
    onTap: _showBufferSecDialog,
  ),
  NormalModel(
    title: '直播緩衝大小',
    leading: const Icon(Icons.storage_outlined),
    getSubtitle: () =>
        '當前：${Pref.liveBufferSize > 0 ? '${Pref.liveBufferSize}MB' : '跟隨緩衝大小（${(Pref.bufferSize * 2).toStringAsFixed(0)}MB）'}。僅對直播流生效，小於等於0時使用緩衝大小的2倍（此選項即mpv的--demuxer-max-bytes）',
    onTap: _showLiveBufferSizeDialog,
  ),
  NormalModel(
    title: '直播緩衝時長',
    leading: const Icon(Icons.av_timer),
    getSubtitle: () =>
        '當前：${Pref.liveBufferSec > 0 ? '${Pref.liveBufferSec}s' : '不限制'}。僅對直播流生效，大於0時可限制直播緩衝時長以降低延遲（此選項即mpv的--cache-secs）',
    onTap: _showLiveBufferSecDialog,
  ),
  NormalModel(
    title: '自動同步',
    leading: const Icon(Icons.sync_rounded),
    getSubtitle: () => '當前：${Pref.autosync}（此項即mpv的--autosync）',
    onTap: _showAutoSyncDialog,
  ),
  NormalModel(
    title: '影片同步',
    leading: const Icon(Icons.view_timeline_outlined),
    getSubtitle: () => '當前：${Pref.videoSync}（此項即mpv的--video-sync）',
    onTap: _showVideoSyncDialog,
  ),
  NormalModel(
    title: '硬解模式',
    leading: const Icon(Icons.memory_outlined),
    getSubtitle: () => '當前：${Pref.hardwareDecoding}（此項即mpv的--hwdec）',
    onTap: _showHwDecDialog,
  ),
];

Future<void> _showCDNDialog(BuildContext context, VoidCallback setState) async {
  await showDialog<void>(
    context: context,
    builder: (context) => const CdnSettingsDialog(),
  );
  setState();
}

Future<void> _showLiveCDNDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  String host = Pref.liveCdnUrl ?? '';
  String? res = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('輸入CDN host'),
      content: TextFormField(
        initialValue: host,
        autofocus: true,
        onChanged: (value) => host = value,
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
          onPressed: () => Get.back(result: host),
          child: const Text('確定'),
        ),
      ],
    ),
  );
  if (res != null) {
    if (res.isEmpty) {
      res = null;
      await GStorage.setting.delete(SettingBoxKey.liveCdnUrl);
    } else {
      if (!res.startsWith('http')) {
        res = 'https://$res';
      }
      await GStorage.setting.put(SettingBoxKey.liveCdnUrl, res);
    }
    VideoUtils.liveCdnUrl = res;
    setState();
  }
}

Future<void> _showSpeedUnitDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<int>(
    context: context,
    builder: (context) => SelectDialog<int>(
      title: '網速單位',
      value: Pref.speedUnit,
      values: [
        for (var i = 0; i < speedUnitLabels.length; i++)
          (i, speedUnitLabels[i]),
      ],
    ),
  );
  if (res != null) {
    await GStorage.setting.put(SettingBoxKey.speedUnit, res);
    setState();
  }
}

Future<void> _showVideoQaDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<int>(
    context: context,
    builder: (context) => SelectDialog<int>(
      title: '預設畫質',
      value: Pref.defaultVideoQa,
      values: VideoQuality.values.map((e) => (e.code, e.desc)).toList(),
    ),
  );
  if (res != null) {
    await GStorage.setting.put(SettingBoxKey.defaultVideoQa, res);
    setState();
  }
}

Future<void> _showVideoCellularQaDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<int>(
    context: context,
    builder: (context) => SelectDialog<int>(
      title: '蜂窩網路畫質',
      value: Pref.defaultVideoQaCellular,
      values: VideoQuality.values.map((e) => (e.code, e.desc)).toList(),
    ),
  );
  if (res != null) {
    await GStorage.setting.put(
      SettingBoxKey.defaultVideoQaCellular,
      res,
    );
    setState();
  }
}

Future<void> _showAudioQaDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<int>(
    context: context,
    builder: (context) => SelectDialog<int>(
      title: '預設音質',
      value: Pref.defaultAudioQa,
      values: AudioQuality.values.map((e) => (e.code, e.desc)).toList(),
    ),
  );
  if (res != null) {
    await GStorage.setting.put(SettingBoxKey.defaultAudioQa, res);
    setState();
  }
}

Future<void> _showAudioCellularQaDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<int>(
    context: context,
    builder: (context) => SelectDialog<int>(
      title: '蜂窩網路音質',
      value: Pref.defaultAudioQaCellular,
      values: AudioQuality.values.map((e) => (e.code, e.desc)).toList(),
    ),
  );
  if (res != null) {
    await GStorage.setting.put(
      SettingBoxKey.defaultAudioQaCellular,
      res,
    );
    setState();
  }
}

Future<void> _showLiveQaDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<int>(
    context: context,
    builder: (context) => SelectDialog<int>(
      title: '直播預設畫質',
      value: Pref.liveQuality,
      values: LiveQuality.values.map((e) => (e.code, e.desc)).toList(),
    ),
  );
  if (res != null) {
    await GStorage.setting.put(SettingBoxKey.liveQuality, res);
    setState();
  }
}

Future<void> _showLiveCellularQaDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<int>(
    context: context,
    builder: (context) => SelectDialog<int>(
      title: '蜂窩網路直播預設畫質',
      value: Pref.liveQualityCellular,
      values: LiveQuality.values.map((e) => (e.code, e.desc)).toList(),
    ),
  );
  if (res != null) {
    await GStorage.setting.put(SettingBoxKey.liveQualityCellular, res);
    setState();
  }
}

Future<void> _showCodecsDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<List<VideoDecodeFormatType>>(
    context: context,
    builder: (context) => OrderedMultiSelectDialog<VideoDecodeFormatType>(
      title: const Text('首選解碼格式'),
      initValues: Pref.preferCodecs,
      values: {for (final e in VideoDecodeFormatType.values) e: e.name},
    ),
  );
  if (res != null && res.isNotEmpty) {
    await GStorage.setting.put(
      SettingBoxKey.preferCodecs,
      res.map((i) => i.name).toList(),
    );
    setState();
  }
}

Future<void> _showCellularCodecsDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<List<VideoDecodeFormatType>>(
    context: context,
    builder: (context) => OrderedMultiSelectDialog<VideoDecodeFormatType>(
      title: const Text('蜂窩網路首選解碼格式'),
      initValues: Pref.preferCodecsCellular,
      values: {for (final e in VideoDecodeFormatType.values) e: e.name},
    ),
  );
  if (res != null && res.isNotEmpty) {
    await GStorage.setting.put(
      SettingBoxKey.preferCodecsCellular,
      res.map((i) => i.name).toList(),
    );
    setState();
  }
}

Future<void> _showAudioOutputDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<List<String>>(
    context: context,
    builder: (context) => OrderedMultiSelectDialog<String>(
      title: const Text('音訊輸出裝置'),
      initValues: Pref.audioOutput.split(','),
      values: {
        for (final e in AudioOutput.values) e.name: e.label,
      },
    ),
  );
  if (res != null && res.isNotEmpty) {
    await GStorage.setting.put(
      SettingBoxKey.audioOutput,
      res.join(','),
    );
    setState();
  }
}

Future<void> _showVideoSyncDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<String>(
    context: context,
    builder: (context) => SelectDialog<String>(
      title: '影片同步',
      value: Pref.videoSync,
      values: const [
        'audio',
        'display-resample',
        'display-resample-vdrop',
        'display-resample-desync',
        'display-tempo',
        'display-vdrop',
        'display-adrop',
        'display-desync',
        'desync',
      ].map((e) => (e, e)).toList(),
    ),
  );
  if (res != null) {
    await GStorage.setting.put(SettingBoxKey.videoSync, res);
    setState();
  }
}

Future<void> _showHwDecDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<List<String>>(
    context: context,
    builder: (context) => OrderedMultiSelectDialog<String>(
      title: const Text('硬解模式'),
      initValues: Pref.hardwareDecoding.split(','),
      values: {
        for (final e in HwDecType.values) e.hwdec: '${e.hwdec}\n${e.desc}',
      },
    ),
  );
  if (res != null && res.isNotEmpty) {
    await GStorage.setting.put(
      SettingBoxKey.hardwareDecoding,
      res.join(','),
    );
    setState();
  }
}

void _showAutoSyncDialog(BuildContext context, VoidCallback setState) {
  String autosync = Pref.autosync.toString();
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('自動同步'),
      content: TextFormField(
        autofocus: true,
        initialValue: autosync,
        keyboardType: TextInputType.number,
        onChanged: (value) => autosync = value,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
              // validate
              int.parse(autosync);
              Get.back();
              await GStorage.setting.put(SettingBoxKey.autosync, autosync);
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

void _showDecimalDialog(
  BuildContext context,
  VoidCallback setState, {
  required String key,
  required double defVal,
  required String title,
  required String? suffix,
}) {
  String value = (GStorage.setting.get(key) ?? defVal).toString();
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextFormField(
        autofocus: true,
        initialValue: value,
        keyboardType: const .numberWithOptions(decimal: true),
        onChanged: (val) => value = val,
        inputFormatters: FilteringText.decimal,
        decoration: suffix == null ? null : InputDecoration(suffixText: suffix),
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
              final val = double.parse(value);
              Get.back();
              await GStorage.setting.put(key, val);
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

void _showBufferSizeDialog(BuildContext context, VoidCallback setState) =>
    _showDecimalDialog(
      context,
      setState,
      key: SettingBoxKey.bufferSize,
      defVal: Pref.bufferSize,
      title: '緩衝大小',
      suffix: 'MB',
    );

void _showBufferSecDialog(BuildContext context, VoidCallback setState) =>
    _showDecimalDialog(
      context,
      setState,
      key: SettingBoxKey.bufferSec,
      defVal: Pref.bufferSec,
      title: '緩衝時長',
      suffix: 's',
    );

void _showLiveBufferSizeDialog(BuildContext context, VoidCallback setState) =>
    _showDecimalDialog(
      context,
      setState,
      key: SettingBoxKey.liveBufferSize,
      defVal: Pref.liveBufferSize,
      title: '直播緩衝大小',
      suffix: 'MB',
    );

void _showLiveBufferSecDialog(BuildContext context, VoidCallback setState) =>
    _showDecimalDialog(
      context,
      setState,
      key: SettingBoxKey.liveBufferSec,
      defVal: Pref.liveBufferSec,
      title: '直播緩衝時長',
      suffix: 's',
    );
