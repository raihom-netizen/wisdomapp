/// Stub for non-web: PWA install not applicable.
bool get isPwaStandalone => false;
bool get hasPwaDeferredPrompt => false;
bool get isPwaIos => false;
void initPwaBeforeInstallPrompt(void Function() onPrompt) {}
Future<void> triggerPwaInstall() async {}
