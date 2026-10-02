import 'package:flutter/material.dart';

import '../services/app_theme_controller.dart';
import '../theme/app_colors.dart';
import 'modern_module_ui.dart';

/// Card em Configurações: modo claro ou escuro manual (não segue o sistema).
class AppThemeModeCard extends StatefulWidget {
  const AppThemeModeCard({super.key});

  @override
  State<AppThemeModeCard> createState() => _AppThemeModeCardState();
}

class _AppThemeModeCardState extends State<AppThemeModeCard> {
  late bool _dark;

  @override
  void initState() {
    super.initState();
    _dark = AppThemeController.instance.isDark;
    AppThemeController.instance.addListener(_sync);
  }

  @override
  void dispose() {
    AppThemeController.instance.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    setState(() => _dark = AppThemeController.instance.isDark);
  }

  Future<void> _pick(bool dark) async {
    if (_dark == dark) return;
    setState(() => _dark = dark);
    if (dark) {
      await AppThemeController.instance.setDark();
    } else {
      await AppThemeController.instance.setLight();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          dark
              ? 'Modo escuro ativado em todo o app.'
              : 'Modo claro ativado em todo o app.',
        ),
      ),
    );
  }

  Widget _modeChip({
    required bool selected,
    required IconData icon,
    required String label,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
            decoration: BoxDecoration(
              gradient: selected
                  ? LinearGradient(
                      colors: gradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: selected
                  ? null
                  : ModernModuleUI.cardBg(context).withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected
                    ? gradient.last.withValues(alpha: 0.55)
                    : ModernModuleUI.subtleBorder(context),
                width: selected ? 1.6 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: gradient.last.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: selected
                      ? Colors.white
                      : ModernModuleUI.onSurfaceMuted(context),
                  size: 26,
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: selected
                        ? Colors.white
                        : ModernModuleUI.onSurface(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ModernModuleUI.iconBadge(
                  icon: Icons.dark_mode_rounded,
                  gradient: const [Color(0xFF6366F1), Color(0xFF7C3AED)],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Aparência do app',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: ModernModuleUI.onSurface(context),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Escolha manualmente entre modo claro ou escuro. O app não muda '
              'sozinho com o sistema — vale para todos os módulos, prévias e gráficos.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: ModernModuleUI.onSurfaceMuted(context),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _modeChip(
                  selected: !_dark,
                  icon: Icons.wb_sunny_rounded,
                  label: 'Modo claro',
                  gradient: const [Color(0xFF38BDF8), Color(0xFF2563EB)],
                  onTap: () => _pick(false),
                ),
                const SizedBox(width: 10),
                _modeChip(
                  selected: _dark,
                  icon: Icons.nights_stay_rounded,
                  label: 'Modo escuro',
                  gradient: const [Color(0xFF7C3AED), Color(0xFF1E293B)],
                  onTap: () => _pick(true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
