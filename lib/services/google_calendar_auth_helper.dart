import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/google_oauth_config.dart';
import '../utils/firestore_web_guard.dart';

/// Resultado ao pedir acesso ao Google Calendar.
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

/// Obtém token OAuth do Google Calendar (Web = Firebase Auth + GIS; mobile = google_sign_in).
class GoogleCalendarAuthHelper {
  GoogleCalendarAuthHelper._();

  static const _calendarScope = GoogleOAuthConfig.calendarScope;

  static const _prefsTokenKey = 'google_calendar_access_token';
  static const _prefsTokenUntilKey = 'google_calendar_access_until_ms';
  static const _prefsTokenEmailKey = 'google_calendar_token_email';

  static String? _cachedToken;
  static DateTime? _cachedUntil;
  static const _cacheTtl = Duration(minutes: 50);

  static Map<String, String> _webOAuthParams({
    String? email,
    bool silent = false,
    bool forceConsent = false,
  }) {
    final params = <String, String>{
      'include_granted_scopes': 'true',
      'access_type': 'online',
    };
    final hint = email?.trim();
    if (hint != null && hint.isNotEmpty) {
      params['login_hint'] = hint;
    }
    if (silent) {
      params['prompt'] = 'none';
    } else if (forceConsent) {
      params['prompt'] = 'consent';
    }
    return params;
  }

  static String? _resolveEmail({
    String? preferredEmail,
    User? user,
  }) {
    final preferred = preferredEmail?.trim();
    if (preferred != null && preferred.isNotEmpty) return preferred;
    final login = (user?.email ?? '').trim();
    if (login.isNotEmpty) return login;
    return null;
  }

  static Future<void> cacheToken(String token, {String? email}) async {
    _cachedToken = token;
    _cachedUntil = DateTime.now().add(_cacheTtl);
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

  static Future<GoogleCalendarAuthResult?> _loadPersistedToken({
    String? preferredEmail,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_prefsTokenKey);
      final untilMs = prefs.getInt(_prefsTokenUntilKey);
      if (token == null || token.isEmpty || untilMs == null) return null;
      if (DateTime.now().millisecondsSinceEpoch >= untilMs) {
        await clearCache();
        return null;
      }
      final storedEmail = (prefs.getString(_prefsTokenEmailKey) ?? '').trim();
      if (preferredEmail != null &&
          preferredEmail.isNotEmpty &&
          storedEmail.isNotEmpty &&
          storedEmail.toLowerCase() != preferredEmail.toLowerCase()) {
        return null;
      }
      _cachedToken = token;
      _cachedUntil = DateTime.fromMillisecondsSinceEpoch(untilMs);
      return GoogleCalendarAuthResult(
        accessToken: token,
        email: storedEmail.isEmpty ? preferredEmail : storedEmail,
      );
    } catch (_) {
      return null;
    }
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
      return 'Origem do site não autorizada no Google Cloud. '
          'Adicione ${Uri.base.origin} em «Origens JavaScript autorizadas» '
          'do cliente OAuth Web do projeto wisdomapp-b9e98.';
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

  static bool _needsInteractive(Object e) {
    final raw = e.toString().toLowerCase();
    return raw.contains('interaction_required') ||
        raw.contains('login_required') ||
        raw.contains('consent_required') ||
        raw.contains('account_selection_required') ||
        raw.contains('user_not_signed_in');
  }

  /// Pedido interativo (ativar sync) — tenta silencioso antes de abrir popup.
  static Future<GoogleCalendarAuthResult> requestInteractive({
    String? preferredEmail,
  }) async {
    final silent = await requestSilent(preferredEmail: preferredEmail);
    if (silent.ok) return silent;

    await clearCache();
    if (kIsWeb) {
      return _requestWebInteractive(preferredEmail: preferredEmail);
    }
    return _requestMobileInteractive(preferredEmail: preferredEmail);
  }

  /// Token silencioso (leitura/sync) — sem popup quando possível.
  static Future<GoogleCalendarAuthResult> requestSilent({
    String? preferredEmail,
  }) async {
    final cached = cachedTokenIfValid();
    if (cached != null) {
      return GoogleCalendarAuthResult(
        accessToken: cached,
        email: preferredEmail,
      );
    }

    final persisted = await _loadPersistedToken(preferredEmail: preferredEmail);
    if (persisted != null && persisted.ok) return persisted;

    if (kIsWeb) {
      final gis = await _requestGoogleSignInSilent(preferredEmail: preferredEmail);
      if (gis.ok) return gis;
      return _requestWebFirebaseSilent(preferredEmail: preferredEmail);
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

      final hasScope = await gs.requestScopes([_calendarScope]);
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

  static Future<GoogleCalendarAuthResult> _requestWebFirebaseSilent({
    String? preferredEmail,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const GoogleCalendarAuthResult(
        errorMessage: 'Sessão inválida. Entre novamente.',
      );
    }
    if (!user.providerData.any((p) => p.providerId == 'google.com')) {
      return const GoogleCalendarAuthResult(
        errorMessage: 'Conta Google não vinculada.',
      );
    }

    final email = _resolveEmail(preferredEmail: preferredEmail, user: user);
    final provider = GoogleAuthProvider();
    provider.addScope(_calendarScope);
    provider.addScope('email');
    provider.setCustomParameters(_webOAuthParams(email: email, silent: true));

    try {
      final cred = await user.reauthenticateWithPopup(provider);
        await FirestoreWebGuard.stabilizeAfterWebSignIn();
        return await _fromUserCredential(cred, preferredEmail: preferredEmail);
      } catch (e, st) {
        debugPrint('GoogleCalendarAuthHelper web silent: $e\n$st');
      if (_needsInteractive(e) || _userCancelled(e)) {
        return const GoogleCalendarAuthResult(
          errorMessage: 'Autorização do calendário necessária.',
        );
      }
      return GoogleCalendarAuthResult(errorMessage: _friendlyError(e));
    }
  }

  static Future<GoogleCalendarAuthResult> _requestWebInteractive({
    String? preferredEmail,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const GoogleCalendarAuthResult(
        errorMessage: 'Sessão inválida. Entre novamente.',
      );
    }

    final email = _resolveEmail(preferredEmail: preferredEmail, user: user);

    Future<GoogleCalendarAuthResult> runFirebase() async {
      final provider = GoogleAuthProvider();
      provider.addScope(_calendarScope);
      provider.addScope('email');
      provider.setCustomParameters(
        _webOAuthParams(email: email, forceConsent: true),
      );

      try {
        final hasGoogle =
            user.providerData.any((p) => p.providerId == 'google.com');

        UserCredential cred;
        if (hasGoogle) {
          cred = await user.reauthenticateWithPopup(provider);
        } else {
          try {
            cred = await user.linkWithPopup(provider);
          } on FirebaseAuthException catch (e) {
            if (e.code == 'provider-already-linked') {
              cred = await user.reauthenticateWithPopup(provider);
            } else if (e.code == 'credential-already-in-use' ||
                e.code == 'account-exists-with-different-credential') {
              return const GoogleCalendarAuthResult(
                errorMessage:
                    'Este Gmail já está em outro cadastro WISDOMAPP. '
                    'Use outra conta Google ou entre com Google no login principal.',
              );
            } else if (e.code == 'popup-closed-by-user') {
              return const GoogleCalendarAuthResult(cancelled: true);
            } else {
              rethrow;
            }
          }
        }

        await FirestoreWebGuard.stabilizeAfterWebSignIn();
        return await _fromUserCredential(cred, preferredEmail: preferredEmail);
      } catch (e, st) {
        debugPrint('GoogleCalendarAuthHelper web: $e\n$st');
        if (_userCancelled(e)) {
          return const GoogleCalendarAuthResult(cancelled: true);
        }
        final msg = _friendlyError(e);
        return GoogleCalendarAuthResult(
          errorMessage:
              msg.isEmpty ? 'Não foi possível autorizar o Google Calendar.' : msg,
        );
      }
    }

    Future<GoogleCalendarAuthResult> run() async {
      final hasGoogle =
          user.providerData.any((p) => p.providerId == 'google.com');

      // Conta Google via Firebase Auth: popup Firebase é o caminho mais confiável na Web.
      if (hasGoogle) {
        final fb = await runFirebase();
        if (fb.ok) return fb;
        if (fb.cancelled) return fb;
        final gis = await _requestGoogleSignInInteractive(
          preferredEmail: email,
        );
        if (gis.ok) return gis;
        return fb.errorMessage != null && fb.errorMessage!.isNotEmpty
            ? fb
            : gis;
      }

      // Login Apple: escolher Gmail via GIS ou vincular conta Google.
      final gis = await _requestGoogleSignInInteractive(
        preferredEmail: email,
      );
      if (gis.ok) return gis;
      if (gis.cancelled) return gis;
      return runFirebase();
    }

    return FirestoreWebGuard.runWebGoogleSignInFlow(run);
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

  static Future<GoogleCalendarAuthResult> _fromUserCredential(
    UserCredential cred, {
    String? preferredEmail,
  }) async {
    final oauth = cred.credential;
    if (oauth is! OAuthCredential) {
      return const GoogleCalendarAuthResult(
        errorMessage: 'Resposta OAuth inválida do Google.',
      );
    }
    final token = oauth.accessToken;
    if (token == null || token.isEmpty) {
      return const GoogleCalendarAuthResult(
        errorMessage:
            'Permissão do calendário não concedida. Marque todas as caixas na janela do Google.',
      );
    }

    var email = (cred.user?.email ?? '').trim();
    if (email.isEmpty) {
      final profile = cred.additionalUserInfo?.profile;
      if (profile != null) {
        email = (profile['email'] ?? '').toString().trim();
      }
    }
    if (email.isEmpty && preferredEmail != null) {
      email = preferredEmail.trim();
    }

    await cacheToken(token, email: email.isEmpty ? null : email);
    return GoogleCalendarAuthResult(
      accessToken: token,
      email: email.isEmpty ? null : email,
    );
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

      final hasScope = await gs.requestScopes([_calendarScope]);
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
