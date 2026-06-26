// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

bool _hasDeferredPrompt = false;
dynamic _deferredPrompt;

/// True quando o app está rodando no Safari do iPhone/iPad (instalação é manual).
bool get isPwaIos {
  try {
    final ua = html.window.navigator.userAgent;
    final uaLower = ua.toLowerCase();
    final nav = html.window.navigator;

    // iPadOS mais recente costuma mascarar como Mac ("Macintosh"), então
    // usamos heurística por toque (maxTouchPoints > 1) além de iPhone/iPad.
    final platform = (nav.platform ?? '').toString().toLowerCase();
    final maxTouchPoints = (nav as dynamic).maxTouchPoints ?? 0;

    return uaLower.contains('iphone') ||
        uaLower.contains('ipad') ||
        (uaLower.contains('macintosh') &&
            (platform.contains('macintel') || maxTouchPoints > 1));
  } catch (_) {
    return false;
  }
}

bool get isPwaStandalone {
  try {
    if (html.window.matchMedia('(display-mode: standalone)').matches) return true;
    if (html.window.matchMedia('(display-mode: fullscreen)').matches) return true;
    final nav = html.window.navigator;
    try {
      return (nav as dynamic).standalone == true;
    } catch (_) {
      return false;
    }
  } catch (_) {
    return false;
  }
}

bool get hasPwaDeferredPrompt => _hasDeferredPrompt;

void initPwaBeforeInstallPrompt(void Function() onPrompt) {
  html.window.addEventListener('beforeinstallprompt', (html.Event e) {
    e.preventDefault();
    _deferredPrompt = e;
    _hasDeferredPrompt = true;
    onPrompt();
  });
}

Future<void> triggerPwaInstall() async {
  // Prioridade ao script do index.html (captura o evento antes do Flutter carregar)
  try {
    final instalarApp = (html.window as dynamic).instalarApp;
    if (instalarApp != null) {
      instalarApp();
      return;
    }
  } catch (_) {}
  // Fallback: prompt capturado pelo listener do Dart
  if (_deferredPrompt != null) {
    try {
      await (_deferredPrompt as dynamic).prompt();
      await (_deferredPrompt as dynamic).userChoice;
    } catch (_) {}
  }
}
