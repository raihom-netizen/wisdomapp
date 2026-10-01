import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/theme_context.dart';

/// Componentes WISDOMAPP reutilizáveis (AppBar gradiente, cards, seções).
abstract final class ModernModuleUI {
  ModernModuleUI._();

  static const Color scaffoldBg = Color(0xFFF1F5F9);

  static Color scaffoldBgOf(BuildContext context) =>
      Theme.of(context).scaffoldBackgroundColor;

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color cardBg(BuildContext context) => isDark(context)
      ? context.appDarkModuleSurface
      : Theme.of(context).colorScheme.surface;

  static Color moduleSurfaceColor(BuildContext context) => cardBg(context);

  /// Fundo do corpo dos módulos (gradiente escuro neon ou claro suave).
  static Widget bodyWithGradient({
    required BuildContext context,
    required Widget child,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: context.appBodyGradient,
        ),
      ),
      child: child,
    );
  }

  /// Card de preview/sheet (substitui `DecoratedBox(color: Colors.white)`).
  static BoxDecoration previewSheetDecoration(
    BuildContext context, {
    double radius = 22,
  }) {
    if (isDark(context)) {
      return context.appNeonCardDecoration(radius: radius);
    }
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.18),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  /// Campo/data em sheet ou diálogo.
  static BoxDecoration formFieldDecoration(BuildContext context) {
    return BoxDecoration(
      color: context.appInputFill,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: context.appBorderSubtle),
    );
  }

  static Color onSurface(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;

  static Color onSurfaceMuted(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;

  static Color subtleBorder(BuildContext context) =>
      onSurface(context).withValues(alpha: isDark(context) ? 0.14 : 0.07);

  static PreferredSizeWidget appBar({
    required BuildContext context,
    required String title,
    List<Widget>? actions,
    VoidCallback? onBack,
  }) {
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: AppColors.logoGradient,
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.2),
      ),
      leading: IconButton(
        icon: Icon(Icons.arrow_back_rounded),
        onPressed: onBack ?? () => Navigator.of(context).maybePop(),
      ),
      actions: actions,
    );
  }

  static BoxDecoration moduleCardDecoration(
    BuildContext context, {
    double radius = 18,
    Color? borderAccent,
  }) =>
      context.appModuleCardDecoration(
        radius: radius,
        borderAccent: borderAccent,
      );

  static TextStyle moduleTitleStyle(
    BuildContext context, {
    double fontSize = 16,
    FontWeight weight = FontWeight.w900,
  }) =>
      TextStyle(
        fontWeight: weight,
        fontSize: fontSize,
        color: onSurface(context),
        letterSpacing: -0.2,
      );

  static TextStyle moduleSubtitleStyle(
    BuildContext context, {
    double fontSize = 12.5,
  }) =>
      TextStyle(
        fontSize: fontSize,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: onSurfaceMuted(context),
      );

  static Widget sectionTitle(
    BuildContext context,
    String title, {
    Color? accent,
    double fontSize = 13,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10, top: 6),
      child: Row(
        children: [
          Container(
            width: 4,
            height: fontSize > 14 ? 20 : 16,
            decoration: BoxDecoration(
              color: accent ?? AppColors.primary,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w900,
                color: onSurface(context),
                letterSpacing: fontSize > 14 ? -0.2 : 0.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget infoBanner({
    required BuildContext context,
    required IconData icon,
    required List<Color> iconGradient,
    required String text,
  }) {
    final dark = isDark(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: dark
              ? [
                  AppColors.primary.withValues(alpha: 0.22),
                  iconGradient.last.withValues(alpha: 0.16),
                ]
              : [
                  AppColors.primary.withValues(alpha: 0.1),
                  iconGradient.last.withValues(alpha: 0.08),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: dark ? 0.28 : 0.14),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: iconGradient),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.38,
                fontWeight: FontWeight.w600,
                color: onSurfaceMuted(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget modernCard({
    required BuildContext context,
    required List<Widget> children,
    double indent = 68,
    Color? borderAccent,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: context.appNeonCardDecoration(
        radius: 18,
        borderAccent: borderAccent,
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: indent,
                color: subtleBorder(context),
              ),
            children[i],
          ],
        ],
      ),
    );
  }

  static Widget iconBadge({
    required IconData icon,
    required List<Color> gradient,
    double size = 44,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradient),
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [
          BoxShadow(
            color: gradient.last.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.5),
    );
  }

  static Widget gradientActionCard({
    required List<Color> gradient,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool compact = false,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: gradient.last.withValues(alpha: 0.38),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: compact ? 11 : 14,
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(compact ? 8 : 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.35)),
                ),
                child: Icon(icon, color: Colors.white, size: compact ? 20 : 22),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: compact ? 14 : 15.5,
                        height: 1.2,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontWeight: FontWeight.w600,
                        fontSize: compact ? 11 : 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: 0.85)),
            ],
          ),
        ),
      ),
    );
  }

  /// Botão central moderno para escolher arquivo (galeria / documentos).
  static Widget centeredPickButton({
    required List<Color> gradient,
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool secondary = false,
    double minWidth = 280,
  }) {
    if (secondary) {
      return ConstrainedBox(
        constraints: BoxConstraints(minWidth: minWidth, minHeight: 48),
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 20, color: gradient.first),
          label: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: gradient.first,
            ),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            side: BorderSide(color: gradient.first.withValues(alpha: 0.55)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: gradient.last.withValues(alpha: 0.38),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: minWidth, minHeight: 52),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Botão preenchido com gradiente moderno (Compartilhar / Escolher pasta).
  /// Texto sempre em uma linha — evita letras empilhadas em telas estreitas.
  static Widget gradientFilledButton({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
    required List<Color> gradient,
    double height = 52,
    double fontSize = 14,
    BorderRadiusGeometry borderRadius =
        const BorderRadius.all(Radius.circular(16)),
    bool compact = false,
  }) {
    final radius = borderRadius.resolve(TextDirection.ltr);
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: onPressed,
        borderRadius: radius,
        child: Ink(
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: radius,
            boxShadow: onPressed == null
                ? null
                : [
                    BoxShadow(
                      color: gradient.last.withValues(alpha: 0.32),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: compact ? 20 : 22, color: Colors.white),
                SizedBox(width: compact ? 6 : 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                      color: Colors.white,
                      height: 1.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Par Compartilhar + Escolher pasta — layout horizontal padronizado.
  /// Usado na barra de resultado e nos sheets dos Utilitários.
  static Widget shareSaveActionRow({
    required VoidCallback? onShare,
    required VoidCallback? onSave,
    String shareLabel = 'Compartilhar',
    String saveLabel = 'Salvar',
    double height = 50,
    bool shareFirst = true,
  }) {
    final share = Expanded(
      child: gradientFilledButton(
        onPressed: onShare,
        icon: Icons.share_rounded,
        label: shareLabel,
        gradient: const [Color(0xFF22C55E), Color(0xFF16A34A)],
        height: height,
        fontSize: 13.5,
        compact: true,
      ),
    );
    final save = Expanded(
      child: gradientFilledButton(
        onPressed: onSave,
        icon: Icons.folder_open_rounded,
        label: saveLabel,
        gradient: const [Color(0xFF2563EB), Color(0xFF3B82F6)],
        height: height,
        fontSize: 13.5,
        compact: true,
      ),
    );
    return Row(
      children: shareFirst
          ? [share, const SizedBox(width: 10), save]
          : [save, const SizedBox(width: 10), share],
    );
  }

  /// Estado vazio padronizado: ícone + instrução + botão central para adicionar.
  static Widget emptyPickState({
    required BuildContext context,
    required List<Color> gradient,
    required IconData icon,
    required String title,
    required String subtitle,
    required String buttonLabel,
    required VoidCallback? onPressed,
    IconData buttonIcon = Icons.folder_open_rounded,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconBadge(icon: icon, gradient: gradient, size: 64),
            const SizedBox(height: 20),
            Text(
              title,
              style: moduleTitleStyle(context),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: moduleSubtitleStyle(context),
            ),
            const SizedBox(height: 24),
            centeredPickButton(
              gradient: gradient,
              icon: buttonIcon,
              label: buttonLabel,
              onPressed: onPressed,
            ),
          ],
        ),
      ),
    );
  }

  /// Cabeçalho de preview/sheet WISDOMAPP com botão Voltar.
  static Widget previewHeader({
    required BuildContext context,
    required String title,
    String? subtitle,
    IconData icon = Icons.tune_rounded,
    List<Color>? gradient,
    VoidCallback? onBack,
  }) {
    final g = gradient ?? AppColors.logoGradient;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(4, 10, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: g,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            onPressed: onBack ?? () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.arrow_back_rounded, color: Colors.white),
            tooltip: 'Voltar',
            style: IconButton.styleFrom(
              minimumSize: const Size(48, 48),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    height: 1.2,
                  ),
                ),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      height: 1.25,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Rodapé padrão com botão Voltar (previews e diálogos).
  static const String previewRetornarLabel = 'Retornar';

  static Widget previewVoltarButton(BuildContext context,
      {String label = 'Voltar'}) {
    final fg = onSurfaceMuted(context);
    return TextButton.icon(
      onPressed: () => Navigator.of(context).maybePop(),
      icon: Icon(Icons.arrow_back_rounded, size: 18, color: fg),
      label: Text(
        label,
        style: TextStyle(fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }

  /// Atalho padrão «Retornar» nos previews do módulo Escalas e fluxos relacionados.
  static Widget previewRetornarButton(BuildContext context) =>
      previewVoltarButton(context, label: previewRetornarLabel);

  /// Leading do AppBar com texto «Retornar» (lista plantões, telas empurradas).
  static Widget appBarRetornarLeading(BuildContext context, {Color? color}) {
    final fg = color ??
        Theme.of(context).appBarTheme.foregroundColor ??
        Theme.of(context).colorScheme.onSurface;
    return TextButton.icon(
      onPressed: () => Navigator.of(context).maybePop(),
      icon: Icon(Icons.arrow_back_rounded, size: 20, color: fg),
      label: Text(
        previewRetornarLabel,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: fg,
          fontSize: 13,
        ),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        minimumSize: const Size(48, 48),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
