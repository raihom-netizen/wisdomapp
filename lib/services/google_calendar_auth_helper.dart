import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/google_oauth_config.dart';

/// Resultado OAuth Google Calendar.
class GoogleCalendarAuthResult {
  const GoogleCalendarAuthResult({
    this.accessToken,
    this.email,
    this.errorMessage,
    this.cancelled = false,
    this.needsInteractive = false,
  });

  final String? accessToken;
  final String? email;
  final String? errorMessage;
  final bool cancelled;
  final bool needsInteractive;

  bool get ok => accessToken != null && accessToken!.isNotEmpty;
}

/// Sessão Google Calendar — **uma** instância [GoogleSignIn], silent-first, estável Web/mobile.
///
/// Não usa popup Firebase na Web (evita origin_mismatch e conflito com login).
class GoogleCalendarAuthHelper {
  GoogleCalendarAuthHelper._();

  static const _calendarScope = GoogleOAuthConfig.calendarScope;
  static const _scopes = [_calendarScope, 'email', 'profile'];

  static const _prefsTokenKey = 'google_calendar_access_token';
  static const _prefsTokenUntilKey = 'google_calendar_access_until_ms';
  static const _prefsTokenEmailKey = 'google_calendar_token_email';

  /// Token Google expira ~1h — cache local evita GIS a cada request HTTP.
  static const _tokenCacheTtl = Duration(minutes: 50);

  static GoogleSignIn? _gsi;
  static String? _cachedToken;
  static DateTime? _cachedUntil;
  static Future<GoogleCalendarAuthResult>? _inFlightEnsure;

  static GoogleSignIn _signIn({bool recreate = false}) {
    if (recreate || _gsi == null) {
      _gsi = GoogleSignIn(
        clientId: kIsWeb ? GoogleOAuthConfig.webClientId : null,
        serverClientId: kIsWeb ? null : GoogleOAuthConfig.webClientId,
        scopes: _scopes,
      );
    }
    return _gsi!;
  }

  static Future<void> cacheToken(String token, {String? email}) async {
    _cachedToken = token;
    _cachedUntil = DateTime.now().add(_tokenCacheTtl);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsTokenKey, token);
      await prefs.setInt(
        _prefsTokenUntilKey,
        _cachedUntil!.millisecondsSinceEpoch,
      );
      final e = email?.trim();
      if (e != null && e.isNotEmpty) {
        await prefs.setString(_prefsTokenEmailKey, e);
      }
    } catch (_) {}
  }

  static Future<void> clearCache() async {
    _cachedToken = null;
    _cachedUntil = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsTokenKey);
      await prefs.remove(_prefsTokenUntilKey);
      await prefs.remove(_prefsTokenEmailKey);
    } catch (_) {}
  }

  static Future<String?> storedCalendarEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final e = (prefs.getString(_prefsTokenEmailKey) ?? '').trim();
      return e.isEmpty ? null : e;
    } catch (_) {
      return null;
    }
  }

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

  static Future<bool> hasStoredCalendarLink() async {
    final email = await storedCalendarEmail();
    return email != null && email.isNotEmpty;
  }

  static Future<void> _hydrateFromPrefs() async {
    if (cachedTokenIfValid() != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = (prefs.getString(_prefsTokenKey) ?? '').trim();
      final untilMs = prefs.getInt(_prefsTokenUntilKey);
      if (token.isEmpty || untilMs == null) return;
      final until = DateTime.fromMillisecondsSinceEpoch(untilMs);
      if (DateTime.now().isBefore(until)) {
        _cachedToken = token;
        _cachedUntil = until;
      }
    } catch (_) {}
  }

  /// Boot silencioso — login / abrir Agenda (sem UI).
  static Future<void> bootstrapSession({String? preferredEmail}) async {
    await _hydrateFromPrefs();
    if (cachedTokenIfValid() != null) return;
    unawaited(
      ensureToken(preferredEmail: preferredEmail, interactive: false),
    );
  }

  /// Token silencioso — **nunca** abre popup.
  static Future<GoogleCalendarAuthResult> requestSilent({
    String? preferredEmail,
  }) =>
      ensureToken(preferredEmail: preferredEmail, interactive: false);

  /// Autorização com UI — tenta silent antes; só abre Google se necessário.
  static Future<GoogleCalendarAuthResult> requestInteractive({
    String? preferredEmail,
    bool forceNewCredentials = false,
  }) async {
    if (!forceNewCredentials) {
      final silent = await requestSilent(preferredEmail: preferredEmail);
      if (silent.ok) return silent;
    }
    return ensureToken(
      preferredEmail: forceNewCredentials ? null : preferredEmail,
      interactive: true,
      forceAccountPicker: forceNewCredentials,
    );
  }

  /// Após HTTP 401 da API Calendar.
  static Future<GoogleCalendarAuthResult> refreshAfterUnauthorized({
    String? preferredEmail,
  }) async {
    _cachedToken = null;
    _cachedUntil = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsTokenKey);
      await prefs.remove(_prefsTokenUntilKey);
    } catch (_) {}
    final silent = await ensureToken(
      preferredEmail: preferredEmail,
      interactive: false,
    );
    if (silent.ok) return silent;
    return GoogleCalendarAuthResult(
      needsInteractive: true,
      email: preferredEmail ?? await storedCalendarEmail(),
      errorMessage: silent.errorMessage,
    );
  }

  /// Obtém token válido — deduplica chamadas simultâneas.
  static Future<GoogleCalendarAuthResult> ensureToken({
    String? preferredEmail,
    required bool interactive,
    bool forceAccountPicker = false,
  }) {
    if (_inFlightEnsure != null) return _inFlightEnsure!;

    _inFlightEnsure = _ensureTokenCore(
      preferredEmail: preferredEmail,
      interactive: interactive,
      forceAccountPicker: forceAccountPicker,
    ).whenComplete(() => _inFlightEnsure = null);

    return _inFlightEnsure!;
  }

  static Future<GoogleCalendarAuthResult> _ensureTokenCore({
    String? preferredEmail,
    required bool interactive,
    bool forceAccountPicker = false,
  }) async {
    await _hydrateFromPrefs();

    final cached = cachedTokenIfValid();
    if (cached != null) {
      return GoogleCalendarAuthResult(
        accessToken: cached,
        email: preferredEmail ?? await storedCalendarEmail(),
      );
    }

    if (forceAccountPicker) {
      await clearCache();
      try {
        await _signIn(recreate: true).signOut();
      } catch (_) {}
    }

    try {
      final gs = _signIn();
      var account = await gs.signInSilently(suppressErrors: true);

      final hint = _resolveEmailHint(preferredEmail);
      if (account != null && hint != null && !_emailsMatch(account.email, hint)) {
        if (interactive || forceAccountPicker) {
          try {
            await gs.signOut();
          } catch (_) {}
          account = null;
        } else {
          return const GoogleCalendarAuthResult(
            errorMessage: 'Conta Google diferente da vinculada.',
          );
        }
      }

      if (account == null && interactive) {
        account = await gs.signIn();
        if (account == null) {
          return const GoogleCalendarAuthResult(cancelled: true);
        }
      }

      if (account == null) {
        return GoogleCalendarAuthResult(
          needsInteractive: !interactive,
          email: hint,
          errorMessage: interactive
              ? 'Selecione sua conta Google.'
              : 'Autorize o Google Calendar para sincronizar.',
        );
      }

      var hasScope = await gs.canAccessScopes([_calendarScope]);
      if (!hasScope) {
        if (!interactive) {
          return GoogleCalendarAuthResult(
            needsInteractive: true,
            email: account.email,
            errorMessage: 'Permissão do calendário necessária.',
          );
        }
        hasScope = await gs.requestScopes([_calendarScope]);
        if (!hasScope) {
          return const GoogleCalendarAuthResult(
            errorMessage: 'Permissão do Google Calendar negada.',
          );
        }
      }

      final token = await _readAccessToken(account);
      if (token == null || token.isEmpty) {
        return GoogleCalendarAuthResult(
          needsInteractive: interactive,
          email: account.email,
          errorMessage: 'Token Google indisponível. Tente autorizar de novo.',
        );
      }

      await cacheToken(token, email: account.email);
      return GoogleCalendarAuthResult(
        accessToken: token,
        email: account.email,
      );
    } catch (e, st) {
      debugPrint('GoogleCalendarAuthHelper.ensureToken: $e\n$st');
      if (_userCancelled(e)) {
        return const GoogleCalendarAuthResult(cancelled: true);
      }
      final msg = _friendlyError(e);
      if (msg.isEmpty) {
        return const GoogleCalendarAuthResult(cancelled: true);
      }
      return GoogleCalendarAuthResult(errorMessage: msg);
    }
  }

  static Future<String?> _readAccessToken(GoogleSignInAccount account) async {
    final auth = await account.authentication;
    var token = auth.accessToken;
    if (token != null && token.isNotEmpty) return token;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final retry = await account.authentication;
    return retry.accessToken;
  }

  static String? _resolveEmailHint(String? preferredEmail) {
    final p = preferredEmail?.trim();
    if (p != null && p.isNotEmpty) return p;
    if (isApplePrimaryLogin()) return null;
    final login = (FirebaseAuth.instance.currentUser?.email ?? '').trim();
    return login.isEmpty ? null : login;
  }

  static bool _emailsMatch(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  static String _friendlyError(Object e) {
    final raw = e.toString();
    if (raw.contains('origin_mismatch')) {
      final origin = Uri.base.origin;
      return 'Erro de autorização Google (origin_mismatch). '
          'Origem: $origin. Adicione em «Origens JavaScript autorizadas» '
          'do cliente OAuth Web no Google Cloud Console.';
    }
    if (raw.contains('popup_closed_by_user') ||
        raw.contains('cancelled-popup') ||
        raw.contains('popup-blocked')) {
      return '';
    }
    if (raw.contains('access_denied') || raw.contains('permission')) {
      return 'Permissão do Google Calendar negada.';
    }
    if (raw.contains('interaction_required') ||
        raw.contains('login_required') ||
        raw.contains('consent_required')) {
      return '';
    }
    return raw.split('\n').first;
  }

  static bool _userCancelled(Object e) {
    final raw = e.toString().toLowerCase();
    return raw.contains('popup_closed') ||
        raw.contains('cancelled') ||
        raw.contains('canceled') ||
        raw.contains('user_cancel');
  }

  /// Instância compartilhada (ex.: trocar conta / signOut).
  static GoogleSignIn sharedSignIn() => _signIn();

  /// Encerra sessão GIS do calendário.
  static Future<void> signOutCalendarSession() async {
    await clearCache();
    try {
      await _signIn().signOut();
    } catch (_) {}
  }

  /// Login principal foi Apple — Gmail da agenda pode ser outro.
  static bool isApplePrimaryLogin() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final providers = user.providerData.map((p) => p.providerId).toSet();
    return providers.contains('apple.com') && !providers.contains('google.com');
  }
}
