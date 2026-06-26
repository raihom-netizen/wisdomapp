/// Stub para web: biometria não disponível.
Future<bool> authenticateWithBiometric() async => false;
Future<({bool available, bool hardware})> probeBiometricCapabilities() async =>
    (available: false, hardware: false);
Future<bool> isBiometricAvailable() async => false;
Future<bool> isBiometricHardwareAvailable() async => false;
