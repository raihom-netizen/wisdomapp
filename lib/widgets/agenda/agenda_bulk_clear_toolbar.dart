import 'package:flutter/material.dart';

/// Barra estreita com atalhos de limpeza rápida (semana / mês / período).
class AgendaBulkClearToolbar extends StatelessWidget {
  const AgendaBulkClearToolbar({
    super.key,
    required this.onClearWeek,
    required this.onClearMonth,
    required this.onClearPeriod,
    this.enabled = true,
  });

  final VoidCallback onClearWeek;
  final VoidCallback onClearMonth;
  final VoidCallback onClearPeriod;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF0F172A).withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Icon(Icons.bolt_rounded, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 6),
          Text(
            'Limpeza rápida',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade700,
            ),
          ),
          const Spacer(),
          _ChipAction(
            label: 'Semana',
            icon: Icons.view_week_rounded,
            colors: const [Color(0xFF0EA5E9), Color(0xFF2563EB)],
            onTap: enabled ? onClearWeek : null,
          ),
          const SizedBox(width: 6),
          _ChipAction(
            label: 'Mês',
            icon: Icons.calendar_month_rounded,
            colors: const [Color(0xFFF59E0B), Color(0xFFEA580C)],
            onTap: enabled ? onClearMonth : null,
          ),
          const SizedBox(width: 6),
          _ChipAction(
            label: 'Período',
            icon: Icons.date_range_rounded,
            colors: const [Color(0xFFA855F7), Color(0xFF7C3AED)],
            onTap: enabled ? onClearPeriod : null,
          ),
        ],
      ),
    );
  }
}

class _ChipAction extends StatelessWidget {
  const _ChipAction({
    required this.label,
    required this.icon,
    required this.colors,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            gradient: disabled
                ? null
                : LinearGradient(colors: colors),
            color: disabled ? Colors.grey.shade300 : null,
            borderRadius: BorderRadius.circular(12),
            boxShadow: disabled
                ? null
                : [
                    BoxShadow(
                      color: colors.last.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: Colors.white),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
