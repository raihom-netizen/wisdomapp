import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:controle_total_premium/utils/finance_account_balance_utils.dart';

/// «Evolução do Saldo» do painel: só o que está pago, no dia da data efetiva.
void main() {
  Map<String, dynamic> tx(String type, double amount, String status, DateTime date,
          {DateTime? pagoEm}) =>
      {
        'type': type,
        'amount': amount,
        'status': status,
        'date': Timestamp.fromDate(date),
        if (pagoEm != null) 'paidAt': Timestamp.fromDate(pagoEm),
        if (pagoEm != null) 'effectiveDate': Timestamp.fromDate(pagoEm),
      };

  final de = DateTime(2026, 10, 1);
  final ate = DateTime(2026, 10, 31);

  test('receita pendente NÃO entra (antes entrava)', () {
    final m = FinanceAccountBalanceUtils.movimentoDiarioPago(
      items: [tx('income', 500, 'pending', DateTime(2026, 10, 10))],
      from: de,
      to: ate,
    );
    expect(m, isEmpty);
  });

  test('pago entra no dia da data efetiva, não no vencimento', () {
    final m = FinanceAccountBalanceUtils.movimentoDiarioPago(
      items: [
        tx('income', 1000, 'paid', DateTime(2026, 10, 5), pagoEm: DateTime(2026, 10, 7, 9)),
        tx('expense', 200, 'paid', DateTime(2026, 10, 3), pagoEm: DateTime(2026, 10, 7, 15)),
        tx('expense', 80, 'paid', DateTime(2026, 10, 12)),
      ],
      from: de,
      to: ate,
    );
    expect(m[DateTime(2026, 10, 7)], 800);
    expect(m[DateTime(2026, 10, 12)], -80);
    expect(m.containsKey(DateTime(2026, 10, 5)), isFalse);
  });

  test('fora do período não entra', () {
    final m = FinanceAccountBalanceUtils.movimentoDiarioPago(
      items: [
        tx('income', 90, 'paid', DateTime(2026, 9, 30)),
      ],
      from: de,
      to: ate,
    );
    expect(m, isEmpty);
  });
}
