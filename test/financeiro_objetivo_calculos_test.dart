// Correções de cálculo do Financeiro + Objetivo autorizadas pelo dono em
// 02/10/2026 (saldo da conta na meta, fixas dia 29–31, 52 semanas,
// parcelamento em centavos, reserva de meta fora dos totais).
import 'package:controle_total_premium/services/goal_deposit_service.dart';
import 'package:controle_total_premium/utils/fifty_two_weeks_plan.dart';
import 'package:controle_total_premium/utils/finance_fora_dos_totais.dart';
import 'package:controle_total_premium/utils/fixed_flow_schedule.dart';
import 'package:controle_total_premium/utils/installment_split.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _tx({
  required String type,
  required double amount,
  required DateTime date,
  String status = 'paid',
  String? account,
  String? paidFrom,
}) =>
    {
      'type': type,
      'amount': amount,
      'status': status,
      'date': Timestamp.fromDate(date),
      'effectiveDate': Timestamp.fromDate(date),
      if (account != null) 'financeAccountId': account,
      if (paidFrom != null) 'paidFromFinanceAccountId': paidFrom,
    };

void main() {
  group('1 · saldo da conta na meta = regra do carrossel', () {
    test('abertura + líquido pago do mês, fatura paga debita a conta', () {
      final from = DateTime(2026, 10, 1);
      final to = DateTime(2026, 10, 31);
      final itens = [
        _tx(type: 'income', amount: 200, date: DateTime(2026, 10, 5), account: 'nu'),
        _tx(type: 'expense', amount: 50, date: DateTime(2026, 10, 6), account: 'nu'),
        // pagamento da fatura do cartão feito pela conta «nu»
        _tx(
            type: 'expense',
            amount: 300,
            date: DateTime(2026, 10, 10),
            account: 'cartao',
            paidFrom: 'nu'),
        // compra no cartão: não mexe no saldo da conta
        _tx(type: 'expense', amount: 80, date: DateTime(2026, 10, 11), account: 'cartao'),
        // pendente não entra
        _tx(
            type: 'expense',
            amount: 999,
            date: DateTime(2026, 10, 12),
            account: 'nu',
            status: 'pending'),
      ];
      final saldo = GoalDepositService.accountBalanceFromMaps(
        opening: 1000,
        monthItems: itens,
        from: from,
        to: to,
        accountId: 'nu',
        creditCardIds: {'cartao'},
      );
      // 1000 + 200 − 50 − 300 = 850 (o cálculo antigo dava 1150: ignorava
      // a fatura paga pela conta).
      expect(saldo, closeTo(850, 0.001));
    });
  });

  group('2 · fixas por parcelas com início dia 29–31', () {
    test('data final no último dia do mês final', () {
      expect(
        FixedFlowSchedule.installmentsEndDate(
            start: DateTime(2026, 1, 31), totalParcelas: 2),
        DateTime(2026, 2, 28),
      );
      expect(
        FixedFlowSchedule.installmentsEndDate(
            start: DateTime(2026, 1, 31), totalParcelas: 3),
        DateTime(2026, 3, 31),
      );
      expect(
        FixedFlowSchedule.installmentsEndDate(
            start: DateTime(2026, 8, 30), totalParcelas: 10, parcelaInicial: 4),
        DateTime(2027, 2, 28),
      );
      // fórmula antiga transbordava: 31/01 + 1 mês = 03/03
      expect(DateTime(2026, 1 + 2 - 1, 31), DateTime(2026, 3, 3));
    });

    test('mês depois da última parcela não gera (antes repetia 2/2)', () {
      final start = DateTime(2026, 1, 31);
      int? idx(DateTime m) => FixedFlowSchedule.installmentIndexForMonth(
          start: start, month: m, parcelaInicial: 1, totalParcelas: 2);
      expect(idx(DateTime(2026, 1, 1)), 1);
      expect(idx(DateTime(2026, 2, 1)), 2);
      expect(idx(DateTime(2026, 3, 1)), isNull);
    });

    test('ID determinístico por fixa + mês', () {
      expect(
        FixedFlowSchedule.generatedTxId(
            prefix: 'fx', fixedId: 'abc', month: DateTime(2026, 3, 1)),
        'fx_abc_202603',
      );
    });
  });

  group('8 · editar fixa sincroniza pendentes', () {
    test('valor/descrição atualizam e o que sobrou é apagado', () {
      final before = {
        'description': 'Carro',
        'category': 'Transporte',
        'amount': 100.0,
        'mode': 'installments',
        'totalParcelas': 12,
        'parcelaInicial': 1,
        'startDate': DateTime(2026, 1, 10),
        'endDate': DateTime(2026, 12, 10),
      };
      final after = {
        ...before,
        'amount': 120.0,
        'totalParcelas': 6,
        'endDate': DateTime(2026, 6, 10),
      };
      Map<String, dynamic> p(int m, int idx) => {
            'fixedExpenseMonthKey': '2026-${m.toString().padLeft(2, '0')}',
            'amount': 100.0,
            'description': 'Carro · $idx/12',
            'installmentCount': 12,
            'installmentIndex': idx,
          };
      final plan = FixedFlowSchedule.planPendingSync(
        before: before,
        after: after,
        pending: [
          (id: 'mar', data: p(3, 3)),
          (id: 'jul', data: p(7, 7)),
          (id: 'dez', data: p(12, 12)),
        ],
        monthKeyField: 'fixedExpenseMonthKey',
        modeInstallments: 'installments',
      );
      expect(plan.deletes, containsAll(['jul', 'dez']));
      expect(plan.updates['mar']!['amount'], 120.0);
      expect(plan.updates['mar']!['description'], 'Carro · 3/6');
      expect(plan.updates['mar']!['installmentCount'], 6);
    });

    test('valor da fixa igual: ajuste manual do mês não é sobrescrito', () {
      final fixa = {
        'description': 'Luz',
        'category': 'Casa',
        'amount': 150.0,
        'mode': 'period',
        'startDate': DateTime(2026, 1, 5),
        'endDate': DateTime(2030, 1, 5),
      };
      final plan = FixedFlowSchedule.planPendingSync(
        before: fixa,
        after: {...fixa, 'category': 'Energia'},
        pending: [
          (
            id: 'out',
            data: {
              'fixedExpenseMonthKey': '2026-10',
              'amount': 173.4,
              'description': 'Luz'
            }
          ),
        ],
        monthKeyField: 'fixedExpenseMonthKey',
        modeInstallments: 'installments',
      );
      expect(plan.updates['out'], {'category': 'Energia'});
      expect(plan.deletes, isEmpty);
    });
  });

  group('3 · 52 semanas só marca semana coberta por inteiro', () {
    // Meta 1378 → semana n = R$ n (52 × 53 / 2 = 1378).
    final schedule = FiftyTwoWeeksPlan.buildSchedule(
        target: 1378, planStart: DateTime(2026, 1, 5));

    test('R\$ 5 marca 1 e 2 (antes marcava 1, 2 e 3 = R\$ 6)', () {
      expect(
        FiftyTwoWeeksPlan.weeksForDepositAmount(
            amount: 5, schedule: schedule, paidWeeks: const []),
        [1, 2],
      );
    });

    test('valor menor que a semana não marca nada (antes marcava a semana)', () {
      expect(
        FiftyTwoWeeksPlan.weeksForDepositAmount(
            amount: 0.5, schedule: schedule, paidWeeks: const []),
        isEmpty,
      );
    });

    test('a sobra acumula para o próximo depósito', () {
      final a = FiftyTwoWeeksPlan.allocateDeposits(schedule: schedule, deposits: const [
        FiftyTwoWeeksDeposit(amount: 5),
        FiftyTwoWeeksDeposit(amount: 1),
      ]);
      expect(a.weeksByDeposit, [
        [1, 2],
        [3],
      ]);
      expect(a.leftover, closeTo(0, 0.001));
    });

    test('semanas escolhidas pelo usuário são respeitadas', () {
      final a = FiftyTwoWeeksPlan.allocateDeposits(schedule: schedule, deposits: const [
        FiftyTwoWeeksDeposit(amount: 10, chosenWeeks: [10]),
        FiftyTwoWeeksDeposit(amount: 1),
      ]);
      expect(a.weeksByDeposit[0], [10]);
      expect(a.weeksByDeposit[1], [1]);
      expect(a.paidWeeks, [1, 10]);
    });

    test('resgate desmarca as últimas semanas até o saldo fechar', () {
      final a = FiftyTwoWeeksPlan.allocateDeposits(schedule: schedule, deposits: const [
        FiftyTwoWeeksDeposit(amount: 6),
        FiftyTwoWeeksDeposit(amount: -4),
      ]);
      expect(a.paidWeeks, [1]);
      expect(a.leftover, closeTo(1, 0.001));
    });
  });

  group('12 · parcelamento em centavos', () {
    test('R\$ 100 em 3× = 33,33 + 33,33 + 33,34', () {
      final p = splitInstallmentsInCents(total: 100, installments: 3);
      expect(p, [33.33, 33.33, 33.34]);
      expect(p.fold<double>(0, (s, v) => s + v), closeTo(100, 0.0001));
    });

    test('lotes de 450', () {
      final lotes = chunked(List.generate(999, (i) => i), size: 450).toList();
      expect(lotes.map((l) => l.length), [450, 450, 99]);
    });
  });

  group('6 · reserva de meta fora dos totais', () {
    test('goalReserve não é receita nem despesa de categoria', () {
      final reserva = {'type': 'expense', 'amount': 50, 'goalReserve': true};
      final resgate = {'type': 'income', 'amount': 20, 'goalReserve': true};
      final antigo = {'type': 'income', 'amount': 50, 'goalId': 'g1'};
      expect(financeForaDosTotais(reserva, financePro: false), isTrue);
      expect(financeForaDosTotais(resgate, financePro: false), isTrue);
      expect(financeForaDosTotais(antigo, financePro: false), isFalse);
      expect(financeRotuloForaDosTotais(reserva, financePro: false),
          'Reserva para meta');
      expect(financeRotuloForaDosTotais(resgate, financePro: false),
          'Resgate de meta');
    });
  });
}
