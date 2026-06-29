import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Opções de limpeza de escalas — chips modernos (padrão Agenda WISDOMAPP).
class ScaleBulkClearSheet extends StatelessWidget {
  const ScaleBulkClearSheet({
    super.key,
    required this.ref,
    required this.onClearWeek,
    required this.onClearMonth,
    required this.onClearPeriod,
    required this.onClearRecentBatches,
  });

  final DateTime ref;
  final VoidCallback onClearWeek;
  final VoidCallback onClearMonth;
  final VoidCallback onClearPeriod;
  final VoidCallback onClearRecentBatches;

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('MMMM/yyyy', 'pt_BR').format(ref);
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFDC2626), Color(0xFFEA580C)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Remover escalas',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1A237E),
                            letterSpacing: -0.3,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Limpeza rápida por período',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Fechar',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Para um dia específico, toque na data no calendário. Esta ação não pode ser desfeita.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.35),
              ),
              const SizedBox(height: 16),
              _ClearOptionTile(
                title: 'Semana',
                subtitle:
                    'Plantões da semana do dia ${DateFormat('dd/MM').format(ref)}',
                icon: Icons.view_week_rounded,
                colors: const [Color(0xFF0EA5E9), Color(0xFF2563EB)],
                onTap: () {
                  Navigator.pop(context);
                  onClearWeek();
                },
              ),
              const SizedBox(height: 8),
              _ClearOptionTile(
                title: 'Mês',
                subtitle: 'Plantões de $monthLabel',
                icon: Icons.calendar_month_rounded,
                colors: const [Color(0xFFF59E0B), Color(0xFFEA580C)],
                onTap: () {
                  Navigator.pop(context);
                  onClearMonth();
                },
              ),
              const SizedBox(height: 8),
              _ClearOptionTile(
                title: 'Período',
                subtitle: 'Escolher data inicial e final',
                icon: Icons.date_range_rounded,
                colors: const [Color(0xFFA855F7), Color(0xFF7C3AED)],
                onTap: () {
                  Navigator.pop(context);
                  onClearPeriod();
                },
              ),
              const SizedBox(height: 8),
              _ClearOptionTile(
                title: 'Últimos lançamentos',
                subtitle: 'Lotes do botão mágico (últimos 3 dias)',
                icon: Icons.history_rounded,
                colors: const [Color(0xFF10B981), Color(0xFF059669)],
                onTap: () {
                  Navigator.pop(context);
                  onClearRecentBatches();
                },
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Cancelar', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClearOptionTile extends StatelessWidget {
  const _ClearOptionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: colors.first.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.last.withValues(alpha: 0.28)),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: colors),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: colors.last.withValues(alpha: 0.32),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: colors.last),
            ],
          ),
        ),
      ),
    );
  }
}
