import 'package:flutter/material.dart';

import '../models/finance_account.dart';
import '../theme/app_colors.dart';

/// Confirma exclusão de banco/cartão — aviso em vermelho sobre lançamentos vinculados.
Future<bool> showConfirmDeleteFinanceAccountDialog(
  BuildContext context, {
  required FinanceAccount account,
  required int linkedTransactionsCount,
}) async {
  final name = account.displayName;
  final countLabel = linkedTransactionsCount == 1
      ? '1 lançamento vinculado'
      : '$linkedTransactionsCount lançamentos vinculados';

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      icon: Icon(
        Icons.warning_amber_rounded,
        color: AppColors.error,
        size: 44,
      ),
      iconPadding: const EdgeInsets.only(top: 20),
      title: Text(
        'Excluir «$name»?',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 18,
          color: Color(0xFF991B1B),
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'ATENÇÃO: ao confirmar, o sistema removerá permanentemente '
            'todos os lançamentos financeiros ligados a este banco/cartão.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w800,
              color: AppColors.error,
            ),
          ),
          const SizedBox(height: 12),
          if (linkedTransactionsCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  Icon(Icons.receipt_long_rounded, color: AppColors.error, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      countLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Text(
              'Nenhum lançamento vinculado foi encontrado; apenas o cadastro do banco será removido.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          const SizedBox(height: 10),
          Text(
            'Esta ação não pode ser desfeita.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(ctx, false),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(120, 44),
            foregroundColor: AppColors.primary,
          ),
          child: const Text('Não', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            minimumSize: const Size(120, 44),
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
          ),
          child: const Text('Sim, excluir', style: TextStyle(fontWeight: FontWeight.w900)),
        ),
      ],
    ),
  );
  return result == true;
}
