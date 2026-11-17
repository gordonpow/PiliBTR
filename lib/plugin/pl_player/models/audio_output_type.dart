import 'package:PiliPlus/models/common/enum_with_label.dart';

/// mpv 的 Android 音訊輸出（`ao`）。清單依序嘗試，第一個能用的生效。
enum AudioOutput implements EnumWithLabel {
  opensles('OpenSL ES'),
  audiotrack('AudioTrack'),
  // AAudio 放最後：部分裝置（三星 S 系列等）用 AAudio 時，跳轉進度後
  // 影片畫面會永久停住、聲音繼續（上游 PiliPlus #2544）。
  aaudio('AAudio'),
  ;

  static final defaultValue = values.map((e) => e.name).join(',');

  /// 舊版的預設值（AAudio 排在 AudioTrack 前面）。存成這個值的設定
  /// 視為沒有自訂，改用新的 [defaultValue]。
  static const oldDefaultValue = 'opensles,aaudio,audiotrack';

  @override
  final String label;
  const AudioOutput(this.label);
}
