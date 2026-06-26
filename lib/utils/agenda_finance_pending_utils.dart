import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/app_business_rules.dart';
import '../utils/finance_account_balance_utils.dart';
import '../utils/finance_line_opening.dart';

/// Lançamento financeiro pendente exibido na Agenda.
class AgendaFinancePendingItem {
  const AgendaFinancePendingItem({
    required this.docId,
    required this.data,
    required this.type,
  });

  final String docId;
  final Map<String, dynamic> data;
  final String type;

  bool get isIncome => type == 'income';
}

DateTime agendaFinanceDayKey(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime? agendaFinanceEffectiveDay(Map<String, dynamic> data) {
  final effective = FinanceLineOpening.effectiveDateTimeFromMap(data) ??
      (data['date'] as Timestamp?)?.toDate();
  if (effective == null) return null;
  return agendaFinanceDayKey(effective);
}

/// Mesma regra dos cards azul/laranja do Financeiro (fixas, cartão, horizonte).
List<AgendaFinancePendingItem> filterAgendaFinancePending({
  required Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  required String type,
  required Set<String> creditCardAccountIds,
  required bool showFixedInPending,
  required DateTime limitDate,
  DateTime? onlyDay,
}) {
  assert(type == 'income' || type == 'expense');
  final fixedField = type == 'income' ? 'fixedIncomeId' : 'fixedExpenseId';
  final out = <AgendaFinancePendingItem>[];

  for (final doc in docs) {
    final d = Map<String, dynamic>.from(doc.data());
    if ((d['status'] ?? 'paid').toString() != 'pending') continue;
    if ((d['type'] ?? '').toString() != type) continue;
    if (FinanceAccountBalanceUtils.isOnCreditCardAccount(d, creditCardAccountIds)) {
      continue;
    }
    if (!showFixedInPending && (d[fixedField] ?? '').toString().isNotEmpty) {
      continue;
    }
    final day = agendaFinanceEffectiveDay(d);
    if (day == null) continue;
    if (day.isAfter(limitDate)) continue;
    if (onlyDay != null && day != agendaFinanceDayKey(onlyDay)) continue;
    out.add(AgendaFinancePendingItem(docId: doc.id, data: d, type: type));
  }

  out.sort((a, b) {
    final da = agendaFinanceEffectiveDay(a.data);
    final db = agendaFinanceEffectiveDay(b.data);
    if (da == null || db == null) return 0;
    return da.compareTo(db);
  });
  return out;
}

DateTime agendaFinancePendingLimitDate(int monthsAhead) {
  final m = monthsAhead.clamp(1, 12);
  final now = DateTime.now();
  return DateTime(now.year, now.month + m, 1);
}

int defaultAgendaFinancePendingMonthsAhead() =>
    AppBusinessRules.pendingMonthsAheadDefault;

double sumAgendaFinancePendingAmount(Iterable<AgendaFinancePendingItem> items) {
  var total = 0.0;
  for (final item in items) {
    total += ((item.data['amount'] ?? 0) as num).toDouble().abs();
  }
  return total;
}

Map<DateTime, List<AgendaFinancePendingItem>> groupAgendaFinancePendingByDay(
  Iterable<AgendaFinancePendingItem> items,
) {
  final map = <DateTime, List<AgendaFinancePendingItem>>{};
  for (final item in items) {
    final day = agendaFinanceEffectiveDay(item.data);
    if (day == null) continue;
    map.putIfAbsent(day, () => []).add(item);
  }
  return map;
}
