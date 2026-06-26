import 'package:cloud_firestore/cloud_firestore.dart';

/// `app_config/pro_open_finance` — teto global de conexões bancárias (PRO + extras), editável no Admin.
class ProOpenFinanceConfig {
  const ProOpenFinanceConfig({required this.maxTotalBankConnections});

  /// Máximo de conexões Open Finance **simultâneas** (incluídas + pagas), p.ex. 5.
  final int maxTotalBankConnections;

  static const int defaultMaxTotal = 5;

  static ProOpenFinanceConfig fromFirestore(Map<String, dynamic>? raw) {
    final d = parseMax(raw?['maxTotalBankConnections'] ?? raw?['max_total_bank_connections']);
    return ProOpenFinanceConfig(maxTotalBankConnections: d ?? defaultMaxTotal);
  }

  static int? parseMax(dynamic v) {
    if (v == null) return null;
    if (v is int) return v.clamp(1, 99);
    if (v is num) return v.toInt().clamp(1, 99);
    final n = int.tryParse(v.toString().trim());
    if (n == null) return null;
    return n.clamp(1, 99);
  }
}

class ProOpenFinanceConfigService {
  ProOpenFinanceConfigService._();

  static final DocumentReference<Map<String, dynamic>> _doc =
      FirebaseFirestore.instance.collection('app_config').doc('pro_open_finance');

  static Stream<ProOpenFinanceConfig> watch() {
    return _doc.snapshots().map((s) => ProOpenFinanceConfig.fromFirestore(s.data()));
  }

  static Future<ProOpenFinanceConfig> getOnce() async {
    final s = await _doc.get();
    return ProOpenFinanceConfig.fromFirestore(s.data());
  }

  static ProOpenFinanceConfig currentOrDefault(ProOpenFinanceConfig? c) => c ?? ProOpenFinanceConfig.fromFirestore(null);

  /// Capacidade efetiva: `min(incluídas + extras ativas, teto global)`.
  static int effectiveConnectionCapacity({
    required int includedSlots,
    required int validExtraEntitlementCount,
    required int maxTotalBankConnections,
  }) {
    final sum = includedSlots + validExtraEntitlementCount;
    return sum < maxTotalBankConnections ? sum : maxTotalBankConnections;
  }

  /// Ainda é possível **comprar** mais um add-on? (não confundir com ainda ter slot vazio.)
  static bool canPurchaseAnotherExtra({
    required int includedSlots,
    required int validExtraEntitlementCount,
    required int maxTotalBankConnections,
  }) {
    return includedSlots + validExtraEntitlementCount < maxTotalBankConnections;
  }
}
