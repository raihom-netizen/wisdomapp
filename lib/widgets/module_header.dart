import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Cabeçalho padronizado para módulos: ícone em destaque, título e subtítulo.
/// Cada módulo pode usar [colorStart] e [colorEnd] para identidade visual.
class ModuleHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color? colorStart;
  final Color? colorEnd;

  const ModuleHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.colorStart,
    this.colorEnd,
  });

  /// Cores por módulo (identidade visual)
  static Color get financeStart => const Color(0xFF0B1F4B);
  static Color get financeEnd => const Color(0xFF122B6B);
  static Color get planejamentoStart => AppColors.deepBlueDark;
  static Color get planejamentoEnd => AppColors.deepBlue;
  static Color get scalesStart => const Color(0xFF1A237E);
  static Color get scalesEnd => const Color(0xFF3949AB);
  static Color get calculadoraStart => AppColors.accent;
  static Color get calculadoraEnd => const Color(0xFF0D9488);
  static Color get agendaStart => AppColors.secondary;
  static Color get agendaEnd => AppColors.primary;
  static Color get downloadsStart => const Color(0xFF1E3A5F);
  static Color get downloadsEnd => const Color(0xFF3949AB);

  @override
  Widget build(BuildContext context) {
    final start = colorStart ?? financeStart;
    final end = colorEnd ?? financeEnd;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [start, end],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: start.withOpacity(0.25),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
