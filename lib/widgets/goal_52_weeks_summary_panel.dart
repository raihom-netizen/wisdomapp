import 'package:flutter/material.dart';

import '../constants/currency_formats.dart';

/// Resumo colorido do Projeto 52 semanas (preview, painel Início, módulo Objetivo).
class Goal52WeeksSummaryPanel extends StatelessWidget {
  const Goal52WeeksSummaryPanel({
    super.key,
    required this.target,
    required this.deposited,
    required this.paidWeeks,
    this.currentWeek = 0,
    this.gradient,
    this.compact = false,
  });

  final double target;
  final double deposited;
  final int paidWeeks;
  final int currentWeek;
  final List<Color>? gradient;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final remainingWeeks = (52 - paidWeeks).clamp(0, 52);
    final percent = target > 0 ? ((deposited / target) * 100).clamp(0.0, 100.0) : 0.0;
    final remainingValue = (target - deposited).clamp(0.0, double.infinity);
    final g = gradient ??
        const [
          Color(0xFF6366F1),
          Color(0xFF0D9488),
          Color(0xFFEC4899),
        ];

    return Container(
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: g,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(compact ? 16 : 18),
        boxShadow: [
          BoxShadow(
            color: g.first.withValues(alpha: 0.28),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Projeto 52 semanas',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontWeight: FontWeight.w800,
                    fontSize: compact ? 11 : 12,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${percent.toStringAsFixed(1)}% concluído',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: percent / 100,
              minHeight: compact ? 8 : 10,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          SizedBox(height: compact ? 10 : 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _metricChip(
                label: 'Meta total',
                value: CurrencyFormats.formatBRL(target),
                compact: compact,
              ),
              _metricChip(
                label: 'Depositado',
                value: CurrencyFormats.formatBRL(deposited),
                compact: compact,
              ),
              _metricChip(
                label: 'Falta guardar',
                value: CurrencyFormats.formatBRL(remainingValue),
                compact: compact,
              ),
              _metricChip(
                label: 'Semanas ok',
                value: '$paidWeeks / 52',
                compact: compact,
              ),
              _metricChip(
                label: 'Semanas restantes',
                value: '$remainingWeeks',
                compact: compact,
              ),
              if (currentWeek > 0)
                _metricChip(
                  label: 'Semana atual',
                  value: '$currentWeek',
                  compact: compact,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricChip({
    required String label,
    required String value,
    required bool compact,
  }) {
    return Container(
      width: compact ? null : 148,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white30),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: compact ? 9.5 : 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 12 : 13.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

/// Botão moderno para exportar PDF do objetivo 52 semanas.
class Goal52WeeksPdfButton extends StatelessWidget {
  const Goal52WeeksPdfButton({
    super.key,
    required this.onPressed,
    this.loading = false,
    this.expand = true,
    this.label = 'Exportar PDF',
  });

  final VoidCallback? onPressed;
  final bool loading;
  final bool expand;
  final String label;

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: loading ? null : onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFDC2626), Color(0xFFEA580C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFEA580C).withValues(alpha: 0.28),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              children: [
                if (loading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                else
                  const Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}
