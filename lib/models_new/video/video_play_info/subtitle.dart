import 'package:PiliPlus/utils/storage_pref.dart';

class Subtitle implements Comparable<Subtitle> {
  late String lan;
  String? lanDoc;
  String? subtitleUrl;
  String? subtitleUrlV2;
  bool isAi = false;

  Subtitle({
    required this.lan,
    this.lanDoc,
    this.subtitleUrl,
    this.isAi = false,
  });

  Subtitle.fromJson(Map<String, dynamic> json) {
    lan = json["lan"];
    isAi = json["type"] == 1;
    lanDoc = '${json["lan_doc"]}${isAi ? '（AI）' : ''}';
    subtitleUrl = json["subtitle_url"];
    subtitleUrlV2 = json["subtitle_url_v2"];
  }

  /// English track: `en`, `en-US`, `ai-en`, ...
  bool get isEnglish => lan.startsWith('en') || lan == 'ai-en';

  /// Chinese track: `zh-CN`, `ai-zh`, ...
  bool get isChinese => lan.contains('zh');

  @override
  int compareTo(Subtitle other) =>
      compareWith(other, englishFirst: Pref.appLanguage == 3);

  /// With [englishFirst] (English UI mode) English tracks sort before the
  /// rest; otherwise Chinese first, then non-AI first.
  int compareWith(Subtitle other, {required bool englishFirst}) {
    if (englishFirst && isEnglish != other.isEnglish) {
      return isEnglish ? -1 : 1;
    }
    final thisHasZh = lan.contains('zh');
    final otherHasZh = other.lan.contains('zh');
    if (thisHasZh != otherHasZh) return thisHasZh ? -1 : 1;
    if (isAi != other.isAi) return isAi ? 1 : -1;
    return 0;
  }
}
