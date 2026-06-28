import 'dart:async';
import 'dart:convert';

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import '../constants/google_oauth_config.dart';
import 'google_calendar_auth_helper.dart';
import 'google_calendar_oauth_bridge.dart';
import 'google_calendar_token_store.dart';

/// OAuth 2.0 Authorization Code na Web — refresh_token no servidor (Cloud Function).
class GoogleCalendarOAuthPlatform {
  GoogleCalendarOAuthPlatform._();

  static const _codeStorageKey = 'wisdomapp_gcal_auth_code';
  static const _enableUidKey = 'wisdomapp_gcal_enable_uid';

  static Future<GoogleCalendarAuthResult> ensureToken({
    required String? preferredEmail,
    required bool interactive,
    bool forceAccountPicker = false,
  }) async {
    final cached = GoogleCalendarTokenStore.cachedTokenIfValid();
    if (cached != null) {
      return GoogleCalendarAuthResult(
        accessToken: cached,
        email: preferredEmail ?? await GoogleCalendarTokenStore.storedEmail(),
      );
    }

    final server = await GoogleCalendarOAuthBridge.refreshAccessToken();
    if (server != null) {
      await GoogleCalendarTokenStore.save(
        server.accessToken,
        email: server.email ?? preferredEmail,
        expiresAt: server.expiresAt,
      );
      return GoogleCalendarAuthResult(
        accessToken: server.accessToken,
        email: server.email ?? preferredEmail,
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
    final returnUrl = html.window.location.href;
    final params = <String, String>{
      'start': '1',
      'return': returnUrl,
    };
    final email = preferredEmail?.trim();
    if (email != null && email.isNotEmpty) params['email'] = email;
    if (enableUserDocId != null && enableUserDocId.isNotEmpty) {
      params['enable_uid'] = enableUserDocId;
      html.window.sessionStorage[_enableUidKey] = enableUserDocId;
    }
    if (selectAccount) params['select_account'] = '1';
    if (promptNone) params['prompt'] = 'none';

    html.window.location.assign(GoogleOAuthConfig.buildOAuthStartUrl(params));
  }

  /// Lê authorization code após redirect e troca no servidor.
  static Future<bool> consumeWebOAuthReturn() async {
    if (await _consumeHashPayload()) return true;
    return _consumeSessionCode();
  }

  static Future<bool> _consumeHashPayload() async {
    final hash = html.window.location.hash;
    if (!hash.contains('gcal_payload=')) return false;
    try {
      final idx = hash.indexOf('gcal_payload=');
      var payload = hash.substring(idx + 'gcal_payload='.length);
      final amp = payload.indexOf('&');
      if (amp >= 0) payload = payload.substring(0, amp);
      final decoded = Uri.decodeComponent(payload);
      final map = jsonDecode(decoded) as Map<String, dynamic>;
      final code = (map['authorization_code'] ?? '').toString().trim();
      _stripHashFromUrl();
      if (code.isEmpty) return false;
      return _exchangeCodeAndCache(code);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _consumeSessionCode() async {
    final code = html.window.sessionStorage[_codeStorageKey];
    if (code == null || code.trim().isEmpty) return false;
    html.window.sessionStorage.remove(_codeStorageKey);
    return _exchangeCodeAndCache(code.trim());
  }

  static Future<bool> _exchangeCodeAndCache(String code) async {
    try {
      final server = await GoogleCalendarOAuthBridge.exchangeAuthorizationCode(code);
      if (server == null || server.accessToken.isEmpty) return false;

      await GoogleCalendarTokenStore.save(
        server.accessToken,
        email: server.email,
        expiresAt: server.expiresAt,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  static void _stripHashFromUrl() {
    final path = html.window.location.pathname;
    final search = html.window.location.search;
    html.window.history.replaceState(null, '', '$path$search');
  }

  static String? pendingEnableUserDocId() {
    final v = html.window.sessionStorage[_enableUidKey];
    if (v == null || v.trim().isEmpty) return null;
    return v.trim();
  }

  static void clearPendingEnableUserDocId() {
    html.window.sessionStorage.remove(_enableUidKey);
  }

  static Future<void> signOutCalendarSession() async {
    html.window.sessionStorage.remove(_codeStorageKey);
    html.window.sessionStorage.remove(_enableUidKey);
  }

  static Object? sharedSignIn() => null;
}
