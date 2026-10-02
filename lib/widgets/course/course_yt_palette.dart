import 'package:flutter/material.dart';

/// Paleta do módulo Cursos no estilo YouTube que segue o tema do app.
///
/// Modo claro (padrão): fundo branco/cinza bem claro, cards brancos com sombra
/// suave, títulos pretos e detalhes em vermelho YouTube. Modo escuro: as cores
/// escuras do YouTube. Nada aqui é fixo por tela — tudo vem do [Theme] atual.
abstract final class CourseYt {
  /// Vermelho YouTube — abas/chips ativos, ícone de play, progresso.
  static const Color red = Color(0xFFFF0000);
  static const Color redDark = Color(0xFFCC0000);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Fundo da tela (vitrine, tela do curso, aba Dicas).
  static Color background(BuildContext context) =>
      isDark(context) ? const Color(0xFF0F0F0F) : const Color(0xFFF9F9F9);

  /// Card / painel.
  static Color card(BuildContext context) =>
      isDark(context) ? const Color(0xFF1A1A1A) : Colors.white;

  /// Superfície secundária: chip inativo, campo de busca, placeholder de capa.
  static Color surfaceAlt(BuildContext context) =>
      isDark(context) ? const Color(0xFF272727) : const Color(0xFFF2F2F2);

  /// Título / texto principal.
  static Color text(BuildContext context) =>
      isDark(context) ? Colors.white : const Color(0xFF0F0F0F);

  /// Texto de apoio (descrição, metadados).
  static Color textSecondary(BuildContext context) =>
      isDark(context) ? const Color(0xFFAAAAAA) : const Color(0xFF606060);

  /// Texto bem discreto / ícones inativos.
  static Color textMuted(BuildContext context) =>
      isDark(context) ? const Color(0xFF8A8A8A) : const Color(0xFF909090);

  /// Borda fina de cards e campos.
  static Color border(BuildContext context) => isDark(context)
      ? Colors.white.withValues(alpha: 0.08)
      : Colors.black.withValues(alpha: 0.06);

  /// Trilho da barra de progresso sobre fundo de card.
  static Color track(BuildContext context) => isDark(context)
      ? Colors.white.withValues(alpha: 0.08)
      : Colors.black.withValues(alpha: 0.08);

  /// Texto de destaque do progresso («35% assistido», «Continuar»).
  static Color progressText(BuildContext context) =>
      isDark(context) ? const Color(0xFFFCA5A5) : const Color(0xFFCC0000);

  /// Sombra suave dos cards (só no claro; no escuro não há sombra).
  static List<BoxShadow> cardShadow(BuildContext context) => isDark(context)
      ? const []
      : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ];

  /// Decoração padrão de card (fundo + borda + sombra).
  static BoxDecoration cardDecoration(
    BuildContext context, {
    double radius = 14,
    Color? borderColor,
    double borderWidth = 1,
  }) =>
      BoxDecoration(
        color: card(context),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor ?? border(context),
          width: borderWidth,
        ),
        boxShadow: cardShadow(context),
      );

  /// Gradiente de capa vazia (sem imagem).
  static List<Color> coverFallbackGradient(BuildContext context) =>
      isDark(context)
          ? const [Color(0xFF1A1A2E), Color(0xFF7F1D1D)]
          : const [Color(0xFFFFE4E4), Color(0xFFF3F4F6)];

  /// Ícone sobre capa vazia.
  static Color coverFallbackIcon(BuildContext context) =>
      isDark(context) ? Colors.white38 : Colors.black.withValues(alpha: 0.28);
}
