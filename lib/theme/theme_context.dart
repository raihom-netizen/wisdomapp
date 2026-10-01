import 'package:flutter/material.dart';

import 'app_colors.dart';

// Cores do destaque «neón» e superfícies escuras (porte do Controle Total —
// o GeminiTheme do WISDOMAPP não as define; ficam locais a esta extensão).
const Color _kNeon = Color(0xFF39FF14);
const Color _kNeonOn = Color(0xFF07130A);
const Color _kNeonSoft = Color(0xFF6EF57A);
const Color _kDarkSurface = Color(0xFF1E293B);
const Color _kDarkBackground = Color(0xFF0F172A);

/// Tokens de cor derivados do [Theme] — use em vez de branco/cinza fixos no modo escuro.
extension AppThemeContext on BuildContext {
  ThemeData get appTheme => Theme.of(this);

  bool get isDarkMode => appTheme.brightness == Brightness.dark;

  // `scaffoldBackgroundColor` nunca é nulo no Material 3 — o `??` que estava
  // aqui era código morto que o analisador apontava.
  Color get appScaffold => appTheme.scaffoldBackgroundColor;

  Color get appSurface => appTheme.colorScheme.surface;

  Color get appSurfaceHigh => appTheme.colorScheme.surfaceContainerHighest;

  Color get appOnSurface => appTheme.colorScheme.onSurface;

  Color get appOnSurfaceMuted =>
      appTheme.colorScheme.onSurfaceVariant;

  Color get appTextPrimary =>
      isDarkMode ? const Color(0xFFFFFFFF) : AppColors.textPrimary;

  Color get appTextSecondary =>
      isDarkMode ? const Color(0xFFB3B3B3) : AppColors.textSecondary;

  Color get appTextMuted =>
      isDarkMode ? const Color(0xFF94A3B8) : AppColors.textMuted;

  /// Títulos azul-escuro no claro; texto primário legível no escuro.
  Color get appDeepTitle =>
      isDarkMode ? appOnSurface : const Color(0xFF1A237E);

  /// Cabeçalho SEG–SEX no calendário.
  Color get appCalendarWeekday =>
      isDarkMode ? appTextSecondary : const Color(0xFF455A64);

  /// Feriado / fim de semana no calendário.
  Color get appCalendarHoliday =>
      isDarkMode ? const Color(0xFFEF5350) : const Color(0xFFE53935);

  /// Fundo de campos preenchidos (InputDecoration, chips idle).
  Color get appInputFill =>
      isDarkMode ? appSurfaceHigh : const Color(0xFFF1F5F9);

  Color get appBorderSubtle =>
      appOnSurface.withValues(alpha: isDarkMode ? 0.14 : 0.08);

  Color get appChipIdleBg =>
      isDarkMode ? appSurfaceHigh : const Color(0xFFF8FAFC);

  Color get appChipIdleBorder =>
      isDarkMode ? const Color(0xFF2E3A47) : const Color(0xFFE2E8F0);

  Color get appChipIdleLabel =>
      isDarkMode ? const Color(0xFFCBD5E1) : AppColors.textPrimary;

  /// Verde fluorescente dos destaques do modo escuro (no claro, o verde sólido
  /// da marca — neón sobre branco não se lê).
  ///
  /// Use para o que está ATIVO: aba escolhida, filtro marcado, barra de
  /// progresso, dinheiro que entrou. Sobre ele, texto em [appNeonOn].
  Color get appNeon =>
      isDarkMode ? _kNeon : const Color(0xFF15803D);

  /// Texto/ícone sobre [appNeon].
  Color get appNeonOn => isDarkMode ? _kNeonOn : Colors.white;

  /// Neón suavizado, para texto longo e áreas grandes.
  Color get appNeonSoft =>
      isDarkMode ? _kNeonSoft : const Color(0xFF15803D);

  /// Valores R$ no módulo Escalas — verde fluorescente no escuro para destaque.
  Color get appScalesMoneyValue =>
      isDarkMode ? const Color(0xFF39FF14) : const Color(0xFF15803D);

  /// Valores monetários (Financeiro, Painel, Escalas).
  Color get appFinanceMoneyValue => appScalesMoneyValue;

  /// Superfície escura de cards de módulo (gráficos, KPIs).
  Color get appDarkModuleSurface =>
      isDarkMode ? _kDarkSurface : appSurface;

  /// Superfície suave (empty states, campos secundários).
  Color get appMutedSurface => appChipIdleBg;

  /// Fundo com tom de accent (chips, faixas informativas).
  Color appAccentSurface(
    Color accent, {
    double darkAlpha = 0.18,
    double lightAlpha = 0.10,
  }) =>
      isDarkMode
          ? Color.alphaBlend(
              accent.withValues(alpha: darkAlpha), appDarkModuleSurface)
          : Color.alphaBlend(
              accent.withValues(alpha: lightAlpha), Colors.white);

  /// Painel/card sobre o scaffold (substitui `Colors.white` fixo).
  BoxDecoration appPanelDecoration({
    double radius = 14,
    Color? borderColor,
    Color? borderAccent,
    double borderAlpha = 0.12,
    double borderWidth = 1,
    List<BoxShadow>? boxShadow,
  }) {
    final accent = borderAccent ?? AppColors.primary;
    final border = borderColor ??
        (borderAccent != null
            ? accent.withValues(alpha: isDarkMode ? borderAlpha * 1.5 : borderAlpha)
            : appBorderSubtle);
    return BoxDecoration(
      color: isDarkMode ? appDarkModuleSurface : appSurface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border, width: borderWidth),
      boxShadow: boxShadow ??
          [
            BoxShadow(
              color: (isDarkMode ? Colors.black : AppColors.deepBlueDark)
                  .withValues(alpha: isDarkMode ? 0.45 : 0.06),
              blurRadius: isDarkMode ? 18 : 12,
              offset: const Offset(0, 4),
            ),
            if (!isDarkMode)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
          ],
    );
  }

  /// Fundo suave do corpo (Início, Financeiro, etc.).
  List<Color> get appBodyGradient => isDarkMode
      // Grafite com um sopro de verde no fim: dá profundidade à rolagem sem
      // puxar a tela para o azul, que competia com os destaques neón.
      ? const [
          Color(0xFF111A22),
          _kDarkBackground,
          Color(0xFF0A1710),
        ]
      : const [
          Color(0xFFF0F4FF),
          Color(0xFFF8FAFC),
          Color(0xFFEFFDF9),
        ];

  BoxDecoration appModuleCardDecoration({
    double radius = 18,
    Color? borderAccent,
    double borderAlpha = 0.12,
  }) {
    if (isDarkMode) {
      return appNeonCardDecoration(
        radius: radius,
        borderAccent: borderAccent,
        borderAlpha: borderAlpha,
      );
    }
    final accent = borderAccent ?? AppColors.primary;
    return BoxDecoration(
      color: appSurface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: accent.withValues(alpha: borderAlpha),
      ),
      boxShadow: [
        BoxShadow(
          color: AppColors.deepBlueDark.withValues(alpha: 0.08),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  /// Card neon no escuro; no claro usa o padrão de módulo.
  BoxDecoration appNeonCardDecoration({
    double radius = 18,
    Color? borderAccent,
    double borderAlpha = 0.12,
    bool elevated = true,
  }) {
    if (!isDarkMode) {
      return appModuleCardDecoration(
        radius: radius,
        borderAccent: borderAccent,
        borderAlpha: borderAlpha,
      );
    }
    final accent = borderAccent ?? AppColors.primary;
    final borderA = (borderAlpha * 2.4).clamp(0.22, 0.55);
    return BoxDecoration(
      color: appDarkModuleSurface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: accent.withValues(alpha: borderA),
        width: 1.2,
      ),
      boxShadow: elevated
          ? [
              BoxShadow(
                color: accent.withValues(alpha: 0.30),
                blurRadius: 22,
                spreadRadius: -2,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ]
          : null,
    );
  }

  /// Card de gráfico (linha, pizza, barras).
  BoxDecoration appChartCardDecoration({
    double radius = 22,
    Color? accent,
  }) =>
      appNeonCardDecoration(
        radius: radius,
        borderAccent: accent ?? AppColors.primary,
        borderAlpha: 0.20,
      );

  /// Bottom sheet / modal — escuro com borda neon no modo escuro.
  BoxDecoration appSheetDecoration({
    double radius = 24,
    Color? tint,
  }) {
    final accent = tint ?? AppColors.primary;
    if (!isDarkMode) {
      return BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
      );
    }
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          accent.withValues(alpha: 0.16),
          appDarkModuleSurface,
          _kDarkBackground,
        ],
        stops: const [0.0, 0.14, 0.38],
      ),
      borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
      border: Border.all(color: accent.withValues(alpha: 0.28)),
      boxShadow: [
        BoxShadow(
          color: accent.withValues(alpha: 0.20),
          blurRadius: 28,
          offset: const Offset(0, -6),
        ),
      ],
    );
  }

  /// Faixa informativa (ex.: Banco de Horas) — sem branco no escuro.
  BoxDecoration appInfoBannerDecoration(Color accent, {double radius = 8}) =>
      BoxDecoration(
        color: appAccentSurface(accent, darkAlpha: 0.16, lightAlpha: 0.08),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: accent.withValues(alpha: isDarkMode ? 0.38 : 0.22),
        ),
      );
}
