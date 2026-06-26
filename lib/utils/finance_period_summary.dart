import 'finance_line_opening.dart';
import 'finance_server_totals.dart';
import 'finance_transactions_realtime.dart';

/// Totais do período (mesmas regras de filtro de status que o painel Financeiro).
class FinancePeriodSummary {
  FinancePeriodSummary._();

  static bool docMatchesCategory(
    Map<String, dynamic> d,
    String? categoryExact,
    String? semCategoriaToken,
  ) {
    if (categoryExact == null || categoryExact.isEmpty) return true;
    final cat = (d['category'] ?? '').toString().trim();
    final tok = semCategoriaToken ?? '';
    if (tok.isNotEmpty && categoryExact == tok) return cat.isEmpty;
    return cat == categoryExact;
  }

  static Future<({double income, double expense, int docCount})> load({
    required String uid,
    required DateTime from,
    required DateTime to,
    required String statusFilter,
    String? categoryExact,
    String? semCategoriaToken,
    /// `all` | `income` | `expense` — só afeta agregação/caminho em lote quando sem categoria.
    String typeFilter = 'all',
  }) async {
    if (uid.isEmpty) return (income: 0.0, expense: 0.0, docCount: 0);
    var f = DateTime(from.year, from.month, from.day);
    var t = DateTime(to.year, to.month, to.day, 23, 59, 59);
    if (t.isBefore(f)) {
      final x = f;
      f = DateTime(t.year, t.month, t.day);
      t = DateTime(x.year, x.month, x.day, 23, 59, 59);
    }

    final canUseServer = categoryExact == null || categoryExact.isEmpty;
    if (canUseServer) {
      try {
        final server = await FinanceServerTotals.load(
          uid: uid,
          from: f,
          to: t,
          statusFilter: statusFilter == 'all' ? 'paid' : statusFilter,
          typeFilter: typeFilter == 'income' || typeFilter == 'expense' || typeFilter == 'all'
              ? typeFilter
              : 'all',
        );
        return (income: server.income, expense: server.expense, docCount: 0);
      } catch (_) {
        // Fallback: agregação local abaixo.
      }
    }

    // Mescla date + effectiveDate — agregado só em [date] perde lançamentos migrados.
    final docs = await financePeriodMergedDocumentsCollect(
      uid: uid,
      from: f,
      to: t,
      statusFilter: statusFilter,
      typeFilter: typeFilter == 'income' || typeFilter == 'expense' || typeFilter == 'all'
          ? typeFilter
          : 'all',
    );
    double inc = 0;
    double exp = 0;
    var n = 0;
    for (final doc in docs) {
      final d = doc.data();
      if (statusFilter != 'all') {
        if ((d['status'] ?? 'paid').toString() != statusFilter) continue;
      }
      final effective = FinanceLineOpening.effectiveDateTimeFromMap(d);
      if (effective == null || effective.isBefore(f) || effective.isAfter(t)) continue;
      if (typeFilter == 'income' && (d['type'] ?? 'expense').toString() != 'income') continue;
      if (typeFilter == 'expense' && (d['type'] ?? 'expense').toString() != 'expense') continue;
      if (!docMatchesCategory(d, categoryExact, semCategoriaToken)) continue;
      n++;
      final amount = (d['amount'] ?? 0).toDouble();
      if (d['type'] == 'income') inc += amount;
      if (d['type'] == 'expense') exp += amount.abs();
    }
    return (income: inc, expense: exp, docCount: n);
  }
}
