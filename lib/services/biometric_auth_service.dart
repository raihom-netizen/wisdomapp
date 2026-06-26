import 'package:shared_preferences/shared_preferences.dart';



import 'biometric_auth_stub.dart'

    if (dart.library.io) 'biometric_auth_io.dart' as bio_impl;



export 'biometric_auth_stub.dart'

    if (dart.library.io) 'biometric_auth_io.dart';



/// Chave para preferência: biometria habilitada.

const String _kBiometricEnabled = 'biometric_enabled';

/// Chave: já perguntou ao usuário se quer ativar (não perguntar de novo).

const String _kBiometricAsked = 'biometric_asked';



/// Pré-carrega prefs de biometria no cold start — evita spinner extra antes do painel.

class BiometricStartupCache {

  BiometricStartupCache._();



  static Future<List<dynamic>>? _prefetch;



  /// `false` assim que prefs indicam biometria desligada (sem esperar hardware).

  static bool? enabledHint;



  static void prefetch() {

    _prefetch ??= _load();

  }



  /// Só lê prefs (rápido) — usado em [main] antes do primeiro frame autenticado.

  static Future<void> warmUpEnabledHint() async {

    if (enabledHint != null) return;

    enabledHint = await BiometricPreferences.isEnabled();

    if (enabledHint == true) prefetch();

  }



  static Future<List<dynamic>> _load() async {

    final enabled = await BiometricPreferences.isEnabled();

    enabledHint = enabled;

    if (!enabled) return [false, false, false];

    final cap = await bio_impl.probeBiometricCapabilities();

    return [enabled, cap.available, cap.hardware];

  }



  static Future<List<dynamic>> get future {

    prefetch();

    return _prefetch!;

  }



  static void invalidate() {

    _prefetch = null;

    enabledHint = null;

  }

}



/// Preferências de biometria (SharedPreferences).

class BiometricPreferences {

  static Future<bool> isEnabled() async {

    final prefs = await SharedPreferences.getInstance();

    return prefs.getBool(_kBiometricEnabled) ?? false;

  }



  static Future<void> setEnabled(bool value) async {

    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(_kBiometricEnabled, value);

    BiometricStartupCache.invalidate();

  }



  static Future<bool> wasAsked() async {

    final prefs = await SharedPreferences.getInstance();

    return prefs.getBool(_kBiometricAsked) ?? false;

  }



  static Future<void> setAsked() async {

    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(_kBiometricAsked, true);

  }

}


