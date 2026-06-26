import 'package:controle_total_premium/utils/smart_input_live_mask.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SmartInputLiveMask', () {
    test('completa dd/mm com ano quando válido', () {
      expect(
        SmartInputLiveMask.expandShortDates('compra 12/04 no mercado', 2026),
        'compra 12/04/2026 no mercado',
      );
      expect(
        SmartInputLiveMask.expandShortDates('12/04', 2026),
        '12/04/2026',
      );
    });

    test('completa d/m com um dígito e normaliza para dd/mm/aaaa', () {
      expect(SmartInputLiveMask.expandShortDates('compra 3/4 no mercado', 2026), 'compra 03/04/2026 no mercado');
      expect(SmartInputLiveMask.expandShortDates('12/4/2026 x', 2026), '12/4/2026 x');
      expect(SmartInputLiveMask.expandShortDates('7/5 mercado', 2026), '07/05/2026 mercado');
    });

    test('não altera data já com ano nem data parcial', () {
      expect(SmartInputLiveMask.expandShortDates('12/04/2025 x', 2026), '12/04/2025 x');
      expect(SmartInputLiveMask.expandShortDates('12/040', 2026), '12/040');
      expect(SmartInputLiveMask.expandShortDates('31/02', 2026), '31/02');
    });

    test('não expande dd/mm colado a letra (ditado sem espaço)', () {
      expect(SmartInputLiveMask.expandShortDates('supermer13/04', 2026), 'supermer13/04');
    });

    test('sufixo dd/mm no fim com texto antes: não re-completa ano ao apagar (permite editar)', () {
      expect(SmartInputLiveMask.expandShortDates('mercado 13/04', 2026), 'mercado 13/04');
      expect(SmartInputLiveMask.expandShortDates('mercado 13/04/202', 2026), 'mercado 13/04/202');
    });

    test('formata sufixo numérico como centavos quando há descrição com letra', () {
      final s = SmartInputLiveMask.apply('supermercado 25000', 2026);
      expect(s, contains('R\$'));
      expect(s, contains('250,00'));
    });

    test('linha composta com valor BR existente e novo bloco', () {
      final s = SmartInputLiveMask.apply('posto de gasolina 87,55 , supermercado 250000', 2026);
      expect(s, contains('87,55'));
      expect(s, contains('2.500,00'));
    });

    test('formata valor no início da frase como centavos', () {
      final s = SmartInputLiveMask.apply('100 mercado', 2026);
      expect(s, contains('R\$'));
      expect(s, contains('mercado'));
      expect(s, contains('1,00'));
    });

    test('formata prefixo e sufixo na mesma parte', () {
      final s = SmartInputLiveMask.apply('100 mercado 25000', 2026);
      expect(s, contains('mercado'));
      expect(s, contains('250,00'));
      expect(s, contains('1,00'));
    });

    test('ditado: 100 reais ou cem reais são reais inteiros (não centavos)', () {
      expect(SmartInputLiveMask.apply('100 reais', 2026), contains('100,00'));
      expect(SmartInputLiveMask.apply('100 reais', 2026), contains('R\$'));
      expect(SmartInputLiveMask.apply('cem reais', 2026), contains('100,00'));
      expect(SmartInputLiveMask.apply('mil reais', 2026), contains('1.000,00'));
      expect(SmartInputLiveMask.apply('vinte e cinco reais', 2026), contains('25,00'));
      expect(SmartInputLiveMask.apply('dois mil reais', 2026), contains('2.000,00'));
    });

    test('compra 100 reais mantém descrição e valor', () {
      final s = SmartInputLiveMask.apply('compra 100 reais', 2026);
      expect(s, contains('compra'));
      expect(s, contains('100,00'));
    });

    test(r'R$ com vírgula e espaço antes dos centavos (8750) vira 87,50 não 750,00', () {
      final s = SmartInputLiveMask.apply(r'farmácia 04/04/2026 R$ 8, 750', 2026);
      expect(s, contains('87,50'));
      expect(s, isNot(contains('750,00')));
      expect(s.toLowerCase(), contains('farmácia'));
    });

    test(r'R$ com vírgula e espaço em valor com dois decimais: 87, 50', () {
      final s = SmartInputLiveMask.apply(r'farmácia R$ 87, 50', 2026);
      expect(s, contains('87,50'));
    });
  });
}
