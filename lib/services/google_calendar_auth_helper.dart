import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import 'google_calendar_oauth_platform.dart';
import 'google_calendar_token_store.dart';

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

/// Sessão Google Calendar — Web: OAuth 2.0 redirect; mobile: google_sign_in.
class GoogleCalendarAuthHelper {
  GoogleCalendarAuthHelper._();

  static Future<void> cacheToken(String token, {String? email}) =>
      GoogleCalendarTokenStore.save(token, email: email);

  static Future<void> clearCache() => GoogleCalendarTokenStore.clear();

  static Future<String?> storedCalendarEmail() =>
      GoogleCalendarTokenStore.storedEmail();

  static String? cachedTokenIfValid() =>
      GoogleCalendarTokenStore.cachedTokenIfValid();

  static Future<bool> hasStoredCalendarLink() async {
    final email = await storedCalendarEmail();
    return email != null && email.isNotEmpty;
  }

  /// Após redirect OAuth na Web — lê token do localStorage.
  static Future<bool> consumeWebOAuthReturn() =>
      GoogleCalendarOAuthPlatform.consumeWebOAuthReturn();

  static String? pendingWebEnableUserDocId() =>
      GoogleCalendarOAuthPlatform.pendingEnableUserDocId();

  static void clearPendingWebEnableUserDocId() =>
      GoogleCalendarOAuthPlatform.clearPendingEnableUserDocId();

  /// Redireciona para OAuth Google (somente Web).
  static void startWebOAuthRedirect({
    String? preferredEmail,
    String? enableUserDocId,
    bool selectAccount = false,
  }) {
    GoogleCalendarOAuthPlatform.startWebOAuthRedirect(
      preferredEmail: preferredEmail,
      enableUserDocId: enableUserDocId,
      selectAccount: selectAccount,
    );
  }

  static Future<void> bootstrapSession({String? preferredEmail}) async {
    await GoogleCalendarTokenStore.hydrateFromPrefs();
    if (cachedTokenIfValid() != null) return;
    if (!kIsWeb) {
      unawaited(
        ensureToken(preferredEmail: preferredEmail, interactive: false),
      );
    }
  }

  static Future<GoogleCalendarAuthResult> requestSilent({
    String? preferredEmail,
  }) =>
      ensureToken(preferredEmail: preferredEmail, interactive: false);

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

  static Future<GoogleCalendarAuthResult> refreshAfterUnauthorized({
    String? preferredEmail,
  }) async {
    await clearCache();
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

  static Future<GoogleCalendarAuthResult> ensureToken({
    String? preferredEmail,
    required bool interactive,
    bool forceAccountPicker = false,
  }) {
    return _ensureTokenCore(
      preferredEmail: preferredEmail,
      interactive: interactive,
      forceAccountPicker: forceAccountPicker,
    );
  }

  static Future<GoogleCalendarAuthResult>? _inFlight;

  static Future<GoogleCalendarAuthResult> _ensureTokenCore({
    String? preferredEmail,
    required bool interactive,
    bool forceAccountPicker = false,
  }) async {
    if (_inFlight != null) return _inFlight!;

    _inFlight = _doEnsure(
      preferredEmail: preferredEmail,
      interactive: interactive,
      forceAccountPicker: forceAccountPicker,
    ).whenComplete(() => _inFlight = null);

    return _inFlight!;
  }

  static Future<GoogleCalendarAuthResult> _doEnsure({
    String? preferredEmail,
    required bool interactive,
    bool forceAccountPicker = false,
  }) async {
    await GoogleCalendarTokenStore.hydrateFromPrefs();

    final cached = cachedTokenIfValid();
    if (cached != null) {
      return GoogleCalendarAuthResult(
        accessToken: cached,
        email: preferredEmail ?? await storedCalendarEmail(),
      );
    }

    if (forceAccountPicker) {
      await clearCache();
      await GoogleCalendarOAuthPlatform.signOutCalendarSession();
    }

    try {
      final hint = _resolveEmailHint(preferredEmail);
      final result = await GoogleCalendarOAuthPlatform.ensureToken(
        preferredEmail: hint,
        interactive: interactive,
        forceAccountPicker: forceAccountPicker,
      );

      if (result.ok && result.accessToken != null) {
        await cacheToken(result.accessToken!, email: result.email);
      }
      return result;
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

  static String? _resolveEmailHint(String? preferredEmail) {
    final p = preferredEmail?.trim();
    if (p != null && p.isNotEmpty) return p;
    if (isApplePrimaryLogin()) return null;
    final login = (FirebaseAuth.instance.currentUser?.email ?? '').trim();
    return login.isEmpty ? null : login;
  }

  static String _friendlyError(Object e) {
    final raw = e.toString();
    if (raw.contains('origin_mismatch')) {
      return 'Configure no Google Cloud Console (cliente OAuth Web): '
          'Origem JS: ${Uri.base.origin} · '
          'Redirect: ${Uri.base.origin}/google_calendar_oauth.html';
    }
    if (raw.contains('popup_closed') || raw.contains('cancelled')) return '';
    if (raw.contains('access_denied') || raw.contains('permission')) {
      return 'Permissão do Google Calendar negada.';
    }
    return raw.split('\n').first;
  }

  static bool _userCancelled(Object e) {
    final raw = e.toString().toLowerCase();
    return raw.contains('popup_closed') ||
        raw.contains('cancelled') ||
        raw.contains('canceled');
  }

  static GoogleSignIn? sharedSignIn() {
    if (kIsWeb) return null;
    return GoogleCalendarOAuthPlatform.sharedSignIn() as GoogleSignIn?;
  }

  static Future<void> signOutCalendarSession() async {
    await clearCache();
    await GoogleCalendarOAuthPlatform.signOutCalendarSession();
  }

  static bool isApplePrimaryLogin() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final providers = user.providerData.map((p) => p.providerId).toSet();
    return providers.contains('apple.com') && !providers.contains('google.com');
  }
}
