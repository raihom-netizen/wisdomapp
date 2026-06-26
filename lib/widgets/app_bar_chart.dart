import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../constants/currency_formats.dart';

/// Gráfico de barras moderno para uso em Dashboard, Financeiro, Admin.
class AppBarChart extends StatelessWidget {
  final String title;
  final List<double> values;
  final List<String> labels;
  final Color barColor;
  final double height;

  const AppBarChart({
    super.key,
    required this.title,
    required this.values,
    required this.labels,
    this.barColor = const Color(0xFF2D5BFF),
    this.height = 180,
  });

  double _leftAxisReservedSize(double maxY) {
    final sample = CurrencyFormats.formatBRLTight(maxY);
    // ~5.5px por caractere em fonte 10 — garante R$ completo sem cortar.
    return (sample.length * 5.8 + 14).clamp(78.0, 118.0);
  }

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty || labels.isEmpty) {
      return _chartShell(
        title: title,
        child: SizedBox(height: height * 0.5, child: const Center(child: Text('Sem dados'))),
      );
    }
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final maxVal = maxY <= 0 ? 1.0 : maxY * 1.15;
    final leftReserved = _leftAxisReservedSize(maxY);

    return _chartShell(
      title: title,
      child: SizedBox(
        height: height,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxVal,
            barTouchData: BarTouchData(
              enabled: true,
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => const Color(0xFF0F172A).withValues(alpha: 0.92),
                tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final i = group.x.toInt();
                  if (i < 0 || i >= labels.length) return null;
                  return BarTooltipItem(
                    '${labels[i]}\n${CurrencyFormats.formatBRLTight(rod.toY)}',
                    const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11.5),
                  );
                },
              ),
            ),
            titlesData: FlTitlesData(
              show: true,
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                    final i = value.toInt();
                    if (i >= 0 && i < labels.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          labels[i],
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 9.5, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                  reservedSize: 36,
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: leftReserved,
                  interval: maxVal / 4,
                  getTitlesWidget: (value, meta) {
                    if (value < 0 || value > maxVal * 1.01) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        CurrencyFormats.formatBRLTight(value),
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        textAlign: TextAlign.right,
                      ),
                    );
                  },
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
                    color: barColor,
                    width: 16,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                    gradient: LinearGradient(
                      colors: [barColor, Color.lerp(barColor, Colors.white, 0.25)!],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
          duration: const Duration(milliseconds: 300),
        ),
      ),
    );
  }

  Widget _chartShell({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
