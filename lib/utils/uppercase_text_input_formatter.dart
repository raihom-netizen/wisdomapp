import 'package:flutter/services.dart';

/// Força o texto digitado/colido a ficar em maiúsculas (padronização plantões, escalas, locais).
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final t = newValue.text.toUpperCase();
    if (t == newValue.text) return newValue;
    return newValue.copyWith(text: t, composing: TextRange.empty);
  }
}
