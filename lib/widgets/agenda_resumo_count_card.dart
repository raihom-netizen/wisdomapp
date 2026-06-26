import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Paleta super premium dos mini-cards Audiências / Compromissos (Painel + Agenda).
class AgendaResumoCountPalette {
  const AgendaResumoCountPalette({
    required this.gradient,
    required this.iconGradient,
    required this.border,
    required this.accentBar,
    required this.shadow,
    required this.label,
    required this.count,
  });

  final List<Color> gradient;
  final List<Color> iconGradient;
  final Color border;
  final Color accentBar;
  final Color shadow;
  final Color label;
  final Color count;

  static AgendaResumoCountPalette audiencia() => const AgendaResumoCountPalette(
        gradient: [
          Color(0xFFBBD4FF),
          Color(0xFFD6E6FF),
          Color(0xFFF0F6FF),
        ],
        iconGradient: [
          Color(0xFF0B1F4B),
          AppColors.deepBlue,
          AppColors.primary,
        ],
        border: Color(0xFF5B7FD6),
        accentBar: AppColors.primary,
        shadow: AppColors.deepBlue,
        label: AppColors.deepBlueDark,
        count: Color(0xFF1E40AF),
      );

  static AgendaResumoCountPalette compromisso() => const AgendaResumoCountPalette(
        gradient: [
          Color(0xFF7FE8D8),
          Color(0xFFB8F5EC),
          Color(0xFFE8FCF8),
        ],
        iconGradient: [
          Color(0xFF047857),
          Color(0xFF0D9488),
          AppColors.accent,
        ],
        border: Color(0xFF14B8A6),
        accentBar: AppColors.accent,
        shadow: Color(0xFF0D9488),
        label: Color(0xFF065F46),
        count: Color(0xFF0F766E),
      );
}

/// Card de contagem — super premium, cores vivas por tipo.
class AgendaResumoCountCard extends StatelessWidget {
  const AgendaResumoCountCard({
    super.key,
    required this.icon,
    required this.label,
    required this.count,
    required this.palette,
    this.countFontSize = 22,
  });

  final IconData icon;
  final String label;
  final int count;
  final AgendaResumoCountPalette palette;
  final double countFontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: 0.26),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
          BoxShadow(
            color: palette.border.withValues(alpha: 0.12),
            blurRadius: 0,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: palette.gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: palette.border, width: 1.5),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 5,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    palette.accentBar,
                    palette.accentBar.withValues(alpha: 0.55),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: palette.iconGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: palette.shadow.withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(icon, size: 21, color: Colors.white),
                ),
                const SizedBox(height: 10),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: palette.label,
                    letterSpacing: 0.15,
                  ),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: countFontSize,
                    fontWeight: FontWeight.w900,
                    color: palette.count,
                    height: 1,
                    shadows: [
                      Shadow(
                        color: palette.shadow.withValues(alpha: 0.15),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
