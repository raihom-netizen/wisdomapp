import 'package:flutter/material.dart' show Icons;

import '../constants/currency_formats.dart';
import '../models/finance_assistant_insight.dart';
import '../theme/app_colors.dart';
import 'finance_smart_tips_composer.dart';

/// Gera alertas e análises automáticas com base nos lançamentos do período (+ opcional período anterior).
class FinanceAssistantInsightsEngine {
  FinanceAssistantInsightsEngine._();

  static List<FinanceAssistantInsight> buildAlerts(
    FinanceSmartTipsStats s, {
    double? prevIncome,
    double? prevExpense,
  }) {
    final out = <FinanceAssistantInsight>[];
    final inc = s.totalIncome;
    final exp = s.totalExpense;
    final bal = s.balancePeriod;

    void add(FinanceAssistantInsight x) {
      if (out.any((e) => e.title == x.title)) return;
      out.add(x);
    }

    if (exp > inc + 0.01 && inc > 0.01) {
      add(
        FinanceAssistantInsight(
          title: 'Saídas acima das entradas',
          body:
              'As despesas (${CurrencyFormats.formatBRL(exp)}) superam as receitas (${CurrencyFormats.formatBRL(inc)}) neste período. '
              'Revise categorias e pendências antes de novos gastos.',
          icon: Icons.warning_amber_rounded,
          accentColor: AppColors.error,
          kind: FinanceAssistantInsightKind.warning,
        ),
      );
    }

    final top = s.topExpenseCategoryName;
    final share = s.topExpenseCategorySharePct;
    if (top != null && exp > 0.01) {
      final pctStr = share != null ? ' (~${share.toStringAsFixed(0)}% das despesas)' : '';
      add(
        FinanceAssistantInsight(
          title: 'Maior peso nas despesas',
          body:
              '«$top» está no topo do período$pctStr. Abra «Veja mais» nas categorias ou o extrato para cortar desperdício onde der.',
          icon: Icons.pie_chart_outline_rounded,
          accentColor: AppColors.logoOrange,
          kind: FinanceAssistantInsightKind.trend,
        ),
      );
    }

    if (exp > 0.01) {
      final save = exp * 0.10;
      add(
        FinanceAssistantInsight(
          title: 'Simulação: -10% nos gastos',
          body:
              'Reduzir 10% das despesas do período equivale a cerca de ${CurrencyFormats.formatBRL(save)} — ótimo para reserva ou metas.',
          icon: Icons.savings_outlined,
          accentColor: AppColors.success,
          kind: FinanceAssistantInsightKind.info,
        ),
      );
    }

    if (prevIncome != null && prevExpense != null) {
      final prevBal = prevIncome - prevExpense;
      if (prevExpense > 0.01 && exp > prevExpense * 1.08) {
        final p = ((exp - prevExpense) / prevExpense) * 100;
        add(
          FinanceAssistantInsight(
            title: 'Despesas em alta',
            body:
                'O total de despesas subiu cerca de ${p.toStringAsFixed(0)}% em relação ao período anterior (mesma duração).',
            icon: Icons.show_chart_rounded,
            accentColor: AppColors.financePendente,
            kind: FinanceAssistantInsightKind.trend,
          ),
        );
      }
      if (prevBal.abs() > 0.01 || bal.abs() > 0.01) {
        final deltaBal = bal - prevBal;
        final denom = prevBal.abs() > 0.01 ? prevBal.abs() : 1.0;
        final pctBal = (deltaBal / denom) * 100;
        if (pctBal.abs() >= 8) {
          add(
            FinanceAssistantInsight(
              title: deltaBal < 0 ? 'Saldo do período em queda' : 'Saldo do período em melhora',
              body: deltaBal < 0
                  ? 'Em relação ao intervalo anterior, o saldo (receitas - despesas) caiu cerca de ${pctBal.abs().toStringAsFixed(0)}%.'
                  : 'Em relação ao intervalo anterior, o saldo (receitas - despesas) melhorou cerca de ${pctBal.abs().toStringAsFixed(0)}%.',
              icon: deltaBal < 0 ? Icons.trending_down_rounded : Icons.trending_up_rounded,
              accentColor: deltaBal < 0 ? AppColors.error : AppColors.success,
              kind: FinanceAssistantInsightKind.trend,
            ),
          );
        }
      }
    }

    if (bal >= -0.01 && inc > 0.01 && bal >= 0) {
      add(
        FinanceAssistantInsight(
          title: 'Caixa do período no azul',
          body: 'Saldo receitas - despesas positivo. Ótimo momento para reforçar reserva ou metas.',
          icon: Icons.verified_rounded,
          accentColor: AppColors.primary,
          kind: FinanceAssistantInsightKind.success,
        ),
      );
    } else if (bal < -0.01) {
      add(
        FinanceAssistantInsight(
          title: 'Saldo do período negativo',
          body: 'Entradas não cobriram saídas neste intervalo. Priorize cortes discricionários e dívidas caras.',
          icon: Icons.report_problem_rounded,
          accentColor: AppColors.error,
          kind: FinanceAssistantInsightKind.warning,
        ),
      );
    }

    return out;
  }
}
