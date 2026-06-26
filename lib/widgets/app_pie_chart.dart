import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../constants/currency_formats.dart';

/// Gráfico de pizza para distribuição (ex: planos, categorias).
class AppPieChart extends StatelessWidget {
  final String title;
  final List<({String label, double value, Color color})> segments;

  const AppPieChart({super.key, required this.title, required this.segments});

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) {
      return _shell(title: title, child: const Center(child: Text('Sem dados')));
    }
    final total = segments.fold<double>(0, (s, e) => s + e.value);
    if (total <= 0) {
      return _shell(title: title, child: const Center(child: Text('Sem dados')));
    }
    final sections = segments.asMap().entries.map((e) {
      final seg = e.value;
      return PieChartSectionData(
        value: seg.value,
        title: total > 0 ? '${(seg.value / total * 100).round()}%' : '',
        color: seg.color,
        radius: 52,
        titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white),
      );
    }).toList();

    return _shell(
      title: title,
      child: LayoutBuilder(
        builder: (context, c) {
          final stacked = c.maxWidth < 360;
          final chart = SizedBox(
            width: stacked ? double.infinity : 150,
            height: 150,
            child: PieChart(
              PieChartData(
                sections: sections,
                sectionsSpace: 2,
                centerSpaceRadius: 28,
              ),
              duration: const Duration(milliseconds: 300),
            ),
          );
          final legend = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: segments.map((s) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      margin: const EdgeInsets.only(top: 3),
                      decoration: BoxDecoration(color: s.color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade800),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            CurrencyFormats.formatBRLTight(s.value),
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: s.color),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          );
          if (stacked) {
            return Column(
              children: [
                chart,
                const SizedBox(height: 12),
                legend,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              chart,
              const SizedBox(width: 12),
              Expanded(child: legend),
            ],
          );
        },
      ),
    );
  }

  Widget _shell({required String title, required Widget child}) {
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
