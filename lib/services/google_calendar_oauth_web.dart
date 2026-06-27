import 'dart:convert';

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:http/http.dart' as http;

import '../constants/google_oauth_config.dart';
import 'google_calendar_auth_helper.dart';
import 'google_calendar_token_store.dart';

/// OAuth 2.0 implícito na Web — redirecionamento (sem GIS/popup; evita origin_mismatch).
class GoogleCalendarOAuthPlatform {
  GoogleCalendarOAuthPlatform._();

  static const _oauthStorageKey = 'wisdomapp_gcal_oauth';
  static const _enableUidKey = 'wisdomapp_gcal_enable_uid';
  static const _calendarScope = GoogleOAuthConfig.calendarScope;

  static Future<GoogleCalendarAuthResult> ensureToken({
    required String? preferredEmail,
    required bool interactive,
    bool forceAccountPicker = false,
  }) async {
    final stored = _readStoredToken();
    if (stored != null) {
      final email = preferredEmail ?? await _fetchEmail(stored.token);
      return GoogleCalendarAuthResult(
        accessToken: stored.token,
        email: email,
      );
    }

    if (!interactive) {
      return GoogleCalendarAuthResult(
        needsInteractive: true,
        email: preferredEmail,
        errorMessage: 'Autorize o Google Calendar para sincronizar.',
      );
    }

    startWebOAuthRedirect(
      preferredEmail: preferredEmail,
      selectAccount: forceAccountPicker,
    );
    return const GoogleCalendarAuthResult(cancelled: true);
  }

  static void startWebOAuthRedirect({
    required String? preferredEmail,
    String? enableUserDocId,
    bool selectAccount = false,
    bool promptNone = false,
  }) {
    final returnPath =
        '${html.window.location.pathname}${html.window.location.search}';
    final params = <String, String>{
      'start': '1',
      'return': returnPath.isEmpty ? '/' : returnPath,
    };
    final email = preferredEmail?.trim();
    if (email != null && email.isNotEmpty) params['email'] = email;
    if (enableUserDocId != null && enableUserDocId.isNotEmpty) {
      params['enable_uid'] = enableUserDocId;
      html.window.sessionStorage[_enableUidKey] = enableUserDocId;
    }
    if (selectAccount) params['select_account'] = '1';
    if (promptNone) params['prompt'] = 'none';

    final qs = params.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
    html.window.location.assign('/google_calendar_oauth.html?$qs');
  }

  /// Lê token gravado por [google_calendar_oauth.html] após redirect do Google.
  static Future<bool> consumeWebOAuthReturn() async {
    final raw = html.window.localStorage[_oauthStorageKey];
    if (raw == null || raw.isEmpty) return false;

    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final token = (map['access_token'] ?? '').toString();
      final expiresAt = map['expires_at'];
      if (token.isEmpty) return false;

      if (expiresAt is num) {
        if (DateTime.now().millisecondsSinceEpoch >= expiresAt.toInt()) {
          html.window.localStorage.remove(_oauthStorageKey);
          return false;
        }
      }

      final scope = (map['scope'] ?? '').toString();
      if (scope.isNotEmpty && !scope.contains(_calendarScope)) {
        return false;
      }

      final email = await _fetchEmail(token);
      await GoogleCalendarTokenStore.save(token, email: email);
      html.window.localStorage.remove(_oauthStorageKey);
      return true;
    } catch (_) {
      return false;
    }
  }

  static String? pendingEnableUserDocId() {
    final v = html.window.sessionStorage[_enableUidKey];
    if (v == null || v.trim().isEmpty) return null;
    return v.trim();
  }

  static void clearPendingEnableUserDocId() {
    html.window.sessionStorage.remove(_enableUidKey);
  }

  static ({String token, DateTime until})? _readStoredToken() {
    final raw = html.window.localStorage[_oauthStorageKey];
    if (raw != null && raw.isNotEmpty) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final token = (map['access_token'] ?? '').toString();
        final expiresAt = map['expires_at'];
        if (token.isNotEmpty && expiresAt is num) {
          final until =
              DateTime.fromMillisecondsSinceEpoch(expiresAt.toInt());
          if (DateTime.now().isBefore(until)) {
            return (token: token, until: until);
          }
        }
      } catch (_) {}
    }
    return null;
  }

  static Future<String?> _fetchEmail(String token) async {
    try {
      final res = await http.get(
        Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final email = (body['email'] ?? '').toString().trim();
        if (email.isNotEmpty) return email;
      }
    } catch (_) {}
    return null;
  }

  static Future<void> signOutCalendarSession() async {
    html.window.localStorage.remove(_oauthStorageKey);
    html.window.sessionStorage.remove(_enableUidKey);
  }

  static Object? sharedSignIn() => null;
}
