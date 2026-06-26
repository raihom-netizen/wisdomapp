import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../constants/currency_formats.dart';
import '../constants/finance_category_visuals.dart';
import '../theme/app_colors.dart';

/// Entrada ordenada para gráficos por categoria.
typedef FinanceCategoryEntry = ({String category, double value});

/// Agrupa fatias menores em «Outros».
List<FinanceCategoryEntry> collapseFinanceCategoryEntries(
  Map<String, double> totals, {
  int maxSlices = 8,
}) {
  if (totals.isEmpty) return const [];
  final sorted = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  if (sorted.length <= maxSlices) {
    return sorted.map((e) => (category: e.key, value: e.value)).toList();
  }
  final top = sorted.take(maxSlices - 1).toList();
  final others = sorted.skip(maxSlices - 1).fold<double>(0, (s, e) => s + e.value);
  return [
    ...top.map((e) => (category: e.key, value: e.value)),
    (category: 'Outros', value: others),
  ];
}

/// Donut moderno por categorias (receitas ou despesas).
class FinanceCategoryPiePanel extends StatelessWidget {
  const FinanceCategoryPiePanel({
    super.key,
    required this.title,
    required this.entries,
    required this.isIncome,
    this.subtitle,
    this.maxLegendRows = 8,
  });

  final String title;
  final String? subtitle;
  final List<FinanceCategoryEntry> entries;
  final bool isIncome;
  final int maxLegendRows;

  static const _anim = Duration(milliseconds: 650);
  static const _minPctLabel = 0.055;

  Color get _accent =>
      isIncome ? AppColors.financeReceita : AppColors.financeDespesa;

  @override
  Widget build(BuildContext context) {
    final visible = entries.where((e) => e.value > 0).toList();
    final total = visible.fold<double>(0, (s, e) => s + e.value);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _accent.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: _accent.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _accent,
                      Color.lerp(_accent, Colors.black, 0.15)!,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isIncome ? Icons.trending_up_rounded : Icons.pie_chart_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    if (subtitle != null && subtitle!.trim().isNotEmpty)
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (total <= 0)
            _emptyState()
          else
            LayoutBuilder(
              builder: (context, c) {
                final stacked = c.maxWidth < 380;
                final chart = _donut(total: total, visible: visible);
                final legend = _legend(total: total, visible: visible);
                if (stacked) {
                  return Column(
                    children: [
                      chart,
                      const SizedBox(height: 14),
                      legend,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    chart,
                    const SizedBox(width: 14),
                    Expanded(child: legend),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _accent.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          Icon(Icons.donut_large_outlined, size: 40, color: _accent.withValues(alpha: 0.45)),
          const SizedBox(height: 8),
          Text(
            'Sem lançamentos por categoria',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _donut({required double total, required List<FinanceCategoryEntry> visible}) {
    final sections = visible.asMap().entries.map((e) {
      final entry = e.value;
      final pct = entry.value / total;
      final color = entry.category == 'Outros'
          ? AppColors.textMuted
          : financeCategoryVisualFor(entry.category, isIncome: isIncome).color;
      final showTitle = pct >= _minPctLabel;
      return PieChartSectionData(
        value: entry.value,
        color: color,
        radius: 58,
        title: showTitle ? '${(pct * 100).round()}%' : '',
        showTitle: showTitle,
        titleStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          shadows: [Shadow(color: Colors.black26, blurRadius: 2)],
        ),
      );
    }).toList();

    return SizedBox(
      width: 168,
      height: 168,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              sections: sections,
              sectionsSpace: 2.5,
              centerSpaceRadius: 46,
              startDegreeOffset: -90,
            ),
            duration: _anim,
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                CurrencyFormats.formatBRLTight(total),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: _accent,
                  height: 1.1,
                ),
              ),
              Text(
                '${visible.length} cat.',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend({required double total, required List<FinanceCategoryEntry> visible}) {
    final rows = visible.take(maxLegendRows).toList();
    final maxVal = rows.isEmpty ? 1.0 : rows.map((e) => e.value).reduce(math.max);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows.map((entry) {
        final pct = total > 0 ? (entry.value / total * 100) : 0.0;
        final color = entry.category == 'Outros'
            ? AppColors.textMuted
            : financeCategoryVisualFor(entry.category, isIncome: isIncome).color;
        final ratio = maxVal <= 0 ? 0.0 : (entry.value / maxVal).clamp(0.04, 1.0);

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              financeCategoryLeadingTile(
                entry.category,
                isIncome: isIncome,
                size: 32,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.category,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ),
                        Text(
                          CurrencyFormats.formatPercentBr(pct),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      CurrencyFormats.formatBRLTight(entry.value),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 5,
                        backgroundColor: color.withValues(alpha: 0.12),
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// Conjunto de gráficos por categoria conforme escopo (receitas, despesas ou ambos).
class FinanceCategoryChartsSuite extends StatelessWidget {
  const FinanceCategoryChartsSuite({
    super.key,
    required this.mode,
    required this.incomeByCategory,
    required this.expenseByCategory,
    this.maxSlices = 8,
  });

  /// `income` | `expense` | `both`
  final String mode;
  final Map<String, double> incomeByCategory;
  final Map<String, double> expenseByCategory;
  final int maxSlices;

  @override
  Widget build(BuildContext context) {
    final showIncome = mode == 'income' || mode == 'both';
    final showExpense = mode == 'expense' || mode == 'both';

    final incomeEntries = collapseFinanceCategoryEntries(incomeByCategory, maxSlices: maxSlices);
    final expenseEntries = collapseFinanceCategoryEntries(expenseByCategory, maxSlices: maxSlices);

    if (!showIncome && !showExpense) return const SizedBox.shrink();

    if (showIncome && showExpense) {
      return LayoutBuilder(
        builder: (context, c) {
          final sideBySide = c.maxWidth >= 720;
          final incomePanel = FinanceCategoryPiePanel(
            title: 'Receitas por categoria',
            isIncome: true,
            entries: incomeEntries,
          );
          final expensePanel = FinanceCategoryPiePanel(
            title: 'Despesas por categoria',
            isIncome: false,
            entries: expenseEntries,
          );
          if (sideBySide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: incomePanel),
                const SizedBox(width: 10),
                Expanded(child: expensePanel),
              ],
            );
          }
          return Column(
            children: [
              incomePanel,
              const SizedBox(height: 10),
              expensePanel,
            ],
          );
        },
      );
    }

    if (showIncome) {
      return FinanceCategoryPiePanel(
        title: 'Receitas por categoria',
        isIncome: true,
        entries: incomeEntries,
      );
    }

    return FinanceCategoryPiePanel(
      title: 'Despesas por categoria',
      isIncome: false,
      entries: expenseEntries,
    );
  }
}
