import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Modo do campo — alinhado ao Gestão Yahweh (formulários simples e rápidos no Android).
enum FastTextFieldKind {
  /// Texto geral (título, local, etc.).
  standard,

  /// Parágrafos (resumo, divulgação) — mantém autocorreção como no Yahweh.
  prose,

  /// Busca / filtro — sem sugestões (máxima velocidade do Gboard).
  search,

  email,
  url,
  multiline,
}

/// Campo de texto com IME leve no Android — mesmo espírito do mural/avisos Yahweh.
class FastTextField extends StatelessWidget {
  const FastTextField({
    super.key,
    required this.controller,
    this.focusNode,
    this.decoration,
    this.kind = FastTextFieldKind.standard,
    this.keyboardType,
    this.maxLines = 1,
    this.minLines,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    this.onTapOutside,
    this.onTap,
    this.readOnly = false,
    this.obscureText = false,
    this.autofocus = false,
    this.inputFormatters,
    this.textCapitalization,
    this.style,
    this.enabled = true,
    this.scrollPadding = const EdgeInsets.all(20.0),
    this.autocorrect,
    this.enableSuggestions,
    this.enableIMEPersonalizedLearning,
    this.spellCheckConfiguration,
    this.smartDashesType,
    this.smartQuotesType,
    this.autofillHints,
    this.maxLength,
    this.maxLengthEnforcement,
    this.contextMenuBuilder,
    this.onEditingComplete,
    this.cursorColor,
    this.validator,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final InputDecoration? decoration;
  final FastTextFieldKind kind;
  /// Sobrescreve o tipo derivado de [kind] (ex.: número, data).
  final TextInputType? keyboardType;
  final int maxLines;
  final int? minLines;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final TapRegionCallback? onTapOutside;
  final GestureTapCallback? onTap;
  final bool readOnly;
  final bool obscureText;
  final bool autofocus;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization? textCapitalization;
  final TextStyle? style;
  final bool enabled;
  final EdgeInsets scrollPadding;
  final bool? autocorrect;
  final bool? enableSuggestions;
  final bool? enableIMEPersonalizedLearning;
  final SpellCheckConfiguration? spellCheckConfiguration;
  final SmartDashesType? smartDashesType;
  final SmartQuotesType? smartQuotesType;
  final Iterable<String>? autofillHints;
  final int? maxLength;
  final MaxLengthEnforcement? maxLengthEnforcement;
  final EditableTextContextMenuBuilder? contextMenuBuilder;
  final VoidCallback? onEditingComplete;
  final Color? cursorColor;
  final FormFieldValidator<String>? validator;

  bool get _prose =>
      kind == FastTextFieldKind.prose || kind == FastTextFieldKind.multiline;

  TextInputType get _keyboardType {
    switch (kind) {
      case FastTextFieldKind.email:
        return TextInputType.emailAddress;
      case FastTextFieldKind.url:
        return TextInputType.url;
      case FastTextFieldKind.multiline:
      case FastTextFieldKind.prose:
        return TextInputType.multiline;
      case FastTextFieldKind.search:
        return TextInputType.text;
      case FastTextFieldKind.standard:
        return TextInputType.text;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMultiline = maxLines != 1 || kind == FastTextFieldKind.multiline;
    final effectiveAction = textInputAction ??
        (isMultiline ? TextInputAction.newline : TextInputAction.next);
    final fastIme = kind == FastTextFieldKind.search ||
        kind == FastTextFieldKind.email ||
        kind == FastTextFieldKind.url;

    final defaultAutocorrect = _prose && !fastIme;
    final common = (
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      readOnly: readOnly,
      obscureText: obscureText,
      autofocus: autofocus,
      style: style,
      scrollPadding: scrollPadding,
      minLines: minLines ?? (isMultiline ? 1 : null),
      maxLines: isMultiline ? maxLines : 1,
      keyboardType: keyboardType ?? _keyboardType,
      textInputAction: effectiveAction,
      textCapitalization: textCapitalization ??
          (_prose
              ? TextCapitalization.sentences
              : TextCapitalization.none),
      autocorrect: autocorrect ?? defaultAutocorrect,
      enableSuggestions: enableSuggestions ?? defaultAutocorrect,
      enableIMEPersonalizedLearning:
          enableIMEPersonalizedLearning ?? false,
      spellCheckConfiguration: spellCheckConfiguration ??
          (_prose ? null : const SpellCheckConfiguration.disabled()),
      smartDashesType: smartDashesType ??
          (_prose ? SmartDashesType.enabled : SmartDashesType.disabled),
      smartQuotesType: smartQuotesType ??
          (_prose ? SmartQuotesType.enabled : SmartQuotesType.disabled),
      inputFormatters: inputFormatters,
      autofillHints: autofillHints,
      maxLength: maxLength,
      maxLengthEnforcement: maxLengthEnforcement,
      contextMenuBuilder: contextMenuBuilder,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onEditingComplete: onEditingComplete,
      onTap: onTap,
      onTapOutside: onTapOutside ??
          (_) => FocusManager.instance.primaryFocus?.unfocus(),
      cursorColor: cursorColor,
      decoration: decoration,
    );

    if (validator != null) {
      return TextFormField(
        controller: common.controller,
        focusNode: common.focusNode,
        enabled: common.enabled,
        readOnly: common.readOnly,
        obscureText: common.obscureText,
        autofocus: common.autofocus,
        style: common.style,
        scrollPadding: common.scrollPadding,
        minLines: common.minLines,
        maxLines: common.maxLines,
        keyboardType: common.keyboardType,
        textInputAction: common.textInputAction,
        textCapitalization: common.textCapitalization,
        autocorrect: common.autocorrect,
        enableSuggestions: common.enableSuggestions,
        enableIMEPersonalizedLearning: common.enableIMEPersonalizedLearning,
        spellCheckConfiguration: common.spellCheckConfiguration,
        smartDashesType: common.smartDashesType,
        smartQuotesType: common.smartQuotesType,
        inputFormatters: common.inputFormatters,
        autofillHints: common.autofillHints,
        maxLength: common.maxLength,
        maxLengthEnforcement: common.maxLengthEnforcement,
        contextMenuBuilder: common.contextMenuBuilder,
        onChanged: common.onChanged,
        onFieldSubmitted: common.onSubmitted,
        onEditingComplete: common.onEditingComplete,
        onTap: common.onTap,
        onTapOutside: common.onTapOutside,
        cursorColor: common.cursorColor,
        decoration: common.decoration,
        validator: validator,
      );
    }

    return TextField(
      controller: common.controller,
      focusNode: common.focusNode,
      enabled: common.enabled,
      readOnly: common.readOnly,
      obscureText: common.obscureText,
      autofocus: common.autofocus,
      style: common.style,
      scrollPadding: common.scrollPadding,
      minLines: common.minLines,
      maxLines: common.maxLines,
      keyboardType: common.keyboardType,
      textInputAction: common.textInputAction,
      textCapitalization: common.textCapitalization,
      autocorrect: common.autocorrect,
      enableSuggestions: common.enableSuggestions,
      enableIMEPersonalizedLearning: common.enableIMEPersonalizedLearning,
      spellCheckConfiguration: common.spellCheckConfiguration,
      smartDashesType: common.smartDashesType,
      smartQuotesType: common.smartQuotesType,
      inputFormatters: common.inputFormatters,
      autofillHints: common.autofillHints,
      maxLength: common.maxLength,
      maxLengthEnforcement: common.maxLengthEnforcement,
      contextMenuBuilder: common.contextMenuBuilder,
      onChanged: common.onChanged,
      onSubmitted: common.onSubmitted,
      onEditingComplete: common.onEditingComplete,
      onTap: common.onTap,
      onTapOutside: common.onTapOutside,
      cursorColor: common.cursorColor,
      decoration: common.decoration,
    );
  }
}
