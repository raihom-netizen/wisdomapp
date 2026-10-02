import 'package:controle_total_premium/services/finance_sort_preference.dart';
import 'package:controle_total_premium/utils/finance_fatura_transaction_sort.dart';
import 'package:controle_total_premium/utils/finance_line_opening.dart';
import 'package:controle_total_premium/utils/finance_transaction_datetime.dart';
import 'package:controle_total_premium/utils/finance_transaction_status_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

/// Port do Controle Total (02/10/2026) — lançamentos de despesas e receitas.
void main() {
  group('ordem das grids', () {
    test('padrão do sistema é da mais antiga para a mais recente', () {
      expect(FinanceSortPreference.padrao, FinanceFaturaTxSortMode.dateAsc);
      expect(FinanceFaturaTxSortModeUi.fromKey('qualquer-coisa'),
          FinanceFaturaTxSortMode.dateAsc);
    });

    test('chave gravada volta para o mesmo modo', () {
      for (final m in FinanceFaturaTxSortMode.values) {
        expect(FinanceFaturaTxSortModeUi.fromKey(m.storageKey), m);
      }
    });
  });

  group('status do lançamento', () {
    test('«Pendente» escolhido na tela continua pendente mesmo no passado', () {
      final ontem = DateTime.now().subtract(const Duration(days: 1));
      expect(
        FinanceTransactionStatusResolver.resolveByDateTime(ontem,
            preferredStatus: 'pending', respeitarPendente: true),
        'pending',
      );
      // Sem a flag, a regra antiga: data passada entra como paga.
      expect(
        FinanceTransactionStatusResolver.resolveByDateTime(ontem,
            preferredStatus: 'pending'),
        'paid',
      );
    });
  });

  group('data e hora', () {
    test('sem segundos e com a hora escolhida no seletor', () {
      final d = DateTime(2026, 10, 2, 14, 35, 59, 999);
      expect(FinanceTransactionDatetime.withoutSeconds(d),
          DateTime(2026, 10, 2, 14, 35));
      expect(
          FinanceTransactionDatetime.mergeCalendarDayWithTimeOfDay(d, 8, 5),
          DateTime(2026, 10, 2, 8, 5));
    });

    test('data sem horário recebe o relógio; com horário é preservada', () {
      final comHora = DateTime(2026, 10, 2, 9, 30, 12);
      expect(FinanceTransactionDatetime.normalizeManualDateTime(comHora),
          DateTime(2026, 10, 2, 9, 30));
      final meiaNoite = DateTime(2026, 10, 2);
      final n = FinanceTransactionDatetime.normalizeManualDateTime(meiaNoite);
      expect(DateTime(n.year, n.month, n.day), meiaNoite);
    });
  });

  test('fórmula do saldo de abertura não mudou com o helper foraDoSaldo', () {
    final pagoControle = {
      'type': 'expense',
      'amount': 50.0,
      'status': 'paid',
      FinanceLineOpening.kBaixaSemSaldo: true,
    };
    expect(FinanceLineOpening.foraDoSaldo(pagoControle), isTrue);
    // WISDOMAPP não tem Finance Pro: o saldo continua contando o lançamento.
    expect(FinanceLineOpening.openingContribution(pagoControle), -50.0);
  });
}
