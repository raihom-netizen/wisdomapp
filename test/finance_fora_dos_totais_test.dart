import 'package:controle_total_premium/utils/finance_fora_dos_totais.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pagamento de fatura e transferência própria saem de receitas/despesas,
/// mas o saldo do período continua o MESMO de antes (autorizado pelo dono em
/// 01/10/2026). Caso de referência: Nubank pago pela Caixa.
void main() {
  final docs = <Map<String, dynamic>>[
    // Compras do cartão (despesas de verdade).
    {'type': 'expense', 'amount': 5000.0, 'category': 'Construção'},
    {'type': 'expense', 'amount': 652.44, 'category': 'Mercado'},
    // Salário.
    {'type': 'income', 'amount': 10591.17, 'category': 'Salários'},
    // Pix da Caixa para a Nu Pagamentos (pagamento da fatura).
    {
      'type': 'expense',
      'amount': 5652.44,
      'category': 'Pagamento de fatura',
      'faturaPagamento': true,
      'transferenciaPropria': true,
      'transferCounterpartyLabel': 'Nubank',
    },
    // «Pagamento recebido» no extrato do cartão.
    {'type': 'income', 'amount': 5652.44, 'category': 'Pagamento de fatura', 'faturaPagamento': true},
    // Transferência para conta própria reconhecida pelo Finance Pro.
    {'type': 'expense', 'amount': 300.0, 'category': 'Transferência', 'transferenciaPropria': true},
  ];

  ({double rec, double desp, double ajuste}) somar(List<Map<String, dynamic>> l) {
    var rec = 0.0, desp = 0.0, ajuste = 0.0;
    for (final d in l) {
      if (financeForaDosTotais(d)) {
        ajuste += financeValorComSinal(d);
        continue;
      }
      if (d['type'] == 'income') rec += (d['amount'] as num).toDouble();
      if (d['type'] == 'expense') desp += (d['amount'] as num).toDouble();
    }
    return (rec: rec, desp: desp, ajuste: ajuste);
  }

  test('pagamento de fatura e transferência própria não somam como receita nem despesa', () {
    final s = somar(docs);
    expect(s.rec, closeTo(10591.17, 0.001));
    expect(s.desp, closeTo(5652.44, 0.001), reason: 'só as compras do cartão');
  });

  test('o saldo do período continua igual ao de antes', () {
    var antes = 0.0;
    for (final d in docs) {
      antes += financeValorComSinal(d);
    }
    final s = somar(docs);
    expect(s.rec - s.desp + s.ajuste, closeTo(antes, 0.001));
    expect(financeAjusteSaldoForaDosTotais(docs), closeTo(s.ajuste, 0.001));
  });

  // Transferência pelo botão «Transferência» do app (par transferPairId).
  final transferenciaDoApp = <Map<String, dynamic>>[
    {'type': 'expense', 'amount': 800.0, 'category': 'Transferência', 'transferPairId': 'p1'},
    {'type': 'income', 'amount': 800.0, 'category': 'Transferência', 'transferPairId': 'p1'},
    {'type': 'expense', 'amount': 120.0, 'category': 'Mercado'},
  ];

  test('com Finance Pro: transferência do app fora dos totais, saldo igual', () {
    FinanceProTotais.definirParaTeste(true);
    final s = somar(transferenciaDoApp);
    expect(s.rec, 0);
    expect(s.desp, 120.0);
    expect(s.rec - s.desp + s.ajuste, closeTo(-120.0, 0.001));
    expect(financeRotuloForaDosTotais(transferenciaDoApp[0]), 'Transferência entre contas');
  });

  test('sem Finance Pro: transferência do app continua somando como hoje', () {
    FinanceProTotais.definirParaTeste(false);
    final s = somar(transferenciaDoApp);
    expect(s.rec, 800.0);
    expect(s.desp, 920.0);
    expect(s.ajuste, 0);
    expect(financeRotuloForaDosTotais(transferenciaDoApp[0]), isNull);
    // Pagamento de fatura continua fora para todos.
    expect(financeForaDosTotais(docs[3]), isTrue);
    // E o parâmetro explícito vale mais que o da sessão.
    expect(financeForaDosTotais(transferenciaDoApp[0], financePro: true), isTrue);
  });

  test('cache local só liga o Finance Pro; o servidor decide o «não»', () {
    FinanceProTotais.registrar('u1', true);
    FinanceProTotais.registrar('u1', false, deServidor: false);
    expect(FinanceProTotais.ativo, isTrue);
    FinanceProTotais.registrar('u1', false);
    expect(FinanceProTotais.ativo, isFalse);
    FinanceProTotais.registrar('u2', true, deServidor: false);
    expect(FinanceProTotais.ativo, isTrue, reason: 'outro usuário: começa do zero');
  });

  test('rótulo na lista', () {
    expect(financeRotuloForaDosTotais(docs[3]), 'Pagamento de fatura · Nubank');
    expect(financeRotuloForaDosTotais(docs[4], contaDoLancamento: 'Nubank'), 'Pagamento de fatura · Nubank');
    expect(financeRotuloForaDosTotais(docs[5]), 'Transferência entre contas');
    expect(financeRotuloForaDosTotais(docs[0]), isNull);
  });
}
