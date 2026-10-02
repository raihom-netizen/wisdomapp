import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme_preferences.dart';

/// Controla tema claro/escuro manualmente (sem ThemeMode.system).
class AppThemeController extends ChangeNotifier {
  AppThemeController._();
  static final AppThemeController instance = AppThemeController._();

  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;
  bool get isDark => _themeMode == ThemeMode.dark;

  Future<void> warmUp() async {
    _themeMode = await AppThemePreferences.getThemeMode();
    _applySystemOverlay();
    notifyListeners();
  }

  Future<void> setLight() => _set(ThemeMode.light);

  Future<void> setDark() => _set(ThemeMode.dark);

  Future<void> _set(ThemeMode mode) async {
    final next = mode == ThemeMode.dark ? ThemeMode.dark : ThemeMode.light;
    if (_themeMode == next) return;
    _themeMode = next;
    await AppThemePreferences.setThemeMode(next);
    _applySystemOverlay();
    notifyListeners();
  }

  void _applySystemOverlay() {
    if (kIsWeb) return;
    final dark = isDark;
    final style = SystemUiOverlayStyle(
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarIconBrightness:
          dark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: dark ? const Color(0xFF121212) : Colors.white,
    );
    SystemChrome.setSystemUIOverlayStyle(style);
  }
}
