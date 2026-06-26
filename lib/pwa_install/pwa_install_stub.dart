/// Stub para plataformas não-web: PWA install não disponível.
class PwaInstall {
  static bool get supported => false;
  static bool get isIos => false;
  static bool get isInstalled => false;
  static bool get canPrompt => false;

  static Future<String> promptInstall() async => 'unavailable';
}
