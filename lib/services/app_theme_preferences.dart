import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kAppThemeModeKey = 'app_theme_mode_v1';

/// Preferência manual de aparência (nunca segue o sistema automaticamente).
class AppThemePreferences {
  static SharedPreferences? _prefs;
  static ThemeMode? _startupMode;

  /// Disponível após [warmUpForStartup] (antes do primeiro frame).
  static ThemeMode? get startupThemeMode => _startupMode;

  static Future<SharedPreferences> _prefsOrLoad() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  static Future<void> warmUpForStartup() async {
    _startupMode = await getThemeMode();
  }

  static Future<ThemeMode> getThemeMode() async {
    if (_startupMode != null) return _startupMode!;
    final prefs = await _prefsOrLoad();
    final raw = (prefs.getString(_kAppThemeModeKey) ?? 'light').trim().toLowerCase();
    _startupMode = raw == 'dark' ? ThemeMode.dark : ThemeMode.light;
    return _startupMode!;
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    final resolved = mode == ThemeMode.dark ? ThemeMode.dark : ThemeMode.light;
    final prefs = await _prefsOrLoad();
    await prefs.setString(
      _kAppThemeModeKey,
      resolved == ThemeMode.dark ? 'dark' : 'light',
    );
    _startupMode = resolved;
  }
}
