import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:controle_total_premium/utils/compromisso_share.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_BR');
  });

  group('compromissoMapLink', () {
    test('link http fica como está; texto vira busca no Maps', () {
      expect(compromissoMapLink('https://maps.app.goo.gl/x'),
          'https://maps.app.goo.gl/x');
      expect(
        compromissoMapLink('Av. Paulista, 1000'),
        'https://www.google.com/maps/search/?api=1&query=Av.+Paulista%2C+1000',
      );
      expect(compromissoMapLink('  '), isNull);
      expect(compromissoMapLink(null), isNull);
    });
  });

  group('compromissoShareText', () {
    test('título com emoji, data, horário, local, mapa e notas', () {
      final txt = compromissoShareText({
        'title': 'Aniversário Ana',
        'commitmentSymbol': 'emoji:🎂',
        'date': Timestamp.fromDate(DateTime(2027, 3, 10)),
        'time': '19:00',
        'endTime': '22:00',
        'linkLocalizacao': 'Rua das Flores, 10',
        'notes': 'Levar bolo\n\n🔁 Repete todo ano em 10/03. Série anual: '
            'aparece no calendário de Escalas e neste módulo.',
      });
      final linhas = txt.split('\n');
      expect(linhas.first, '🎂 Aniversário Ana');
      expect(txt, contains('📅 Quarta-feira, 10/03/2027'));
      expect(txt, contains('🕘 19:00 às 22:00'));
      expect(txt, contains('📍 Rua das Flores, 10'));
      expect(txt, contains('🗺️ Mapa: https://www.google.com/maps/search/'));
      expect(txt, contains('📝 Levar bolo'));
      // Linha técnica da série anual não vai para fora.
      expect(txt, isNot(contains('Repete todo ano')));
    });

    test('sem local nem notas: só o essencial; link http sem 📍', () {
      final txt = compromissoShareText({
        'title': 'Reunião',
        'time': '09:00',
        'linkLocalizacao': 'https://meet.example.com/abc',
      });
      expect(txt, isNot(contains('📍')));
      expect(txt, contains('🗺️ Mapa: https://meet.example.com/abc'));
      expect(txt, isNot(contains('📝')));
      expect(txt, contains('🕘 09:00'));
    });
  });
}
