import 'package:flutter/material.dart';

import '../constants/currency_formats.dart';
import 'form_validation_alert.dart';

/// Verifica nome, valor e conta/banco. Exibe alerta colorido se faltar algo.
/// Retorna `true` quando o formulário pode ser gravado.
Future<bool> validateGoalFormOrShowAlert(
  BuildContext context, {
  required String title,
  required String targetText,
  required String? financeAccountId,
}) async {
  final missing = collectGoalFormMissingFields(
    title: title,
    targetText: targetText,
    financeAccountId: financeAccountId,
  );
  if (missing.isEmpty) return true;
  await showFormMissingFieldsAlert(
    context,
    missing: missing,
    headline: 'Complete para salvar',
    body: 'Preencha os itens abaixo antes de gravar o objetivo:',
  );
  return false;
}

List<FormMissingField> collectGoalFormMissingFields({
  required String title,
  required String targetText,
  required String? financeAccountId,
}) {
  final missing = <FormMissingField>[];

  if (title.trim().isEmpty) {
    missing.add(
      const FormMissingField(
        label: 'Nome do objetivo',
        hint: 'Informe como você quer chamar esta meta',
        icon: Icons.flag_rounded,
        colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
      ),
    );
  }

  final target = CurrencyFormats.parseBRLInput(targetText) ?? 0;
  if (target <= 0) {
    missing.add(
      const FormMissingField(
        label: 'Valor alvo',
        hint: 'Informe quanto você quer juntar (ex.: 50.000,00)',
        icon: Icons.payments_rounded,
        colors: [Color(0xFFF59E0B), Color(0xFFEA580C)],
      ),
    );
  }

  final account = (financeAccountId ?? '').trim();
  if (account.isEmpty) {
    missing.add(
      const FormMissingField(
        label: 'Conta / banco',
        hint: 'Selecione onde o dinheiro será guardado',
        icon: Icons.account_balance_rounded,
        colors: [Color(0xFF0EA5E9), Color(0xFF2563EB)],
      ),
    );
  }

  return missing;
}
