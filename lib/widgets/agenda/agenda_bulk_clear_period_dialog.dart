import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/theme_context.dart';
import '../date_time_field.dart';

/// Diálogo direto: data inicial + data final (digitar ou calendário).
/// Retorna o intervalo escolhido; a confirmação com quantidade fica no passo seguinte.
Future<DateTimeRange?> showAgendaBulkClearPeriodDialog(
  BuildContext context, {
  required DateTime initialRef,
}) async {
  var dataInicial = DateTime(initialRef.year, initialRef.month, 1);
  var dataFinal = DateTime(initialRef.year, initialRef.month + 1, 0);
  const accent = Color(0xFFA855F7);
  const accent2 = Color(0xFF7C3AED);

  return showDialog<DateTimeRange>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [accent2, accent],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.date_range_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Limpar por período',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Digite ou escolha data inicial e final',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close_rounded,
                              color: Colors.white),
                          tooltip: 'Fechar',
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                    child: Column(
                      children: [
                        DateFieldWithCalendarOrManual(
                          label: 'Data inicial',
                          value: dataInicial,
                          firstDate: DateTime(2020, 1, 1),
                          lastDate: DateTime(2035, 12, 31),
                          onChanged: (d) {
                            setSheet(() {
                              dataInicial =
                                  DateTime(d.year, d.month, d.day);
                              if (dataFinal.isBefore(dataInicial)) {
                                dataFinal = dataInicial;
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 14),
                        DateFieldWithCalendarOrManual(
                          label: 'Data final',
                          value: dataFinal,
                          firstDate: dataInicial,
                          lastDate: DateTime(2035, 12, 31),
                          onChanged: (d) {
                            setSheet(() {
                              dataFinal = DateTime(d.year, d.month, d.day);
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: accent.withValues(alpha: 0.22),
                            ),
                          ),
                          child: Text(
                            'Período: ${DateFormat('dd/MM/yyyy').format(dataInicial)}'
                            ' — ${DateFormat('dd/MM/yyyy').format(dataFinal)}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: ctx.isDarkMode
                                  ? ctx.appTextPrimary
                                  : Colors.grey.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: OutlinedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Cancelar',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () {
                              final inicio = DateTime(
                                dataInicial.year,
                                dataInicial.month,
                                dataInicial.day,
                              );
                              final fim = DateTime(
                                dataFinal.year,
                                dataFinal.month,
                                dataFinal.day,
                              );
                              if (fim.isBefore(inicio)) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Data final deve ser igual ou posterior à inicial.',
                                    ),
                                  ),
                                );
                                return;
                              }
                              Navigator.pop(
                                ctx,
                                DateTimeRange(start: inicio, end: fim),
                              );
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: accent2,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: const Text(
                              'OK',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
