import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Barra compacta: ← **Voltar** + **Fechar (X)** — previews e sheets modais.
Widget previewSheetTopBar(BuildContext context) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
    child: Row(
      children: [
        Material(
          color: AppColors.primary.withValues(alpha: 0.08),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => Navigator.of(context).pop(),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                Icons.arrow_back_rounded,
                color: AppColors.primary,
                size: 22,
                semanticLabel: 'Voltar',
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            minimumSize: const Size(44, 44),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            foregroundColor: AppColors.primary,
          ),
          child: const Text(
            'Voltar',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ),
        const Spacer(),
        Material(
          color: Colors.grey.shade100,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => Navigator.of(context).pop(),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(
                Icons.close_rounded,
                size: 22,
                color: Color(0xFF1A237E),
                semanticLabel: 'Fechar',
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
      ],
    ),
  );
}

/// Botão largo «Voltar» — fácil de tocar no iPhone/Android.
Widget sheetWideVoltarButton(
  BuildContext context, {
  VoidCallback? onPressed,
  bool footer = false,
  String label = 'Voltar',
}) {
  return Padding(
    padding: EdgeInsets.only(
      left: 16,
      right: 16,
      bottom: footer ? 6 : 12,
      top: footer ? 18 : 0,
    ),
    child: SizedBox(
      width: double.infinity,
      child: FilledButton.tonalIcon(
        onPressed: onPressed ?? () => Navigator.of(context).pop(),
        icon: const Icon(Icons.arrow_back_rounded, size: 22),
        label: Text(label),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          foregroundColor: AppColors.primary,
          backgroundColor: Colors.white,
        ),
      ),
    ),
  );
}
