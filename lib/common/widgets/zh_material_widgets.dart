// ignore_for_file: deprecated_member_use

import 'package:PiliPlus/utils/zh_convert.dart';
import 'package:material_ui/material_ui.dart' as material;
import 'package:material_ui/material_ui.dart' show InputDecoration;

// Material widgets that take label text as a String and draw it with
// Flutter's own Text. These versions convert the String to the script of
// the language setting (see ZhConvert). zh_material.dart exports them in
// place of the material_ui ones.

String? _zh(String? text) => text == null ? null : ZhConvert.convert(text);

/// [material.Tab] with the [text] label converted.
class Tab extends material.Tab {
  const Tab({
    super.key,
    super.text,
    super.icon,
    super.iconMargin,
    super.height,
    super.child,
  });

  @override
  String? get text => _zh(super.text);
}

/// [material.TextField] with the hint, label and helper texts of
/// [decoration] converted. The typed text is not changed.
class TextField extends material.TextField {
  const TextField({
    super.key,
    super.groupId,
    super.controller,
    super.focusNode,
    super.undoController,
    super.decoration,
    super.keyboardType,
    super.textInputAction,
    super.textCapitalization,
    super.style,
    super.strutStyle,
    super.textAlign,
    super.textAlignVertical,
    super.textDirection,
    super.readOnly,
    super.toolbarOptions,
    super.showCursor,
    super.autofocus,
    super.statesController,
    super.obscuringCharacter,
    super.obscureText,
    super.autocorrect,
    super.smartDashesType,
    super.smartQuotesType,
    super.enableSuggestions,
    super.maxLines,
    super.minLines,
    super.expands,
    super.maxLength,
    super.maxLengthEnforcement,
    super.onChanged,
    super.onEditingComplete,
    super.onSubmitted,
    super.onAppPrivateCommand,
    super.inputFormatters,
    super.enabled,
    super.ignorePointers,
    super.cursorWidth,
    super.cursorHeight,
    super.cursorRadius,
    super.cursorOpacityAnimates,
    super.cursorColor,
    super.cursorErrorColor,
    super.selectionHeightStyle,
    super.selectionWidthStyle,
    super.keyboardAppearance,
    super.scrollPadding,
    super.dragStartBehavior,
    super.enableInteractiveSelection,
    super.selectAllOnFocus,
    super.selectionControls,
    super.onTap,
    super.onTapAlwaysCalled,
    super.onTapOutside,
    super.onTapUpOutside,
    super.mouseCursor,
    super.buildCounter,
    super.scrollController,
    super.scrollPhysics,
    super.autofillHints,
    super.contentInsertionConfiguration,
    super.clipBehavior,
    super.restorationId,
    super.scribbleEnabled,
    super.stylusHandwritingEnabled,
    super.enableIMEPersonalizedLearning,
    super.enableInlinePrediction,
    super.contextMenuBuilder,
    super.canRequestFocus,
    super.spellCheckConfiguration,
    super.magnifierConfiguration,
    super.hintLocales,
  });

  @override
  InputDecoration? get decoration => zhDecoration(super.decoration);
}

/// Converts the label texts of [decoration].
InputDecoration? zhDecoration(InputDecoration? decoration) {
  if (decoration == null) return null;
  return decoration.copyWith(
    labelText: _zh(decoration.labelText),
    helperText: _zh(decoration.helperText),
    hintText: _zh(decoration.hintText),
    errorText: _zh(decoration.errorText),
    prefixText: _zh(decoration.prefixText),
    suffixText: _zh(decoration.suffixText),
    counterText: _zh(decoration.counterText),
  );
}
