import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../constants/currency_formats.dart';
import '../theme/app_colors.dart';

/// Gráfico de linhas — recebimentos Mercado Pago **bruto** vs **líquido** (após taxas estimadas).
class AdminMpRevenueLineChart extends StatelessWidget {
  final String title;
  final List<double> brutoBuckets;
  final List<double> liquidoBuckets;
  final List<String> labels;
  final double height;

  const AdminMpRevenueLineChart({
    super.key,
    required this.title,
    required this.brutoBuckets,
    required this.liquidoBuckets,
    required this.labels,
    this.height = 220,
  });

  @override
  Widget build(BuildContext context) {
    final n = brutoBuckets.length;
    if (n == 0 ||
        labels.length != n ||
        liquidoBuckets.length != n ||
        (brutoBuckets.every((e) => e <= 0) && liquidoBuckets.every((e) => e <= 0))) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 16),
              SizedBox(
                height: height * 0.45,
                child: Center(
                  child: Text(
                    'Sem recebimentos aprovados no período.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    double maxY = 0;
    for (var i = 0; i < n; i++) {
      maxY = maxY < brutoBuckets[i] ? brutoBuckets[i] : maxY;
      maxY = maxY < liquidoBuckets[i] ? liquidoBuckets[i] : maxY;
    }
    final top = maxY <= 0 ? 1.0 : maxY * 1.12;

    LineChartBarData line(Color color, List<double> ys, {bool fill = false}) {
      final spots = <FlSpot>[
        for (var i = 0; i < n; i++) FlSpot(i.toDouble(), ys[i]),
      ];
      return LineChartBarData(
        spots: spots,
        isCurved: true,
        color: color,
        barWidth: 3,
        isStrokeCapRound: true,
        dotData: FlDotData(
          show: true,
          getDotPainter: (s, p, b, i) => FlDotCirclePainter(
            radius: 3.5,
            color: color,
            strokeWidth: 1.5,
            strokeColor: Colors.white,
          ),
        ),
        belowBarData: BarAreaData(
          show: fill,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.22),
              color.withValues(alpha: 0.02),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.multiline_chart_rounded, color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      Text(
                        'Bruto (aprovado) × líquido estimado (taxas PIX/cartão)',
                        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600, height: 1.25),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _LegendDot(color: const Color(0xFF6366F1), label: 'Bruto MP'),
                _LegendDot(color: const Color(0xFF10B981), label: 'Líquido MP'),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: height,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: (n - 1).toDouble(),
                  minY: 0,
                  maxY: top,
                  clipData: const FlClipData.all(),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: top > 0 ? top / 4 : 1,
                    getDrawingHorizontalLine: (v) => FlLine(
                      color: Colors.grey.shade200,
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 44,
                        interval: top > 0 ? top / 4 : 1,
                        getTitlesWidget: (v, m) {
                          if (v < 0) return const SizedBox.shrink();
                          return Text(
                            _shortMoney(v),
                            style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 26,
                        interval: 1,
                        getTitlesWidget: (v, m) {
                          final i = v.round();
                          if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                          if (n > 12 && i % 2 == 1) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              labels[i],
                              style: TextStyle(fontSize: 9, color: Colors.grey.shade700),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    enabled: true,
                    touchTooltipData: LineTouchTooltipData(
                      maxContentWidth: 200,
                      getTooltipColor: (_) => const Color(0xFF1E293B),
                      getTooltipItems: (touched) {
                        if (touched.isEmpty) return [];
                        final i = touched.first.x.round().clamp(0, n - 1);
                        final body =
                            '${labels[i]}\nBruto: ${CurrencyFormats.formatBRL(brutoBuckets[i])}\nLíq.: ${CurrencyFormats.formatBRL(liquidoBuckets[i])}';
                        const style = TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                          height: 1.35,
                        );
                        return List<LineTooltipItem?>.generate(
                          touched.length,
                          (j) => j == 0 ? LineTooltipItem(body, style) : null,
                        );
                      },
                    ),
                  ),
                  lineBarsData: [
                    line(const Color(0xFF6366F1), brutoBuckets),
                    line(const Color(0xFF10B981), liquidoBuckets, fill: true),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _shortMoney(double v) {
    if (v >= 1e6) return 'R\$${(v / 1e6).toStringAsFixed(1)}M';
    if (v >= 1e3) return 'R\$${(v / 1e3).toStringAsFixed(1)}k';
    return 'R\$${v.round()}';
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 4),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
      ],
    );
  }
}
