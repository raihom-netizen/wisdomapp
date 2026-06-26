// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

bool isOnline() => html.window.navigator.onLine ?? true;

final List<void Function()> _onlineSubs = [];
final List<void Function()> _offlineSubs = [];
bool _wired = false;

void _dispatchOnline(html.Event _) {
  for (final f in List<void Function()>.from(_onlineSubs)) {
    f();
  }
}

void _dispatchOffline(html.Event _) {
  for (final f in List<void Function()>.from(_offlineSubs)) {
    f();
  }
}

void _ensureWired() {
  if (_wired) return;
  _wired = true;
  html.window.addEventListener('online', _dispatchOnline);
  html.window.addEventListener('offline', _dispatchOffline);
}

void addOnlineListener(void Function() fn) {
  _ensureWired();
  _onlineSubs.add(fn);
}

void addOfflineListener(void Function() fn) {
  _ensureWired();
  _offlineSubs.add(fn);
}

void removeOnlineListener(void Function() fn) {
  _onlineSubs.remove(fn);
}

void removeOfflineListener(void Function() fn) {
  _offlineSubs.remove(fn);
}
