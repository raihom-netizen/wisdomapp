import 'package:controle_total_premium/utils/fixas_resumo.dart';
import 'package:flutter_test/flutter_test.dart';

/// O que não pode quebrar no gráfico das fixas:
///   (a) só entra lançamento ligado a uma fixa — a avulsa do mesmo mês não;
///   (b) despesa fixa e receita fixa não se misturam;
///   (c) pago × a vencer separados;
///   (d) mês sem lançamento aparece zerado, não some do gráfico;
///   (e) «3 meses» é este + os dois próximos (fixa é o que vem pela frente);
///   (f) o intervalo personalizado inclui o último dia inteiro.
DateTime _data(Object? o) => o as DateTime;

Map<String, dynamic> _tx({
  required DateTime data,
  required double valor,
  String tipo = 'expense',
  String status = 'pending',
  String categoria = 'Energia',
  String? fixa = 'f1',
  bool receitaFixa = false,
}) =>
    {
      'type': tipo,
      'amount': valor,
      'status': status,
      'category': categoria,
      'date': data,
      if (fixa != null) (receitaFixa ? 'fixedIncomeId' : 'fixedExpenseId'): fixa,
    };

void main() {
  test('(a)(b) só entra fixa, e do tipo certo', () {
    final docs = [
      _tx(data: DateTime(2026, 9, 5), valor: 200),
      _tx(data: DateTime(2026, 9, 6), valor: 999, fixa: null), // avulsa
      _tx(data: DateTime(2026, 9, 7), valor: 3000, tipo: 'income', receitaFixa: true),
    ];
    final desp = fixasDosDocs(docs, receita: false, data: _data);
    expect(desp.length, 1);
    expect(desp.first.valor, 200);
    final rec = fixasDosDocs(docs, receita: true, data: _data);
    expect(rec.length, 1);
    expect(rec.first.valor, 3000);
  });

  test('(c)(d) pago × a vencer por mês, sem pular mês vazio', () {
    final linhas = fixasDosDocs([
      _tx(data: DateTime(2026, 9, 5), valor: 200, status: 'paid'),
      _tx(data: DateTime(2026, 9, 20), valor: 50),
      _tx(data: DateTime(2026, 11, 5), valor: 200),
    ], receita: false, data: _data);
    final meses = fixasPorMes(linhas, DateTime(2026, 9, 1), DateTime(2026, 11, 30));
    expect(meses.length, 3, reason: 'outubro sem lançamento continua no gráfico');
    expect(meses[0].pago, 200);
    expect(meses[0].aVencer, 50);
    expect(meses[1].total, 0, reason: 'outubro zerado');
    expect(meses[2].aVencer, 200);
  });

  test('(e) «3 meses» é este + os dois próximos, com virada de ano', () {
    final r = fixasIntervalo(FixasPeriodo.tresMeses, agora: DateTime(2026, 11, 15));
    expect(r.de, DateTime(2026, 11, 1));
    expect(r.ate, DateTime(2027, 1, 31, 23, 59, 59));
    final anual = fixasIntervalo(FixasPeriodo.anual, agora: DateTime(2026, 11, 15));
    expect(anual.de, DateTime(2026, 1, 1));
    expect(anual.ate, DateTime(2026, 12, 31, 23, 59, 59));
  });

  test('(f) personalizado inclui o último dia inteiro', () {
    final r = fixasIntervalo(FixasPeriodo.personalizado,
        de: DateTime(2026, 9, 10, 15), ate: DateTime(2026, 9, 20, 8));
    expect(r.de, DateTime(2026, 9, 10));
    expect(r.ate, DateTime(2026, 9, 20, 23, 59, 59));
  });

  test('modo pendentes: toda pendente entra (fixa ou não), paga e cartão não', () {
    final docs = [
      _tx(data: DateTime(2026, 9, 5), valor: 100, fixa: null), // avulsa pendente
      _tx(data: DateTime(2026, 9, 6), valor: 200), // fixa pendente
      _tx(data: DateTime(2026, 9, 7), valor: 300, status: 'paid'), // paga
      {..._tx(data: DateTime(2026, 9, 8), valor: 400, fixa: null), 'financeAccountId': 'cartao1'},
    ];
    final r = fixasDosDocs(docs,
        receita: false,
        data: _data,
        somenteFixas: false,
        somentePendentes: true,
        excluirContas: {'cartao1'});
    expect(r.map((l) => l.valor).toList(), [100, 200],
        reason: 'pendentes (fixa ou avulsa); sem a paga e sem a compra no cartão');
  });

  test('rateio por categoria do maior para o menor', () {
    final linhas = fixasDosDocs([
      _tx(data: DateTime(2026, 9, 1), valor: 100, categoria: 'Internet'),
      _tx(data: DateTime(2026, 9, 2), valor: 900, categoria: 'Aluguel'),
      _tx(data: DateTime(2026, 10, 2), valor: 900, categoria: 'Aluguel'),
    ], receita: false, data: _data);
    final c = fixasPorCategoria(linhas);
    expect(c.first.categoria, 'Aluguel');
    expect(c.first.total, 1800);
    expect(c.first.quantidade, 2);
  });
}
