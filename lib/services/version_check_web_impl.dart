// ignore: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

/// True quando o app está rodando como PWA instalado (ex.: web no celular).
bool isPwaStandalone() {
  try {
    if (html.window.matchMedia('(display-mode: standalone)').matches) return true;
    if (html.window.matchMedia('(display-mode: fullscreen)').matches) return true;
    try {
      return (html.window.navigator as dynamic).standalone == true;
    } catch (_) {
      return false;
    }
  } catch (_) {
    return false;
  }
}

/// Retorna true se a URL já contém v=[version]. Evita loop de reload ao trocar versão.
bool urlAlreadyHasVersion(String version) {
  try {
    final uri = Uri.parse(html.window.location.href);
    final vInUrl = uri.queryParameters['v'];
    return vInUrl != null && vInUrl.trim() == version.trim();
  } catch (_) {
    return false;
  }
}

const _reloadAttemptsKey = 'wisdomapp_reload_attempts';
const _reloadVersionKey = 'wisdomapp_reload_version';
const _reloadWindowMs = 120000;
const _maxReloadAttempts = 2;

/// Evita loop infinito quando o cache ainda serve JS antigo após reload forçado.
bool isWebReloadLoopBlocked(String serverVersion) {
  try {
    final storage = html.window.sessionStorage;
    final prevVersion = storage[_reloadVersionKey];
    final attempts = int.tryParse(storage[_reloadAttemptsKey] ?? '') ?? 0;
    final tsRaw = storage['wisdomapp_reload_ts'];
    final ts = int.tryParse(tsRaw ?? '') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (prevVersion == serverVersion.trim() &&
        attempts >= _maxReloadAttempts &&
        now - ts < _reloadWindowMs) {
      return true;
    }
  } catch (_) {}
  return false;
}

void _recordWebReloadAttempt(String serverVersion) {
  try {
    final storage = html.window.sessionStorage;
    final v = serverVersion.trim();
    final prevVersion = storage[_reloadVersionKey];
    final now = DateTime.now().millisecondsSinceEpoch;
    final prevTs = int.tryParse(storage['wisdomapp_reload_ts'] ?? '') ?? 0;
    var attempts = int.tryParse(storage[_reloadAttemptsKey] ?? '') ?? 0;
    if (prevVersion != v || now - prevTs > _reloadWindowMs) {
      attempts = 0;
    }
    storage[_reloadVersionKey] = v;
    storage[_reloadAttemptsKey] = '${attempts + 1}';
    storage['wisdomapp_reload_ts'] = '$now';
  } catch (_) {}
}

/// Recarrega a página. Se [serverVersion] for informado, usa ?v= e _= (timestamp)
/// na URL para forçar o navegador a buscar a nova versão (evita cache).
/// [forceReload]: quando true (ex.: usuário clicou "Atualizar agora"), SEMPRE recarrega
/// com novo timestamp, mesmo se a URL já tiver v=. Evita ficar travado quando o cache
/// do navegador ainda serve JS antigo.
void reloadPage([String? serverVersion, bool forceReload = false]) {
  if (serverVersion != null && serverVersion.isNotEmpty) {
    if (!forceReload && urlAlreadyHasVersion(serverVersion)) return;
    if (isWebReloadLoopBlocked(serverVersion)) return;
    _recordWebReloadAttempt(serverVersion);
    final ts = DateTime.now().millisecondsSinceEpoch;
    // Sempre ir para a raiz com query para evitar loop (hash routing pode confundir)
    final base = html.window.location.origin;
    final path = (html.window.location.pathname ?? '/');
    final pathNorm = path.endsWith('/') ? path : '$path/';
    final sep = pathNorm.contains('?') ? '&' : '?';
    final fullUrl = '$base$pathNorm${sep}v=$serverVersion&_=$ts';
    html.window.location.href = fullUrl;
    return;
  }
  html.window.location.reload();
}

/// Busca a versão no próprio site (/version.json) para atualização automática
/// mesmo sem Firestore. Cache bust duplo para forçar resposta fresca.
Future<String?> fetchVersionFromHost() async {
  final m = await fetchVersionJsonFromHost();
  final v = m?['version'];
  return v?.toString().trim();
}

/// Mapa completo do `version.json` (version, buildNumber, versionCode, releaseTag, …).
Future<Map<String, dynamic>?> fetchVersionJsonFromHost() async {
  try {
    final url = 'version.json?t=${DateTime.now().millisecondsSinceEpoch}&r=${DateTime.now().microsecondsSinceEpoch}';
    final request = await html.HttpRequest.request(url);
    if (request.status == 200 && request.responseText != null && request.responseText!.isNotEmpty) {
      final Object? decoded = jsonDecode(request.responseText!);
      if (decoded is Map<String, dynamic>) return decoded;
    }
  } catch (_) {}
  return null;
}

/// Última vez que a checagem foi executada (para cooldown no visibility).
DateTime? _lastCheckTime;

/// Registra checagem automática: ao voltar para a aba (cooldown 5 min) e a cada 15 min.
/// Cooldown longo evita piscar/reload ao alternar abas rapidamente.
void registerUpdateChecker(void Function() check) {
  const cooldown = Duration(minutes: 5);
  void runCheck() {
    _lastCheckTime = DateTime.now();
    check();
  }
  html.document.addEventListener('visibilitychange', (_) {
    if (html.document.visibilityState == 'visible') {
      final now = DateTime.now();
      if (_lastCheckTime == null || now.difference(_lastCheckTime!) > cooldown) {
        runCheck();
      }
    }
  });
  Timer.periodic(const Duration(minutes: 15), (_) => runCheck());
}
