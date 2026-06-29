import 'dart:io' show Platform;

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../constants/google_oauth_config.dart';
import 'google_calendar_auth_helper.dart';

/// OAuth Google Calendar via [google_sign_in] (Android / iOS).
///
/// iOS: `canAccessScopes()` / `requestScopes()` não existem na plataforma —
/// escopos vêm do `signIn()` com [scopes] + validação real na API Calendar.
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
        clientId: Platform.isIOS ? GoogleOAuthConfig.iosClientId : null,
      );
    }
    return _gsi!;
  }

  static GoogleSignIn sharedSignIn() => _signIn();

  static Future<void> signOutCalendarSession() async {
    try {
      await _signIn().signOut();
    } catch (_) {}
    _gsi = null;
  }

  /// Confirma que o token acessa calendar.events (substitui canAccessScopes no iOS).
  static Future<bool> _tokenGrantsCalendarAccess(String token) async {
    if (token.isEmpty) return false;
    try {
      final uri = Uri.parse(
        'https://www.googleapis.com/calendar/v3/calendars/primary/events?maxResults=1',
      );
      final res = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> _readAccessToken(GoogleSignInAccount account) async {
    var auth = await account.authentication;
    var token = auth.accessToken;
    if (token != null && token.isNotEmpty) return token;
    await Future<void>.delayed(const Duration(milliseconds: 150));
    auth = await account.authentication;
    return auth.accessToken;
  }

  static Future<GoogleCalendarAuthResult> _resultFromAccount(
    GoogleSignInAccount account, {
    required bool interactive,
  }) async {
    var token = await _readAccessToken(account);
    if (token != null &&
        token.isNotEmpty &&
        await _tokenGrantsCalendarAccess(token)) {
      return GoogleCalendarAuthResult(
        accessToken: token,
        email: account.email,
      );
    }

    if (!interactive) {
      return GoogleCalendarAuthResult(
        needsInteractive: true,
        email: account.email,
        errorMessage: 'Autorize o Google Calendar para sincronizar.',
      );
    }

    // Sessão Google sem escopo de calendário — novo signIn com scopes.
    try {
      await _signIn().signOut();
    } catch (_) {}
    _gsi = null;
    final gs = _signIn(recreate: true);
    final fresh = await gs.signIn();
    if (fresh == null) {
      return const GoogleCalendarAuthResult(cancelled: true);
    }
    token = await _readAccessToken(fresh);
    if (token == null || token.isEmpty) {
      return GoogleCalendarAuthResult(
        email: fresh.email,
        errorMessage: 'Token Google indisponível.',
      );
    }
    if (!await _tokenGrantsCalendarAccess(token)) {
      return const GoogleCalendarAuthResult(
        errorMessage:
            'Permissão do Google Calendar negada ou indisponível nesta conta.',
      );
    }
    return GoogleCalendarAuthResult(
      accessToken: token,
      email: fresh.email,
    );
  }

  static Future<GoogleCalendarAuthResult> ensureToken({
    required String? preferredEmail,
    required bool interactive,
    bool forceAccountPicker = false,
  }) async {
    if (forceAccountPicker) {
      await signOutCalendarSession();
    }

    final gs = _signIn();
    GoogleSignInAccount? account;

    try {
      account = await gs.signInSilently(suppressErrors: true);
    } catch (_) {
      account = null;
    }

    final hint = preferredEmail?.trim();
    if (account != null &&
        hint != null &&
        hint.isNotEmpty &&
        account.email.trim().toLowerCase() != hint.toLowerCase()) {
      if (interactive || forceAccountPicker) {
        await signOutCalendarSession();
        account = null;
      } else {
        return const GoogleCalendarAuthResult(
          errorMessage: 'Conta Google diferente da vinculada.',
        );
      }
    }

    if (account == null && interactive) {
      try {
        account = await _signIn().signIn();
      } catch (e) {
        final msg = e.toString();
        if (msg.contains('cancel') || msg.contains('Cancel')) {
          return const GoogleCalendarAuthResult(cancelled: true);
        }
        return GoogleCalendarAuthResult(
          errorMessage: msg.split('\n').first,
        );
      }
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

    try {
      return await _resultFromAccount(
        account,
        interactive: interactive,
      );
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('UnimplementedError')) {
        if (!interactive) {
          return GoogleCalendarAuthResult(
            needsInteractive: true,
            email: account.email,
            errorMessage: 'Autorize o Google Calendar para sincronizar.',
          );
        }
        await signOutCalendarSession();
        try {
          final retry = await _signIn(recreate: true).signIn();
          if (retry == null) {
            return const GoogleCalendarAuthResult(cancelled: true);
          }
          return await _resultFromAccount(retry, interactive: true);
        } catch (e2) {
          return GoogleCalendarAuthResult(
            errorMessage: e2.toString().split('\n').first,
          );
        }
      }
      rethrow;
    }
  }

  static Future<bool> consumeWebOAuthReturn() async => false;

  static String? pendingEnableUserDocId() => null;

  static void clearPendingEnableUserDocId() {}

  static void startWebOAuthRedirect({
    required String? preferredEmail,
    String? enableUserDocId,
    bool selectAccount = false,
    bool promptNone = false,
    bool forceConsent = false,
  }) {}
}
