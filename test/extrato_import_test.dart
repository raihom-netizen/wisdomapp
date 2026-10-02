import 'package:controle_total_premium/utils/extrato_import.dart';
import 'package:flutter_test/flutter_test.dart';

const _ofxContaCorrente = '''
OFXHEADER:100
DATA:OFXSGML
<OFX>
<BANKMSGSRSV1><STMTTRNRS><STMTRS>
<BANKTRANLIST>
<STMTTRN>
<TRNTYPE>CREDIT
<DTPOSTED>20261001000000[-3:BRT]
<TRNAMT>2500.00
<FITID>a1
<MEMO>SALARIO EMPRESA X
</STMTTRN>
<STMTTRN>
<TRNTYPE>DEBIT
<DTPOSTED>20261002000000[-3:BRT]
<TRNAMT>-45.90
<FITID>a2
<MEMO>PADARIA SAO JOSE
</STMTTRN>
</BANKTRANLIST>
</STMTRS></STMTTRNRS></BANKMSGSRSV1>
</OFX>
''';

const _ofxFatura = '''
OFXHEADER:100
<OFX>
<SIGNONMSGSRSV1><SONRS><FI><ORG>NU PAGAMENTOS</ORG></FI></SONRS></SIGNONMSGSRSV1>
<CREDITCARDMSGSRSV1><CCSTMTTRNRS><CCSTMTRS>
<BANKTRANLIST>
<STMTTRN>
<TRNTYPE>DEBIT
<DTPOSTED>20260905
<TRNAMT>-15.96
<FITID>f1
<MEMO>Mercado Bom Preco
</STMTTRN>
<STMTTRN>
<TRNTYPE>CREDIT
<DTPOSTED>20260910
<TRNAMT>979.83
<FITID>f2
<MEMO>Pagamento recebido
</STMTTRN>
</BANKTRANLIST>
</CCSTMTRS></CCSTMTTRNRS></CREDITCARDMSGSRSV1>
</OFX>
''';

void main() {
  group('OFX conta corrente', () {
    test('crédito = receita, débito = despesa', () {
      final lote = extratoInterpretar(_ofxContaCorrente, nomeArquivo: 'extrato.ofx')!;
      expect(lote.formato, 'ofx');
      expect(lote.fatura, isFalse);
      expect(lote.itens, hasLength(2));
      final salario = lote.itens[0];
      expect(salario.credito, isTrue);
      expect(salario.valor, 2500.0);
      expect(salario.data, DateTime(2026, 10, 1));
      final padaria = lote.itens[1];
      expect(padaria.credito, isFalse);
      expect(padaria.valor, 45.90);
      expect(padaria.pagamentoFatura, isFalse);

      final campos = extratoCamposDoLancamento(padaria, contaId: 'c1');
      expect(campos['type'], 'expense');
      expect(campos['status'], 'paid');
      expect(campos['financeAccountId'], 'c1');
      expect(campos.containsKey('faturaPagamento'), isFalse);
      expect(extratoCamposDoLancamento(salario, contaId: 'c1')['type'], 'income');
    });
  });

  group('OFX fatura de cartão', () {
    test('compra negativa vira despesa (não receita)', () {
      final lote = extratoInterpretar(_ofxFatura, nomeArquivo: 'fatura.ofx')!;
      expect(lote.fatura, isTrue);
      final compra = lote.itens.firstWhere((i) => i.descricao.contains('Mercado'));
      expect(compra.credito, isFalse);
      expect(compra.valor, 15.96);
      final campos = extratoCamposDoLancamento(
        compra,
        contaId: 'cartao',
        faturaDeCartao: true,
        diaFechamento: 1,
      );
      expect(campos['type'], 'expense');
      expect(campos['status'], 'pending');
      expect(campos['cartaoCredito'], isTrue);
      expect(campos['faturaRef'], '2026-10');
    });

    test('«Pagamento recebido» não é receita: fora dos totais', () {
      final lote = extratoInterpretar(_ofxFatura, nomeArquivo: 'fatura.ofx')!;
      final pg = lote.itens.firstWhere((i) => i.descricao.contains('Pagamento'));
      expect(pg.pagamentoFatura, isTrue);
      expect(pg.marcado, isFalse, reason: 'nasce desmarcado');
      final campos = extratoCamposDoLancamento(
        pg,
        contaId: 'cartao',
        faturaDeCartao: true,
      );
      expect(campos['faturaPagamento'], isTrue);
      expect(campos['status'], 'paid');
      expect(campos.containsKey('cartaoCredito'), isFalse);
      // Resumo não soma o pagamento como receita.
      final r = extratoResumir(lote.itens);
      expect(r.totalReceitas, 0);
      expect(r.totalDespesas, 15.96);
    });
  });

  group('CSV', () {
    test('extrato simples com cabeçalho (BR)', () {
      const csv = 'Data;Descrição;Valor\n'
          '01/10/2026;Salário;3.200,00\n'
          '03/10/2026;Supermercado;-250,35\n'
          '05/10/2026;Farmácia;-42,10\n';
      final lote = extratoInterpretar(csv, nomeArquivo: 'extrato.csv')!;
      expect(lote.formato, 'csv');
      expect(lote.fatura, isFalse);
      expect(lote.itens, hasLength(3));
      expect(lote.itens[0].credito, isTrue);
      expect(lote.itens[0].valor, 3200.0);
      expect(lote.itens[1].credito, isFalse);
      expect(lote.itens[1].valor, 250.35);
      expect(lote.itens[2].data, DateTime(2026, 10, 5));
    });

    test('fatura em CSV (tudo positivo) = compras', () {
      const csv = 'date,title,amount\n'
          '2026-09-01,Uber,23.50\n'
          '2026-09-02,iFood,48.90\n'
          '2026-09-03,Netflix,55.90\n';
      final lote = extratoInterpretar(csv, nomeArquivo: 'nubank.csv')!;
      expect(lote.fatura, isTrue);
      expect(lote.itens.every((i) => !i.credito), isTrue);
    });
  });

  group('dedupe', () {
    test('marca e desmarca o que já existe no app', () {
      final lote = extratoInterpretar(_ofxContaCorrente, nomeArquivo: 'extrato.ofx')!;
      final existente = extratoChaveDeLancamento(
        {'amount': 45.9, 'type': 'expense', 'description': 'Padaria São José'},
        DateTime(2026, 10, 2, 14, 30),
      );
      final n = extratoMarcarRepetidos(lote.itens, {existente});
      expect(n, 1);
      final padaria = lote.itens[1];
      expect(padaria.repetido, isTrue);
      expect(padaria.marcado, isFalse);
      expect(lote.itens[0].repetido, isFalse);
      expect(lote.itens[0].marcado, isTrue);
    });

    test('mesmo valor e dia mas tipo diferente não é duplicata', () {
      final lote = extratoInterpretar(_ofxContaCorrente, nomeArquivo: 'extrato.ofx')!;
      final chave = extratoChaveDeLancamento(
        {'amount': 45.9, 'type': 'income', 'description': 'Padaria Sao Jose'},
        DateTime(2026, 10, 2),
      );
      expect(extratoMarcarRepetidos(lote.itens, {chave}), 0);
    });
  });
}
