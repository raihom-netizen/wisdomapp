import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/currency_formats.dart';
import '../constants/date_time_formats.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';
import '../utils/finance_line_opening.dart';
import '../utils/finance_period_summary.dart';
import '../utils/finance_transactions_realtime.dart';
import '../widgets/finance_premium_ui.dart';

/// Full screen: distribuição de **despesas** por categoria (gráfico pizza + lista estilo fintech).
///
/// Dados reais do período e dos mesmos filtros de status / conta / pesquisa da tela Financeiro.
typedef FinanceCategoryInsightOpener = Future<void> Function(BuildContext context, String categoryName);

class FinanceCategoriesFullscreenPage extends StatefulWidget {
  const FinanceCategoriesFullscreenPage({
    super.key,
    required this.uid,
    required this.profile,
    required this.from,
    required this.to,
    required this.statusFilter,
    this.financeAccountFilterId,
    this.searchLower = '',
    required this.onCategoryTap,
  });

  final String uid;
  final UserProfile profile;
  final DateTime from;
  final DateTime to;
  final String statusFilter;
  final String? financeAccountFilterId;
  final String searchLower;
  final FinanceCategoryInsightOpener onCategoryTap;

  @override
  State<FinanceCategoriesFullscreenPage> createState() => _FinanceCategoriesFullscreenPageState();
}

class _FinanceCategoriesFullscreenPageState extends State<FinanceCategoriesFullscreenPage> {
  static const int _kMaxPieSlices = 10;

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>? _docsFuture;
  Future<({double income, double expense})>? _totalsFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _docsFuture = _loadDocs();
    _totalsFuture = FinancePeriodSummary.load(
      uid: widget.uid,
      from: widget.from,
      to: widget.to,
      statusFilter: widget.statusFilter,
      typeFilter: 'all',
    ).then((r) => (income: r.income, expense: r.expense));
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _loadDocs() async {
    return financePeriodMergedDocumentsCollect(
      uid: widget.uid,
      from: widget.from,
      to: widget.to,
      statusFilter: widget.statusFilter,
      typeFilter: 'all',
      financeAccountId: widget.financeAccountFilterId,
    );
  }

  /// Mesma ideia de [_WhereMoneyExpenseCard] em `finance_screen.dart`.
  static Color _accentForCategory(String category) {
    const palette = <Color>[
      Color(0xFFE11D48),
      Color(0xFFEA580C),
      Color(0xFF7C3AED),
      Color(0xFF0891B2),
      Color(0xFF059669),
      Color(0xFF2563EB),
      Color(0xFFDB2777),
      Color(0xFFD97706),
    ];
    return palette[category.hashCode.abs() % palette.length];
  }

  static IconData _iconForCategory(String category) {
    final l = category.toLowerCase().trim();
    if (l.contains('cart')) return Icons.credit_card_rounded;
    if (l.contains('escola') || l.contains('educa')) return Icons.school_rounded;
    if (l.contains('consórcio') || l.contains('consorcio')) return Icons.groups_rounded;
    if (l.contains('combust') || l.contains('gasolina')) return Icons.local_gas_station_rounded;
    if (l.contains('mercado') || l.contains('super')) return Icons.shopping_cart_rounded;
    if (l.contains('saúde') || l.contains('saude') || l.contains('medic')) return Icons.medical_services_rounded;
    if (l.contains('moradia') || l.contains('aluguel')) return Icons.home_rounded;
    if (l.contains('lazer')) return Icons.sports_esports_rounded;
    if (l.contains('restaur')) return Icons.restaurant_rounded;
    if (l.contains('transport')) return Icons.directions_car_rounded;
    return Icons.pie_chart_rounded;
  }

  List<MapEntry<String, double>> _expenseByCategory(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final m = <String, double>{};
    final rs = DateTime(widget.from.year, widget.from.month, widget.from.day);
    final re = DateTime(widget.to.year, widget.to.month, widget.to.day, 23, 59, 59);
    final search = widget.searchLower.trim().toLowerCase();
    for (final doc in docs) {
      final d = doc.data();
      if ((d['type'] ?? 'expense').toString() != 'expense') continue;
      final effective = FinanceLineOpening.effectiveDateTimeFromMap(d);
      if (effective == null || effective.isBefore(rs) || effective.isAfter(re)) continue;
      if (search.isNotEmpty) {
        final text = '${d['category'] ?? ''} ${d['description'] ?? ''}'.toLowerCase();
        if (!text.contains(search)) continue;
      }
      final cat = (d['category'] ?? '').toString().trim();
      final key = cat.isEmpty ? 'Sem categoria' : cat;
      final amt = (d['amount'] ?? 0);
      m[key] = (m[key] ?? 0) + (amt is num ? amt.toDouble().abs() : 0);
    }
    final list = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return list;
  }

  List<MapEntry<String, double>> _collapseOthers(List<MapEntry<String, double>> sorted, int maxSlices) {
    if (sorted.length <= maxSlices) return sorted;
    final head = sorted.take(maxSlices - 1).toList();
    var rest = 0.0;
    for (var i = maxSlices - 1; i < sorted.length; i++) {
      rest += sorted[i].value;
    }
    return [...head, MapEntry('Outros', rest)];
  }

  @override
  Widget build(BuildContext context) {
    final periodLabel =
        '${DateTimeFormats.dateBR.format(widget.from)} — ${DateTimeFormats.dateBR.format(widget.to)}';

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    tooltip: 'Voltar',
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Despesas por categoria',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1A237E),
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          periodLabel,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<dynamic>>(
                future: Future.wait([_docsFuture!, _totalsFuture!]),
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done && !snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Erro ao carregar: ${snap.error}',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade800),
                        ),
                      ),
                    );
                  }
                  final docs = (snap.data![0] as List<QueryDocumentSnapshot<Map<String, dynamic>>>);
                  final totals = snap.data![1] as ({double income, double expense});
                  final entriesFull = _expenseByCategory(docs);
                  final totalExpense = totals.expense > 0 ? totals.expense : entriesFull.fold<double>(0, (s, e) => s + e.value);
                  final pieEntries = _collapseOthers(entriesFull, _kMaxPieSlices);

                  if (entriesFull.isEmpty || totalExpense <= 0) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.pie_chart_outline_rounded, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                              'Sem despesas no período',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.grey.shade700),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Ajuste filtros na tela Financeiro ou escolha outro período.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.35),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final sections = <PieChartSectionData>[];
                  for (var i = 0; i < pieEntries.length; i++) {
                    final e = pieEntries[i];
                    final color = e.key == 'Outros' ? AppColors.textMuted : _accentForCategory(e.key);
                    final pct = totalExpense > 0 ? (e.value / totalExpense * 100) : 0.0;
                    sections.add(
                      PieChartSectionData(
                        color: color,
                        value: e.value,
                        title: pct >= 1 ? CurrencyFormats.formatPercentBr(pct) : '',
                        radius: 52,
                        titleStyle: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          shadows: [Shadow(color: Colors.black26, blurRadius: 2)],
                        ),
                      ),
                    );
                  }

                  final hPad = math.max(16.0, (MediaQuery.sizeOf(context).width - 560) / 2);

                  return CustomScrollView(
                    physics: const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                    slivers: [
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 12),
                        sliver: SliverToBoxAdapter(
                          child: FinanceInsightPeriodTotalizer(
                            income: totals.income,
                            expense: totals.expense,
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 12),
                        sliver: SliverToBoxAdapter(
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.deepBlueDark.withValues(alpha: 0.06),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            AppColors.financeDespesa.withValues(alpha: 0.2),
                                            AppColors.primary.withValues(alpha: 0.12),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Icon(Icons.donut_large_rounded, color: AppColors.financeDespesa, size: 22),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Distribuição',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.4,
                                              color: AppColors.textMuted,
                                            ),
                                          ),
                                          Text(
                                            CurrencyFormats.formatBRLTight(totalExpense),
                                            style: const TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.w900,
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 18),
                                SizedBox(
                                  height: 220,
                                  child: PieChart(
                                    PieChartData(
                                      sections: sections,
                                      sectionsSpace: 2,
                                      centerSpaceRadius: 56,
                                      startDegreeOffset: -90,
                                    ),
                                    duration: const Duration(milliseconds: 420),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 8),
                        sliver: SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 4, bottom: 6),
                            child: Text(
                              'Categorias',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: Colors.grey.shade800,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 24),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final e = entriesFull[index];
                              final pct = totalExpense > 0 ? (e.value / totalExpense * 100) : 0.0;
                              final accent = _accentForCategory(e.key);
                              final icon = _iconForCategory(e.key);
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Material(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(18),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(18),
                                    onTap: widget.profile.hasActiveLicense
                                        ? () => widget.onCategoryTap(context, e.key)
                                        : () {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Recurso disponível com licença ativa.')),
                                            );
                                          },
                                    child: Ink(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(color: const Color(0xFFE2E8F0)),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.04),
                                            blurRadius: 12,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                        child: Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 22,
                                              backgroundColor: accent.withValues(alpha: 0.15),
                                              child: Icon(icon, color: accent, size: 22),
                                            ),
                                            const SizedBox(width: 14),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    e.key,
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.w800,
                                                      fontSize: 15,
                                                      color: AppColors.textPrimary,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  ClipRRect(
                                                    borderRadius: BorderRadius.circular(99),
                                                    child: LinearProgressIndicator(
                                                      value: pct / 100,
                                                      minHeight: 6,
                                                      backgroundColor: Colors.grey.shade200,
                                                      color: accent.withValues(alpha: 0.85),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              children: [
                                                Text(
                                                  CurrencyFormats.formatBRLTight(e.value),
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: 15,
                                                    color: AppColors.textPrimary,
                                                  ),
                                                ),
                                                Text(
                                                  CurrencyFormats.formatPercentBr(pct),
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 12,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(width: 4),
                                            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                            childCount: entriesFull.length,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
