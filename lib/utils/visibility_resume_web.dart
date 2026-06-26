import 'dart:html' as html;

void Function()? _removeListener;

/// Configura listener do Page Visibility API para web/PWA.
/// Quando a página volta a ficar visível (após inatividade), chama [onVisible].
/// Em PWA instalado, evita tela preta ao retornar do background.
void setupVisibilityResumeListener(void Function() onVisible) {
  void handler(html.Event _) {
    if (html.document.visibilityState == 'visible') {
      onVisible();
    }
  }
  html.document.addEventListener('visibilitychange', handler);
  _removeListener = () => html.document.removeEventListener('visibilitychange', handler);
}

void disposeVisibilityResumeListener() {
  _removeListener?.call();
  _removeListener = null;
}
