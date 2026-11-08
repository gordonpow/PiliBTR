// ignore_for_file: deprecated_member_use

import 'package:PiliPlus/utils/zh_convert.dart';
import 'package:material_ui/material_ui.dart' as material;
import 'package:material_ui/material_ui.dart'
    show
        AlignmentGeometry,
        BorderSide,
        ButtonShapeVariant,
        ButtonSizeVariant,
        ButtonStyle,
        Color,
        EdgeInsetsGeometry,
        IconButtonWidthVariant,
        InputDecoration,
        InteractiveInkFeatureFactory,
        MaterialTapTargetSize,
        MouseCursor,
        OutlinedBorder,
        Size,
        VisualDensity;

// Material widgets that take label text as a String and draw it with
// Flutter's own Text. These versions convert the String to the script of
// the language setting (see ZhConvert). zh_material.dart exports them in
// place of the material_ui ones.

String? _zh(String? text) => text == null ? null : ZhConvert.convert(text);

/// [material.Tooltip] with the [message] converted.
class Tooltip extends material.Tooltip {
  const Tooltip({
    super.key,
    super.message,
    super.richMessage,
    super.height,
    super.constraints,
    super.padding,
    super.margin,
    super.verticalOffset,
    super.preferBelow,
    super.excludeFromSemantics,
    super.decoration,
    super.textStyle,
    super.textAlign,
    super.waitDuration,
    super.showDuration,
    super.exitDuration,
    super.enableTapToDismiss,
    super.triggerMode,
    super.enableFeedback,
    super.onTriggered,
    super.mouseCursor,
    super.ignorePointer,
    super.positionDelegate,
    super.child,
  });

  @override
  String? get message => _zh(super.message);
}

/// [material.IconButton] with the [tooltip] converted.
class IconButton extends material.IconButton {
  const IconButton({
    super.key,
    super.iconSize,
    super.visualDensity,
    super.padding,
    super.alignment,
    super.splashRadius,
    super.color,
    super.focusColor,
    super.hoverColor,
    super.highlightColor,
    super.splashColor,
    super.disabledColor,
    required super.onPressed,
    super.onHover,
    super.onLongPress,
    super.mouseCursor,
    super.focusNode,
    super.autofocus,
    super.tooltip,
    super.enableFeedback,
    super.constraints,
    super.style,
    super.isSelected,
    super.selectedIcon,
    super.statesController,
    required super.icon,
  });

  const IconButton.outlined({
    super.key,
    super.iconSize,
    super.visualDensity,
    super.padding,
    super.alignment,
    super.splashRadius,
    super.color,
    super.focusColor,
    super.hoverColor,
    super.highlightColor,
    super.splashColor,
    super.disabledColor,
    required super.onPressed,
    super.onHover,
    super.onLongPress,
    super.mouseCursor,
    super.focusNode,
    super.autofocus,
    super.tooltip,
    super.enableFeedback,
    super.constraints,
    super.style,
    super.isSelected,
    super.selectedIcon,
    super.statesController,
    required super.icon,
  }) : super.outlined();

  const IconButton.filled({
    super.key,
    super.iconSize,
    super.visualDensity,
    super.padding,
    super.alignment,
    super.splashRadius,
    super.color,
    super.focusColor,
    super.hoverColor,
    super.highlightColor,
    super.splashColor,
    super.disabledColor,
    required super.onPressed,
    super.onHover,
    super.onLongPress,
    super.mouseCursor,
    super.focusNode,
    super.autofocus,
    super.tooltip,
    super.enableFeedback,
    super.constraints,
    super.style,
    super.isSelected,
    super.selectedIcon,
    super.statesController,
    required super.icon,
  }) : super.filled();

  const IconButton.filledTonal({
    super.key,
    super.iconSize,
    super.visualDensity,
    super.padding,
    super.alignment,
    super.splashRadius,
    super.color,
    super.focusColor,
    super.hoverColor,
    super.highlightColor,
    super.splashColor,
    super.disabledColor,
    required super.onPressed,
    super.onHover,
    super.onLongPress,
    super.mouseCursor,
    super.focusNode,
    super.autofocus,
    super.tooltip,
    super.enableFeedback,
    super.constraints,
    super.style,
    super.isSelected,
    super.selectedIcon,
    super.statesController,
    required super.icon,
  }) : super.filledTonal();

  /// Same as [material.IconButton.styleFrom] (statics are not inherited).
  static ButtonStyle styleFrom({
    Color? foregroundColor,
    Color? backgroundColor,
    Color? disabledForegroundColor,
    Color? disabledBackgroundColor,
    Color? focusColor,
    Color? hoverColor,
    Color? highlightColor,
    Color? shadowColor,
    Color? surfaceTintColor,
    Color? overlayColor,
    double? elevation,
    Size? minimumSize,
    Size? fixedSize,
    Size? maximumSize,
    double? iconSize,
    BorderSide? side,
    OutlinedBorder? shape,
    EdgeInsetsGeometry? padding,
    MouseCursor? enabledMouseCursor,
    MouseCursor? disabledMouseCursor,
    VisualDensity? visualDensity,
    MaterialTapTargetSize? tapTargetSize,
    Duration? animationDuration,
    bool? enableFeedback,
    AlignmentGeometry? alignment,
    InteractiveInkFeatureFactory? splashFactory,
    ButtonSizeVariant? sizeVariant,
    IconButtonWidthVariant? iconButtonWidth,
    ButtonShapeVariant? shapeVariant,
  }) => material.IconButton.styleFrom(
    foregroundColor: foregroundColor,
    backgroundColor: backgroundColor,
    disabledForegroundColor: disabledForegroundColor,
    disabledBackgroundColor: disabledBackgroundColor,
    focusColor: focusColor,
    hoverColor: hoverColor,
    highlightColor: highlightColor,
    shadowColor: shadowColor,
    surfaceTintColor: surfaceTintColor,
    overlayColor: overlayColor,
    elevation: elevation,
    minimumSize: minimumSize,
    fixedSize: fixedSize,
    maximumSize: maximumSize,
    iconSize: iconSize,
    side: side,
    shape: shape,
    padding: padding,
    enabledMouseCursor: enabledMouseCursor,
    disabledMouseCursor: disabledMouseCursor,
    visualDensity: visualDensity,
    tapTargetSize: tapTargetSize,
    animationDuration: animationDuration,
    enableFeedback: enableFeedback,
    alignment: alignment,
    splashFactory: splashFactory,
    sizeVariant: sizeVariant,
    iconButtonWidth: iconButtonWidth,
    shapeVariant: shapeVariant,
  );

  @override
  String? get tooltip => _zh(super.tooltip);
}

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
