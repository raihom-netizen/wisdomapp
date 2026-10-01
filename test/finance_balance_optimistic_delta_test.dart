import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:controle_total_premium/utils/finance_account_balance_utils.dart';

/// A diferença otimista aplicada na hora (confirmar pagamento, editar, excluir)
/// tem que dar EXATAMENTE o mesmo saldo que o recálculo completo depois.
void main() {
  final periodStart = DateTime(2026, 9, 1);
  final periodEnd = DateTime(2026, 9, 30, 23, 59, 59);
  const cards = {'card'};

  Map<String, dynamic> tx({
    required String type,
    required double amount,
    required String status,
    required DateTime date,
    String account = '',
    String paidFrom = '',
    DateTime? effective,
  }) =>
      {
        'type': type,
        'amount': amount,
        'status': status,
        'date': Timestamp.fromDate(date),
        if (effective != null) 'effectiveDate': Timestamp.fromDate(effective),
        if (account.isNotEmpty) 'financeAccountId': account,
        if (paidFrom.isNotEmpty) 'paidFromFinanceAccountId': paidFrom,
      };

  Map<String, double> opening(Map<String, Map<String, dynamic>> docs) =>
      FinanceAccountBalanceUtils.openingPaidByAccountFromDocMaps(
        items: docs.values,
        periodStart: periodStart,
        creditCardIds: cards,
      );

  Map<String, double> period(Map<String, Map<String, dynamic>> docs) =>
      FinanceAccountBalanceUtils.netPaidByAccountEffectiveFromMaps(
        items: docs.values,
        from: periodStart,
        to: periodEnd,
        creditCardIds: cards,
      );

  void expectSame(Map<String, double> a, Map<String, double> b) {
    final keys = {...a.keys, ...b.keys};
    for (final k in keys) {
      expect((a[k] ?? 0), closeTo(b[k] ?? 0, 1e-9), reason: 'conta $k');
    }
  }

  Map<String, Map<String, dynamic>> baseDocs() => {
        'a': tx(
            type: 'income',
            amount: 1000,
            status: 'paid',
            date: DateTime(2026, 8, 5),
            account: 'nubank'),
        'b': tx(
            type: 'expense',
            amount: 120.5,
            status: 'pending',
            date: DateTime(2026, 8, 20),
            account: 'nubank'),
        'c': tx(
            type: 'expense',
            amount: 80,
            status: 'paid',
            date: DateTime(2026, 9, 10),
            account: 'itau'),
        'd': tx(
            type: 'expense',
            amount: 300,
            status: 'pending',
            date: DateTime(2026, 8, 15),
            account: 'card'),
        'e': tx(
            type: 'expense',
            amount: 45,
            status: 'pending',
            date: DateTime(2026, 9, 12),
            account: 'itau'),
      };

  void checkMutation(
    String id,
    Map<String, dynamic>? after,
  ) {
    final docs = baseDocs();
    final before = docs[id];
    final openBefore = opening(docs);
    final periodBefore = period(docs);

    if (after == null) {
      docs.remove(id);
    } else {
      docs[id] = after;
    }

    expectSame(
      FinanceAccountBalanceUtils.applyMutationToOpening(
        base: openBefore,
        before: before,
        after: after,
        periodStart: periodStart,
        creditCardIds: cards,
      ),
      opening(docs),
    );
    expectSame(
      FinanceAccountBalanceUtils.applyMutationToPeriodNet(
        base: periodBefore,
        before: before,
        after: after,
        from: periodStart,
        to: periodEnd,
        creditCardIds: cards,
      ),
      period(docs),
    );
  }

  test('confirmar pendente com data antes do período mexe na abertura', () {
    final after = {
      ...baseDocs()['b']!,
      'status': 'paid',
      'paidAt': Timestamp.fromDate(DateTime(2026, 8, 25)),
      'effectiveDate': Timestamp.fromDate(DateTime(2026, 8, 25)),
    };
    checkMutation('b', after);
  });

  test('confirmar pendente hoje (dentro do período) mexe só no período', () {
    final after = {
      ...baseDocs()['b']!,
      'status': 'paid',
      'paidAt': Timestamp.fromDate(DateTime(2026, 9, 29)),
      'effectiveDate': Timestamp.fromDate(DateTime(2026, 9, 29)),
      'financeAccountId': 'itau',
    };
    checkMutation('b', after);
  });

  test('pagar fatura: compra do cartão debita a conta que pagou', () {
    final after = {
      ...baseDocs()['d']!,
      'status': 'paid',
      'paidAt': Timestamp.fromDate(DateTime(2026, 9, 5)),
      'effectiveDate': Timestamp.fromDate(DateTime(2026, 9, 5)),
      'paidFromFinanceAccountId': 'nubank',
    };
    checkMutation('d', after);
  });

  test('editar valor e conta de lançamento pago', () {
    final after = {
      ...baseDocs()['c']!,
      'amount': 95.3,
      'financeAccountId': 'nubank',
    };
    checkMutation('c', after);
  });

  test('excluir lançamento pago de antes do período', () {
    checkMutation('a', null);
  });

  test('criar lançamento pago novo', () {
    final docs = baseDocs();
    final created = tx(
      type: 'income',
      amount: 250,
      status: 'paid',
      date: DateTime(2026, 9, 3),
      account: 'itau',
    );
    final period0 = period(docs);
    docs['f'] = created;
    expectSame(
      FinanceAccountBalanceUtils.applyMutationToPeriodNet(
        base: period0,
        after: created,
        from: periodStart,
        to: periodEnd,
        creditCardIds: cards,
      ),
      period(docs),
    );
  });

  test('pendente continua pendente: nenhuma diferença', () {
    final after = {...baseDocs()['e']!, 'description': 'mudou'};
    checkMutation('e', after);
  });
}
