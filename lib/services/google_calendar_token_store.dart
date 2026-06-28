import 'package:shared_preferences/shared_preferences.dart';

/// Cache local do token Google Calendar (memória + SharedPreferences).
class GoogleCalendarTokenStore {
  GoogleCalendarTokenStore._();

  static const prefsTokenKey = 'google_calendar_access_token';
  static const prefsTokenUntilKey = 'google_calendar_access_until_ms';
  static const prefsTokenEmailKey = 'google_calendar_token_email';
  static const tokenCacheTtl = Duration(minutes: 50);

  static String? _cachedToken;
  static DateTime? _cachedUntil;

  static String? cachedTokenIfValid() {
    final t = _cachedToken;
    final until = _cachedUntil;
    if (t == null || until == null) return null;
    if (DateTime.now().isAfter(until)) {
      _cachedToken = null;
      _cachedUntil = null;
      return null;
    }
    return t;
  }

  static Future<void> hydrateFromPrefs() async {
    if (cachedTokenIfValid() != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = (prefs.getString(prefsTokenKey) ?? '').trim();
      final untilMs = prefs.getInt(prefsTokenUntilKey);
      if (token.isEmpty || untilMs == null) return;
      final until = DateTime.fromMillisecondsSinceEpoch(untilMs);
      if (DateTime.now().isBefore(until)) {
        _cachedToken = token;
        _cachedUntil = until;
      }
    } catch (_) {}
  }

  static Future<void> save(
    String token, {
    String? email,
    DateTime? expiresAt,
  }) async {
    _cachedToken = token;
    _cachedUntil = expiresAt ??
        DateTime.now().add(tokenCacheTtl);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsTokenKey, token);
      await prefs.setInt(prefsTokenUntilKey, _cachedUntil!.millisecondsSinceEpoch);
      final e = email?.trim();
      if (e != null && e.isNotEmpty) {
        await prefs.setString(prefsTokenEmailKey, e);
      }
    } catch (_) {}
  }

  static Future<void> clear() async {
    _cachedToken = null;
    _cachedUntil = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(prefsTokenKey);
      await prefs.remove(prefsTokenUntilKey);
      await prefs.remove(prefsTokenEmailKey);
    } catch (_) {}
  }

  static Future<String?> storedEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final e = (prefs.getString(prefsTokenEmailKey) ?? '').trim();
      return e.isEmpty ? null : e;
    } catch (_) {
      return null;
    }
  }
}
