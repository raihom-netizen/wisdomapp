import 'package:flutter_test/flutter_test.dart';

import 'package:controle_total_premium/widgets/finance_calendar_color_picker.dart';

/// Regra (port Controle Total, 01/10/2026): lançamento financeiro só aparece
/// na Agenda com opt-in explícito (`addToCalendar == true`).
void main() {
  Map<String, dynamic> base([Map<String, dynamic> extra = const {}]) => {
        'type': 'expense',
        'amount': 30.0,
        'status': 'pending',
        'description': 'Conta de luz',
        ...extra,
      };

  test('sem o campo (legado) fica desligado', () {
    expect(FinanceCalendarColorPicker.calendarioLigado(base()), isFalse);
    expect(
      FinanceCalendarColorPicker.calendarioLigado(base({'fixedExpenseId': 'f1'})),
      isFalse,
    );
    expect(FinanceCalendarColorPicker.calendarioLigado(null), isFalse);
  });

  test('addToCalendar false fica desligado', () {
    expect(
      FinanceCalendarColorPicker.calendarioLigado(base({'addToCalendar': false})),
      isFalse,
    );
  });

  test('addToCalendar true liga', () {
    expect(
      FinanceCalendarColorPicker.calendarioLigado(base({'addToCalendar': true})),
      isTrue,
    );
  });

  test('hideFromCalendar true vence', () {
    expect(
      FinanceCalendarColorPicker.calendarioLigado(
          base({'addToCalendar': true, 'hideFromCalendar': true})),
      isFalse,
    );
  });

  test('cor sugerida: vermelho despesa, verde receita', () {
    expect(FinanceCalendarColorPicker.defaultHexFor(false), '#E53935');
    expect(FinanceCalendarColorPicker.defaultHexFor(true), '#2E7D32');
  });
}
