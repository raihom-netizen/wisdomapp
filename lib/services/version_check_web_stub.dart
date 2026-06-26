import 'dart:async';

/// Stub para plataformas não-web: não recarrega.
void reloadPage([String? serverVersion, bool forceReload = false]) {}

/// Stub: não-web não tem URL.
bool urlAlreadyHasVersion(String version) => false;

/// Stub: só web PWA pode auto-atualizar.
bool isPwaStandalone() => false;

/// Retorno null = sem fallback (mobile não usa version.json).
Future<String?> fetchVersionFromHost() async => null;

/// Mobile: não usa version.json no stub.
Future<Map<String, dynamic>?> fetchVersionJsonFromHost() async => null;

/// No mobile, verifica nova versão a cada 30 min.
void registerUpdateChecker(void Function() check) {
  Timer.periodic(const Duration(minutes: 30), (_) => check());
}
