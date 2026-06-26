import 'package:flutter/material.dart';

/// Cores padronizadas do app — alinhadas à logo (escudo azul, gradiente azul→teal, laranja, amarelo).
class AppColors {
  AppColors._();

  /// Azul principal (logo)
  static const Color primary = Color(0xFF2D5BFF);
  static const Color secondary = Color(0xFF4B3DF0);
  /// Teal/verde do gradiente da logo
  static const Color accent = Color(0xFF12B5A5);
  static const Color success = Color(0xFF22C55E);
  static const Color error = Color(0xFFEF4444);
  /// Saldo: verde escuro (positivo) e vermelho escuro (negativo) — negrito
  static const Color saldoPositive = Color(0xFF166534);
  static const Color saldoNegative = Color(0xFF991B1B);
  /// Amarelo/laranja da logo (calculadora, gráficos)
  static const Color amber = Color(0xFFFFB648);
  static const Color logoOrange = Color(0xFFF97316);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF475569);
  static const Color textMuted = Color(0xFF64748B);
  /// Azuis do escudo da logo (gradiente header)
  static const Color deepBlue = Color(0xFF122B6B);
  static const Color deepBlueDark = Color(0xFF0B1F4B);
  /// Prata/cinza da logo (detalhes)
  static const Color logoSilver = Color(0xFF94A3B8);

  /// Gradiente padrão da logo: azul escuro → azul → teal
  static const List<Color> logoGradient = [deepBlueDark, deepBlue, accent];

  /// Receitas em KPIs, gráficos e listas (mesmo tom dos lançamentos tipo receita).
  static Color get financeReceita => success;

  /// Despesas em KPIs, gráficos e listas (mesmo tom dos lançamentos tipo despesa).
  static Color get financeDespesa => error;

  /// Estado pendente (Pendente, faixas e alertas de quitação).
  static Color get financePendente => logoOrange;

  /// Vínculo plantão — Estado / Município / Particular (lançamento expresso, pré-cadastro na escala, editar plantão).
  static const Color vinculoEstado = Color(0xFF2E7D32);
  static const Color vinculoMunicipio = Color(0xFFFFC107);
  static const Color vinculoParticular = Color(0xFF1565C0);

  /// Cor de plantão no calendário / pré-cadastro mais viva (satura, evita cinza “lavado”).
  static Color vividShift(Color c) {
    final hsl = HSLColor.fromColor(c);
    final sat = hsl.saturation < 0.12
        ? 0.52
        : (hsl.saturation * 1.2).clamp(0.0, 1.0);
    final light = hsl.lightness.clamp(0.34, 0.7);
    return hsl.withSaturation(sat).withLightness(light).toColor();
  }

  /// Cor de texto legível sobre preenchimento do dia (número do calendário).
  static Color onVividFill(Color fill) {
    return fill.computeLuminance() > 0.57
        ? textPrimary
        : Colors.white;
  }

  /// Halo para dígitos sobre fatias coloridas (sem caixa branca grande).
  static List<Shadow> calendarDialLegibilityShadows({required bool darkInk}) {
    if (darkInk) {
      return const [
        Shadow(
          color: Color(0xE6FFFFFF),
          blurRadius: 3,
          offset: Offset(0, 0),
        ),
        Shadow(
          color: Color(0x66000000),
          blurRadius: 2,
          offset: Offset(0, 1),
        ),
      ];
    }
    return const [
      Shadow(
        color: Color(0x73000000),
        blurRadius: 4,
        offset: Offset(0, 1),
      ),
      Shadow(
        color: Color(0x4DFFFFFF),
        blurRadius: 2,
        offset: Offset(0, -1),
      ),
    ];
  }
}
