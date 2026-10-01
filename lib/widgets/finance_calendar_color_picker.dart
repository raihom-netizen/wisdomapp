import 'package:flutter/material.dart';

import '../constants/color_palette.dart';

/// Seletor de cor para lançamentos financeiros exibidos no calendário Agenda/Escala.
/// Padrão: vermelho para despesas, verde para receitas.
abstract final class FinanceCalendarColorPicker {
  static String defaultHexFor(bool isIncome) =>
      isIncome ? '#2E7D32' : '#E53935';

  /// Regra única (port Controle Total, 01/10/2026): lançamento financeiro só
  /// aparece na Agenda com opt-in explícito (`addToCalendar == true`).
  /// Ausente = desligado — inclusive na EDIÇÃO de lançamentos antigos.
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
    final palette = kColorPaletteHex.take(72).toList();
    final defaultHex = defaultHexFor(isIncome);
    final currentClean = (currentHex ?? defaultHex)
        .replaceFirst('#', '')
        .replaceFirst(RegExp(r'^0x', caseSensitive: false), '')
        .toUpperCase();
    final currentSix = currentClean.length > 6
        ? currentClean.substring(currentClean.length - 6)
        : currentClean;

    final idx = await showDialog<int>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(18, 12, 8, 2),
        title: Row(
          children: [
            Expanded(
              child: Text(
                'Cor no calendário',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
            TextButton.icon(
              onPressed: () => Navigator.pop(dlgCtx),
              icon: Icon(Icons.close_rounded, size: 18),
              label: Text('Cancelar'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(dlgCtx).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List.generate(palette.length, (i) {
              final hex = palette[i];
              var clean = hex
                  .replaceFirst('#', '')
                  .replaceFirst(RegExp(r'^0x', caseSensitive: false), '')
                  .toUpperCase();
              if (clean.length > 6) {
                clean = clean.substring(clean.length - 6);
              }
              final color = Color(int.parse('FF$clean', radix: 16));
              final isSelected = clean == currentSix;
              return GestureDetector(
                onTap: () => Navigator.pop(dlgCtx, i),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? Colors.white : Colors.black26,
                      width: isSelected ? 3 : 1,
                    ),
                  ),
                  child: isSelected
                      ? Icon(Icons.check_rounded, size: 18, color: Colors.white)
                      : null,
                ),
              );
            }),
          ),
        ),
      ),
    );
    if (idx != null && idx >= 0 && idx < palette.length) {
      return palette[idx];
    }
    return null;
  }
}
