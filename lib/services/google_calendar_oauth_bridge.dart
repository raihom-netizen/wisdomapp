import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../constants/google_oauth_config.dart';

/// Ponte Flutter ↔ Cloud Functions (OAuth code + refresh token no servidor).
class GoogleCalendarOAuthBridge {
  GoogleCalendarOAuthBridge._();

  static final FirebaseFunctions _fn =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  /// Prazo das callables: sem ele o interruptor ficava girando até 60 s por
  /// chamada (e o fluxo fazia até 3 chamadas em série).
  static final HttpsCallableOptions _opts =
      HttpsCallableOptions(timeout: const Duration(seconds: 20));

  /// Texto amigável para falha de callable (function não publicada, fora do
  /// ar, sem login…), mostrado no painel em vez de girar sem fim.
  static String friendlyError(Object e) {
    if (e is FirebaseFunctionsException) {
      switch (e.code) {
        case 'not-found':
          return 'Serviço do Google Calendar não encontrado no servidor (function não publicada).';
        case 'unavailable':
        case 'deadline-exceeded':
          return 'O servidor demorou para responder. Verifique a internet e tente de novo.';
        case 'unauthenticated':
          return 'Sessão expirada. Saia e entre de novo.';
        default:
          final m = (e.message ?? '').trim();
          if (m.isNotEmpty && m.toUpperCase() != 'INTERNAL') return m;
          return 'Erro no servidor ao conectar o Google Calendar (${e.code}).';
      }
    }
    return e.toString().split('\n').first;
  }

  /// Último erro da troca do código (para explicar o motivo na tela).
  static String? lastExchangeError;

  static Future<GoogleCalendarServerToken?> exchangeAuthorizationCode(
    String code,
  ) async {
    if (code.trim().isEmpty) return null;
    try {
      final res = await _fn
          .httpsCallable('ctGoogleCalendarExchangeCode', options: _opts)
          .call<Map<String, dynamic>>({
        'code': code.trim(),
        'redirectUri': GoogleOAuthConfig.oauthRedirectUri,
      });
      return _parseTokenResponse(res.data);
    } catch (e, st) {
      debugPrint('GoogleCalendarOAuthBridge.exchangeCode: $e\n$st');
      lastExchangeError = friendlyError(e);
      rethrow;
    }
  }

  static Future<GoogleCalendarServerToken?> refreshAccessToken() async {
    try {
      final res = await _fn
          .httpsCallable('ctGoogleCalendarRefreshAccessToken', options: _opts)
          .call<Map<String, dynamic>>({});
      return _parseTokenResponse(res.data);
    } catch (e, st) {
      debugPrint('GoogleCalendarOAuthBridge.refresh: $e\n$st');
      return null;
    }
  }

  static Future<void> disconnectServerSession() async {
    try {
      await _fn
          .httpsCallable('ctGoogleCalendarDisconnect', options: _opts)
          .call({});
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
