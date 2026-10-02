import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:controle_total_premium/widgets/color_palette_tabs_dialog.dart';

/// Compatibilidade com as cores JÁ LANÇADAS pelos usuários.
///
/// O seletor novo lê o mesmo campo `colorHex` que anos de compromissos,
/// escalas, audiências e lançamentos gravaram — em formatos diferentes,
/// conforme a tela que salvou. Nenhum desses valores pode derrubar a tela nem
/// mudar a cor que a pessoa escolheu.
void main() {
  group('lê os formatos que existem no banco', () {
    test('#RRGGBB (o mais comum)', () {
      expect(ColorPaletteTabsDialog.corDeHex('#2E7D32'),
          const Color(0xFF2E7D32));
    });

    test('RRGGBB sem cerquilha', () {
      expect(ColorPaletteTabsDialog.corDeHex('2E7D32'), const Color(0xFF2E7D32));
    });

    test('0xFFRRGGBB — usa os ÚLTIMOS seis, não os primeiros', () {
      // Pegar os primeiros devolvia 0xFFFF2E7D: outra cor, e o usuário via o
      // compromisso mudar sozinho de cor.
      expect(ColorPaletteTabsDialog.corDeHex('0xFF2E7D32'),
          const Color(0xFF2E7D32));
    });

    test('FFRRGGBB (com alfa, sem prefixo)', () {
      expect(ColorPaletteTabsDialog.corDeHex('FF2E7D32'),
          const Color(0xFF2E7D32));
    });

    test('minúsculas', () {
      expect(ColorPaletteTabsDialog.corDeHex('#2e7d32'),
          const Color(0xFF2E7D32));
    });

    test('com espaços em volta', () {
      expect(ColorPaletteTabsDialog.corDeHex('  #2E7D32 '),
          const Color(0xFF2E7D32));
    });
  });

  group('não quebra com dado ruim', () {
    test('nulo', () {
      expect(() => ColorPaletteTabsDialog.corDeHex(null), returnsNormally);
    });

    test('vazio', () {
      expect(() => ColorPaletteTabsDialog.corDeHex(''), returnsNormally);
    });

    test('texto que não é cor', () {
      expect(() => ColorPaletteTabsDialog.corDeHex('verde'), returnsNormally);
    });

    test('hex incompleto', () {
      expect(() => ColorPaletteTabsDialog.corDeHex('#2E7'), returnsNormally);
    });

    test('caracteres inválidos', () {
      expect(() => ColorPaletteTabsDialog.corDeHex('#ZZZZZZ'), returnsNormally);
    });

    test('dado ruim cai numa cor válida, não em transparente', () {
      final c = ColorPaletteTabsDialog.corDeHex('lixo');
      expect(c.a, 1.0, reason: 'cor invisível esconderia o lançamento');
    });
  });

  group('cores antigas continuam sendo exibidas como foram salvas', () {
    // Tons do Material Design 2 que ficaram gravados antes da paleta nova.
    const antigas = {
      '#2E7D32': Color(0xFF2E7D32), // verde escuro
      '#8D6E63': Color(0xFF8D6E63), // marrom
      '#455A64': Color(0xFF455A64), // cinza-azulado
      '#F9A825': Color(0xFFF9A825), // dourado mostarda
      '#00897B': Color(0xFF00897B), // teal
    };

    test('todas voltam exatamente iguais', () {
      antigas.forEach((hex, esperada) {
        expect(ColorPaletteTabsDialog.corDeHex(hex), esperada,
            reason: '$hex mudou de cor — lançamento antigo seria alterado');
      });
    });
  });
}
