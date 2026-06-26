import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/gemini_theme.dart';

/// Rodapé duplo (Cancelar + ação principal) — Audiência, Compromisso, Lançamento expresso, etc.
/// Layout estável em telemóveis (evita o texto «Cancelar» a partir ao meio); padrão visual premium.
class AgendaFormFooterActions extends StatelessWidget {
  const AgendaFormFooterActions({
    super.key,
    required this.onCancel,
    required this.onSave,
    required this.saveLabel,
    this.isBusy = false,
    this.busyLabel = 'Salvando…',
    this.saveIcon = Icons.check_circle_rounded,
  });

  final VoidCallback onCancel;
  final VoidCallback onSave;
  final String saveLabel;
  /// Quando true, desativa Cancelar e mostra progresso no botão principal.
  final bool isBusy;
  final String busyLabel;
  /// Ícone do botão principal (ex.: [Icons.add_task_rounded] no lançamento expresso).
  final IconData saveIcon;

  static const double _kMinHeight = 52;

  @override
  Widget build(BuildContext context) {
    final radius = GeminiTheme.buttonRadius;

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 400;

        final cancel = OutlinedButton(
          onPressed: isBusy ? null : onCancel,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
            backgroundColor: const Color(0xFFF8FAFC),
            side: BorderSide(color: AppColors.primary.withValues(alpha: 0.32), width: 1.2),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
            minimumSize: const Size(0, _kMinHeight),
            tapTargetSize: MaterialTapTargetSize.padded,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.max,
            children: [
              Icon(
                Icons.close_rounded,
                size: 20,
                color: AppColors.textSecondary.withValues(alpha: 0.95),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Cancelar',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.15,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        );

        final save = FilledButton(
          onPressed: isBusy ? null : onSave,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.deepBlue,
            foregroundColor: Colors.white,
            elevation: isBusy ? 0 : 2,
            shadowColor: AppColors.deepBlueDark.withValues(alpha: 0.38),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
            minimumSize: const Size(0, _kMinHeight),
            tapTargetSize: MaterialTapTargetSize.padded,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.max,
            children: [
              if (isBusy) ...[
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    busyLabel,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.2,
                      fontSize: 15,
                    ),
                  ),
                ),
              ] else ...[
                Icon(saveIcon, size: 21),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    saveLabel,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.2,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              cancel,
              const SizedBox(height: 10),
              save,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: cancel),
            const SizedBox(width: 12),
            Expanded(child: save),
          ],
        );
      },
    );
  }
}
