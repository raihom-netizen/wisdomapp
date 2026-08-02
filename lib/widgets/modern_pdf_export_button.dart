import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Ícone e gradiente padrão WISDOMAPP para exportação PDF.
abstract final class ModernPdfUi {
  ModernPdfUi._();

  static const IconData icon = Icons.picture_as_pdf_rounded;

  static const List<Color> actionGradient = [
    AppColors.logoOrange,
    Color(0xFFEA580C),
  ];

  static Widget iconBadge({
    double size = 40,
    Color? background,
    List<Color>? gradient,
    Color iconColor = Colors.white,
  }) {
    final g = gradient ?? actionGradient;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: background == null ? LinearGradient(colors: g) : null,
        color: background,
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: g.last.withValues(alpha: 0.28),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(icon, color: iconColor, size: size * 0.52),
    );
  }
}

/// Botão laranja WISDOMAPP — padrão «Exportar PDF» (paridade Controle Total).
class ModernPdfExportButton extends StatelessWidget {
  const ModernPdfExportButton({
    super.key,
    required this.onPressed,
    this.label = 'Exportar PDF',
    this.subtitle,
    this.loading = false,
    this.enabled = true,
    this.expand = true,
    this.compact = false,
    this.minimumHeight = 48,
  });

  final VoidCallback? onPressed;
  final String label;
  final String? subtitle;
  final bool loading;
  final bool enabled;
  final bool expand;
  final bool compact;
  final double minimumHeight;

  @override
  Widget build(BuildContext context) {
    final active = enabled && !loading && onPressed != null;
    final radius = compact ? 14.0 : 16.0;
    final idleBg = Colors.grey.shade200;
    final idleFg = Colors.grey.shade700;

    Widget child = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: active ? onPressed : null,
        borderRadius: BorderRadius.circular(radius),
        child: Ink(
          decoration: BoxDecoration(
            gradient: active
                ? const LinearGradient(
                    colors: ModernPdfUi.actionGradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: active ? null : idleBg,
            borderRadius: BorderRadius.circular(radius),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: ModernPdfUi.actionGradient.last
                          .withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minimumHeight),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 14 : 16,
                vertical: compact ? 10 : 12,
              ),
              child: Row(
                mainAxisAlignment:
                    expand ? MainAxisAlignment.center : MainAxisAlignment.start,
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                children: [
                  if (loading)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  else if (compact)
                    Icon(
                      ModernPdfUi.icon,
                      color: active ? Colors.white : idleFg,
                      size: 20,
                    )
                  else
                    ModernPdfUi.iconBadge(size: 32),
                  SizedBox(width: compact ? 8 : 12),
                  if (subtitle != null &&
                      subtitle!.trim().isNotEmpty &&
                      !compact)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: active ? Colors.white : idleFg,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: active
                                  ? Colors.white.withValues(alpha: 0.92)
                                  : Colors.grey.shade600,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: expand ? TextAlign.center : TextAlign.start,
                        style: TextStyle(
                          color: active ? Colors.white : idleFg,
                          fontWeight: FontWeight.w900,
                          fontSize: compact ? 13 : 14,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (expand) {
      child = SizedBox(width: double.infinity, child: child);
    }
    return child;
  }
}
