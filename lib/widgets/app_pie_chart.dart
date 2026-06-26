import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../constants/currency_formats.dart';
import '../theme/app_colors.dart';

/// Gráfico de pizza genérico (metas, admin, etc.) — visual alinhado ao financeiro.
class AppPieChart extends StatelessWidget {
  final String title;
  final List<({String label, double value, Color color})> segments;
  final String? subtitle;

  const AppPieChart({
    super.key,
    required this.title,
    required this.segments,
    this.subtitle,
  });

  static const _anim = Duration(milliseconds: 550);
  static const _minPctLabel = 0.06;

  @override
  Widget build(BuildContext context) {
    final visible = segments.where((s) => s.value > 0).toList();
    final total = visible.fold<double>(0, (s, e) => s + e.value);

    if (visible.isEmpty || total <= 0) {
      return _shell(
        title: title,
        subtitle: subtitle,
        child: _emptyState(),
      );
    }

    final sections = visible.map((seg) {
      final pct = seg.value / total;
      final showTitle = pct >= _minPctLabel;
      return PieChartSectionData(
        value: seg.value,
        title: showTitle ? '${(pct * 100).round()}%' : '',
        showTitle: showTitle,
        color: seg.color,
        radius: 58,
        titleStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          shadows: [Shadow(color: Colors.black26, blurRadius: 2)],
        ),
      );
    }).toList();

    return _shell(
      title: title,
      subtitle: subtitle,
      child: LayoutBuilder(
        builder: (context, c) {
          final stacked = c.maxWidth < 360;
          final chart = SizedBox(
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
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      '${visible.length} itens',
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
          final legend = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: visible.map((s) {
              final pct = total > 0 ? (s.value / total * 100) : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        color: s.color,
                        borderRadius: BorderRadius.circular(4),
                      ),
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
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${CurrencyFormats.formatBRLTight(s.value)} · ${CurrencyFormats.formatPercentBr(pct)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: s.color,
                            ),
                          ),
                          const SizedBox(height: 5),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: pct / 100,
                              minHeight: 5,
                              backgroundColor: s.color.withValues(alpha: 0.12),
                              color: s.color,
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
    );
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
      ),
      child: Center(
        child: Text(
          'Sem dados para exibir',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  Widget _shell({
    required String title,
    required Widget child,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 14.5,
              color: Color(0xFF0F172A),
            ),
          ),
          if (subtitle != null && subtitle.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
