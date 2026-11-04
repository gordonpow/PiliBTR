import 'package:PiliPlus/pages/setting/models/dm_settings.dart';
import 'package:PiliPlus/pages/setting/models/dyn_settings.dart';
import 'package:PiliPlus/pages/setting/models/extra_settings.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/pages/setting/models/play_settings.dart';
import 'package:PiliPlus/pages/setting/models/privacy_settings.dart';
import 'package:PiliPlus/pages/setting/models/recommend_settings.dart';
import 'package:PiliPlus/pages/setting/models/reply_settings.dart';
import 'package:PiliPlus/pages/setting/models/style_settings.dart';
import 'package:PiliPlus/pages/setting/models/video_settings.dart';

enum SettingType {
  privacySetting('隱私設定'),
  recommendSetting('推薦流設定'),
  videoSetting('音影片設定'),
  playSetting('播放器設定'),
  dmSetting('彈幕設定'),
  replySetting('評論設定'),
  dynSetting('動態設定'),
  styleSetting('外觀設定'),
  extraSetting('其它設定'),
  webdavSetting('WebDAV 設定'),
  about('關於'),
  ;

  final String title;
  const SettingType(this.title);

  List<SettingsModel> get settings => switch (this) {
    .privacySetting => privacySettings,
    .recommendSetting => recommendSettings,
    .videoSetting => videoSettings,
    .playSetting => playSettings,
    .dmSetting => dmSettings,
    .dynSetting => dynSettings,
    .replySetting => replySettings,
    .styleSetting => styleSettings,
    .extraSetting => extraSettings,
    .webdavSetting || .about => throw UnimplementedError(),
  };
}
