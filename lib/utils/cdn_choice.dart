import 'package:PiliPlus/services/download/btr_config.dart';
import 'package:PiliPlus/services/download/btr_proxy.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/video_utils.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

/// Label of what plays the video: BTR (multi-CDN) or one CDN node.
String cdnChoiceLabel() => BtrConfig.playback
    ? '線程撕裂者（${BtrConfig.cdnMode.label}）'
    : VideoUtils.cdnService.desc;

/// Changes when a CDN setting that affects playback changes. Compare the
/// value before and after the CDN settings dialog to know if the video
/// must load again.
String cdnSignature() => [
  BtrConfig.playback,
  BtrConfig.cdnMode.index,
  BtrConfig.customCdn.join(','),
  BtrConfig.playbackThreads,
  VideoUtils.cdnService.name,
].join('|');

/// Turns BTR playback on or off. Off means one CDN node plays the video:
/// only one of the two is on. Returns false when BTR cannot be turned on
/// (custom mode without nodes).
Future<bool> setBtrPlayback(bool on) async {
  if (on == BtrConfig.playback) return true;
  if (on &&
      BtrConfig.cdnMode == BtrCdnMode.custom &&
      BtrConfig.customCdn.isEmpty) {
    SmartDialog.showToast('請先線上程撕裂者設定中輸入自定義節點');
    return false;
  }
  await GStorage.setting.put(SettingBoxKey.btrPlayback, on);
  BtrProxy.reset();
  return true;
}
