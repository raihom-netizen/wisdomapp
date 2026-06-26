import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_colors.dart';

/// Mês/ano em destaque nos cards «Controle de horas» / «Resumo de horas no mês».
class MonthYearResumoHeader extends StatelessWidget {
  const MonthYearResumoHeader({
    super.key,
    required this.monthStart,
    this.compact = false,
    this.accentWhenCurrent = AppColors.primary,
  });

  /// Primeiro dia do mês exibido (só ano/mês importam).
  final DateTime monthStart;
  final bool compact;

  /// Cor de ênfase quando for o mês civil corrente.
  final Color accentWhenCurrent;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrentMonth =
        monthStart.year == now.year && monthStart.month == now.month;

    final nomeMes = DateFormat('MMMM', 'pt_BR').format(monthStart).trim();
    final mesCap = nomeMes.isEmpty
        ? nomeMes
        : '${nomeMes[0].toUpperCase()}${nomeMes.substring(1)}';
    final ano = monthStart.year.toString();

    final mesSize = isCurrentMonth
        ? (compact ? 21.0 : 24.0)
        : (compact ? 17.0 : 19.0);
    final anoSize = isCurrentMonth
        ? (compact ? 18.0 : 20.0)
        : (compact ? 15.0 : 16.0);
    final mesColor =
        isCurrentMonth ? accentWhenCurrent : const Color(0xFF37474F);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isCurrentMonth)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: accentWhenCurrent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: accentWhenCurrent.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                'MÊS ATUAL',
                style: TextStyle(
                  fontSize: compact ? 9.5 : 10.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.15,
                  color: accentWhenCurrent,
                ),
              ),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                mesCap,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: mesSize,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                  letterSpacing: -0.25,
                  color: mesColor,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              ano,
              style: TextStyle(
                fontSize: anoSize,
                fontWeight: FontWeight.w800,
                height: 1.05,
                color: mesColor.withValues(alpha: 0.92),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
