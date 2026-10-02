import 'package:controle_total_premium/services/yearly_commitment_repeat_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chave de data excluída no formato yyyy-MM-dd', () {
    expect(
      YearlyCommitmentRepeatService.excludedDateKey(DateTime(2026, 3, 7)),
      '2026-03-07',
    );
  });

  test('lê datas excluídas e ignora vazios', () {
    final s = YearlyCommitmentRepeatService.excludedDatesFromData({
      'yearlyRepeatExcludedDates': ['2026-03-07', '', ' 2026-03-14 '],
    });
    expect(s, {'2026-03-07', '2026-03-14'});
    expect(YearlyCommitmentRepeatService.excludedDatesFromData({}), isEmpty);
  });

  test('ocorrência por dia da semana tem id com mês e dia', () {
    final id = YearlyCommitmentRepeatService.instanceDocId('tpl', 2026,
        month: 3, day: 7);
    expect(id, 'tpl_y2026m03d07');
    expect(YearlyCommitmentRepeatService.isYearlyInstanceDocId(id), isTrue);
  });
}
