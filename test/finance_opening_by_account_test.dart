import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:controle_total_premium/utils/finance_account_balance_utils.dart';

Map<String, dynamic> _tx(String type, double amount, DateTime date, String acc,
        {String status = 'paid'}) =>
    {
      'type': type,
      'amount': amount,
      'status': status,
      'date': Timestamp.fromDate(date),
      'financeAccountId': acc,
    };

void main() {
  // Caso real (02/10/2026): Início mostrava abertura R$ 996,50 e os cards das
  // contas no Financeiro R$ 0,00. A abertura por conta recalculada dos
  // lançamentos pagos tem de fechar com o total.
  test('abertura por conta: Caixa 1.700, Bradesco −703,50, total 996,50', () {
    final items = [
      _tx('income', 1700, DateTime(2026, 6, 28), 'caixa'),
      _tx('expense', 253.5, DateTime(2026, 6, 10), 'bradesco'),
      _tx('expense', 150, DateTime(2026, 6, 20), 'bradesco'),
      _tx('expense', 150, DateTime(2026, 8, 5), 'bradesco'),
      _tx('expense', 150, DateTime(2026, 8, 15), 'bradesco'),
      _tx('expense', 500, DateTime(2026, 8, 20), 'bradesco', status: 'pending'),
    ];
    final m = FinanceAccountBalanceUtils.openingPaidByAccountFromDocMaps(
      items: items,
      periodStart: DateTime(2026, 10, 1),
      creditCardIds: const {},
    );
    expect(m['caixa'], closeTo(1700, 1e-9));
    expect(m['bradesco'], closeTo(-703.5, 1e-9));
    expect(m.values.fold<double>(0, (a, b) => a + b), closeTo(996.5, 1e-9));
  });
}
