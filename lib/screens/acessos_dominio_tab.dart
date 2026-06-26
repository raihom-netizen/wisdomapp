import 'package:flutter/material.dart' hide showDatePicker;
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../services/functions_service.dart';
import '../theme/app_colors.dart';
import '../widgets/module_header_premium.dart';
import '../widgets/admin/admin_page_shell.dart';
import '../utils/date_picker_a11y.dart';

/// Aba Admin: Acessos ao domínio wisdomapp-b9e98.web.app — gráficos diário (por hora), semanal, mensal, anual.
class AcessosDominioTab extends StatefulWidget {
  const AcessosDominioTab({super.key});

  @override
  State<AcessosDominioTab> createState() => _AcessosDominioTabState();
}

class _AcessosDominioTabState extends State<AcessosDominioTab> {
  String _period = 'daily';
  DateTime _referenceDate = DateTime.now();
  late Future<Map<String, dynamic>> _statsFuture;

  static const Map<String, String> _periodLabels = {
    'daily': 'Diário (por hora)',
    'weekly': 'Semanal',
    'monthly': 'Mensal',
    'yearly': 'Anual',
  };

  @override
  void initState() {
    super.initState();
    _statsFuture = _loadStats();
  }

  Future<Map<String, dynamic>> _loadStats() {
    final dateISO = DateFormat('yyyy-MM-dd').format(_referenceDate);
    return FunctionsService().getDomainAccessStats(period: _period, dateISO: dateISO);
  }

  void _refresh() {
    setState(() {
      _statsFuture = _loadStats();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: AdminPageShell.listPadding(context, top: 8),
      children: [
        const ModuleHeaderPremium(
          title: 'Acessos ao domínio',
          icon: Icons.analytics_rounded,
          subtitle: 'Visitas ao site wisdomapp-b9e98.web.app. Diário por hora, semanal, mensal ou anual.',
        ),
        const SizedBox(height: 20),
        _buildPeriodSelector(),
        const SizedBox(height: 16),
        _buildDateSelector(),
        const SizedBox(height: 24),
        FutureBuilder<Map<String, dynamic>>(
          future: _statsFuture,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()));
            }
            if (snap.hasError) {
              return Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          snap.error.toString(),
                          style: TextStyle(color: Colors.red.shade700, fontSize: 14),
                        ),
                      ),
                      TextButton(onPressed: _refresh, child: const Text('Tentar novamente')),
                    ],
                  ),
                ),
              );
            }
            final data = snap.data ?? {};
            return _buildCharts(data);
          },
        ),
      ],
    );
  }

  Widget _buildPeriodSelector() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Período', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey.shade700)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _periodLabels.entries.map((e) {
                final sel = _period == e.key;
                return ChoiceChip(
                  label: Text(e.value),
                  selected: sel,
                  onSelected: (v) {
                    setState(() {
                      _period = e.key;
                      _statsFuture = _loadStats();
                    });
                  },
                  selectedColor: AppColors.primary.withOpacity(0.25),
                  backgroundColor: Colors.grey.shade100,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateSelector() {
    final label = _period == 'daily'
        ? 'Data'
        : _period == 'weekly'
            ? 'Semana contendo'
            : _period == 'monthly'
                ? 'Mês'
                : 'Ano';
    final display = _period == 'yearly'
        ? '${_referenceDate.year}'
        : DateFormat('dd/MM/yyyy', 'pt_BR').format(_referenceDate);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.grey.shade200)),
      child: ListTile(
        leading: Icon(Icons.calendar_month_rounded, color: AppColors.primary),
        title: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        subtitle: Text(display, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        trailing: IconButton(
          icon: const Icon(Icons.edit_calendar_rounded),
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _referenceDate,
              firstDate: DateTime(2020),
              lastDate: DateTime.now(),
            );
            if (picked != null && mounted) {
              setState(() {
                _referenceDate = picked;
                _statsFuture = _loadStats();
              });
            }
          },
        ),
      ),
    );
  }

  Widget _buildCharts(Map<String, dynamic> data) {
    if (_period == 'daily') {
      return _buildDailyChart(data);
    }
    return _buildAggregateChart(data);
  }

  static List<double> _parseHoursList(Map<String, dynamic> data) {
    final raw = data['hours'];
    if (raw == null) return List.filled(24, 0.0);
    if (raw is! List) return List.filled(24, 0.0);
    final list = <double>[];
    for (var i = 0; i < 24; i++) {
      if (i < raw.length) {
        final item = raw[i];
        if (item is Map) {
          final count = item['count'];
          list.add((count is num) ? count.toDouble() : double.tryParse(count?.toString() ?? '0') ?? 0);
        } else {
          list.add(0);
        }
      } else {
        list.add(0);
      }
    }
    while (list.length < 24) list.add(0);
    return list;
  }

  static List<Map<String, dynamic>> _parseDaysList(Map<String, dynamic> data) {
    final raw = data['days'];
    if (raw == null || raw is! List) return [];
    return raw.map((e) {
      if (e is Map) return Map<String, dynamic>.from(e as Map);
      return <String, dynamic>{'date': '', 'count': 0};
    }).toList();
  }

  Widget _buildDailyChart(Map<String, dynamic> data) {
    final values = _parseHoursList(data);
    final total = (data['total'] is num) ? (data['total'] as num).toInt() : int.tryParse(data['total']?.toString() ?? '0') ?? 0;
    final labels = List.generate(24, (i) => '$i h');
    final maxVal = values.isEmpty ? 1.0 : (values.reduce((a, b) => a > b ? a : b) * 1.2).clamp(1.0, double.infinity);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTotalCard(total, 'Total de acessos no dia'),
        const SizedBox(height: 20),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.grey.shade200)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Acessos por hora (horário Brasília)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
                const SizedBox(height: 16),
                if (values.isEmpty || values.every((v) => v == 0))
                  SizedBox(height: 180, child: Center(child: Text('Sem dados neste dia', style: TextStyle(color: Colors.grey.shade600))))
                else
                  SizedBox(
                    height: 220,
                    child: BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        minY: 0,
                        maxY: maxVal,
                        barTouchData: BarTouchData(enabled: true),
                        titlesData: FlTitlesData(
                          show: true,
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 24,
                              interval: 2,
                              getTitlesWidget: (v, meta) {
                                final i = v.toInt();
                                if (i >= 0 && i < 24) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(labels[i], style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 32,
                              getTitlesWidget: (v, meta) => Text(
                                v.toInt().toString(),
                                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                              ),
                            ),
                          ),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                        ),
                        borderData: FlBorderData(show: false),
                        barGroups: values.asMap().entries.map((e) {
                          return BarChartGroupData(
                            x: e.key,
                            barRods: [
                              BarChartRodData(
                                toY: e.value,
                                color: AppColors.primary,
                                width: 12,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                backDrawRodData: BackgroundBarChartRodData(show: true, toY: maxVal, color: Colors.grey.shade100),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                      duration: const Duration(milliseconds: 300),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAggregateChart(Map<String, dynamic> data) {
    final days = _parseDaysList(data);
    final total = (data['total'] is num) ? (data['total'] as num).toInt() : int.tryParse(data['total']?.toString() ?? '0') ?? 0;
    final startISO = (data['startISO'] ?? '').toString();
    final endISO = (data['endISO'] ?? '').toString();
    final periodLabel = _periodLabels[_period] ?? _period;
    final counts = days.map((d) {
      final c = d['count'];
      return (c is num) ? c.toDouble() : (double.tryParse(c?.toString() ?? '0') ?? 0);
    }).toList();
    final maxVal = counts.isEmpty ? 1.0 : (counts.reduce((a, b) => a > b ? a : b) * 1.2).clamp(1.0, double.infinity);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTotalCard(total, 'Total no período'),
        if (startISO.isNotEmpty && endISO.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('$startISO a $endISO', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ),
        const SizedBox(height: 20),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.grey.shade200)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$periodLabel — acessos por dia', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
                const SizedBox(height: 16),
                if (days.isEmpty || counts.every((c) => c == 0))
                  SizedBox(height: 200, child: Center(child: Text('Sem dados no período', style: TextStyle(color: Colors.grey.shade600))))
                else
                  SizedBox(
                    height: 240,
                    child: BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        minY: 0,
                        maxY: maxVal,
                        barTouchData: BarTouchData(enabled: true),
                        titlesData: FlTitlesData(
                          show: true,
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 28,
                              interval: (days.length / 8).clamp(1.0, double.infinity),
                              getTitlesWidget: (v, meta) {
                                final i = v.toInt();
                                if (i >= 0 && i < days.length) {
                                  final date = (days[i]['date'] ?? '').toString();
                                  final dd = date.length >= 10 ? '${date.substring(8, 10)}/${date.substring(5, 7)}' : date;
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(dd, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 36,
                              getTitlesWidget: (v, meta) => Text(
                                v.toInt().toString(),
                                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                              ),
                            ),
                          ),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                        ),
                        borderData: FlBorderData(show: false),
                        barGroups: counts.asMap().entries.map((e) {
                          return BarChartGroupData(
                            x: e.key,
                            barRods: [
                              BarChartRodData(
                                toY: e.value,
                                color: AppColors.primary,
                                width: 10,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                backDrawRodData: BackgroundBarChartRodData(
                                  show: true,
                                  toY: maxVal,
                                  color: Colors.grey.shade100,
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                      duration: const Duration(milliseconds: 300),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTotalCard(int total, String label) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: AppColors.primary.withOpacity(0.3))),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [AppColors.deepBlue, AppColors.primary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.trending_up_rounded, color: Colors.white.withOpacity(0.9), size: 36),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.9))),
                  const SizedBox(height: 4),
                  Text('$total', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              onPressed: _refresh,
            ),
          ],
        ),
      ),
    );
  }
}
