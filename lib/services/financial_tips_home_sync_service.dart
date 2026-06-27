import 'package:cloud_firestore/cloud_firestore.dart';

/// Configuração publicada no Início dos usuários (admin → «Sincronizar»).
class FinancialTipsHomeConfig {
  const FinancialTipsHomeConfig({
    required this.homeTipIds,
    required this.favoriteTipIds,
    this.rotationOrder = const [],
    this.weekdayTipIds = const {},
    this.syncedAt,
    this.syncedByEmail = '',
  });

  /// IDs marcados «Início» (legado + base da rotação).
  final List<String> homeTipIds;

  /// Ordem explícita da rotação diária (se vazio, usa [homeTipIds]).
  final List<String> rotationOrder;

  /// Dia da semana (1=seg … 7=dom) → ID da dica fixa naquele dia.
  final Map<int, String> weekdayTipIds;

  final List<String> favoriteTipIds;
  final DateTime? syncedAt;
  final String syncedByEmail;

  bool get hasSelection =>
      homeTipIds.isNotEmpty ||
      rotationOrder.isNotEmpty ||
      weekdayTipIds.values.any((id) => id.isNotEmpty);

  /// Ordem efetiva para alternar dia a dia.
  List<String> get effectiveRotationOrder =>
      rotationOrder.isNotEmpty ? rotationOrder : homeTipIds;
}

/// Publica dicas selecionadas no Início (`app_config/financial_tips_home`).
class FinancialTipsHomeSyncService {
  static const docId = 'financial_tips_home';
  static const docPath = 'app_config/financial_tips_home';

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Map<int, String> _parseWeekdayMap(dynamic raw) {
    final out = <int, String>{};
    if (raw is! Map) return out;
    raw.forEach((key, value) {
      final day = int.tryParse(key.toString());
      final id = value?.toString().trim() ?? '';
      if (day != null && day >= 1 && day <= 7 && id.isNotEmpty) {
        out[day] = id;
      }
    });
    return out;
  }

  static List<String> _parseIdList(dynamic raw) {
    if (raw is! List) return [];
    return raw.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
  }

  static FinancialTipsHomeConfig? parse(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return null;
    final homeIds = _parseIdList(data['homeTipIds']);
    final rotation = _parseIdList(data['rotationOrder']);
    final favIds = _parseIdList(data['favoriteTipIds']);
    final weekday = _parseWeekdayMap(data['weekdayTipIds']);
    if (homeIds.isEmpty &&
        rotation.isEmpty &&
        weekday.isEmpty &&
        favIds.isEmpty) {
      return null;
    }

    DateTime? syncedAt;
    final ts = data['syncedAt'];
    if (ts is Timestamp) syncedAt = ts.toDate();

    return FinancialTipsHomeConfig(
      homeTipIds: homeIds,
      rotationOrder: rotation,
      weekdayTipIds: weekday,
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
    List<String> rotationOrder = const [],
    Map<int, String> weekdayTipIds = const {},
    required String syncedByEmail,
  }) async {
    final weekdayPayload = <String, String>{};
    weekdayTipIds.forEach((day, id) {
      if (id.trim().isNotEmpty) weekdayPayload['$day'] = id.trim();
    });
    await _db.doc(docPath).set({
      'homeTipIds': homeTipIds,
      'favoriteTipIds': favoriteTipIds,
      'rotationOrder': rotationOrder,
      'weekdayTipIds': weekdayPayload,
      'syncedAt': FieldValue.serverTimestamp(),
      'syncedByEmail': syncedByEmail.trim(),
    }, SetOptions(merge: true));
  }
}
