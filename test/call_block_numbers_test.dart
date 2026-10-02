import 'package:flutter_test/flutter_test.dart';

import 'package:controle_total_premium/services/call_block_numbers.dart';

/// Mesma regra de `CallBlockNumbers.kt` (quem decide a ligação no Android).
void main() {
  group('callBlockMesmoNumero', () {
    test('contato formatado × chamada E.164', () {
      expect(callBlockMesmoNumero('(62) 99999-9999', '+5562999999999'), isTrue);
      expect(callBlockMesmoNumero('62 99999 9999', 'tel:+55 62 99999-9999'), isTrue);
      expect(callBlockMesmoNumero('+55 (62) 9 9999-9999', '62999999999'), isTrue);
    });

    test('zero de longa distância e operadora', () {
      expect(callBlockMesmoNumero('062999999999', '+5562999999999'), isTrue);
      expect(callBlockMesmoNumero('0 41 62 99999-9999', '+5562999999999'), isTrue);
      expect(callBlockMesmoNumero('0 21 62 3333-4444', '+556233334444'), isTrue);
      expect(callBlockMesmoNumero('005562999999999', '+5562999999999'), isTrue);
      expect(callBlockMesmoNumero('5562999999999', '+5562999999999'), isTrue);
    });

    test('9º dígito: contato antigo de 8 dígitos casa com o atual', () {
      expect(callBlockMesmoNumero('(62) 9999-9999', '+5562999999999'), isTrue);
      expect(callBlockMesmoNumero('9999-9999', '+5562999999999'), isTrue);
    });

    test('contato salvo sem DDD casa com qualquer DDD', () {
      expect(callBlockMesmoNumero('99999-9999', '+5562999999999'), isTrue);
      expect(callBlockMesmoNumero('3333-4444', '+556233334444'), isTrue);
    });

    test('DDD diferente NÃO é o mesmo número', () {
      expect(callBlockMesmoNumero('(61) 99999-9999', '+5562999999999'), isFalse);
      expect(callBlockMesmoNumero('(11) 3333-4444', '(21) 3333-4444'), isFalse);
    });

    test('fixo × celular e números diferentes', () {
      expect(callBlockMesmoNumero('(62) 3333-4444', '(62) 99999-9999'), isFalse);
      expect(callBlockMesmoNumero('(62) 99999-9998', '(62) 99999-9999'), isFalse);
    });

    test('DDD 55 (Santa Maria) não é confundido com +55', () {
      expect(callBlockMesmoNumero('(55) 99999-9999', '+5555999999999'), isTrue);
      expect(callBlockMesmoNumero('(55) 99999-9999', '+5562999999999'), isFalse);
    });

    test('curtos só iguais', () {
      expect(callBlockMesmoNumero('190', '190'), isTrue);
      expect(callBlockMesmoNumero('190', '192'), isFalse);
      expect(callBlockMesmoNumero('190', '+5562999990190'), isFalse);
    });

    test('estrangeiro', () {
      expect(callBlockMesmoNumero('+1 555 123 4567', '+15551234567'), isTrue);
      expect(callBlockMesmoNumero('15551234567', '+15551234567'), isTrue);
      expect(callBlockMesmoNumero('+351 912 345 678', '+5562912345678'), isFalse);
    });

    test('oculto / vazio nunca casa', () {
      expect(callBlockMesmoNumero('', ''), isFalse);
      expect(callBlockMesmoNumero('', '+5562999999999'), isFalse);
      expect(callBlockMesmoNumero(null, '190'), isFalse);
    });
  });

  group('emergência', () {
    test('190/192/193/112 são emergência', () {
      for (final n in ['190', '192', '193', '112', '911', '199', '188']) {
        expect(callBlockEhEmergencia(n), isTrue, reason: n);
      }
    });
    test('número comum não é', () {
      expect(callBlockEhEmergencia('+5562999999999'), isFalse);
      expect(callBlockEhEmergencia('1901'), isFalse);
      expect(callBlockEhEmergencia(''), isFalse);
    });
  });

  group('variantes para o PhoneLookup', () {
    test('celular com 9º dígito gera as formas com e sem o 9', () {
      final v = callBlockVariantesBusca('+5562999999999');
      expect(v.first, '+5562999999999');
      expect(v, containsAll(['62999999999', '062999999999', '+556299999999', '6299999999', '999999999', '99999999']));
    });
    test('fixo de 8 dígitos não ganha 9', () {
      final v = callBlockVariantesBusca('+556233334444');
      expect(v, containsAll(['6233334444', '33334444']));
      expect(v.any((e) => e.endsWith('933334444')), isFalse);
    });
    test('estrangeiro e curto ficam como vieram', () {
      expect(callBlockVariantesBusca('+15551234567'), ['+15551234567']);
      expect(callBlockVariantesBusca('190'), ['190']);
    });
  });
}
