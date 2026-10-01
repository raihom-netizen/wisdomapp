import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:controle_total_premium/utils/home_painel_resumo.dart';
import 'package:flutter_test/flutter_test.dart';

({String id, Map<String, dynamic> data}) _doc(
  String id,
  DateTime data,
  double valor, {
  String? fixa,
  String? conta,
}) =>
    (
      id: id,
      data: {
        'date': Timestamp.fromDate(data),
        'amount': valor,
        if (fixa != null) 'fixedExpenseId': fixa,
        if (conta != null) 'financeAccountId': conta,
      },
    );

void main() {
  group('saudação e data', () {
    test('saudação pela hora', () {
      expect(saudacaoPorHora(DateTime(2026, 10, 1, 6)), 'Bom dia');
      expect(saudacaoPorHora(DateTime(2026, 10, 1, 13)), 'Boa tarde');
      expect(saudacaoPorHora(DateTime(2026, 10, 1, 20)), 'Boa noite');
      expect(saudacaoPorHora(DateTime(2026, 10, 1, 2)), 'Boa noite');
    });

    test('data por extenso', () {
      expect(dataPorExtenso(DateTime(2026, 10, 1)), 'quinta-feira, 1 de outubro de 2026');
    });
  });

  group('pendentes (mesma regra do Financeiro)', () {
    final hoje = DateTime(2026, 10, 15);

    test('conta de hoje até o fim do mês seguinte e ignora vencidos', () {
      final r = resumirPendentes(
        docs: [
          _doc('a', DateTime(2026, 10, 10), 50), // vencido: fora
          _doc('b', DateTime(2026, 10, 15), 100),
          _doc('c', DateTime(2026, 11, 30), 20),
          _doc('d', DateTime(2026, 12, 1), 999), // depois do limite
        ],
        hoje: hoje,
        mesesAFrente: 1,
        mostrarFixas: true,
        campoFixa: 'fixedExpenseId',
      );
      expect(r.total, 120);
      expect(r.itens.map((e) => e['id']), ['b', 'c']);
    });

    test('tira cartão de crédito e, se pedido, as fixas', () {
      final r = resumirPendentes(
        docs: [
          _doc('a', DateTime(2026, 10, 20), 10, conta: 'cartao'),
          _doc('b', DateTime(2026, 10, 20), 30, fixa: 'f1'),
          _doc('c', DateTime(2026, 10, 20), -40),
        ],
        hoje: hoje,
        mesesAFrente: 0,
        mostrarFixas: false,
        campoFixa: 'fixedExpenseId',
        contasCartao: {'cartao'},
      );
      expect(r.total, 40);
      expect(r.quantidade, 1);
    });
  });

  test('fixas do mês: vencidas × a vencer', () {
    final r = resumirFixasDoMes(
      pendentes: [
        {'fixedExpenseId': 'x', 'date': Timestamp.fromDate(DateTime(2026, 9, 5)), 'amount': 100},
        {'fixedExpenseId': 'y', 'date': Timestamp.fromDate(DateTime(2026, 10, 20)), 'amount': 40},
        {'date': Timestamp.fromDate(DateTime(2026, 10, 20)), 'amount': 999}, // não é fixa
        {'fixedExpenseId': 'z', 'date': Timestamp.fromDate(DateTime(2026, 11, 2)), 'amount': 7},
      ],
      hoje: DateTime(2026, 10, 15),
      campoFixa: 'fixedExpenseId',
    );
    expect(r.vencidas, 1);
    expect(r.totalVencidas, 100);
    expect(r.aVencer, 1);
    expect(r.totalAVencer, 40);
    expect(r.totalEmAberto, 140);
  });

  group('evolução do saldo', () {
    test('parte da abertura e para em hoje', () {
      final p = evolucaoDoSaldo(
        abertura: 1000,
        movimento: {DateTime(2026, 10, 2): -100, DateTime(2026, 10, 3): 50},
        de: DateTime(2026, 10, 1),
        ate: DateTime(2026, 10, 31, 23, 59, 59),
        hoje: DateTime(2026, 10, 3, 10),
      );
      expect(p.length, 3);
      expect(p.first.saldo, 1000);
      expect(p.last.saldo, 950);
    });

    test('pago com data futura estende a linha até ele', () {
      final p = evolucaoDoSaldo(
        abertura: 0,
        movimento: {DateTime(2026, 10, 10): 30},
        de: DateTime(2026, 10, 1),
        ate: DateTime(2026, 10, 31),
        hoje: DateTime(2026, 10, 3),
      );
      expect(p.last.dia, DateTime(2026, 10, 10));
      expect(p.last.saldo, 30);
    });
  });
}
