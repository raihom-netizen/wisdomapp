import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/currency_formats.dart';
import 'report_layout_responsive.dart';

/// Raios e sombras no estilo “Clean Premium” (referência: Gestão Yahweh — Relatório Financeiro).
const double _kRadiusMd = 14.0;
const double _kRadiusLg = 18.0;
const Color _kEmerald = Color(0xFF059669);
const List<BoxShadow> _kSoftShadow = [
  BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4)),
];

/// KPI compacto com fundo tintado (mesmo padrão visual do Yahweh).
class ReportFinanceStatCard extends StatelessWidget {
  final String title;
  final double value;
  final Color color;

  const ReportFinanceStatCard({
    super.key,
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              CurrencyFormats.formatBRLTight(value),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Agrega despesas por categoria (ordenado desc. por valor).
List<Map<String, dynamic>> computeReportGastosPorCategoria(List<Map<String, dynamic>> expenseList) {
  final m = <String, double>{};
  for (final e in expenseList) {
    final cat = (e['category'] ?? '').toString().trim();
    final key = cat.isEmpty ? 'Sem categoria' : cat;
    m[key] = (m[key] ?? 0) + ((e['amount'] ?? 0) as num).toDouble();
  }
  final list = m.entries.map((e) => {'categoria': e.key, 'valor': e.value}).toList();
  list.sort((a, b) => ((b['valor'] ?? 0) as num).compareTo((a['valor'] ?? 0) as num));
  return list;
}

/// Entradas e saídas por conta no período (IDs vazios agrupam em “Sem conta”).
List<Map<String, dynamic>> computeReportPorConta(
  List<Map<String, dynamic>> incomeList,
  List<Map<String, dynamic>> expenseList,
  Map<String, String> accountIdToName,
) {
  const semId = '__sem_conta__';
  final m = <String, Map<String, double>>{};

  void bump(String rawId, bool entrada, double amt) {
    final id = rawId.trim().isEmpty ? semId : rawId.trim();
    m.putIfAbsent(id, () => {'entradas': 0, 'saidas': 0});
    if (entrada) {
      m[id]!['entradas'] = (m[id]!['entradas'] ?? 0) + amt;
    } else {
      m[id]!['saidas'] = (m[id]!['saidas'] ?? 0) + amt;
    }
  }

  for (final e in incomeList) {
    bump((e['financeAccountId'] ?? '').toString(), true, ((e['amount'] ?? 0) as num).toDouble());
  }
  for (final e in expenseList) {
    bump((e['financeAccountId'] ?? '').toString(), false, ((e['amount'] ?? 0) as num).toDouble());
  }

  String nome(String id) {
    if (id == semId) return 'Sem conta';
    return accountIdToName[id] ?? 'Conta removida';
  }

  final out = m.entries.map((e) {
    final inn = ((e.value['entradas'] ?? 0) as num).toDouble();
    final outv = ((e.value['saidas'] ?? 0) as num).toDouble();
    return {
      'id': e.key,
      'nome': nome(e.key),
      'entradas': inn,
      'saidas': outv,
      'liquido': inn - outv,
    };
  }).toList()
    ..sort((a, b) => ((b['liquido'] ?? 0) as num).toDouble().abs().compareTo(((a['liquido'] ?? 0) as num).toDouble().abs()));

  return out;
}

/// Série temporal receitas x despesas no intervalo (dia a dia ou mês a mês se > 90 dias).
class ReportFinanceEvolucao {
  final List<String> labels;
  final List<double> receitas;
  final List<double> despesas;

  const ReportFinanceEvolucao({
    required this.labels,
    required this.receitas,
    required this.despesas,
  });

  bool get isEffectivelyEmpty {
    if (labels.isEmpty) return true;
    double t = 0;
    for (final v in receitas) {
      t += v;
    }
    for (final v in despesas) {
      t += v;
    }
    return t < 0.0001;
  }
}

ReportFinanceEvolucao computeReportFinanceEvolucao({
  required List<Map<String, dynamic>> incomeList,
  required List<Map<String, dynamic>> expenseList,
  required DateTime rangeStart,
  required DateTime rangeEnd,
}) {
  final inicioD = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
  final fimD = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day);
  final spanDays = fimD.difference(inicioD).inDays + 1;

  final monthly = spanDays > 90;
  int n;
  if (monthly) {
    n = (rangeEnd.year - rangeStart.year) * 12 + (rangeEnd.month - rangeStart.month) + 1;
  } else {
    n = spanDays;
  }
  if (n < 1) n = 1;

  final rec = List<double>.filled(n, 0);
  final des = List<double>.filled(n, 0);

  void addRow(Map<String, dynamic> e, bool isIncome) {
    final ts = e['date'];
    final dt = ts is Timestamp ? ts.toDate() : DateTime.now();
    int idx = -1;
    if (monthly) {
      idx = (dt.year - inicioD.year) * 12 + (dt.month - inicioD.month);
      if (idx < 0 || idx >= n) idx = -1;
    } else {
      idx = DateTime(dt.year, dt.month, dt.day).difference(inicioD).inDays;
      if (idx < 0 || idx >= n) idx = -1;
    }
    if (idx < 0) return;
    final val = ((e['amount'] ?? 0) as num).toDouble();
    if (isIncome) {
      rec[idx] += val;
    } else {
      des[idx] += val;
    }
  }

  for (final e in incomeList) {
    addRow(e, true);
  }
  for (final e in expenseList) {
    addRow(e, false);
  }

  final labels = <String>[];
  if (monthly) {
    for (var i = 0; i < n; i++) {
      final d = DateTime(inicioD.year, inicioD.month + i);
      labels.add(DateFormat('MMM/yy', 'pt_BR').format(d));
    }
  } else {
    for (var i = 0; i < n; i++) {
      final d = inicioD.add(Duration(days: i));
      labels.add('${d.day}/${d.month}');
    }
  }

  return ReportFinanceEvolucao(labels: labels, receitas: rec, despesas: des);
}

/// Gráfico de linhas — entradas (verde) e saídas (vermelho), como no Yahweh.
class ReportFinanceEvolucaoLineChart extends StatelessWidget {
  final ReportFinanceEvolucao data;

  const ReportFinanceEvolucaoLineChart({super.key, required this.data});

  static const _anim = Duration(milliseconds: 650);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (data.labels.isEmpty) {
      return const SizedBox.shrink();
    }
    if (data.isEffectivelyEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(_kRadiusMd),
          boxShadow: _kSoftShadow,
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Text(
          'Sem movimentação no período para o gráfico de evolução.',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
        ),
      );
    }
    final maxVal = [...data.receitas, ...data.despesas].reduce(math.max);
    final maxY = maxVal <= 0 ? 100.0 : maxVal * 1.12;
    final n = data.labels.length;
    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < kReportGridBreakpointCompact;
        final leftR = narrow ? 36.0 : 48.0;
        final chartH = narrow ? 200.0 : 228.0;
        final labelFs = narrow ? 8.0 : 9.0;
        return Container(
          padding: EdgeInsets.all(narrow ? 12 : 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.surface,
                Color.lerp(scheme.surface, _kEmerald, Theme.of(context).brightness == Brightness.dark ? 0.1 : 0.04) ?? scheme.surface,
              ],
            ),
            borderRadius: BorderRadius.circular(_kRadiusLg),
            boxShadow: _kSoftShadow,
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _kEmerald.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.show_chart_rounded, color: _kEmerald, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Evolução no período',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Receitas e despesas por dia ou por mês, conforme a duração do período.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, height: 1.3),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: chartH,
                child: LineChart(
                  LineChartData(
                    minY: 0,
                    maxY: maxY,
                    clipData: const FlClipData.all(),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: maxY > 0 ? maxY / 4 : 25,
                      getDrawingHorizontalLine: (_) => FlLine(
                        color: scheme.outlineVariant.withValues(alpha: 0.55),
                        strokeWidth: 1,
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: leftR,
                          getTitlesWidget: (v, _) => Text(
                            NumberFormat.compactCurrency(locale: 'pt_BR', symbol: r'R$').format(v),
                            style: TextStyle(fontSize: labelFs, color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: narrow ? 26 : 28,
                          interval: n > 14 ? (n / 8).ceilToDouble() : 1,
                          getTitlesWidget: (v, _) {
                            final i = v.toInt();
                            if (i >= 0 && i < n) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  data.labels[i],
                                  style: TextStyle(fontSize: labelFs, color: scheme.onSurfaceVariant),
                                ),
                              );
                            }
                            return const SizedBox();
                          },
                        ),
                      ),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: List.generate(n, (i) => FlSpot(i.toDouble(), data.receitas[i])),
                        isCurved: true,
                        curveSmoothness: 0.22,
                        color: const Color(0xFF16A34A),
                        barWidth: 3,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          color: const Color(0xFF16A34A).withValues(alpha: 0.08),
                        ),
                      ),
                      LineChartBarData(
                        spots: List.generate(n, (i) => FlSpot(i.toDouble(), data.despesas[i])),
                        isCurved: true,
                        curveSmoothness: 0.22,
                        color: const Color(0xFFDC2626),
                        barWidth: 3,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          color: const Color(0xFFDC2626).withValues(alpha: 0.06),
                        ),
                      ),
                    ],
                    lineTouchData: LineTouchData(
                      enabled: true,
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipItems: (List<LineBarSpot> touchedSpots) {
                          return touchedSpots.map((t) {
                            final i = t.x.toInt();
                            if (i < 0 || i >= n) return null;
                            final isRec = t.barIndex == 0;
                            final label = isRec ? 'Receitas' : 'Despesas';
                            final val = isRec ? data.receitas[i] : data.despesas[i];
                            return LineTooltipItem(
                              '$label\n${NumberFormat.currency(locale: 'pt_BR', symbol: r'R$').format(val)}',
                              const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            );
                          }).whereType<LineTooltipItem>().toList();
                        },
                      ),
                    ),
                  ),
                  duration: _anim,
                  curve: Curves.easeOutCubic,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 16,
                runSpacing: 6,
                children: const [
                  _LegendDot(color: Color(0xFF16A34A), label: 'Receitas'),
                  _LegendDot(color: Color(0xFFDC2626), label: 'Despesas'),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final o = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: o),
        ),
      ],
    );
  }
}

/// Por conta: cards empilhados no telefone / PWA estreito; tabela em telas largas.
class ReportFinancePorContaPanel extends StatelessWidget {
  final List<Map<String, dynamic>> rows;

  const ReportFinancePorContaPanel({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(_kRadiusLg),
        boxShadow: _kSoftShadow,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _kEmerald.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.account_balance_wallet_rounded, color: _kEmerald, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Por conta (detalhe)',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Receitas creditadas e despesas debitadas em cada conta no período.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, height: 1.3),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              final compact = c.maxWidth < kReportGridBreakpointCompact;
              final slice = rows.take(24).toList();
              if (compact) {
                return Column(
                  children: [
                    for (final m in slice) _porContaCard(context, m),
                  ],
                );
              }
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: math.max(c.maxWidth, 480)),
                  child: DataTable(
                    dataRowMinHeight: 48,
                    headingRowHeight: 44,
                    horizontalMargin: 16,
                    columnSpacing: 20,
                    headingRowColor: WidgetStateProperty.all(
                      Color.lerp(scheme.surface, scheme.onSurface, 0.04) ?? scheme.surface,
                    ),
                    dataTextStyle: TextStyle(fontSize: 13, color: scheme.onSurface),
                    headingTextStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                    columns: const [
                      DataColumn(label: Text('Conta')),
                      DataColumn(label: Text('Receitas'), numeric: true),
                      DataColumn(label: Text('Despesas'), numeric: true),
                      DataColumn(label: Text('Líquido'), numeric: true),
                    ],
                    rows: [
                      for (final m in slice)
                        DataRow(
                          cells: [
                            DataCell(
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 220),
                                child: Text(
                                  (m['nome'] ?? '').toString(),
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            DataCell(Text(
                              CurrencyFormats.formatBRL((m['entradas'] ?? 0) as num),
                              style: const TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.w600),
                            )),
                            DataCell(Text(
                              CurrencyFormats.formatBRL((m['saidas'] ?? 0) as num),
                              style: const TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.w600),
                            )),
                            DataCell(Text(
                              CurrencyFormats.formatBRL((m['liquido'] ?? 0) as num),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: ((m['liquido'] ?? 0) as num).toDouble() >= 0
                                    ? const Color(0xFF0D9488)
                                    : const Color(0xFFB91C1C),
                              ),
                            )),
                          ],
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  static Widget _porContaCard(BuildContext context, Map<String, dynamic> m) {
    final s = Theme.of(context).colorScheme;
    final liq = ((m['liquido'] ?? 0) as num).toDouble();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: s.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: s.outlineVariant),
        boxShadow: const [
          BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            (m['nome'] ?? '').toString(),
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: s.onSurface),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _porContaMini(
                  context,
                  'Receitas',
                  CurrencyFormats.formatBRL((m['entradas'] ?? 0) as num),
                  const Color(0xFF16A34A),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _porContaMini(
                  context,
                  'Despesas',
                  CurrencyFormats.formatBRL((m['saidas'] ?? 0) as num),
                  const Color(0xFFDC2626),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _porContaMini(
            context,
            'Líquido',
            CurrencyFormats.formatBRL((m['liquido'] ?? 0) as num),
            liq >= 0 ? const Color(0xFF0D9488) : const Color(0xFFB91C1C),
            wide: true,
          ),
        ],
      ),
    );
  }

  static Widget _porContaMini(
    BuildContext context,
    String label,
    String value,
    Color c, {
    bool wide = false,
  }) {
    final s = Theme.of(context).colorScheme;
    return Container(
      width: wide ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: c, letterSpacing: 0.2),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: c),
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Barras totais Receitas × Despesas + pizza de despesas por categoria.
class ReportFinanceBiCharts extends StatelessWidget {
  final double totalReceitas;
  final double totalDespesas;
  final List<Map<String, dynamic>> gastosPorCategoria;

  const ReportFinanceBiCharts({
    super.key,
    required this.totalReceitas,
    required this.totalDespesas,
    required this.gastosPorCategoria,
  });

  static const _anim = Duration(milliseconds: 750);

  List<PieChartSectionData> _pieSections() {
    const palette = <Color>[
      Color(0xFFDC2626),
      Color(0xFFEA580C),
      Color(0xFFCA8A04),
      Color(0xFF16A34A),
      Color(0xFF2563EB),
      Color(0xFF7C3AED),
      Color(0xFFDB2777),
      Color(0xFF0891B2),
    ];
    final top = gastosPorCategoria.take(8).toList();
    final total = top.fold<double>(0, (a, e) => a + ((e['valor'] ?? 0) as num).toDouble());
    if (total <= 0) return [];
    return List.generate(top.length, (i) {
      final val = ((top[i]['valor'] ?? 0) as num).toDouble();
      return PieChartSectionData(
        value: val,
        title: '${(100 * val / total).toStringAsFixed(0)}%',
        color: palette[i % palette.length],
        radius: 52,
        titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxY = math.max(100.0, math.max(totalReceitas, totalDespesas) * 1.12);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final narrow = c.maxWidth < kReportGridBreakpointCompact;
            final leftR = narrow ? 36.0 : 48.0;
            final barW = narrow ? 22.0 : 30.0;
            return Container(
              padding: EdgeInsets.all(narrow ? 12 : 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(_kRadiusMd),
                boxShadow: _kSoftShadow,
                border: Border.all(color: const Color(0xFFF1F5F9)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Receitas vs despesas (totais no período)',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey.shade800),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: narrow ? 176 : 200,
                    child: BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: maxY,
                        barTouchData: BarTouchData(enabled: true),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (v, _) {
                                final fs = narrow ? 10.0 : 11.0;
                                if (v.toInt() == 0) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text('Receitas', style: TextStyle(fontSize: fs, fontWeight: FontWeight.w600)),
                                  );
                                }
                                if (v.toInt() == 1) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text('Despesas', style: TextStyle(fontSize: fs, fontWeight: FontWeight.w600)),
                                  );
                                }
                                return const SizedBox();
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: leftR,
                              getTitlesWidget: (v, _) => Text(
                                NumberFormat.compactCurrency(locale: 'pt_BR', symbol: r'R$').format(v),
                                style: TextStyle(fontSize: narrow ? 8 : 9),
                              ),
                            ),
                          ),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        gridData: FlGridData(show: true, drawVerticalLine: false),
                        borderData: FlBorderData(show: false),
                        barGroups: [
                          BarChartGroupData(
                            x: 0,
                            barRods: [
                              BarChartRodData(
                                toY: totalReceitas,
                                color: const Color(0xFF15803D),
                                width: barW,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ],
                          ),
                          BarChartGroupData(
                            x: 1,
                            barRods: [
                              BarChartRodData(
                                toY: totalDespesas,
                                color: const Color(0xFFDC2626),
                                width: barW,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ],
                          ),
                        ],
                      ),
                      duration: _anim,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(_kRadiusMd),
            boxShadow: _kSoftShadow,
            border: Border.all(color: const Color(0xFFF1F5F9)),
          ),
          child: gastosPorCategoria.isEmpty
              ? Text(
                  'Sem despesas no período para o gráfico por categoria.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                )
              : LayoutBuilder(
                  builder: (context, c) {
                    final narrow = c.maxWidth < 520;
                    final sections = _pieSections();
                    if (sections.isEmpty) {
                      return Text(
                        'Sem despesas no período para o gráfico por categoria.',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      );
                    }
                    final pie = SizedBox(
                      height: 200,
                      width: narrow ? c.maxWidth : 200,
                      child: PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 36,
                          sections: sections,
                        ),
                        duration: _anim,
                      ),
                    );
                    final legend = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Despesas por categoria',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        ...gastosPorCategoria.take(8).map((e) {
                          final cat = (e['categoria'] ?? '').toString();
                          final val = ((e['valor'] ?? 0) as num).toDouble();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '$cat — ${CurrencyFormats.formatBRL(val)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          );
                        }),
                      ],
                    );
                    if (narrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          pie,
                          const SizedBox(height: 12),
                          legend,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        pie,
                        const SizedBox(width: 16),
                        Expanded(child: legend),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}
