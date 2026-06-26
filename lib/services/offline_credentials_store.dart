import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Guarda identificador + senha do login e-mail/CPF no cofre do sistema (Keychain / EncryptedSharedPreferences).
/// Usado para suporte a sessão offline e reautenticação quando a rede voltar; apagado em [clear] no logout.
class OfflineCredentialsStore {
  OfflineCredentialsStore._();

  static final OfflineCredentialsStore instance = OfflineCredentialsStore._();

  static const _kId = 'ct_offline_login_identifier';
  static const _kPass = 'ct_offline_login_password';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<void> saveAfterEmailPasswordLogin(String identifier, String password) async {
    final id = identifier.trim();
    if (id.isEmpty || password.isEmpty) return;
    await _storage.write(key: _kId, value: id);
    await _storage.write(key: _kPass, value: password);
  }

  /// Lê credenciais guardadas após login e-mail/CPF (cofre do sistema).
  Future<({String identifier, String password})?> readStored() async {
    try {
      final id = (await _storage.read(key: _kId))?.trim() ?? '';
      final pass = await _storage.read(key: _kPass) ?? '';
      if (id.isEmpty || pass.isEmpty) return null;
      return (identifier: id, password: pass);
    } catch (_) {
      return null;
    }
  }

  Future<bool> hasStored() async {
    final v = await readStored();
    return v != null;
  }

  Future<void> clear() async {
    await _storage.delete(key: _kId);
    await _storage.delete(key: _kPass);
  }
}
