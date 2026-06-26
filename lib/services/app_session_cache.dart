import 'package:shared_preferences/shared_preferences.dart';

/// Sessão «carregada com sucesso» neste aparelho — reabertura rápida sem bootstrap pesado.
/// Só é limpa em «Sair / trocar conta» nas Configurações ([LoginPreferences.prepareForAccountSwitch]).
class AppSessionCache {
  AppSessionCache._();

  static const _kShellReadyUid = 'app_shell_ready_uid_v1';
  static const _kShellReadyAtMs = 'app_shell_ready_at_ms_v1';

  static String? _memoryUid;
  static bool _memoryReady = false;

  static Future<void> warmUp() async {
    final prefs = await SharedPreferences.getInstance();
    _memoryUid = (prefs.getString(_kShellReadyUid) ?? '').trim();
    _memoryReady = _memoryUid != null && _memoryUid!.isNotEmpty;
  }

  /// Retorno síncrono após [warmUp] (cold start).
  static bool isShellReadyForSync(String? uid) {
    if (uid == null || uid.isEmpty) return false;
    return _memoryReady && _memoryUid == uid;
  }

  /// UID da última sessão bem-sucedida — permite abrir o painel antes do Firebase Auth no disco.
  static String? cachedUidSync() {
    if (!_memoryReady) return null;
    final u = _memoryUid;
    if (u == null || u.isEmpty) return null;
    return u;
  }

  static Future<bool> isShellReadyFor(String? uid) async {
    if (uid == null || uid.isEmpty) return false;
    if (_memoryReady && _memoryUid == uid) return true;
    final prefs = await SharedPreferences.getInstance();
    final stored = (prefs.getString(_kShellReadyUid) ?? '').trim();
    return stored.isNotEmpty && stored == uid;
  }

  static Future<void> markShellReady(String uid) async {
    final clean = uid.trim();
    if (clean.isEmpty) return;
    _memoryUid = clean;
    _memoryReady = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kShellReadyUid, clean);
    await prefs.setInt(
      _kShellReadyAtMs,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Apenas «trocar conta» / sair definitivo — não chamar no logout silencioso.
  static Future<void> clear() async {
    _memoryUid = null;
    _memoryReady = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kShellReadyUid);
    await prefs.remove(_kShellReadyAtMs);
  }
}
