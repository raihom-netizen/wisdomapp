import 'package:flutter/foundation.dart' show kIsWeb;

import 'biometric_auth_service.dart';

/// Biometria só é ativada em Configurações (ou prompt explícito do usuário).
/// Não liga automaticamente após login e-mail/Google.
Future<void> enableBiometricAfterSuccessfulNativeLogin() async {
  if (kIsWeb) return;
  if (!await isBiometricHardwareAvailable()) return;
  final asked = await BiometricPreferences.wasAsked();
  if (!asked) return;
}
