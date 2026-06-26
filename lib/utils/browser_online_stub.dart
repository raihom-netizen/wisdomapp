/// Desktop/mobile: não há `navigator.onLine` — rede tratada só por [Connectivity].
bool browserNavigatorOnline() => true;

void listenBrowserOnlineOffline(void Function(bool online) onChanged) {}
