import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Cabeçalho padrão de módulo (Clean Premium): gradiente azul→teal, nome do módulo e ícone.
/// Use em todos os módulos para manter o mesmo padrão visual do "Financeiro Premium".
class ModuleHeaderPremium extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? subtitle;
  /// Ícone à esquerda customizado (ex.: para Android quando IconData não renderiza).
  final Widget? leadingWidget;
  /// Opcional: ajuste mobile (ex.: telas < 720px) sem alterar o padrão desktop.
  final double? titleFontSize;
  final double? subtitleFontSize;
  /// Menos altura e padding — ex.: painel Início, colado à barra de saudação/licença.
  final bool dense;

  const ModuleHeaderPremium({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    this.leadingWidget,
    this.titleFontSize,
    this.subtitleFontSize,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final hPad = dense ? 16.0 : 20.0;
    final vPad = dense ? 10.0 : 18.0;
    final leadSize = dense ? 40.0 : 48.0;
    final iconSz = dense ? 24.0 : 28.0;
    final innerPad = dense ? 8.0 : 10.0;
    final leadRadius = dense ? 12.0 : 14.0;
    final cardRadius = dense ? 16.0 : 20.0;
    final gap = dense ? 12.0 : 14.0;
    final defaultTitleSize = dense ? 16.0 : 18.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(cardRadius),
        gradient: const LinearGradient(
          colors: [AppColors.deepBlueDark, AppColors.deepBlue, AppColors.accent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepBlueDark.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: leadSize,
            height: leadSize,
            child: Container(
              padding: EdgeInsets.all(innerPad),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(leadRadius),
              ),
              child: Center(
                child: leadingWidget ?? Icon(icon, color: Colors.white, size: iconSz),
              ),
            ),
          ),
          SizedBox(width: gap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: titleFontSize ?? defaultTitleSize,
                    letterSpacing: 0.2,
                  ),
                  softWrap: true,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  SizedBox(height: dense ? 4 : 6),
                  Text(
                    subtitle!,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: subtitleFontSize ?? (dense ? 12.0 : 13.0),
                        height: 1.3),
                    softWrap: true,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          Icon(icon, color: Colors.white.withValues(alpha: 0.9), size: iconSz),
        ],
      ),
    );
  }
}
