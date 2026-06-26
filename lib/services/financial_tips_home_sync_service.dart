import 'package:cloud_firestore/cloud_firestore.dart';

/// Configuração publicada no Início dos usuários (admin → «Sincronizar»).
class FinancialTipsHomeConfig {
  const FinancialTipsHomeConfig({
    required this.homeTipIds,
    required this.favoriteTipIds,
    this.syncedAt,
    this.syncedByEmail = '',
  });

  final List<String> homeTipIds;
  final List<String> favoriteTipIds;
  final DateTime? syncedAt;
  final String syncedByEmail;

  bool get hasSelection => homeTipIds.isNotEmpty;
}

/// Publica dicas selecionadas no Início (`app_config/financial_tips_home`).
class FinancialTipsHomeSyncService {
  static const docId = 'financial_tips_home';
  static const docPath = 'app_config/financial_tips_home';

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static FinancialTipsHomeConfig? parse(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return null;
    final homeRaw = data['homeTipIds'];
    final favRaw = data['favoriteTipIds'];
    final homeIds = homeRaw is List
        ? homeRaw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
        : <String>[];
    final favIds = favRaw is List
        ? favRaw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
        : <String>[];
    if (homeIds.isEmpty && favIds.isEmpty) return null;

    DateTime? syncedAt;
    final ts = data['syncedAt'];
    if (ts is Timestamp) syncedAt = ts.toDate();

    return FinancialTipsHomeConfig(
      homeTipIds: homeIds,
      favoriteTipIds: favIds,
      syncedAt: syncedAt,
      syncedByEmail: (data['syncedByEmail'] ?? '').toString(),
    );
  }

  Future<FinancialTipsHomeConfig?> loadOnce() async {
    final snap = await _db.doc(docPath).get();
    return parse(snap.data());
  }

  Future<void> publish({
    required List<String> homeTipIds,
    required List<String> favoriteTipIds,
    required String syncedByEmail,
  }) async {
    await _db.doc(docPath).set({
      'homeTipIds': homeTipIds,
      'favoriteTipIds': favoriteTipIds,
      'syncedAt': FieldValue.serverTimestamp(),
      'syncedByEmail': syncedByEmail.trim(),
    }, SetOptions(merge: true));
  }
}
