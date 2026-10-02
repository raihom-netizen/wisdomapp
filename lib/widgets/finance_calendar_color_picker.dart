import 'package:flutter/material.dart';

import '../constants/color_palette.dart';
import 'color_palette_tabs_dialog.dart';

/// Seletor de cor para lançamentos financeiros exibidos no calendário Agenda/Escala.
/// Padrão: vermelho para despesas, verde para receitas.
abstract final class FinanceCalendarColorPicker {
  static String defaultHexFor(bool isIncome) =>
      isIncome ? '#2E7D32' : '#E53935';

  /// Regra única (01/10/2026): lançamento financeiro só aparece na
  /// Agenda/Escala com opt-in explícito (`addToCalendar == true`). Ausente
  /// = desligado — inclusive na EDIÇÃO de lançamentos antigos.
  static bool calendarioLigado(Map<String, dynamic>? d) =>
      d != null &&
      d['addToCalendar'] == true &&
      d['hideFromCalendar'] != true;

  /// Ao LIGAR «Mostrar no calendário»: abre a paleta padrão do app já com a
  /// cor sugerida (vermelho despesa / verde receita) ou a que a pessoa já
  /// escolheu. Fechar sem escolher mantém a atual ou a sugerida.
  static Future<String> escolherAoAtivar(
    BuildContext context, {
    required bool isIncome,
    String? currentHex,
  }) async {
    final atual = (currentHex ?? '').trim();
    final base = atual.isNotEmpty ? atual : defaultHexFor(isIncome);
    final picked = await show(context, isIncome: isIncome, currentHex: base);
    final escolhida = (picked ?? '').trim();
    return escolhida.isNotEmpty ? escolhida : base;
  }

  static Future<String?> show(
    BuildContext context, {
    required bool isIncome,
    String? currentHex,
  }) async {
    final defaultHex = defaultHexFor(isIncome);
    final currentClean = (currentHex ?? defaultHex)
        .replaceFirst('#', '')
        .replaceFirst(RegExp(r'^0x', caseSensitive: false), '')
        .toUpperCase();
    final currentSix = currentClean.length > 6
        ? currentClean.substring(currentClean.length - 6)
        : currentClean;

    return await mostrarSeletorDeCores(
      context,
      titulo: isIncome ? 'Cor da receita no calendário' : 'Cor da despesa no calendário',
      selecionadaHex: currentSix,
    );
  }
}
