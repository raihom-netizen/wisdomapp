import 'dart:io';

import 'package:local_auth/local_auth.dart';

final LocalAuthentication _auth = LocalAuthentication();

/// Autentica com digital ou facial. No Android força o diálogo do sistema e permite PIN/senha como fallback.
Future<bool> authenticateWithBiometric() async {
  try {
    if (!await _auth.canCheckBiometrics) return false;
    if (!await _auth.isDeviceSupported()) return false;
    final enrolled = await _auth.getAvailableBiometrics();
    // No Android alguns aparelhos reportam enrolled vazio mesmo com digital cadastrada; tentar authenticate mesmo assim.
    if (enrolled.isEmpty && !Platform.isAndroid) return false;
    // Android: biometricOnly = false (permite PIN/senha), useErrorDialogs = true e stickyAuth = true para o diálogo aparecer e persistir.
    const reason = 'Use a digital ou reconhecimento facial para acessar o WISDOMAPP.';
    if (Platform.isAndroid) {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          useErrorDialogs: true,
          stickyAuth: true,
        ),
      );
    }
    return await _auth.authenticate(
      localizedReason: reason,
      options: const AuthenticationOptions(biometricOnly: true),
    );
  } catch (_) {
    return false;
  }
}

/// Uma passagem nativa: evita duplicar `canCheckBiometrics` / `isDeviceSupported` no cold start.
Future<({bool available, bool hardware})> probeBiometricCapabilities() async {
  try {
    if (!await _auth.canCheckBiometrics) {
      return (available: false, hardware: false);
    }
    if (!await _auth.isDeviceSupported()) {
      return (available: false, hardware: false);
    }
    final enrolled = await _auth.getAvailableBiometrics();
    return (available: enrolled.isNotEmpty, hardware: true);
  } catch (_) {
    return (available: false, hardware: false);
  }
}

/// True apenas se o aparelho tem biometria disponível e pelo menos um método cadastrado (digital/facial).
Future<bool> isBiometricAvailable() async {
  final cap = await probeBiometricCapabilities();
  return cap.available;
}

/// Hardware suporta biometria/PIN do sistema (sem exigir lista de métodos cadastrados).
/// Usado para ativar proteção por digital após login: no Android alguns aparelhos reportam lista vazia.
Future<bool> isBiometricHardwareAvailable() async {
  final cap = await probeBiometricCapabilities();
  return cap.hardware;
}
