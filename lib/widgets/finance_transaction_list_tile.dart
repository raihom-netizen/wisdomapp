import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../constants/currency_formats.dart';
import '../constants/date_time_formats.dart';
import '../models/finance_account.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';
import '../utils/anexo_viewer_helper.dart';
import '../utils/receipt_attachment_utils.dart';
import '../utils/finance_line_opening.dart';
import '../utils/premium_upgrade.dart';

/// Evita chip/valor duplicados quando a descrição já inclui o sufixo «· N/Total» (despesas fixas por parcelas).
bool financeDescriptionEndsWithParcelSuffix(String description, int index, int total) {
  if (total <= 1) return false;
  final t = description.trim();
  final m = RegExp(r'·\s*(\d+)/(\d+)\s*$').firstMatch(t);
  if (m == null) return false;
  final a = int.tryParse(m.group(1) ?? '', radix: 10);
  final b = int.tryParse(m.group(2) ?? '', radix: 10);
  return a == index && b == total;
}

String? financeAccountLabelForTx(List<FinanceAccount> accounts, Map<String, dynamic> d) {
  final aid = (d['financeAccountId'] ?? '').toString().trim();
  if (aid.isEmpty) return null;
  for (final a in accounts) {
    if (a.id == aid) return a.displayName;
  }
  return 'Conta removida';
}

/// Cartão de lançamento (receita/despesa) — usado na lista principal e na vista em tela cheia.
class FinanceTransactionListTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final Map<String, dynamic>? overrideData;
  final UserProfile profile;
  final List<FinanceAccount> financeAccounts;
  final bool gridSelectionMode;
  final bool isSelected;
  final Set<String> optimisticPaidIds;
  final Future<void> Function(BuildContext context, String docId, Map<String, dynamic> data, String type) onEdit;
  final Future<void> Function(BuildContext context, String docId) onDelete;
  final Future<void> Function(BuildContext context, String docId) onConfirmPayment;
  final Future<void> Function(BuildContext context, String docId) onAttachReceipt;
  /// No modo seleção, alterna inclusão deste lançamento na seleção múltipla.
  final VoidCallback? onToggleSelection;

  const FinanceTransactionListTile({
    super.key,
    required this.doc,
    this.overrideData,
    required this.profile,
    required this.financeAccounts,
    required this.gridSelectionMode,
    required this.isSelected,
    required this.optimisticPaidIds,
    required this.onEdit,
    required this.onDelete,
    required this.onConfirmPayment,
    required this.onAttachReceipt,
    this.onToggleSelection,
  });

  @override
  Widget build(BuildContext context) {
    final base = doc.data();
    // Patch otimista é parcial; fundir com o documento para não perder `type` e outros campos.
    final d = (overrideData == null || overrideData!.isEmpty)
        ? base
        : <String, dynamic>{...base, ...overrideData!};
    final id = doc.id;
    final isIncome = d['type'] == 'income';
    final status = optimisticPaidIds.contains(id) || (d['status'] ?? 'paid') == 'paid' ? 'Pago' : 'Pendente';
    final postedAt = FinanceLineOpening.effectiveDateTimeFromMap(d) ??
        (d['date'] as Timestamp?)?.toDate();
    final amount = (d['amount'] ?? 0).toDouble();
    final installmentIndex = (d['installmentIndex'] as num?)?.toInt() ?? 1;
    final installmentCount = (d['installmentCount'] as num?)?.toInt() ?? 1;
    final category = (d['category'] ?? '').toString();
    final description = (d['description'] ?? '').toString();
    final descHasParcelSuffix =
        installmentCount > 1 && financeDescriptionEndsWithParcelSuffix(description, installmentIndex, installmentCount);
    final parcelInfo = installmentCount > 1 && !descHasParcelSuffix ? ' $installmentIndex/$installmentCount' : '';
    final financeAccLabel = financeAccountLabelForTx(financeAccounts, d);

    final receipt = Map<String, dynamic>.from(d['receipt'] ?? {});
    final hasReceiptView = ReceiptAttachmentUtils.hasViewableReceipt(receipt);
    final accent = isIncome ? AppColors.financeReceita : AppColors.financeDespesa;

    // RepaintBoundary isola o repaint deste card do resto da lista: rolagem mais leve no Android.
    return RepaintBoundary(
      child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border(left: BorderSide(color: accent, width: 4)),
        // Sombra única e sutil (antes eram 2 camadas por card → custo alto em listas longas).
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            if (gridSelectionMode) {
              onToggleSelection?.call();
            } else {
              onEdit(context, id, d, isIncome ? 'income' : 'expense');
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (gridSelectionMode) ...[
                  Checkbox(
                    value: isSelected,
                    onChanged: (_) => onToggleSelection?.call(),
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                  ),
                  const SizedBox(width: 8),
                ],
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isIncome ? Icons.south_west_rounded : Icons.north_east_rounded,
                    color: accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 100),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isIncome ? 'Receita' : 'Despesa',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: accent),
                              ),
                            ),
                            Text(
                              category.isNotEmpty ? category : (isIncome ? 'Receita' : 'Despesa'),
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                        if (financeAccLabel != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.account_balance_wallet_rounded, size: 14, color: AppColors.primary),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  financeAccLabel,
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            description,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
                            maxLines: 6,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (installmentCount > 1 && !descHasParcelSuffix) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: accent.withValues(alpha: 0.22)),
                            ),
                            child: Text(
                              '$installmentIndex/$installmentCount',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: accent, letterSpacing: 0.2),
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: status == 'Pago'
                                    ? AppColors.financeReceita.withValues(alpha: 0.15)
                                    : AppColors.financePendente.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                status,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: status == 'Pago' ? AppColors.financeReceita : AppColors.financePendente,
                                ),
                              ),
                            ),
                            if (postedAt != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                DateTimeFormats.formatTimeOnly(postedAt),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${isIncome ? '+ ' : ''}${isIncome ? CurrencyFormats.formatBRL(amount) : CurrencyFormats.formatBRL(-amount.abs())}$parcelInfo',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: accent),
                        textAlign: TextAlign.end,
                      ),
                      const SizedBox(height: 6),
                      if (!gridSelectionMode)
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          alignment: WrapAlignment.end,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (status == 'Pendente') ...[
                              FilledButton.icon(
                                onPressed: () => onConfirmPayment(context, id),
                                icon: const Icon(Icons.check_circle_rounded, size: 18),
                                label: const Text('Pagar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  minimumSize: const Size(44, 44),
                                  tapTargetSize: MaterialTapTargetSize.padded,
                                  backgroundColor: AppColors.success.withValues(alpha: 0.15),
                                  foregroundColor: AppColors.success,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => onDelete(context, id),
                                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                                label: const Text('Excluir', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  minimumSize: const Size(44, 44),
                                  tapTargetSize: MaterialTapTargetSize.padded,
                                  foregroundColor: AppColors.error,
                                  side: BorderSide(color: AppColors.error.withValues(alpha: 0.5)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ],
                            IconButton(
                              icon: Icon(
                                Icons.attach_file_rounded,
                                size: 20,
                                color: profile.temAcessoPremium ? AppColors.textSecondary : Colors.grey,
                              ),
                              onPressed: profile.temAcessoPremium
                                  ? () => onAttachReceipt(context, id)
                                  : () => mostrarAvisoSeLicencaInativa(context, profile),
                              tooltip: 'Anexar comprovante',
                              style: IconButton.styleFrom(minimumSize: const Size(44, 44), tapTargetSize: MaterialTapTargetSize.padded),
                            ),
                            if (hasReceiptView && profile.temAcessoPremium)
                              IconButton(
                                icon: Icon(Icons.visibility_rounded, size: 20, color: AppColors.primary),
                                tooltip: 'Ver comprovante',
                                onPressed: () => mostrarComprovanteReceipt(context, receipt),
                                style: IconButton.styleFrom(minimumSize: const Size(44, 44), tapTargetSize: MaterialTapTargetSize.padded),
                              ),
                            PopupMenuButton<String>(
                              icon: SizedBox(
                                width: 44,
                                height: 44,
                                child: Center(child: Icon(Icons.more_vert_rounded, size: 22, color: AppColors.textSecondary)),
                              ),
                              padding: EdgeInsets.zero,
                              onSelected: (v) async {
                                if (v == 'edit') await onEdit(context, id, d, isIncome ? 'income' : 'expense');
                                if (v == 'view') {
                                  if (hasReceiptView) {
                                    mostrarComprovanteReceipt(context, receipt);
                                  } else if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não há comprovante anexado.')));
                                  }
                                }
                                if (v == 'delete') await onDelete(context, id);
                                if (v == 'attach' && profile.temAcessoPremium) await onAttachReceipt(context, id);
                                if (v == 'attach' && !profile.temAcessoPremium) mostrarAvisoSeLicencaInativa(context, profile);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_rounded, size: 20), SizedBox(width: 8), Text('Editar')])),
                                PopupMenuItem(value: 'view', child: Row(children: [Icon(Icons.visibility_rounded, size: 20), SizedBox(width: 8), Text('Ver anexo')])),
                                PopupMenuItem(value: 'attach', child: Row(children: [Icon(Icons.attach_file_rounded, size: 20), SizedBox(width: 8), Text('Trocar comprovante')])),
                                PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline_rounded, size: 20), SizedBox(width: 8), Text('Excluir')])),
                              ],
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}
