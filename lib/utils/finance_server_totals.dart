import '../services/functions_service.dart';

/// Totais financeiros via Cloud Function (buckets + paginação no servidor).
class FinanceServerTotals {
  FinanceServerTotals._();

  static final Map<String, _FinanceServerTotalsCacheEntry> _cache = {};

  static String _cacheKey({
    required String uid,
    required DateTime from,
    required DateTime to,
    required String statusFilter,
    required String typeFilter,
  }) {
    final f = DateTime(from.year, from.month, from.day);
    final t = DateTime(to.year, to.month, to.day);
    return '$uid|${f.toIso8601String()}|${t.toIso8601String()}|$statusFilter|$typeFilter';
  }

  static FinanceServerTotalsResult? peekCached({
    required String uid,
    required DateTime from,
    required DateTime to,
    String statusFilter = 'paid',
    String typeFilter = 'all',
    Duration maxAge = const Duration(minutes: 3),
  }) {
    if (uid.isEmpty) return null;
    final key = _cacheKey(
      uid: uid,
      from: from,
      to: to,
      statusFilter: statusFilter,
      typeFilter: typeFilter,
    );
    final hit = _cache[key];
    if (hit == null || DateTime.now().difference(hit.at) > maxAge) return null;
    return hit.result;
  }

  static void invalidateForUser(String uid) {
    if (uid.isEmpty) return;
    _cache.removeWhere((k, _) => k.startsWith('$uid|'));
  }

  static Future<FinanceServerTotalsResult> load({
    required String uid,
    required DateTime from,
    required DateTime to,
    String statusFilter = 'paid',
    String typeFilter = 'all',
    Duration cacheTtl = const Duration(minutes: 3),
  }) async {
    if (uid.isEmpty) {
      return const FinanceServerTotalsResult(
        openingTotal: 0,
        openingByAccount: {},
        income: 0,
        expense: 0,
        periodByAccount: {},
        pendingExpenseCount: 0,
      );
    }
    final key = _cacheKey(
      uid: uid,
      from: from,
      to: to,
      statusFilter: statusFilter,
      typeFilter: typeFilter,
    );
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.at) < cacheTtl) {
      return hit.result;
    }
    final raw = await FunctionsService().financePeriodTotals(
      from: from,
      to: to,
      statusFilter: statusFilter,
      typeFilter: typeFilter,
    );
    final openingByAccount = <String, double>{};
    final periodByAccount = <String, double>{};
    final openRaw = raw['openingByAccount'];
    if (openRaw is Map) {
      openRaw.forEach((k, v) {
        if (v is num) openingByAccount[k.toString()] = v.toDouble();
      });
    }
    final periodRaw = raw['periodByAccount'];
    if (periodRaw is Map) {
      periodRaw.forEach((k, v) {
        if (v is num) periodByAccount[k.toString()] = v.toDouble();
      });
    }
    final result = FinanceServerTotalsResult(
      openingTotal: (raw['openingTotal'] as num?)?.toDouble() ?? 0,
      openingByAccount: openingByAccount,
      income: (raw['income'] as num?)?.toDouble() ?? 0,
      expense: (raw['expense'] as num?)?.toDouble() ?? 0,
      periodByAccount: periodByAccount,
      pendingExpenseCount: (raw['pendingExpenseCount'] as num?)?.toInt() ?? 0,
    );
    _cache[key] = _FinanceServerTotalsCacheEntry(result: result, at: DateTime.now());
    return result;
  }
}

class FinanceServerTotalsResult {
  const FinanceServerTotalsResult({
    required this.openingTotal,
    required this.openingByAccount,
    required this.income,
    required this.expense,
    required this.periodByAccount,
    required this.pendingExpenseCount,
  });

  final double openingTotal;
  final Map<String, double> openingByAccount;
  final double income;
  final double expense;
  final Map<String, double> periodByAccount;
  final int pendingExpenseCount;

  double get balance => openingTotal + income - expense;
}

class _FinanceServerTotalsCacheEntry {
  _FinanceServerTotalsCacheEntry({required this.result, required this.at});

  final FinanceServerTotalsResult result;
  final DateTime at;
}
