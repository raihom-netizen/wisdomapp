import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../constants/google_oauth_config.dart';

/// Ponte Flutter ↔ Cloud Functions (OAuth code + refresh token no servidor).
class GoogleCalendarOAuthBridge {
  GoogleCalendarOAuthBridge._();

  static final FirebaseFunctions _fn =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  static Future<GoogleCalendarServerToken?> exchangeAuthorizationCode(
    String code,
  ) async {
    if (code.trim().isEmpty) return null;
    try {
      final res = await _fn
          .httpsCallable('ctGoogleCalendarExchangeCode')
          .call<Map<String, dynamic>>({
        'code': code.trim(),
        'redirectUri': GoogleOAuthConfig.oauthRedirectUri,
      });
      return _parseTokenResponse(res.data);
    } catch (e, st) {
      debugPrint('GoogleCalendarOAuthBridge.exchangeCode: $e\n$st');
      rethrow;
    }
  }

  static Future<GoogleCalendarServerToken?> refreshAccessToken() async {
    try {
      final res = await _fn
          .httpsCallable('ctGoogleCalendarRefreshAccessToken')
          .call<Map<String, dynamic>>({});
      return _parseTokenResponse(res.data);
    } catch (e, st) {
      debugPrint('GoogleCalendarOAuthBridge.refresh: $e\n$st');
      return null;
    }
  }

  static Future<void> disconnectServerSession() async {
    try {
      await _fn.httpsCallable('ctGoogleCalendarDisconnect').call({});
    } catch (e, st) {
      debugPrint('GoogleCalendarOAuthBridge.disconnect: $e\n$st');
    }
  }

  static GoogleCalendarServerToken? _parseTokenResponse(
    Map<String, dynamic>? data,
  ) {
    if (data == null || data['ok'] != true) return null;
    final token = (data['accessToken'] ?? '').toString().trim();
    if (token.isEmpty) return null;
    final expiresAtRaw = data['expiresAt'];
    DateTime? expiresAt;
    if (expiresAtRaw is num) {
      expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresAtRaw.toInt());
    }
    final email = (data['email'] ?? '').toString().trim();
    return GoogleCalendarServerToken(
      accessToken: token,
      expiresAt: expiresAt,
      email: email.isEmpty ? null : email,
      hasRefreshToken: data['hasRefreshToken'] == true,
    );
  }
}

class GoogleCalendarServerToken {
  const GoogleCalendarServerToken({
    required this.accessToken,
    this.expiresAt,
    this.email,
    this.hasRefreshToken = false,
  });

  final String accessToken;
  final DateTime? expiresAt;
  final String? email;
  final bool hasRefreshToken;
}
