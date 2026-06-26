import 'package:flutter_test/flutter_test.dart';

import 'package:controle_total_premium/services/bank_notification_parser.dart';

void main() {
  test('parseManyForBatch: várias linhas SMS Bradesco', () {
    const sms = '''
BRADESCO CARTOES: COMPRA APROVADA NO CARTAO FINAL 2524 EM 23/04/2026 13:28. VALOR DE R\$ 9,00 SORVETERIA E ACAITERIA ANAPOLIS.
BRADESCO CARTOES: COMPRA APROVADA NO CARTAO FINAL 2524 EM 24/04/2026 07:22. VALOR DE R\$ 24,00 JIM.COM KEYLA
''';
    final rows = BankNotificationParser.parseManyForBatch(sms);
    expect(rows.length, 2);
    expect(rows[0].valor, 9.0);
    expect(rows[1].valor, 24.0);
  });

  test('duplicateFingerprint: mesma chave para duplicado', () {
    final a = BankNotificationParser.parse(
      'BRADESCO CARTOES: COMPRA APROVADA EM 23/04/2026. VALOR DE R\$ 9,00 LOJA X',
    );
    final b = BankNotificationParser.parse(
      'BRADESCO CARTOES: COMPRA APROVADA EM 23/04/2026. VALOR DE R\$ 9,00 LOJA X',
    );
    expect(BankNotificationParser.duplicateFingerprint(a), BankNotificationParser.duplicateFingerprint(b));
  });

  test('parseManyForBatch: texto livre com data', () {
    final rows = BankNotificationParser.parseManyForBatch('13/04/2026 supermercado 100,00');
    expect(rows.length, 1);
    expect(rows.first.valor, 100.0);
    expect(rows.first.data?.day, 13);
  });

  test('parseManyForBatch: linha de fatura dd/mm + valor com sinal final', () {
    final rows = BankNotificationParser.parseManyForBatch(
      '12/02 CRED CAMPANHA COMPRAS INT 9,17 -',
    );
    expect(rows.length, 1);
    expect(rows.first.valor, closeTo(9.17, 0.0001));
    expect(rows.first.data?.day, 12);
    expect(rows.first.data?.month, 2);
    expect(rows.first.descricao?.toUpperCase(), contains('CAMPANHA'));
  });

  test(r'parseManyForBatch: linha de fatura com token R$ antes do valor', () {
    final rows = BankNotificationParser.parseManyForBatch(
      r'28/02 Google ChatGPT SAO PAULO R$ 999,90',
    );
    expect(rows.length, 1);
    expect(rows.first.valor, closeTo(999.9, 0.0001));
    expect(rows.first.descricao?.toUpperCase(), contains('CHATGPT'));
  });

  test('parseManyForBatch: fatura com quebra de linha na descrição/valor', () {
    const fatura = '''
05/03 RestauranteComida CAMPO LIMPO
D
3,50
''';
    final rows = BankNotificationParser.parseManyForBatch(fatura);
    expect(rows.length, 1);
    expect(rows.first.valor, closeTo(3.5, 0.0001));
    expect(rows.first.data?.day, 5);
    expect(rows.first.descricao?.toUpperCase(), contains('RESTAURANTECOMIDA'));
  });

  test('parseManyForBatch: fatura dd/mm com valor inteiro no fim', () {
    final rows = BankNotificationParser.parseManyForBatch(
      '02/03 POSTO NACOES ANAPOLIS 100',
    );
    expect(rows.length, 1);
    expect(rows.first.valor, closeTo(100.0, 0.0001));
    expect(rows.first.data?.day, 2);
    expect(rows.first.data?.month, 3);
    expect(rows.first.descricao?.toUpperCase(), contains('POSTO NACOES'));
  });

  test('parseManyForBatch: fatura dd/mm com valor inteiro milhar no fim', () {
    final rows = BankNotificationParser.parseManyForBatch(
      '28/02 Google ChatGPT SAO PAULO 1.999',
    );
    expect(rows.length, 1);
    expect(rows.first.valor, closeTo(1999.0, 0.0001));
    expect(rows.first.data?.day, 28);
    expect(rows.first.data?.month, 2);
    expect(rows.first.descricao?.toUpperCase(), contains('CHATGPT'));
  });

  test(r'texto livre: R$ com vírgula partida + sufixo (8, 750) → 87,50 em reais', () {
    final rows = BankNotificationParser.parseManyForBatch(r'farmácia 04/04/2026 R$ 8, 750');
    expect(rows.length, 1);
    expect(rows.first.valor, closeTo(87.5, 0.0001));
    expect(rows.first.descricao?.toLowerCase(), contains('farmácia'));
    expect(rows.first.descricao?.contains(r'R$ 8,'), isFalse);
  });

  test('parseManyForBatch: uma linha com vírgulas — três lançamentos livres', () {
    const line = '100 mercado, 157,80 farmacia , abastecimento gasolina 237,50';
    final rows = BankNotificationParser.parseManyForBatch(line);
    expect(rows.length, 3);
    expect(rows[0].valor, 100.0);
    expect(rows[0].descricao?.toLowerCase().contains('mercado'), isTrue);
    expect(rows[1].valor, 157.8);
    expect(rows[1].descricao?.toLowerCase().contains('farmacia'), isTrue);
    expect(rows[2].valor, 237.5);
    expect(rows[2].descricao?.toLowerCase().contains('gasolina'), isTrue);
  });

  test('parseManyForBatch: uma linha — mercado R\$, farmácia R\$, feira (três despesas)', () {
    const line = r'mercado R$ 10,00, farmácia R$ R$ 150,00, feira 89, 55';
    final rows = BankNotificationParser.parseManyForBatch(line);
    expect(rows.length, 3);
    expect(rows[0].valor, 10.0);
    expect(rows[0].descricao?.toLowerCase().contains('mercado'), isTrue);
    expect(rows[1].valor, 150.0);
    expect(rows[1].descricao?.toLowerCase().contains('farmácia'), isTrue);
    expect(rows[2].valor, closeTo(89.55, 0.001));
    expect(rows[2].descricao?.toLowerCase().contains('feira'), isTrue);
  });

  test('parseManyForBatch: valor no fim + complemento após vírgula', () {
    const line = 'abastecimento gasolina 237,50 , no banco bradesco';
    final rows = BankNotificationParser.parseManyForBatch(line);
    expect(rows.length, 1);
    expect(rows.first.valor, 237.5);
    expect(rows.first.descricao?.toLowerCase(), contains('bradesco'));
  });

  test('parseManyForBatch: três linhas separadas', () {
    const t = '100 mercado\n157,80 farmacia\nabastecimento gasolina 237,50';
    final rows = BankNotificationParser.parseManyForBatch(t);
    expect(rows.length, 3);
  });

  test('Lançamento inteligente: frases de receita → type income (recebi pix / salário / milhar no fim)', () {
    final a = BankNotificationParser.parseForSmartInputField('recebi pix 400,00');
    expect(a.$1.type, 'income');
    expect(a.$1.valor, closeTo(400, 0.0001));
    final b = BankNotificationParser.parseForSmartInputField('recebi salario 12/04 1200');
    expect(b.$1.type, 'income');
    expect(b.$1.valor, closeTo(1200, 0.0001));
    final c = BankNotificationParser.parseForSmartInputField('comissao recebida 350');
    expect(c.$1.type, 'income');
    expect(c.$1.valor, 350.0);
    final d = BankNotificationParser.parseForSmartInputField('pix recebido 12/04/2026 120');
    expect(d.$1.type, 'income');
    expect(d.$1.valor, 120.0);
    final e = BankNotificationParser.parseForSmartInputField('salario recebido 1.200');
    expect(e.$1.type, 'income');
    expect(e.$1.valor, closeTo(1200, 0.0001));
  });

  test('Lançamento inteligente: paguei continua despesa (empate de palavras)', () {
    final a = BankNotificationParser.parseForSmartInputField('paguei boleto 200');
    expect(a.$1.type, 'expense');
    expect(a.$1.valor, 200.0);
  });

  test('parseManyForBatch: parcelas em texto livre — duas linhas com metade do valor', () {
    final rows = BankNotificationParser.parseManyForBatch(
      '100 reais supermercado em duas parcelas primeiro vencimento 01/05',
    );
    expect(rows.length, 2);
    expect(rows[0].valor, 50.0);
    expect(rows[1].valor, 50.0);
    expect(rows[0].descricao, contains('(1/2)'));
    expect(rows[1].descricao, contains('(2/2)'));
    expect(rows[0].data?.day, 1);
    expect(rows[0].data?.month, 5);
    expect(rows[1].data?.month, 6);
  });

  test('parseManyForBatch: em N parcelas numérico', () {
    final rows = BankNotificationParser.parseManyForBatch(
      '90 padaria em 3 parcelas primeiro vencimento 10/06/2026',
    );
    expect(rows.length, 3);
    expect(rows[0].valor, closeTo(30.0, 0.0001));
    expect(rows[1].valor, closeTo(30.0, 0.0001));
    expect(rows[2].valor, closeTo(30.0, 0.0001));
    expect(rows[0].data?.month, 6);
    expect(rows[0].data?.day, 10);
  });

  test('parseManyForBatch: bloco real Bradesco com várias mensagens gera lote completo', () {
    const sms = r'''
BRADESCO CARTOES: COMPRA APROVADA NO CARTAO FINAL 2524 EM 25/04/2026 10:21. VALOR DE R$ 41,98 MR FARMA                 ANAPOLIS.
BRADESCO CARTOES: COMPRA APROVADA NO CARTAO FINAL 2524 EM 25/04/2026 10:15. VALOR DE R$ 18,00 CHEIRO VERDE SACOLAO     ANAPOLIS.
BRADESCO CARTOES: COMPRA APROVADA NO CARTAO FINAL 2524 EM 25/04/2026 10:11. VALOR DE R$ 50,99 FAZBEMDROGARIAE          ANAPOLIS.
BRADESCO CARTOES: COMPRA APROVADA NO CARTAO FINAL 2524 EM 25/04/2026 10:07. VALOR DE R$ 83,20 CASA DE CARNES CANADA BEEANAPOLIS.
BRADESCO CARTOES: COMPRA APROVADA NO CARTAO FINAL 2524 EM 25/04/2026 08:21. VALOR DE R$ 36,97 SUPERMERCADOS ATENDE MA  ANAPOLIS.
''';
    final rows = BankNotificationParser.parseManyForBatch(sms);
    expect(rows.length, 5);
    expect(rows[0].valor, closeTo(41.98, 0.0001));
    expect(rows[1].valor, closeTo(18.0, 0.0001));
    expect(rows[2].valor, closeTo(50.99, 0.0001));
    expect(rows[3].valor, closeTo(83.2, 0.0001));
    expect(rows[4].valor, closeTo(36.97, 0.0001));
    expect(rows.every((r) => r.hasMinimumForConfirmation), isTrue);
  });

  test('parseManyForBatch: uma mensagem Bradesco no mesmo formato gera 1 lançamento', () {
    const sms = r'BRADESCO CARTOES: COMPRA APROVADA NO CARTAO FINAL 2524 EM 25/04/2026 10:21. VALOR DE R$ 41,98 MR FARMA ANAPOLIS.';
    final rows = BankNotificationParser.parseManyForBatch(sms);
    expect(rows.length, 1);
    expect(rows.first.valor, closeTo(41.98, 0.0001));
    expect(rows.first.data?.day, 25);
    expect(rows.first.data?.month, 4);
    expect(rows.first.data?.year, 2026);
    expect(rows.first.descricao?.toUpperCase(), contains('MR FARMA'));
    expect(rows.first.hasMinimumForConfirmation, isTrue);
  });

  test('parseFromCsvText: date,title,amount (decimal ponto)', () {
    const csv = '''
date,title,amount
2026-04-24,D'Uberrides,16.7
2026-04-24,RAIHOM SEYF,5.2
2026-04-10,Pagamento recebido,-50
''';
    final rows = BankNotificationParser.parseFromCsvText(csv);
    expect(rows.length, 3);
    expect(rows[0].descricao, "D'Uberrides");
    expect(rows[0].valor, closeTo(16.7, 0.0001));
    expect(rows[0].type, 'expense');
    expect(rows[2].valor, closeTo(50.0, 0.0001));
    expect(rows[2].type, 'income');
    expect(rows[0].data?.year, 2026);
  });

  test('parseFromCsvText: cabeçalho pt-BR com ; e vírgula decimal', () {
    const csv = '''
data;descrição;valor
24/04/2026;Farmácia;157,80
24/04/2026;Mercado;100,00
''';
    final rows = BankNotificationParser.parseFromCsvText(csv);
    expect(rows.length, 2);
    expect(rows[0].valor, closeTo(157.8, 0.0001));
    expect(rows[1].descricao, 'Mercado');
  });

  test('parseFromCsvText: memo, merchant e category enriquecem a descrição', () {
    const csv = '''
date,title,amount,memo,merchant,category
2026-04-24,POS purchase,12.50,Store #4412,STARBUCKS 123,Food & Drink
2026-04-25,Transfer,-20.00,,ACME Corp,Internal
''';
    final rows = BankNotificationParser.parseFromCsvText(csv);
    expect(rows.length, 2);
    expect(rows[0].descricao, contains('POS purchase'));
    expect(rows[0].descricao, contains('Store #4412'));
    expect(rows[0].descricao, contains('STARBUCKS 123'));
    expect(rows[0].descricao, contains('Food & Drink'));
    expect(rows[1].descricao, contains('Transfer'));
    expect(rows[1].descricao, contains('ACME Corp'));
    expect(rows[1].descricao, contains('Internal'));
  });

  test('parseFromCsvText: colunas débito e crédito separadas (extrato típico)', () {
    const csv = '''
data;histórico;débito;crédito
24/04/2026;PIX recebido;;150,00
24/04/2026;Compra loja;45,90;
''';
    final rows = BankNotificationParser.parseFromCsvText(csv);
    expect(rows.length, 2);
    expect(rows[0].type, 'income');
    expect(rows[0].valor, closeTo(150.0, 0.0001));
    expect(rows[1].type, 'expense');
    expect(rows[1].valor, closeTo(45.9, 0.0001));
  });

  test('parseManyForBatch: total com «de N» + parcelado em M vezes → M parcelas iguais', () {
    final rows = BankNotificationParser.parseManyForBatch('geladeira de 1200 parcelado em 6 vezes');
    expect(rows.length, 6);
    for (final r in rows) {
      expect(r.valor, closeTo(200.0, 0.0001));
    }
    expect(rows[0].descricao, contains('geladeira'));
    expect(rows[0].descricao, contains('(1/6)'));
    expect(rows[5].descricao, contains('(6/6)'));
  });

  test('parseManyForBatch: descrição + valor + parcelado em M vezes (sem «de»)', () {
    final rows = BankNotificationParser.parseManyForBatch('geladeira 1200 parcelado em 6 vezes');
    expect(rows.length, 6);
    for (final r in rows) {
      expect(r.valor, closeTo(200.0, 0.0001));
    }
  });

  test('parseManyForBatch: total com «de N» + em M parcelas (no fim)', () {
    final rows = BankNotificationParser.parseManyForBatch('geladeira de 1200 em 6 parcelas');
    expect(rows.length, 6);
    for (final r in rows) {
      expect(r.valor, closeTo(200.0, 0.0001));
    }
    expect(rows[0].descricao, contains('(1/6)'));
  });

  test('parseManyForBatch: descrição + total + em M parcelas (sem «de»)', () {
    final rows = BankNotificationParser.parseManyForBatch('geladeira 1200 em 6 parcelas');
    expect(rows.length, 6);
    for (final r in rows) {
      expect(r.valor, closeTo(200.0, 0.0001));
    }
  });
}
