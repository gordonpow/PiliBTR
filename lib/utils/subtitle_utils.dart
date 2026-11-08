import 'package:PiliPlus/models/common/enum_with_label.dart';
import 'package:collection/collection.dart' show IterableExtension;

enum SubtitleFormat implements EnumWithLabel {
  json('JSON'),
  vtt('WEBVTT'),
  srt('SRT');

  @override
  final String label;
  const SubtitleFormat(this.label);
}

/// Format used when copying subtitles to the clipboard.
enum SubtitleCopyFormat {
  plain('純文字'),
  timed('含時間文字'),
  srt('SRT');

  final String label;
  const SubtitleCopyFormat(this.label);
}

abstract final class SubtitleUtils {
  /// One cue per line, no times.
  static String json2Plain(List list) =>
      list.map((e) => e['content'].toString().trim()).join('\n');

  static String _shortTime(num seconds) {
    final t = seconds.toInt();
    final h = t ~/ 3600;
    final m = ((t % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (t % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  /// One cue per line, prefixed with `[mm:ss]` (`[h:mm:ss]` for >= 1 hour).
  static String json2Timed(List list) => list
      .map(
        (e) => '[${_shortTime(e['from'])}] ${e['content'].toString().trim()}',
      )
      .join('\n');

  static String convert(List list, SubtitleCopyFormat format) =>
      switch (format) {
        SubtitleCopyFormat.plain => json2Plain(list),
        SubtitleCopyFormat.timed => json2Timed(list),
        SubtitleCopyFormat.srt => json2Srt(list),
      };

  static String _vttTimecode(num seconds) {
    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    seconds %= 3600;
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    seconds %= 60;
    final sms = seconds.toStringAsFixed(3).padLeft(6, '0');
    return "$h:$m:$sms";
  }

  static String json2Vtt(List list) {
    final sb = StringBuffer('WEBVTT\n\n')
      ..writeAll(
        list.map(
          (item) =>
              '${_vttTimecode(item['from'])} --> ${_vttTimecode(item['to'])}\n${item['content'].trim()}',
        ),
        '\n\n',
      );
    return sb.toString();
  }

  static String _srtTimecode(num seconds) {
    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    seconds %= 3600;
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    seconds %= 60;
    final s = seconds.toInt();
    final ms = ((seconds - s) * 1000).round().toString().padLeft(3, '0');
    return '$h:$m:${s.toString().padLeft(2, '0')},$ms';
  }

  static String json2Srt(List list) {
    final sb = StringBuffer()
      ..writeAll(
        list.mapIndexed(
          (i, e) =>
              '${i + 1}\n${_srtTimecode(e['from'])} --> ${_srtTimecode(e['to'])}\n${e['content'].trim()}',
        ),
        '\n\n',
      );
    return sb.toString();
  }
}
