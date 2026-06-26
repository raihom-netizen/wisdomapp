import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';

/// Atalho para o usuário escolher / trocar o teclado padrão do Android (IME).
///
/// O Flutter **não** embute teclado próprio: ele usa o IME ativo do sistema
/// (Gboard, SwiftKey, Samsung Keyboard, etc.). Então não dá para "forçar" o
/// Gboard pelo app — quem decide é o Android. O que dá pra fazer é abrir o
/// seletor flutuante para o usuário escolher rápido sem sair do app.
///
/// Ponte com [MainActivity.kt] via [MethodChannel] `controletotal/keyboard`.
/// Em iOS / Web este service é no-op.
class AndroidKeyboardService {
  static const MethodChannel _channel = MethodChannel('controletotal/keyboard');

  static bool get isSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android;
  }

  /// Abre o popup flutuante de seleção de teclado (mesmo da barra de
  /// notificações). Se o usuário tiver Gboard instalado, é só tocar nele.
  /// Retorna true se conseguiu abrir.
  static Future<bool> showInputMethodPicker() async {
    if (!isSupported) return false;
    try {
      final v = await _channel.invokeMethod<bool>('showInputMethodPicker');
      return v ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Abre a tela de Configurações > Idioma e entrada > Teclados (fallback se
  /// o popup não aparecer em algum aparelho).
  static Future<bool> openInputMethodSettings() async {
    if (!isSupported) return false;
    try {
      final v = await _channel.invokeMethod<bool>('openInputMethodSettings');
      return v ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Abre a Play Store (ou página web) do **Teclado Google (Gboard)**.
  static Future<bool> openGboardPlayStore() async {
    if (!isSupported) return false;
    try {
      final v = await _channel.invokeMethod<bool>('openGboardPlayStore');
      return v ?? false;
    } catch (_) {
      return false;
    }
  }
}
