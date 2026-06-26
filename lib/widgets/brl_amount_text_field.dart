import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../constants/currency_formats.dart';
import 'native_android_numeric_keypad.dart';

/// Campo de valor BRL: por defeito usa o teclado numérico do sistema + [CurrencyFormats.brlInputFormatters].
///
/// [useNativeAndroidKeypad]: true embute [NativeAndroidNumericKeypad] (AndroidView). **Evitar** dentro de
/// [SingleChildScrollView] / diálogos com scroll — em muitos dispositivos o PlatformView fica em branco
/// mas continua a reservar ~288px (área vazia). Só ative em ecrãs full-screen sem scroll ou após testar.
void _applyKeypadEventToBrl(
  TextEditingController controller,
  Map<String, dynamic> event,
) {
  final type = event['type'] as String?;
  var digits = controller.text.replaceAll(RegExp(r'[^\d]'), '');
  var cents = int.tryParse(digits) ?? 0;

  switch (type) {
    case 'digit':
      final p = event['payload'] as String? ?? '';
      final d = int.tryParse(p);
      if (d == null || d < 0 || d > 9) return;
      final next = cents * 10 + d;
      cents = next > 999999999999 ? cents : next;
      break;
    case 'backspace':
      cents ~/= 10;
      break;
    case 'clear':
      cents = 0;
      break;
    case 'done':
      return;
    default:
      return;
  }

  final formatted = CurrencyFormats.formatBRLInputFromCents(cents);
  controller.value = TextEditingValue(
    text: formatted,
    selection: TextSelection.collapsed(offset: formatted.length),
  );
}

/// Campo montário alinhado ao [CurrencyInputFormatter] (centavos como dígitos).
class BrlAmountTextField extends StatefulWidget {
  const BrlAmountTextField({
    super.key,
    required this.controller,
    this.decoration,
    this.style,
    this.labelText = 'Valor',
    this.focusNode,
    this.scrollPadding = const EdgeInsets.all(20),
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    this.textAlign = TextAlign.start,
    /// Se true no Android, embute teclado nativo (não usar dentro de scroll — ver doc da classe).
    this.useNativeAndroidKeypad = false,
  });

  final TextEditingController controller;
  final InputDecoration? decoration;
  final TextStyle? style;
  final String labelText;
  final FocusNode? focusNode;
  final EdgeInsets scrollPadding;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final TextAlign textAlign;
  final bool useNativeAndroidKeypad;

  @override
  State<BrlAmountTextField> createState() => _BrlAmountTextFieldState();
}

class _BrlAmountTextFieldState extends State<BrlAmountTextField> {
  static int _seq = 1;
  late final int _instanceId = _seq++;

  InputDecoration get _decoration =>
      widget.decoration ??
      InputDecoration(labelText: widget.labelText, isDense: true);

  bool get _useNativePad =>
      widget.useNativeAndroidKeypad &&
      defaultTargetPlatform == TargetPlatform.android &&
      !kIsWeb;

  @override
  Widget build(BuildContext context) {
    if (!_useNativePad) {
      return TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        scrollPadding: widget.scrollPadding,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: false,
        ),
        style: widget.style,
        textAlign: widget.textAlign,
        minLines: 1,
        maxLines: 1,
        textInputAction: widget.textInputAction,
        onSubmitted: widget.onSubmitted,
        onChanged: widget.onChanged,
        enableSuggestions: false,
        autocorrect: false,
        smartDashesType: SmartDashesType.disabled,
        smartQuotesType: SmartQuotesType.disabled,
        inputFormatters: CurrencyFormats.brlInputFormatters,
        decoration: _decoration,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          scrollPadding: widget.scrollPadding,
          readOnly: true,
          keyboardType: TextInputType.none,
          style: widget.style,
          textAlign: widget.textAlign,
          minLines: 1,
          maxLines: 1,
          textInputAction: widget.textInputAction,
          enableSuggestions: false,
          autocorrect: false,
          smartDashesType: SmartDashesType.disabled,
          smartQuotesType: SmartQuotesType.disabled,
          showCursor: true,
          decoration: _decoration,
          onSubmitted: widget.onSubmitted,
          onChanged: widget.onChanged,
        ),
        const SizedBox(height: 8),
        NativeAndroidNumericKeypad(
          instanceId: _instanceId,
          onEvent: (Map<String, dynamic> e) {
            final t = e['type'] as String?;
            if (t == 'done') {
              FocusManager.instance.primaryFocus?.unfocus();
              widget.onSubmitted?.call(widget.controller.text);
              return;
            }
            _applyKeypadEventToBrl(widget.controller, e);
            widget.onChanged?.call(widget.controller.text);
          },
        ),
      ],
    );
  }
}
