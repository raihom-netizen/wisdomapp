import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../constants/currency_formats.dart';
import '../constants/date_time_formats.dart';
import '../models/finance_account.dart';
import '../models/user_profile.dart';
import '../screens/finance_lancamento_detalhe_page.dart';
import '../theme/app_colors.dart';
import '../theme/theme_context.dart';
import '../utils/anexo_viewer_helper.dart';
import '../utils/finance_fora_dos_totais.dart';
import '../utils/receipt_attachment_utils.dart';
import 'finance_pix_sheets.dart';
import '../utils/finance_line_opening.dart';
import '../utils/premium_upgrade.dart';

/// Evita chip/valor duplicados quando a descrição já inclui o sufixo «· N/Total» (despesas fixas por parcelas).
bool financeDescriptionEndsWithParcelSuffix(
    String description, int index, int total) {
  if (total <= 1) return false;
  final t = description.trim();
  final m = RegExp(r'·\s*(\d+)/(\d+)\s*$').firstMatch(t);
  if (m == null) return false;
  final a = int.tryParse(m.group(1) ?? '', radix: 10);
  final b = int.tryParse(m.group(2) ?? '', radix: 10);
  return a == index && b == total;
}

String? financeAccountLabelForTx(
    List<FinanceAccount> accounts, Map<String, dynamic> d) {
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
  final Future<void> Function(BuildContext context, String docId,
      Map<String, dynamic> data, String type) onEdit;
  final Future<void> Function(BuildContext context, String docId) onDelete;
  /// Confirma pagamento/recebimento. Pode devolver `true` quando confirmou
  /// (o «Receber via Pix» fecha sozinho depois da baixa).
  final Future<Object?> Function(BuildContext context, String docId)
      onConfirmPayment;
  final Future<void> Function(BuildContext context, String docId)
      onAttachReceipt;

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
    final status =
        optimisticPaidIds.contains(id) || (d['status'] ?? 'paid') == 'paid'
            ? 'Pago'
            : 'Pendente';
    final postedAt = FinanceLineOpening.effectiveDateTimeFromMap(d) ??
        (d['date'] as Timestamp?)?.toDate();
    final amount = (d['amount'] ?? 0).toDouble();
    final installmentIndex = (d['installmentIndex'] as num?)?.toInt() ?? 1;
    final installmentCount = (d['installmentCount'] as num?)?.toInt() ?? 1;
    final category = (d['category'] ?? '').toString();
    final description = (d['description'] ?? '').toString();
    final descHasParcelSuffix = installmentCount > 1 &&
        financeDescriptionEndsWithParcelSuffix(
            description, installmentIndex, installmentCount);
    final parcelInfo = installmentCount > 1 && !descHasParcelSuffix
        ? ' $installmentIndex/$installmentCount'
        : '';
    final financeAccLabel = financeAccountLabelForTx(financeAccounts, d);
    // «Pagamento de fatura · Nubank» / «Transferência entre contas»: aparece na
    // lista, mas fora dos totais de receita e despesa.
    final rotuloFora = financeRotuloForaDosTotais(d, contaDoLancamento: financeAccLabel);

    final receipt = Map<String, dynamic>.from(d['receipt'] ?? {});
    final hasReceiptView = ReceiptAttachmentUtils.hasViewableReceipt(receipt);
    final accent =
        isIncome ? AppColors.financeReceita : AppColors.financeDespesa;

    // RepaintBoundary isola o repaint deste card do resto da lista: rolagem mais leve no Android.
    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border(left: BorderSide(color: accent, width: 4)),
          boxShadow: [
            BoxShadow(
                color: Colors.black
                    .withValues(alpha: context.isDarkMode ? 0.35 : 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3)),
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
            // Toque longo abre a ficha completa: todos os campos, a
            // observação e o histórico (de onde veio, se o banco confirmou,
            // se alguém trocou a categoria). O toque curto continua editando,
            // que é o que a pessoa faz o tempo todo.
            onLongPress: gridSelectionMode
                ? null
                : () => FinanceLancamentoDetalhePage.abrir(
                      context,
                      uid: profile.uid,
                      docId: id,
                      dados: d,
                    ),
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
                    SizedBox(width: 8),
                  ],
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isIncome
                          ? Icons.south_west_rounded
                          : Icons.north_east_rounded,
                      color: accent,
                      size: 22,
                    ),
                  ),
                  SizedBox(width: 12),
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
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  rotuloFora != null
                                      ? 'Fora dos totais'
                                      : (isIncome ? 'Receita' : 'Despesa'),
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: accent),
                                ),
                              ),
                              Text(
                                rotuloFora ??
                                    (category.isNotEmpty
                                        ? category
                                        : (isIncome ? 'Receita' : 'Despesa')),
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    color: context.appTextPrimary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                          if (financeAccLabel != null) ...[
                            SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(Icons.account_balance_wallet_rounded,
                                    size: 14, color: AppColors.primary),
                                SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    financeAccLabel,
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primary),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (description.isNotEmpty) ...[
                            SizedBox(height: 4),
                            Text(
                              description,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: context.appTextSecondary),
                              maxLines: 6,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          // Observação: o «por quê» do lançamento. Aparece
                          // discreta, em itálico, para não competir com a
                          // descrição — mas aparece, senão ninguém anotaria.
                          if ((d['observacao'] ?? '').toString().trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.sticky_note_2_rounded,
                                    size: 13, color: context.appTextMuted),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    d['observacao'].toString().trim(),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                      color: context.appTextMuted,
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (installmentCount > 1 && !descHasParcelSuffix) ...[
                            SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: accent.withValues(alpha: 0.22)),
                              ),
                              child: Text(
                                '$installmentIndex/$installmentCount',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: accent,
                                    letterSpacing: 0.2),
                              ),
                            ),
                          ],
                          SizedBox(height: 6),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: status == 'Pago'
                                      ? AppColors.financeReceita
                                          .withValues(alpha: 0.15)
                                      : AppColors.financePendente
                                          .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  status,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: status == 'Pago'
                                        ? AppColors.financeReceita
                                        : AppColors.financePendente,
                                  ),
                                ),
                              ),
                              if (postedAt != null) ...[
                                SizedBox(height: 4),
                                Text(
                                  DateTimeFormats.formatDateTimeMinute(
                                      postedAt),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: context.appTextMuted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  // Hora do financeiro sempre em HH:mm; sem segundos na grid.
                                  softWrap: true,
                                  maxLines: 2,
                                  overflow: TextOverflow.visible,
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${isIncome ? '+ ' : ''}${isIncome ? CurrencyFormats.formatBRL(amount) : CurrencyFormats.formatBRL(-amount.abs())}$parcelInfo',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: accent),
                          textAlign: TextAlign.end,
                        ),
                        SizedBox(height: 6),
                        if (!gridSelectionMode)
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            alignment: WrapAlignment.end,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              // Receita pendente: «Receber via Pix» (port
                              // Controle Total) — QR Code e copia e cola com a
                              // sua chave; confirmar dali já dá a baixa.
                              if (status == 'Pendente' && isIncome)
                                OutlinedButton.icon(
                                  onPressed: () => abrirCobrarPix(
                                    context,
                                    profile.uid,
                                    valor: amount.abs(),
                                    descricao: description.trim().isEmpty
                                        ? (d['category'] ?? '').toString().trim()
                                        : description.trim(),
                                    contaSugerida:
                                        (d['financeAccountId'] ?? '').toString().trim(),
                                    onConfirmarRecebimento: (c) async =>
                                        (await onConfirmPayment(c, id)) == true,
                                  ),
                                  icon: const Icon(Icons.qr_code_2_rounded, size: 16),
                                  label: const Text('Receber via Pix',
                                      style: TextStyle(
                                          fontSize: 11, fontWeight: FontWeight.w700)),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 6),
                                    minimumSize: const Size(44, 44),
                                    tapTargetSize: MaterialTapTargetSize.padded,
                                    foregroundColor: const Color(0xFF0D9488),
                                    side: const BorderSide(color: Color(0xFF0D9488)),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              if (status == 'Pendente') ...[
                                FilledButton.icon(
                                  onPressed: () =>
                                      onConfirmPayment(context, id),
                                  icon: Icon(Icons.check_circle_rounded,
                                      size: 18),
                                  label: Text('Pagar',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600)),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 8),
                                    minimumSize: const Size(44, 44),
                                    tapTargetSize: MaterialTapTargetSize.padded,
                                    backgroundColor: AppColors.success
                                        .withValues(alpha: 0.15),
                                    foregroundColor: AppColors.success,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () => onDelete(context, id),
                                  icon: Icon(Icons.delete_outline_rounded,
                                      size: 16),
                                  label: Text('Excluir',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600)),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 6),
                                    minimumSize: const Size(44, 44),
                                    tapTargetSize: MaterialTapTargetSize.padded,
                                    foregroundColor: AppColors.error,
                                    side: BorderSide(
                                        color: AppColors.error
                                            .withValues(alpha: 0.5)),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                ),
                              ],
                              IconButton(
                                icon: Icon(
                                  Icons.attach_file_rounded,
                                  size: 20,
                                  color: profile.temAcessoPremium
                                      ? AppColors.textSecondary
                                      : Colors.grey,
                                ),
                                onPressed: profile.temAcessoPremium
                                    ? () => onAttachReceipt(context, id)
                                    : () => mostrarAvisoSeLicencaInativa(
                                        context, profile),
                                tooltip: 'Anexar comprovante',
                                style: IconButton.styleFrom(
                                    minimumSize: const Size(44, 44),
                                    tapTargetSize:
                                        MaterialTapTargetSize.padded),
                              ),
                              if (hasReceiptView && profile.temAcessoPremium)
                                IconButton(
                                  icon: Icon(Icons.visibility_rounded,
                                      size: 20, color: AppColors.primary),
                                  tooltip: 'Ver comprovante',
                                  onPressed: () =>
                                      mostrarComprovanteReceipt(context, receipt),
                                  style: IconButton.styleFrom(
                                      minimumSize: const Size(44, 44),
                                      tapTargetSize:
                                          MaterialTapTargetSize.padded),
                                ),
                              PopupMenuButton<String>(
                                icon: SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: Center(
                                      child: Icon(Icons.more_vert_rounded,
                                          size: 22,
                                          color: context.appTextSecondary)),
                                ),
                                padding: EdgeInsets.zero,
                                onSelected: (v) async {
                                  if (v == 'edit') {
                                    await onEdit(context, id, d,
                                        isIncome ? 'income' : 'expense');
                                  }
                                  if (v == 'view') {
                                    if (hasReceiptView) {
                                      mostrarComprovanteReceipt(context, receipt);
                                    } else if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                              content: Text(
                                                  'Não há comprovante anexado.')));
                                    }
                                  }
                                  if (v == 'delete') {
                                    await onDelete(context, id);
                                  }
                                  if (v == 'attach' &&
                                      profile.temAcessoPremium) {
                                    await onAttachReceipt(context, id);
                                  }
                                  if (v == 'attach' &&
                                      !profile.temAcessoPremium) {
                                    mostrarAvisoSeLicencaInativa(
                                        context, profile);
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                      value: 'edit',
                                      child: Row(children: [
                                        Icon(Icons.edit_rounded, size: 20),
                                        SizedBox(width: 8),
                                        Text('Editar')
                                      ])),
                                  PopupMenuItem(
                                      value: 'view',
                                      child: Row(children: [
                                        Icon(Icons.visibility_rounded,
                                            size: 20),
                                        SizedBox(width: 8),
                                        Text('Ver anexo')
                                      ])),
                                  PopupMenuItem(
                                      value: 'attach',
                                      child: Row(children: [
                                        Icon(Icons.attach_file_rounded,
                                            size: 20),
                                        SizedBox(width: 8),
                                        Text('Trocar comprovante')
                                      ])),
                                  PopupMenuItem(
                                      value: 'delete',
                                      child: Row(children: [
                                        Icon(Icons.delete_outline_rounded,
                                            size: 20),
                                        SizedBox(width: 8),
                                        Text('Excluir')
                                      ])),
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
