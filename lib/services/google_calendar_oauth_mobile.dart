import 'package:google_sign_in/google_sign_in.dart';

import '../constants/google_oauth_config.dart';
import 'google_calendar_auth_helper.dart';

/// OAuth Google Calendar via [google_sign_in] (Android / iOS).
class GoogleCalendarOAuthPlatform {
  GoogleCalendarOAuthPlatform._();

  static const _calendarScope = GoogleOAuthConfig.calendarScope;
  static const _scopes = [_calendarScope, 'email', 'profile'];

  static GoogleSignIn? _gsi;

  static GoogleSignIn _signIn({bool recreate = false}) {
    if (recreate || _gsi == null) {
      _gsi = GoogleSignIn(
        scopes: _scopes,
        serverClientId: GoogleOAuthConfig.webClientId,
      );
    }
    return _gsi!;
  }

  static GoogleSignIn sharedSignIn() => _signIn();

  static Future<void> signOutCalendarSession() async {
    try {
      await _signIn().signOut();
    } catch (_) {}
  }

  static Future<GoogleCalendarAuthResult> ensureToken({
    required String? preferredEmail,
    required bool interactive,
    bool forceAccountPicker = false,
  }) async {
    if (forceAccountPicker) {
      try {
        await _signIn(recreate: true).signOut();
      } catch (_) {}
    }

    final gs = _signIn();
    var account = await gs.signInSilently(suppressErrors: true);

    final hint = preferredEmail?.trim();
    if (account != null &&
        hint != null &&
        hint.isNotEmpty &&
        account.email.trim().toLowerCase() != hint.toLowerCase()) {
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

    final auth = await account.authentication;
    var token = auth.accessToken;
    if (token == null || token.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      token = (await account.authentication).accessToken;
    }
    if (token == null || token.isEmpty) {
      return GoogleCalendarAuthResult(
        needsInteractive: interactive,
        email: account.email,
        errorMessage: 'Token Google indisponível.',
      );
    }

    return GoogleCalendarAuthResult(
      accessToken: token,
      email: account.email,
    );
  }

  static Future<bool> consumeWebOAuthReturn() async => false;

  static String? pendingEnableUserDocId() => null;

  static void clearPendingEnableUserDocId() {}

  static void startWebOAuthRedirect({
    required String? preferredEmail,
    String? enableUserDocId,
    bool selectAccount = false,
    bool promptNone = false,
  }) {}
}
