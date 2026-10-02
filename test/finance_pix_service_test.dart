import 'package:controle_total_premium/models/finance_account.dart';
import 'package:controle_total_premium/services/finance_pix_service.dart';
import 'package:flutter_test/flutter_test.dart';

FinanceAccount _conta(String id, {String? pix, List<String> outras = const [], String productType = FinanceAccount.kChecking, String? titular}) =>
    FinanceAccount(id: id, presetId: 'nubank', productType: productType, pixKey: pix, pixKeys: outras, holderName: titular);

/// Pix do Financeiro (port do «Meu Pix» do Controle Total, sem Vendas).
void main() {
  test('tipo da chave e validação', () {
    expect(FinancePixService.tipoDaChave('fulano@email.com'), 'E-mail');
    expect(FinancePixService.tipoDaChave('(62) 99999-8888'), 'Celular');
    expect(FinancePixService.tipoDaChave('12.345.678/0001-95'), 'CNPJ');
    expect(FinancePixService.chaveValida('123'), isFalse);
    expect(FinancePixService.chaveValida('fulano@email.com'), isTrue);
  });

  test('Pix padrão do app manda; sem ele vale a conta principal e depois a 1ª com chave', () {
    final dados = FinancePixDados(
      contas: [
        _conta('a', pix: 'a@x.com'),
        _conta('b', pix: 'b@x.com', outras: ['b2@x.com'], titular: 'Maria Silva'),
        _conta('cartao', pix: 'c@x.com', productType: FinanceAccount.kCard),
      ],
      prefs: {
        'pixPadrao': {'contaId': 'b', 'chave': 'b2@x.com'},
        'pixCidade': 'Goiânia',
      },
    );
    final info = FinancePixService.pixDosDados(dados)!;
    expect(info.contaId, 'b');
    expect(info.chave, 'b2@x.com');
    expect(info.titular, 'Maria Silva');
    expect(info.cidade, 'Goiânia');

    final semPadrao = FinancePixDados(contas: dados.contas, prefs: {'defaultFinanceAccountId': 'a'});
    expect(FinancePixService.pixDosDados(semPadrao)!.contaId, 'a');

    // Cartão de crédito não recebe Pix.
    final ops = FinancePixService.opcoesDosDados(dados);
    expect(ops.any((o) => o.conta.id == 'cartao'), isFalse);
    expect(ops.first.selecionadaSozinha, isTrue);
  });

  test('código Pix sai com valor e CRC (BR Code)', () {
    final info = FinancePixService.pixDosDados(FinancePixDados(
      contas: [_conta('a', pix: 'a@x.com', titular: 'João')],
      prefs: const {},
    ))!;
    final codigo = FinancePixService.codigoPix(info, valor: 12.5, descricao: 'Aluguel');
    expect(codigo, contains('br.gov.bcb.pix'));
    expect(codigo, contains('540512.50'));
    expect(codigo, contains('6006BRASIL')); // sem cidade cadastrada
    expect(RegExp(r'6304[0-9A-F]{4}$').hasMatch(codigo), isTrue);
  });
}
