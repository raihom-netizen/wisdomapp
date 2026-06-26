import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

import 'functions_service.dart';

/// Open Finance / Pluggy: connect token no servidor + abertura do fluxo seguro + observação de status no Firestore.
///
/// O [connectUrl] ou [widgetUrl] vem da Cloud Function `ctCreatePluggyConnectToken` (chave Pluggy só no backend).
class BankIntegrationService {
  BankIntegrationService._();

  static final FunctionsService _fn = FunctionsService();

  /// Chama o backend para obter URL de conexão Pluggy (ou erro `configured: false`).
  static Future<Map<String, dynamic>> requestPluggyConnectToken({String? redirectUri}) async {
    return _fn.createPluggyConnectToken(redirectUri: redirectUri);
  }

  /// Abre o fluxo seguro no navegador / visualização externa (recomendado para OAuth institucional).
  static Future<bool> launchSecureConnectUrl(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Observa um documento em `users/{uid}/bank_connections/{connectionId}` até o app atualizar status (ex.: `connected`).
  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchBankConnection({
    required String uid,
    required String connectionDocId,
  }) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('bank_connections')
        .doc(connectionDocId)
        .snapshots();
  }

  static bool isConnectionReady(Map<String, dynamic>? data) {
    final s = (data?['status'] ?? '').toString().toLowerCase();
    return s == 'connected' || s == 'ready';
  }
}
