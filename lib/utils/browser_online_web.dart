// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

bool browserNavigatorOnline() => html.window.navigator.onLine ?? true;

void listenBrowserOnlineOffline(void Function(bool online) onChanged) {
  html.window.onOnline.listen((_) => onChanged(true));
  html.window.onOffline.listen((_) => onChanged(false));
}
