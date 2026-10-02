import 'package:controle_total_premium/utils/pix_br_code.dart';
import 'package:flutter_test/flutter_test.dart';

/// Os valores esperados saíram de functions/pix_br_code.js — o app e o
/// servidor precisam gerar exatamente o mesmo BR Code.
void main() {
  test('chave aleatória (EVP) sem hífen/maiúscula vira 8-4-4-4-12 minúsculo (igual ao servidor)', () {
    expect(
      gerarPixCopiaECola(
        chave: 'ABCDEF0123456789ABCDEF0123456789',
        nome: 'João da Silva',
        cidade: 'Goiânia',
        valor: 10.5,
        txid: 'V24A7K',
      ),
      '00020126580014br.gov.bcb.pix0136abcdef01-2345-6789-abcd-ef0123456789520400005303986540510.505802BR'
      '5913JOAO DA SILVA6007GOIANIA62100506V24A7K63044588',
    );
    expect(chavePixNormalizada('ABCDEF01-2345-6789-ABCD-EF0123456789'), 'abcdef01-2345-6789-abcd-ef0123456789');
    expect(chavePixAleatoria('abcdef0123-45-6789abcdef0123456789'), isNull);
  });

  test('nome/cidade só com emoji viram RECEBEDOR/BRASIL (igual ao servidor)', () {
    expect(
      gerarPixCopiaECola(chave: '11111111111', nome: '😀😀', cidade: '🏙️'),
      '00020126330014br.gov.bcb.pix0111111111111115204000053039865802BR5909RECEBEDOR6006BRASIL62070503***6304C133',
    );
  });

  test('CPF com 11 dígitos iguais é recusado', () {
    expect(cpfPixValido('00000000000'), isFalse);
    expect(cpfPixValido('11111111111'), isFalse);
    expect(cpfPixValido('52998224725'), isTrue);
    expect(chavePixNormalizada('529.982.247-25'), '52998224725');
  });
}
