import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/app_business_rules.dart';
import '../models/finance_account.dart';
import 'finance_line_opening.dart';

/// Regras de saldo vs. fatura de cartão de crédito.
class FinanceAccountBalanceUtils {
  FinanceAccountBalanceUtils._();

  /// Contas que movimentam saldo bancário (pagamento de fatura sai daqui).
  static List<FinanceAccount> debitBankAccounts(Iterable<FinanceAccount> accounts) {
    return accounts
        .where((a) => a.isDebitBankProduct || a.productType == FinanceAccount.kBankAndCard)
        .toList();
  }

  static Set<String> creditCardAccountIds(Iterable<FinanceAccount> accounts) {
    return accounts.where((a) => a.isCreditCardProduct).map((a) => a.id).toSet();
  }

  /// Lançamento vinculado a conta cartão de crédito (fatura — não entra em pendentes normais).
  static bool isOnCreditCardAccount(
    Map<String, dynamic> d,
    Set<String> creditCardIds,
  ) {
    if (creditCardIds.isEmpty) return false;
    final id = (d['financeAccountId'] ?? '').toString().trim();
    return id.isNotEmpty && creditCardIds.contains(id);
  }

  /// Dia civil da previsão do lançamento (`date`).
  static DateTime? transactionScheduleDay(Map<String, dynamic> d) {
    final ts = d['date'];
    if (ts is Timestamp) {
      final dt = ts.toDate();
      return DateTime(dt.year, dt.month, dt.day);
    }
    if (ts is DateTime) return DateTime(ts.year, ts.month, ts.day);
    return null;
  }

  /// Fatura cartão: só lançamentos com data >= [AppBusinessRules.faturaCartaoDataMinima].
  static bool countsForFaturaCartao(Map<String, dynamic> d) {
    final day = transactionScheduleDay(d);
    if (day == null) return false;
    final min = AppBusinessRules.faturaCartaoDataMinima;
    final cutoff = DateTime(min.year, min.month, min.day);
    return !day.isBefore(cutoff);
  }

  static bool _pendingExpenseOnCardForFatura(Map<String, dynamic> d, Set<String> creditCardIds) {
    if ((d['type'] ?? 'expense').toString() != 'expense') return false;
    if ((d['status'] ?? 'paid').toString() != 'pending') return false;
    if (!isOnCreditCardAccount(d, creditCardIds)) return false;
    return countsForFaturaCartao(d);
  }

  static double totalFaturaEmAberto(Map<String, double> faturaByCard) {
    return faturaByCard.values.fold(0.0, (s, v) => s + v);
  }

  static List<FinanceAccount> creditCardsWithOpenFatura(
    Iterable<FinanceAccount> accounts,
    Map<String, double> faturaByCard,
  ) {
    return accounts
        .where(
          (a) => a.isCreditCardProduct && (faturaByCard[a.id] ?? 0) > 0.0001,
        )
        .toList();
  }

  /// Todos os cartões de crédito cadastrados (para escolha no card roxo).
  static List<FinanceAccount> creditCardProducts(Iterable<FinanceAccount> accounts) {
    return accounts.where((a) => a.isCreditCardProduct).toList();
  }

  static int countPendingExpensesOnCreditCards(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> pendingExpenseDocs,
    Set<String> creditCardIds,
  ) {
    if (creditCardIds.isEmpty) return 0;
    var n = 0;
    for (final doc in pendingExpenseDocs) {
      final d = doc.data();
      if (!_pendingExpenseOnCardForFatura(d, creditCardIds)) continue;
      n++;
    }
    return n;
  }

  /// Soma despesas pendentes por cartão (fatura em aberto) — só contas [isCreditCardProduct]
  /// e data >= início do módulo fatura. Sem cartão cadastrado, retorna mapa vazio.
  static Map<String, double> faturaAbertaByCardId(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> pendingExpenseDocs, {
    Set<String>? creditCardIds,
  }) {
    final out = <String, double>{};
    if (creditCardIds == null || creditCardIds.isEmpty) return out;
    for (final doc in pendingExpenseDocs) {
      final d = doc.data();
      if (!_pendingExpenseOnCardForFatura(d, creditCardIds)) continue;
      final id = (d['financeAccountId'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      final amount = (d['amount'] as num?)?.toDouble().abs() ?? 0;
      if (amount <= 0) continue;
      out[id] = (out[id] ?? 0) + amount;
    }
    return out;
  }

  static double faturaAbertaForCard(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> pendingExpenseDocs,
    String cardAccountId, {
    Set<String>? creditCardIds,
  }) {
    if (creditCardIds != null &&
        creditCardIds.isNotEmpty &&
        !creditCardIds.contains(cardAccountId)) {
      return 0;
    }
    return faturaAbertaByCardId(
      pendingExpenseDocs,
      creditCardIds: creditCardIds ?? {cardAccountId},
    )[cardAccountId] ??
        0;
  }

  /// Saldo de abertura por conta (antes de [periodStart]) — mesma regra do
  /// período: cartão fora; pagamento de fatura debita o banco que pagou.
  static Map<String, double> openingPaidByAccountFromDocMaps({
    required Iterable<Map<String, dynamic>> items,
    required DateTime periodStart,
    required Set<String> creditCardIds,
  }) {
    final start = DateTime(periodStart.year, periodStart.month, periodStart.day);
    final m = <String, double>{};
    for (final d in items) {
      if ((d['status'] ?? 'paid').toString() != 'paid') continue;
      final effective = FinanceLineOpening.effectiveDateTimeFromMap(d);
      if (effective == null || !effective.isBefore(start)) continue;
      final type = (d['type'] ?? 'expense').toString();
      final amount = (d['amount'] as num?)?.toDouble().abs() ?? 0;
      if (amount <= 0) continue;
      final accountId = (d['financeAccountId'] ?? '').toString().trim();
      final paidFrom = (d['paidFromFinanceAccountId'] ?? '').toString().trim();

      if (paidFrom.isNotEmpty &&
          type == 'expense' &&
          !creditCardIds.contains(paidFrom)) {
        m[paidFrom] = (m[paidFrom] ?? 0) - amount;
        continue;
      }
      if (accountId.isEmpty || creditCardIds.contains(accountId)) continue;
      final delta = type == 'income' ? amount : -amount;
      m[accountId] = (m[accountId] ?? 0) + delta;
    }
    return m;
  }

  /// Aplica a um mapa de saldos por conta **só a diferença** de uma gravação
  /// local (criar: [before] nulo; excluir: [after] nulo; confirmar/editar: os dois).
  /// Usa exatamente a mesma regra de [openingPaidByAccountFromDocMaps]: o
  /// resultado é idêntico ao recálculo completo com o lançamento já gravado
  /// (port Controle Total, 30/09/2026).
  static Map<String, double> applyMutationToOpening({
    required Map<String, double> base,
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
    required DateTime periodStart,
    required Set<String> creditCardIds,
  }) {
    Map<String, double> slice(Map<String, dynamic>? d) => d == null
        ? const <String, double>{}
        : openingPaidByAccountFromDocMaps(
            items: [d],
            periodStart: periodStart,
            creditCardIds: creditCardIds,
          );
    return _shiftBalances(base, slice(after), slice(before));
  }

  /// Mesma ideia de [applyMutationToOpening] para o líquido pago **do período**
  /// (regra de [netPaidByAccountEffective]).
  static Map<String, double> applyMutationToPeriodNet({
    required Map<String, double> base,
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
    required DateTime from,
    required DateTime to,
    required Set<String> creditCardIds,
  }) {
    Map<String, double> slice(Map<String, dynamic>? d) => d == null
        ? const <String, double>{}
        : netPaidByAccountEffectiveFromMaps(
            items: [d],
            from: from,
            to: to,
            creditCardIds: creditCardIds,
          );
    return _shiftBalances(base, slice(after), slice(before));
  }

  static Map<String, double> _shiftBalances(
    Map<String, double> base,
    Map<String, double> plus,
    Map<String, double> minus,
  ) {
    final out = <String, double>{...base};
    plus.forEach((k, v) => out[k] = (out[k] ?? 0) + v);
    minus.forEach((k, v) => out[k] = (out[k] ?? 0) - v);
    return out;
  }

  /// Movimento líquido pago no período — cartão não entra no saldo; pagamento de fatura debita o banco escolhido.
  static Map<String, double> netPaidByAccountEffective({
    required Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required DateTime from,
    required DateTime to,
    required Set<String> creditCardIds,
  }) {
    return netPaidByAccountEffectiveFromMaps(
      items: docs.map((doc) => doc.data()),
      from: from,
      to: to,
      creditCardIds: creditCardIds,
    );
  }

  /// Mesma regra de [netPaidByAccountEffective], sobre os mapas dos lançamentos
  /// (permite aplicar a versão otimista — já confirmada na tela — antes do servidor).
  static Map<String, double> netPaidByAccountEffectiveFromMaps({
    required Iterable<Map<String, dynamic>> items,
    required DateTime from,
    required DateTime to,
    required Set<String> creditCardIds,
  }) {
    final rs = DateTime(from.year, from.month, from.day);
    final re = DateTime(to.year, to.month, to.day, 23, 59, 59);
    final m = <String, double>{};

    for (final d in items) {
      if ((d['status'] ?? 'paid').toString() != 'paid') continue;
      final type = (d['type'] ?? 'expense').toString();
      final effective = FinanceLineOpening.effectiveDateTimeFromMap(d);
      if (effective == null || effective.isBefore(rs) || effective.isAfter(re)) continue;

      final amount = (d['amount'] as num?)?.toDouble().abs() ?? 0;
      if (amount <= 0) continue;

      final accountId = (d['financeAccountId'] ?? '').toString().trim();
      final paidFrom = (d['paidFromFinanceAccountId'] ?? '').toString().trim();

      if (paidFrom.isNotEmpty && type == 'expense' && !creditCardIds.contains(paidFrom)) {
        m[paidFrom] = (m[paidFrom] ?? 0) - amount;
        continue;
      }

      if (accountId.isEmpty || creditCardIds.contains(accountId)) continue;

      final delta = type == 'income' ? amount : -amount;
      m[accountId] = (m[accountId] ?? 0) + delta;
    }
    return m;
  }
}
