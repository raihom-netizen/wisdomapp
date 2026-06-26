import 'package:flutter/material.dart';

import '../constants/date_time_formats.dart';
import '../models/scale_rates_period.dart';
import '../theme/app_colors.dart';

/// Linha do tempo de períodos de vigência (Goiás global ou personalizado do usuário).
class ScaleRatesTimelineStrip extends StatelessWidget {
  const ScaleRatesTimelineStrip({
    super.key,
    required this.periods,
    this.title = 'Linha do tempo',
    this.accentBlue = AppColors.deepBlue,
    this.accentTeal = AppColors.accent,
    this.onPeriodTap,
    this.readOnly = true,
  });

  final List<ScaleRatesPeriod> periods;
  final String title;
  final Color accentBlue;
  final Color accentTeal;
  final void Function(ScaleRatesPeriod period)? onPeriodTap;
  final bool readOnly;

  String _statusLabel(ScaleRatesPeriod p, List<ScaleRatesPeriod> all) {
    final now = DateTime.now();
    if (p.effectiveFrom.isAfter(now)) return 'Agendado';
    if (p.isActiveAt(now, all)) return 'Vigente';
    return 'Histórico';
  }

  ({Color bg, Color fg, Color accent, IconData icon}) _statusTheme(String status) {
    switch (status) {
      case 'Vigente':
        return (
          bg: const Color(0xFFDCFCE7),
          fg: const Color(0xFF166534),
          accent: const Color(0xFF22C55E),
          icon: Icons.check_circle_rounded,
        );
      case 'Agendado':
        return (
          bg: const Color(0xFFFFEDD5),
          fg: const Color(0xFF9A3412),
          accent: AppColors.logoOrange,
          icon: Icons.schedule_rounded,
        );
      default:
        return (
          bg: const Color(0xFFE2E8F0),
          fg: const Color(0xFF475569),
          accent: const Color(0xFF64748B),
          icon: Icons.history_rounded,
        );
    }
  }

  String _formatFrom(DateTime from) => DateTimeFormats.formatDateTimeSeconds(from);

  String _formatUntil(DateTime? until) {
    if (until == null) return 'Sem fim definido';
    return DateTimeFormats.formatDateTimeSeconds(until);
  }

  @override
  Widget build(BuildContext context) {
    final sorted = ScaleRatesPeriod.sortAsc(periods);
    if (sorted.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          readOnly
              ? 'Nenhum período cadastrado ainda.'
              : 'Toque em "Criar novo padrão" para iniciar sua linha do tempo.',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accentBlue.withValues(alpha: 0.06),
            accentTeal.withValues(alpha: 0.08),
            AppColors.logoOrange.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accentTeal.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 12),
          ...sorted.asMap().entries.map((entry) {
            final i = entry.key;
            final p = entry.value;
            final theme = _statusTheme(_statusLabel(p, sorted));
            final until = p.effectiveUntil(sorted);
            final row = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: theme.accent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(theme.icon, color: Colors.white, size: 16),
                    ),
                    if (i < sorted.length - 1)
                      Container(
                        width: 3,
                        height: 36,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              theme.accent,
                              sorted.length > i + 1
                                  ? _statusTheme(
                                      _statusLabel(sorted[i + 1], sorted),
                                    ).accent
                                  : theme.accent,
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: i < sorted.length - 1 ? 12 : 0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.label,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: theme.fg,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_formatFrom(p.effectiveFrom)} → ${_formatUntil(until)}',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: theme.fg.withValues(alpha: 0.85),
                          ),
                        ),
                        if (p.notes != null && p.notes!.isNotEmpty)
                          Text(
                            p.notes!,
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.fg.withValues(alpha: 0.7),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (!readOnly && onPeriodTap != null)
                  IconButton(
                    icon: const Icon(Icons.edit_rounded, size: 20),
                    tooltip: 'Editar período',
                    onPressed: () => onPeriodTap!(p),
                  ),
              ],
            );
            return row;
          }),
        ],
      ),
    );
  }
}
