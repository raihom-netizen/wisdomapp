import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/google_oauth_config.dart';
import '../utils/firestore_web_guard.dart';

/// Obtém token OAuth do Google Calendar (Web/mobile = google_sign_in / GIS).
class GoogleCalendarAuthResult {
  const GoogleCalendarAuthResult({
    this.accessToken,
    this.email,
    this.errorMessage,
    this.cancelled = false,
  });

  final String? accessToken;
  final String? email;
  final String? errorMessage;
  final bool cancelled;

  bool get ok => accessToken != null && accessToken!.isNotEmpty;
}

/// Helper OAuth Google Calendar (GIS / google_sign_in — sem popup Firebase na Web).
class GoogleCalendarAuthHelper {  GoogleCalendarAuthHelper._();

  static const _calendarScope = GoogleOAuthConfig.calendarScope;

  static const _prefsTokenKey = 'google_calendar_access_token';
  static const _prefsTokenUntilKey = 'google_calendar_access_until_ms';
  static const _prefsTokenEmailKey = 'google_calendar_token_email';

  static String? _cachedToken;
  static DateTime? _cachedUntil;
  /// Token Google expira ~1h — cache curto só para evitar GIS a cada request.
  static const _tokenCacheTtl = Duration(minutes: 50);

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

  static GoogleSignIn _calendarSignIn({String? webClientId}) {
    return GoogleSignIn(
      clientId: webClientId,
      scopes: const [_calendarScope, 'email', 'profile'],
      serverClientId: kIsWeb ? null : GoogleOAuthConfig.webClientId,
    );
  }

  static String _friendlyError(Object e) {
    final raw = e.toString();
    if (raw.contains('origin_mismatch')) {
      final origin = Uri.base.origin;
      return 'Erro de autorização Google (origin_mismatch). '
          'Origem atual: $origin. '
          'Peça ao administrador para adicionar esta URL em «Origens JavaScript autorizadas» '
          'do cliente OAuth Web (${GoogleOAuthConfig.webClientId}) no projeto wisdomapp-b9e98. '
          'Origens recomendadas: ${GoogleOAuthConfig.authorizedJavaScriptOrigins.join(", ")}.';
    }
    if (raw.contains('popup_closed_by_user') ||
        raw.contains('cancelled-popup') ||
        raw.contains('popup-blocked')) {
      return '';
    }
    if (raw.contains('access_denied') || raw.contains('permission')) {
      return 'Permissão do Google Calendar negada. Autorize o acesso na janela do Google.';
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

  /// Pedido interativo (ativar sync) — tenta silencioso antes de abrir popup.
  static Future<GoogleCalendarAuthResult> requestInteractive({
    String? preferredEmail,
    bool forceNewCredentials = false,
  }) async {
    if (!forceNewCredentials) {
      final silent = await requestSilent(preferredEmail: preferredEmail);
      if (silent.ok) return silent;
    } else {
      await clearCache();
      try {
        await _calendarSignIn(
          webClientId: kIsWeb ? GoogleOAuthConfig.webClientId : null,
        ).signOut();
      } catch (_) {}
    }

    if (kIsWeb) {
      return _requestWebInteractive(
        preferredEmail: forceNewCredentials ? null : preferredEmail,
      );
    }
    return _requestMobileInteractive(
      preferredEmail: forceNewCredentials ? null : preferredEmail,
    );
  }

  /// Token silencioso (leitura/sync) — **nunca** abre popup ou nova aba.
  static Future<GoogleCalendarAuthResult> requestSilent({
    String? preferredEmail,
  }) async {
    final memCached = cachedTokenIfValid();
    if (memCached != null) {
      final email = preferredEmail ?? await storedCalendarEmail();
      return GoogleCalendarAuthResult(
        accessToken: memCached,
        email: email,
      );
    }

    // Sempre renova via GIS/google_sign_in — token persistido pode estar expirado no Google.
    if (kIsWeb) {
      return _requestGoogleSignInSilent(preferredEmail: preferredEmail);
    }
    return _requestMobileSilent(preferredEmail: preferredEmail);
  }

  /// Renova token após HTTP 401 da API Calendar (sem popup).
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

    if (kIsWeb) {
      return _requestGoogleSignInSilent(preferredEmail: preferredEmail);
    }
    return _requestMobileSilent(preferredEmail: preferredEmail);
  }

  static Future<GoogleCalendarAuthResult> _requestGoogleSignInSilent({
    String? preferredEmail,
  }) async {
    try {
      final gs = _calendarSignIn(
        webClientId: kIsWeb ? GoogleOAuthConfig.webClientId : null,
      );
      GoogleSignInAccount? account =
          await gs.signInSilently(suppressErrors: true);

      if (account != null &&
          preferredEmail != null &&
          preferredEmail.isNotEmpty &&
          account.email.trim().toLowerCase() != preferredEmail.toLowerCase()) {
        account = null;
      }

      if (account == null) {
        return const GoogleCalendarAuthResult(
          errorMessage: 'Sessão Google indisponível.',
        );
      }

      final hasScope = await gs.canAccessScopes([_calendarScope]);
      if (!hasScope) {
        return const GoogleCalendarAuthResult(
          errorMessage: 'Permissão do calendário ainda não concedida.',
        );
      }

      final auth = await account.authentication;
      final token = auth.accessToken;
      if (token == null || token.isEmpty) {
        return const GoogleCalendarAuthResult(
          errorMessage: 'Token Google indisponível.',
        );
      }

      await cacheToken(token, email: account.email);
      return GoogleCalendarAuthResult(
        accessToken: token,
        email: account.email,
      );
    } catch (e, st) {
      debugPrint('GoogleCalendarAuthHelper GIS silent: $e\n$st');
      return GoogleCalendarAuthResult(errorMessage: _friendlyError(e));
    }
  }

  /// Web: Firebase Auth (login Google) ou GIS (Apple + Gmail separado).
  static Future<GoogleCalendarAuthResult> _requestWebInteractive({
    String? preferredEmail,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const GoogleCalendarAuthResult(
        errorMessage: 'Sessão inválida. Entre novamente.',
      );
    }
    if (!isApplePrimaryLogin()) {
      final fb = await _requestWebFirebaseCalendarAuth(
        preferredEmail: preferredEmail,
      );
      if (fb.ok || fb.cancelled) return fb;
      final err = (fb.errorMessage ?? '').toLowerCase();
      if (err.contains('negada') || err.contains('permission')) return fb;
    }
    return _requestGoogleSignInInteractive(preferredEmail: preferredEmail);
  }

  /// Web — popup Firebase (mesmo fluxo do login), evita origin_mismatch do GIS.
  static Future<GoogleCalendarAuthResult> _requestWebFirebaseCalendarAuth({
    String? preferredEmail,
  }) async {
    try {
      return await FirestoreWebGuard.runWebGoogleSignInFlow(() async {
        final provider = GoogleAuthProvider();
        provider.addScope(_calendarScope);
        final params = <String, String>{
          'include_granted_scopes': 'true',
        };
        if (preferredEmail != null && preferredEmail.isNotEmpty) {
          params['login_hint'] = preferredEmail;
        }
        provider.setCustomParameters(params);

        final auth = FirebaseAuth.instance;
        final user = auth.currentUser;
        if (user == null) {
          return const GoogleCalendarAuthResult(
            errorMessage: 'Sessão inválida. Entre novamente.',
          );
        }

        final UserCredential cred;
        final hasGoogle =
            user.providerData.any((p) => p.providerId == 'google.com');
        if (hasGoogle) {
          cred = await user.reauthenticateWithProvider(provider);
        } else {
          cred = await auth.signInWithPopup(provider);
        }

        final oauthCred = cred.credential;
        final token = oauthCred is OAuthCredential ? oauthCred.accessToken : null;
        if (token == null || token.isEmpty) {
          return const GoogleCalendarAuthResult(
            errorMessage: 'Não foi possível obter token do Google Calendar.',
          );
        }

        final email = cred.user?.email ?? preferredEmail;
        await cacheToken(token, email: email);
        return GoogleCalendarAuthResult(
          accessToken: token,
          email: email,
        );
      });
    } catch (e, st) {
      debugPrint('GoogleCalendarAuthHelper Firebase web calendar: $e\n$st');
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

  static Future<GoogleCalendarAuthResult> _requestGoogleSignInInteractive({
    String? preferredEmail,
  }) async {
    try {
      final gs = _calendarSignIn(
        webClientId: kIsWeb ? GoogleOAuthConfig.webClientId : null,
      );
      GoogleSignInAccount? account =
          await gs.signInSilently(suppressErrors: true);

      if (account != null &&
          preferredEmail != null &&
          preferredEmail.isNotEmpty &&
          account.email.trim().toLowerCase() != preferredEmail.toLowerCase()) {
        try {
          await gs.signOut();
        } catch (_) {}
        account = null;
      }

      account ??= await gs.signIn();
      if (account == null) {
        return const GoogleCalendarAuthResult(cancelled: true);
      }

      final granted = await gs.requestScopes([_calendarScope]);
      if (!granted) {
        return const GoogleCalendarAuthResult(
          errorMessage: 'Permissão do Google Calendar negada.',
        );
      }

      final auth = await account.authentication;
      final token = auth.accessToken;
      if (token == null || token.isEmpty) {
        return const GoogleCalendarAuthResult(
          errorMessage: 'Não foi possível obter token do Google Calendar.',
        );
      }

      await cacheToken(token, email: account.email);
      return GoogleCalendarAuthResult(
        accessToken: token,
        email: account.email,
      );
    } catch (e, st) {
      debugPrint('GoogleCalendarAuthHelper GIS interactive: $e\n$st');
      if (_userCancelled(e)) {
        return const GoogleCalendarAuthResult(cancelled: true);
      }
      return GoogleCalendarAuthResult(errorMessage: _friendlyError(e));
    }
  }

  static Future<GoogleCalendarAuthResult> _requestMobileInteractive({
    String? preferredEmail,
  }) async {
    try {
      final silent = await _requestMobileSilent(preferredEmail: preferredEmail);
      if (silent.ok) return silent;

      final gs = _calendarSignIn();
      GoogleSignInAccount? account =
          await gs.signInSilently(suppressErrors: true);

      if (account != null &&
          preferredEmail != null &&
          preferredEmail.isNotEmpty &&
          account.email.trim().toLowerCase() != preferredEmail.toLowerCase()) {
        try {
          await gs.signOut();
        } catch (_) {}
        account = null;
      }

      account ??= await gs.signIn();
      if (account == null) {
        return const GoogleCalendarAuthResult(cancelled: true);
      }

      final granted = await gs.requestScopes([_calendarScope]);
      if (!granted) {
        return const GoogleCalendarAuthResult(
          errorMessage: 'Permissão do Google Calendar negada.',
        );
      }

      final auth = await account.authentication;
      final token = auth.accessToken;
      if (token == null || token.isEmpty) {
        return const GoogleCalendarAuthResult(
          errorMessage: 'Não foi possível obter token do Google Calendar.',
        );
      }

      await cacheToken(token, email: account.email);
      return GoogleCalendarAuthResult(
        accessToken: token,
        email: account.email,
      );
    } catch (e, st) {
      debugPrint('GoogleCalendarAuthHelper mobile interactive: $e\n$st');
      if (_userCancelled(e)) {
        return const GoogleCalendarAuthResult(cancelled: true);
      }
      return GoogleCalendarAuthResult(errorMessage: _friendlyError(e));
    }
  }

  static Future<GoogleCalendarAuthResult> _requestMobileSilent({
    String? preferredEmail,
  }) async {
    try {
      final gs = _calendarSignIn();
      var account = await gs.signInSilently(suppressErrors: true);
      if (account == null) {
        return const GoogleCalendarAuthResult(
          errorMessage: 'Reative o Calendário Google nas configurações.',
        );
      }
      if (preferredEmail != null &&
          preferredEmail.isNotEmpty &&
          account.email.trim().toLowerCase() != preferredEmail.toLowerCase()) {
        return const GoogleCalendarAuthResult(
          errorMessage: 'Conta Google diferente da sessão.',
        );
      }

      final hasScope = await gs.canAccessScopes([_calendarScope]);
      if (!hasScope) {
        return const GoogleCalendarAuthResult(
          errorMessage: 'Permissão do calendário revogada. Ative novamente.',
        );
      }

      final auth = await account.authentication;
      final token = auth.accessToken;
      if (token == null || token.isEmpty) {
        return const GoogleCalendarAuthResult(
          errorMessage: 'Token expirado. Ative novamente o Calendário Google.',
        );
      }

      await cacheToken(token, email: account.email);
      return GoogleCalendarAuthResult(
        accessToken: token,
        email: account.email,
      );
    } catch (e, st) {
      debugPrint('GoogleCalendarAuthHelper mobile silent: $e\n$st');
      return GoogleCalendarAuthResult(errorMessage: _friendlyError(e));
    }
  }

  /// Login principal foi Apple — pode usar Gmail diferente para agenda.
  static bool isApplePrimaryLogin() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final providers = user.providerData.map((p) => p.providerId).toSet();
    return providers.contains('apple.com') && !providers.contains('google.com');
  }
}
