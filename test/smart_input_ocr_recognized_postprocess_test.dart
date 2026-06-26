import 'package:flutter_test/flutter_test.dart';

import 'package:controle_total_premium/utils/smart_input_ocr_recognized_postprocess.dart';

void main() {
  test('Pix EMV: junta dígitos a partir de 000201 (quebras de linha / ruído)', () {
    // +30 dígitos reais; OCR insere quebras
    const core = '00020126010001'
        '23456789012345678901234';
    final b = StringBuffer();
    for (var i = 0; i < core.length; i++) {
      if (i > 0) b.writeln();
      b.write(core[i]);
    }
    final out = SmartInputOcrRecognizedPostprocess.apply(b.toString().trim());
    final flat = out.replaceAll(RegExp(r'[^\d]'), '');
    expect(flat, core);
  });

  test('Boleto: 47 dígitos com espaços → blocos (legível)', () {
    final d47 = List.filled(47, '3').join();
    final withNoise = d47.split('').join('  ');
    final out = SmartInputOcrRecognizedPostprocess.apply(withNoise);
    expect(out.replaceAll(RegExp(r'[^\d]'), ''), d47);
    expect(out, contains('33333 33333'));
  });

  test('Tabela: data colada a letra (dd/mm/aaaaLetra…)', () {
    const t = r'10/01/2024COMPRA Loja R$ 10,00';
    final out = SmartInputOcrRecognizedPostprocess.apply(t);
    expect(out, contains('10/01/2024 COMPRA'));
  });

  test(r'OCR: R (espaço) $ corrigido para R$ sem espaços errados', () {
    const t = r'Paga R  $ 5,00 fim';
    final out = SmartInputOcrRecognizedPostprocess.apply(t);
    expect(out, 'Paga R\$ 5,00 fim');
  });
}
