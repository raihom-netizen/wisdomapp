import 'package:flutter/foundation.dart';

/// Em produção, evita log de dados sensíveis (CPF, e-mail, valores monetários).
String maskSensitiveData(String? input) {
  if (input == null || input.isEmpty) return '';
  if (kDebugMode) return input;
  // Em release: mascara para evitar vazamento em logs
  const placeholder = '[REDACTED]';
  if (input.length <= 4) return placeholder;
  return '${input.substring(0, 2)}$placeholder${input.substring(input.length - 2)}';
}
