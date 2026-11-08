import 'package:PiliPlus/common/widgets/zh_text.dart' show Text;
import 'package:PiliPlus/services/translate/content_translator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/widgets.dart' as flutter show Text;

/// Keeps a widget state subscribed to [ContentTranslator.enabled] and to the
/// translation of one sentence. It never calls back after [dispose].
class _ContentBinding {
  _ContentBinding(this._onChange);

  final VoidCallback _onChange;
  ValueListenable<String?>? _sentence;
  String? _text;
  ContentPriority _priority = ContentPriority.high;
  bool _disposed = false;

  void init(String? text, ContentPriority priority) {
    ContentTranslator.enabled.addListener(_onEnabled);
    bind(text, priority);
  }

  /// (Re)subscribes for [text]. Call when the text or priority changed.
  void bind(String? text, ContentPriority priority) {
    _unbindSentence();
    _text = text;
    _priority = priority;
    if (text == null || !ContentTranslator.isEnabled) return;
    if (!ContentTranslator.needsTranslation(text)) return;
    final s = ContentTranslator.listen(text);
    _sentence = s..addListener(_onSentence);
    if (s.value == null) ContentTranslator.request(text, priority: priority);
  }

  /// The translation to show, or null for the original.
  String? get translated =>
      ContentTranslator.isEnabled ? _sentence?.value : null;

  void _onEnabled() {
    if (_disposed) return;
    bind(_text, _priority);
    _onChange();
  }

  void _onSentence() {
    if (_disposed) return;
    _onChange();
  }

  void _unbindSentence() {
    _sentence?.removeListener(_onSentence);
    _sentence = null;
  }

  void dispose() {
    _disposed = true;
    ContentTranslator.enabled.removeListener(_onEnabled);
    _unbindSentence();
  }
}

/// Builds with the translation of [text] when there is one. [builder] gets
/// the text to show and whether it is a translation.
class ContentTextBuilder extends StatefulWidget {
  const ContentTextBuilder({
    super.key,
    required this.text,
    required this.builder,
    this.priority = ContentPriority.high,
  });

  final String? text;
  final ContentPriority priority;
  final Widget Function(BuildContext context, String? shown, bool translated)
  builder;

  @override
  State<ContentTextBuilder> createState() => _ContentTextBuilderState();
}

class _ContentTextBuilderState extends State<ContentTextBuilder> {
  late final _ContentBinding _binding;

  @override
  void initState() {
    super.initState();
    _binding = _ContentBinding(_update)..init(widget.text, widget.priority);
  }

  void _update() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(ContentTextBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.priority != widget.priority) {
      _binding.bind(widget.text, widget.priority);
    }
  }

  @override
  void dispose() {
    _binding.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _binding.translated;
    return widget.builder(context, t ?? widget.text, t != null);
  }
}

/// Drop-in replacement of [Text] for server content: in English mode it
/// shows the translation of [text] (the original until it is translated).
class ContentText extends StatelessWidget {
  const ContentText(
    this.text, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.priority = ContentPriority.high,
  });

  final String text;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final ContentPriority priority;

  @override
  Widget build(BuildContext context) {
    return ContentTextBuilder(
      text: text,
      priority: priority,
      builder: (context, shown, translated) {
        // A translation is plain English: use Flutter's Text, which skips
        // the Chinese script conversion.
        if (translated) {
          return flutter.Text(
            shown!,
            style: style,
            strutStyle: strutStyle,
            textAlign: textAlign,
            softWrap: softWrap,
            overflow: overflow,
            textScaler: textScaler,
            maxLines: maxLines,
            textWidthBasis: textWidthBasis,
            textHeightBehavior: textHeightBehavior,
          );
        }
        return Text(
          text,
          style: style,
          strutStyle: strutStyle,
          textAlign: textAlign,
          softWrap: softWrap,
          overflow: overflow,
          textScaler: textScaler,
          maxLines: maxLines,
          textWidthBasis: textWidthBasis,
          textHeightBehavior: textHeightBehavior,
        );
      },
    );
  }
}

/// A smaller gray line with the translation of [text], to put under rich
/// content (which keeps its original text). Hidden when [text] has no
/// Chinese or is not translated yet.
class ContentTranslationLine extends StatelessWidget {
  const ContentTranslationLine(
    this.text, {
    super.key,
    this.style,
    this.priority = ContentPriority.low,
    this.padding = const EdgeInsets.only(top: 4),
    this.maxLines,
  });

  final String? text;
  final TextStyle? style;
  final ContentPriority priority;
  final EdgeInsetsGeometry padding;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    if (!ContentTranslator.needsTranslation(text)) {
      return const SizedBox.shrink();
    }
    return ContentTextBuilder(
      text: text,
      priority: priority,
      builder: (context, shown, translated) {
        if (!translated) return const SizedBox.shrink();
        final base = TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.outline,
        );
        return Padding(
          padding: padding,
          child: flutter.Text(
            shown!,
            style: style == null ? base : base.merge(style),
            maxLines: maxLines,
            overflow: maxLines == null ? null : TextOverflow.ellipsis,
          ),
        );
      },
    );
  }
}
