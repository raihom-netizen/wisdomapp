import 'package:controle_total_premium/services/yearly_commitment_repeat_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Perda de dados: a limpeza da série anual (roda ao abrir Escalas) não pode
/// apagar compromissos comuns nem outras séries anuais.
void main() {
  bool ghost(
    String docId,
    Map<String, dynamic> data, {
    String keepTemplateId = 'tplA',
    String keepTitle = 'Casamento',
    int month = 5,
    int day = 24,
  }) =>
      YearlyCommitmentRepeatService.isGhostOfSeries(
        docId: docId,
        data: data,
        keepTemplateId: keepTemplateId,
        keepTitle: keepTitle,
        anchorMonth: month,
        anchorDay: day,
      );

  group('isGhostOfSeries — nunca apaga o que não é da série', () {
    test('compromisso comum com título parecido no mesmo dia fica', () {
      expect(
        ghost('comum1', {
          'title': 'Aniversário de Casamento',
          'yearlyRepeatMonth': 5,
          'yearlyRepeatDay': 24,
        }),
        isFalse,
      );
      expect(
        ghost('comum2', {
          'title': 'Casamento',
          'repeatYearly': false,
          'yearlyRepeatMonth': 5,
          'yearlyRepeatDay': 24,
        }),
        isFalse,
      );
    });

    test('outro modelo anual com o MESMO título fica (séries não se apagam)',
        () {
      expect(
        ghost('tplB', {
          'title': 'Casamento',
          'repeatYearly': true,
          'isYearlyRepeatTemplate': true,
          'yearlyRepeatMonth': 5,
          'yearlyRepeatDay': 24,
        }),
        isFalse,
      );
    });

    test('ocorrência de OUTRA série fica', () {
      expect(
        ghost('tplB_y2026', {
          'title': 'Casamento',
          'repeatYearly': true,
          'yearlyRepeatTemplateId': 'tplB',
          'yearlyRepeatMonth': 5,
          'yearlyRepeatDay': 24,
        }),
        isFalse,
      );
      expect(
        ghost('mestreB', {
          'title': 'Casamento',
          'repeatYearly': true,
          'yearlyRepeatTemplateId': 'tplB',
          'yearlyRepeatMonth': 5,
          'yearlyRepeatDay': 24,
        }),
        isFalse,
      );
    });

    test('anual legado com título só parecido fica', () {
      expect(
        ghost('legado1', {
          'title': 'Aniversário de Casamento',
          'repeatYearly': true,
          'yearlyRepeatMonth': 5,
          'yearlyRepeatDay': 24,
        }),
        isFalse,
      );
    });

    test('anual legado com título igual em OUTRA data fica', () {
      expect(
        ghost('legado2', {
          'title': 'Casamento',
          'repeatYearly': true,
          'yearlyRepeatMonth': 6,
          'yearlyRepeatDay': 24,
        }),
        isFalse,
      );
    });

    test('o próprio modelo e as ocorrências nunca são «fantasma»', () {
      expect(
          ghost('tplA', {'repeatYearly': true, 'title': 'Casamento'}), isFalse);
      expect(
        ghost('tplA_y2027', {
          'title': 'Casamento',
          'repeatYearly': true,
          'yearlyRepeatTemplateId': 'tplA',
        }),
        isFalse,
      );
    });
  });

  group('isGhostOfSeries — limpa só restos da própria série', () {
    test('mestre fantasma vinculado ao mesmo modelo', () {
      expect(
        ghost('mestreA', {
          'title': 'Casamento',
          'repeatYearly': true,
          'yearlyRepeatTemplateId': 'tplA',
        }),
        isTrue,
      );
    });

    test('legado sem vínculo, mesma data e título EXATAMENTE igual', () {
      expect(
        ghost('legado3', {
          'title': '  CASAMENTO ',
          'repeatYearly': true,
          'yearlyRepeatMonth': 5,
          'yearlyRepeatDay': 24,
        }),
        isTrue,
      );
    });
  });

  group('belongsToSeries', () {
    test('vínculo explícito ou ID de ocorrência', () {
      expect(
        YearlyCommitmentRepeatService.belongsToSeries(
          docId: 'x',
          data: {'yearlyRepeatTemplateId': 'tplA'},
          templateId: 'tplA',
        ),
        isTrue,
      );
      expect(
        YearlyCommitmentRepeatService.belongsToSeries(
          docId: 'tplA_y2026',
          data: const {},
          templateId: 'tplA',
        ),
        isTrue,
      );
      expect(
        YearlyCommitmentRepeatService.belongsToSeries(
          docId: 'tplAB_y2026',
          data: const {},
          templateId: 'tplA',
        ),
        isFalse,
      );
      expect(
        YearlyCommitmentRepeatService.belongsToSeries(
          docId: 'y',
          data: {'title': 'Casamento'},
          templateId: 'tplA',
        ),
        isFalse,
      );
    });
  });
}
