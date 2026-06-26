import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/currency_formats.dart';
import '../models/finance_account.dart';
import '../services/functions_service.dart';
import '../theme/app_colors.dart';
import '../utils/firestore_user_doc_id.dart';
import '../utils/finance_transactions_hub.dart';
import 'finance_premium_ui.dart';

/// Resultado da confirmação de pagamento/recebimento.
class FinanceConfirmPaymentSheetResult {
  const FinanceConfirmPaymentSheetResult({
    required this.paymentDate,
    this.financeAccountId,
    this.receiptBytes,
    this.receiptName = '',
    this.receiptMime,
    this.faturaSchedule,
  });

  final DateTime paymentDate;
  /// Conta bancária vinculada ao lançamento (obrigatória na confirmação).
  final String? financeAccountId;
  final Uint8List? receiptBytes;
  final String receiptName;
  final String? receiptMime;
  /// Fechamento de fatura com data futura (só cartão de crédito).
  final FaturaClosureSchedule? faturaSchedule;
}

/// Como tratar pagamento de fatura com data futura.
class FaturaClosureSchedule {
  const FaturaClosureSchedule({
    required this.autoDebitOnDueDate,
  });

  /// `true` = débito automático na conta no vencimento; `false` = pendente para confirmar manualmente.
  final bool autoDebitOnDueDate;
}

/// Sheet premium: data, banco/conta, comprovante (Premium).
Future<FinanceConfirmPaymentSheetResult?> showFinanceConfirmPaymentSheet({
  required BuildContext context,
  required bool isIncome,
  required List<FinanceAccount> financeAccounts,
  String? initialFinanceAccountId,
  String? orphanAccountId,
  bool canAttachReceipt = true,
  double? amountPreview,
  String? categoryPreview,
  String? descriptionPreview,
}) async {
  final now = DateTime.now();
  var selectedFinanceAccountId = initialFinanceAccountId?.trim();
  if (selectedFinanceAccountId != null && selectedFinanceAccountId.isEmpty) {
    selectedFinanceAccountId = null;
  }
  if (financeAccounts.isNotEmpty &&
      (selectedFinanceAccountId == null || selectedFinanceAccountId.isEmpty)) {
    selectedFinanceAccountId = financeAccounts.first.id;
  }

  var dataConfirmacao = now;
  Uint8List? receiptBytes;
  var receiptName = '';
  String? receiptMime;
  const maxBytes = 5 * 1024 * 1024;
  const allowedExt = ['pdf', 'png', 'jpg', 'jpeg'];

  final confirmTitle = isIncome ? 'Confirmar recebimento' : 'Confirmar pagamento';
  final confirmDateLabel = isIncome ? 'Data do recebimento' : 'Data do pagamento';
  final confirmAccent = isIncome ? AppColors.financeReceita : AppColors.financeDespesa;
  final iconGradient = isIncome
      ? const [Color(0xFF14532D), Color(0xFF15803D), Color(0xFF22C55E), AppColors.accent]
      : const [Color(0xFF7F1D1D), Color(0xFFB91C1C), Color(0xFFEF4444), AppColors.logoOrange];

  final rawOrphan = orphanAccountId?.trim() ?? '';

  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setModalState) {
        final orphan = selectedFinanceAccountId != null &&
            selectedFinanceAccountId!.isNotEmpty &&
            !financeAccounts.any((a) => a.id == selectedFinanceAccountId);
        return DraggableScrollableSheet(
          initialChildSize: 0.72,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          expand: false,
          builder: (ctx, scrollController) => Container(
            decoration: financePremiumSheetDecoration(surfaceTint: confirmAccent),
            child: SafeArea(
              top: false,
              child: ListView(
                controller: scrollController,
                padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.paddingOf(ctx).bottom),
                children: [
                  FinancePremiumSheetHeader(
                    title: confirmTitle,
                    subtitle: isIncome
                        ? 'Escolha banco/conta, data e comprovante se quiser'
                        : 'Escolha banco/conta, data do pagamento e comprovante',
                    icon: isIncome ? Icons.arrow_downward_rounded : Icons.payments_rounded,
                    iconGradient: iconGradient,
                    onBack: () => Navigator.pop(ctx, false),
                  ),
                  if (amountPreview != null) ...[
                    const SizedBox(height: 14),
                    _ConfirmAmountPreviewCard(
                      amount: amountPreview,
                      category: categoryPreview,
                      description: descriptionPreview,
                      isIncome: isIncome,
                      accent: confirmAccent,
                    ),
                  ],
                  const SizedBox(height: 16),
                  FinancePremiumFieldTile(
                    label: confirmDateLabel,
                    value: DateFormat('dd/MM/yyyy · HH:mm').format(
                      DateTime(
                        dataConfirmacao.year,
                        dataConfirmacao.month,
                        dataConfirmacao.day,
                        now.hour,
                        now.minute,
                      ),
                    ),
                    icon: Icons.event_available_rounded,
                    accent: confirmAccent,
                    onTap: () async {
                      final p = await showDatePicker(
                        context: ctx,
                        initialDate: dataConfirmacao,
                        firstDate: DateTime(now.year - 2),
                        lastDate: now,
                        helpText: confirmDateLabel,
                      );
                      if (p != null) setModalState(() => dataConfirmacao = p);
                    },
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Banco / conta',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color: confirmAccent.withValues(alpha: 0.92),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (financeAccounts.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.logoOrange.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.logoOrange.withValues(alpha: 0.28)),
                      ),
                      child: Text(
                        rawOrphan.isNotEmpty
                            ? 'Conta anterior removida. Cadastre em Bancos e cartões para vincular.'
                            : 'Cadastre ao menos uma conta em Bancos e cartões para vincular o lançamento.',
                        style: TextStyle(fontSize: 12.5, color: Colors.grey.shade800, height: 1.35),
                      ),
                    )
                  else
                    DropdownButtonFormField<String?>(
                      key: ValueKey<String?>(selectedFinanceAccountId),
                      value: selectedFinanceAccountId,
                      decoration: financePremiumDropdownDecoration(
                        label: isIncome ? 'Banco / conta de recebimento' : 'Banco / conta de pagamento',
                        prefixIcon: Icons.account_balance_rounded,
                        accent: confirmAccent,
                      ),
                      items: [
                        ...financeAccounts.map(
                          (a) => DropdownMenuItem<String?>(
                            value: a.id,
                            child: Text(a.displayName, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                        if (orphan && rawOrphan.isNotEmpty)
                          DropdownMenuItem<String?>(
                            value: rawOrphan,
                            child: const Text('Manter vínculo antigo'),
                          ),
                      ],
                      onChanged: (v) => setModalState(() => selectedFinanceAccountId = v),
                    ),
                  if (canAttachReceipt) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Comprovante',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        color: confirmAccent.withValues(alpha: 0.92),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () async {
                          final pick = await FilePicker.platform.pickFiles(withData: true);
                          if (pick == null || pick.files.isEmpty) return;
                          final f = pick.files.first;
                          final bytes = f.bytes ?? Uint8List(0);
                          var ext = (f.extension ?? '').toLowerCase();
                          if (ext == 'jpeg') ext = 'jpg';
                          if (!allowedExt.contains(ext)) {
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(content: Text('Use PDF, PNG ou JPG.')),
                              );
                            }
                            return;
                          }
                          if (bytes.lengthInBytes > maxBytes) {
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(content: Text('Arquivo grande. Limite 5 MB.')),
                              );
                            }
                            return;
                          }
                          final mime = ext == 'pdf'
                              ? 'application/pdf'
                              : (ext == 'png' ? 'image/png' : 'image/jpeg');
                          setModalState(() {
                            receiptBytes = bytes;
                            receiptName = f.name;
                            receiptMime = mime;
                          });
                        },
                        child: Ink(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: LinearGradient(
                              colors: [
                                confirmAccent.withValues(alpha: 0.10),
                                Colors.white,
                              ],
                            ),
                            border: Border.all(
                              color: receiptBytes != null
                                  ? AppColors.success.withValues(alpha: 0.55)
                                  : confirmAccent.withValues(alpha: 0.28),
                              width: receiptBytes != null ? 2 : 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: confirmAccent.withValues(alpha: 0.08),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: receiptBytes != null
                                        ? [AppColors.success, Color.lerp(AppColors.success, AppColors.accent, 0.3)!]
                                        : [confirmAccent, Color.lerp(confirmAccent, AppColors.accent, 0.35)!],
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  receiptBytes != null
                                      ? Icons.check_circle_rounded
                                      : Icons.cloud_upload_outlined,
                                  color: Colors.white,
                                  size: 26,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      receiptBytes != null ? 'Comprovante anexado' : 'Anexar comprovante',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 14,
                                        color: confirmAccent.withValues(alpha: 0.95),
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      receiptBytes != null
                                          ? receiptName
                                          : 'PDF, PNG ou JPG · até 5 MB (opcional)',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade700,
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (receiptBytes != null)
                                IconButton(
                                  tooltip: 'Remover comprovante',
                                  onPressed: () => setModalState(() {
                                    receiptBytes = null;
                                    receiptName = '';
                                    receiptMime = null;
                                  }),
                                  icon: Icon(Icons.close_rounded, color: Colors.grey.shade600),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  FinancePremiumSheetActions(
                    confirmLabel: 'Confirmar',
                    confirmColor: confirmAccent,
                    confirmIcon: Icons.check_circle_rounded,
                    onConfirm: () {
                      if (financeAccounts.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Cadastre ao menos uma conta em Bancos e cartões para confirmar.',
                            ),
                          ),
                        );
                        return;
                      }
                      if (selectedFinanceAccountId == null ||
                          selectedFinanceAccountId!.trim().isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text(
                              isIncome
                                  ? 'Selecione o banco/conta do recebimento.'
                                  : 'Selecione o banco/conta do pagamento.',
                            ),
                          ),
                        );
                        return;
                      }
                      Navigator.pop(ctx, true);
                    },
                    onCancel: () => Navigator.pop(ctx, false),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  if (confirmed != true) return null;

  return FinanceConfirmPaymentSheetResult(
    paymentDate: dataConfirmacao,
    financeAccountId: selectedFinanceAccountId?.trim(),
    receiptBytes: receiptBytes,
    receiptName: receiptName,
    receiptMime: receiptMime,
  );
}

/// Grava confirmação no Firestore (+ comprovante Premium no Storage).
Future<void> commitFinanceConfirmPayment({
  required DocumentReference<Map<String, dynamic>> txRef,
  required String uid,
  required FinanceConfirmPaymentSheetResult result,
  bool creditCardFaturaPayment = false,
}) async {
  final confTs = Timestamp.fromDate(result.paymentDate);
  final updateData = <String, dynamic>{
    'status': 'paid',
    'paidAt': confTs,
    'effectiveDate': confTs,
    'updatedAt': FieldValue.serverTimestamp(),
  };
  final aid = result.financeAccountId?.trim() ?? '';
  if (creditCardFaturaPayment) {
    if (aid.isNotEmpty) {
      updateData['paidFromFinanceAccountId'] = aid;
    } else {
      updateData['paidFromFinanceAccountId'] = FieldValue.delete();
    }
  } else if (aid.isEmpty) {
    updateData['financeAccountId'] = FieldValue.delete();
  } else {
    updateData['financeAccountId'] = aid;
  }
  await txRef.update(updateData);
  if (result.receiptBytes != null &&
      result.receiptName.isNotEmpty &&
      result.receiptMime != null &&
      result.receiptBytes!.isNotEmpty) {
    final fn = FunctionsService();
    final fsId = firestoreUserDocIdForAppShell(uid);
    final txPath = 'users/$fsId/transactions/${txRef.id}';
    await fn.uploadReceiptToStorage(
      txPath: txPath,
      filename: result.receiptName,
      bytes: result.receiptBytes!,
      mimeType: result.receiptMime!,
    );
    await txRef.update({
      'hasReceipt': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
  FinanceTransactionsHub.notifyMutated(
    uid: uid,
    effectiveDate: result.paymentDate,
    invalidateOpeningBalance: false,
  );
}

/// Sheet premium em lote: mesma data + mesmo banco para todos (sem comprovante).
Future<FinanceConfirmPaymentSheetResult?> showFinanceConfirmPaymentBatchSheet({
  required BuildContext context,
  required bool isIncome,
  required List<FinanceAccount> financeAccounts,
  required int itemCount,
  double? totalAmountPreview,
  bool creditCardFaturaPayment = false,
  String? cardDisplayName,
}) async {
  final now = DateTime.now();
  var selectedFinanceAccountId =
      financeAccounts.isNotEmpty ? financeAccounts.first.id : null;
  var dataConfirmacao = now;

  final confirmTitle = creditCardFaturaPayment
      ? 'Pagar fatura do cartão'
      : (isIncome ? 'Confirmar recebimentos em lote' : 'Confirmar pagamentos em lote');
  final confirmDateLabel = isIncome ? 'Data do recebimento' : 'Data do pagamento';
  final confirmAccent = creditCardFaturaPayment
      ? const Color(0xFF4F46E5)
      : (isIncome ? AppColors.financeReceita : AppColors.financeDespesa);
  final iconGradient = creditCardFaturaPayment
      ? const [Color(0xFF312E81), Color(0xFF4F46E5), Color(0xFF6366F1)]
      : (isIncome
          ? const [Color(0xFF14532D), Color(0xFF15803D), Color(0xFF22C55E), AppColors.accent]
          : const [Color(0xFF7F1D1D), Color(0xFFB91C1C), Color(0xFFEF4444), AppColors.logoOrange]);
  final cardLabel = (cardDisplayName ?? '').trim();
  var faturaFutureMode = const FaturaClosureSchedule(autoDebitOnDueDate: true);

  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setModalState) {
        return DraggableScrollableSheet(
          initialChildSize: 0.58,
          minChildSize: 0.42,
          maxChildSize: 0.88,
          expand: false,
          builder: (ctx, scrollController) => Container(
            decoration: financePremiumSheetDecoration(surfaceTint: confirmAccent),
            child: SafeArea(
              top: false,
              child: ListView(
                controller: scrollController,
                padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.paddingOf(ctx).bottom),
                children: [
                  FinancePremiumSheetHeader(
                    title: confirmTitle,
                    subtitle: creditCardFaturaPayment
                        ? (cardLabel.isNotEmpty
                            ? 'De qual banco sairá o pagamento da fatura de $cardLabel? ($itemCount lançamento(s))'
                            : 'Escolha o banco de onde sairá o dinheiro ($itemCount lançamento(s))')
                        : (isIncome
                            ? 'Mesma data e banco/conta de recebimento para os $itemCount itens'
                            : 'Mesma data e banco/conta para os $itemCount itens · sem comprovante em lote'),
                    icon: Icons.done_all_rounded,
                    iconGradient: iconGradient,
                    onBack: () => Navigator.pop(ctx, false),
                  ),
                  const SizedBox(height: 14),
                  _BatchConfirmCountCard(
                    count: itemCount,
                    isIncome: isIncome,
                    accent: confirmAccent,
                    totalAmount: totalAmountPreview,
                  ),
                  const SizedBox(height: 16),
                  FinancePremiumFieldTile(
                    label: creditCardFaturaPayment ? 'Data do pagamento / fechamento' : confirmDateLabel,
                    value: DateFormat('dd/MM/yyyy · HH:mm').format(
                      DateTime(
                        dataConfirmacao.year,
                        dataConfirmacao.month,
                        dataConfirmacao.day,
                        now.hour,
                        now.minute,
                      ),
                    ),
                    icon: Icons.event_available_rounded,
                    accent: confirmAccent,
                    onTap: () async {
                      final p = await showDatePicker(
                        context: ctx,
                        initialDate: dataConfirmacao,
                        firstDate: DateTime(now.year - 2),
                        lastDate: creditCardFaturaPayment
                            ? DateTime(now.year + 2, 12, 31)
                            : now,
                        helpText: creditCardFaturaPayment
                            ? 'Data do pagamento da fatura'
                            : confirmDateLabel,
                      );
                      if (p != null) setModalState(() => dataConfirmacao = p);
                    },
                  ),
                  if (creditCardFaturaPayment) ...[
                    Builder(
                      builder: (context) {
                        final payDay = DateTime(
                          dataConfirmacao.year,
                          dataConfirmacao.month,
                          dataConfirmacao.day,
                        );
                        final today = DateTime(now.year, now.month, now.day);
                        if (!payDay.isAfter(today)) return const SizedBox.shrink();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEEF2FF),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFF4F46E5).withValues(alpha: 0.28),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Pagamento em ${DateFormat('dd/MM/yyyy').format(payDay)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                      color: Color(0xFF312E81),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Escolha como registrar o fechamento da fatura:',
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.35,
                                      color: Colors.grey.shade800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            SegmentedButton<bool>(
                              segments: const [
                                ButtonSegment(
                                  value: true,
                                  label: Text('Débito automático', style: TextStyle(fontSize: 11)),
                                  icon: Icon(Icons.schedule_send_rounded, size: 18),
                                ),
                                ButtonSegment(
                                  value: false,
                                  label: Text('Confirmar no dia', style: TextStyle(fontSize: 11)),
                                  icon: Icon(Icons.touch_app_rounded, size: 18),
                                ),
                              ],
                              selected: {faturaFutureMode.autoDebitOnDueDate},
                              onSelectionChanged: (s) {
                                setModalState(
                                  () => faturaFutureMode = FaturaClosureSchedule(
                                    autoDebitOnDueDate: s.first,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 8),
                            Text(
                              faturaFutureMode.autoDebitOnDueDate
                                  ? 'Em ${DateFormat('dd/MM/yyyy').format(payDay)} o valor sairá automaticamente da conta escolhida (ao abrir o app nessa data).'
                                  : 'Os lançamentos ficam na fatura até ${DateFormat('dd/MM/yyyy').format(payDay)} para você confirmar o pagamento manualmente.',
                              style: TextStyle(
                                fontSize: 11.5,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 14),
                  Text(
                    creditCardFaturaPayment ? 'Banco que paga a fatura' : 'Banco / conta (todos)',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color: confirmAccent.withValues(alpha: 0.92),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (financeAccounts.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.logoOrange.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.logoOrange.withValues(alpha: 0.28)),
                      ),
                      child: Text(
                        'Cadastre ao menos uma conta em Bancos e cartões para confirmar.',
                        style: TextStyle(fontSize: 12.5, color: Colors.grey.shade800, height: 1.35),
                      ),
                    )
                  else
                    DropdownButtonFormField<String?>(
                      key: ValueKey<String?>(selectedFinanceAccountId),
                      value: selectedFinanceAccountId,
                      decoration: financePremiumDropdownDecoration(
                        label: isIncome ? 'Banco / conta de recebimento (todos)' : 'Banco / conta de pagamento (todos)',
                        prefixIcon: Icons.account_balance_rounded,
                        accent: confirmAccent,
                      ),
                      items: [
                        ...financeAccounts.map(
                          (a) => DropdownMenuItem<String?>(
                            value: a.id,
                            child: Text(a.displayName, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                      onChanged: (v) => setModalState(() => selectedFinanceAccountId = v),
                    ),
                  const SizedBox(height: 10),
                  Text(
                    'Comprovantes não estão disponíveis em lote. Confirme um a um se precisar anexar.',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 22),
                  FinancePremiumSheetActions(
                    confirmLabel: creditCardFaturaPayment
                        ? 'Gerar fechamento ($itemCount)'
                        : 'Confirmar todos ($itemCount)',
                    confirmColor: confirmAccent,
                    confirmIcon: Icons.done_all_rounded,
                    onConfirm: () {
                      final payDay = DateTime(
                        dataConfirmacao.year,
                        dataConfirmacao.month,
                        dataConfirmacao.day,
                      );
                      final today = DateTime(now.year, now.month, now.day);
                      final futureManual = creditCardFaturaPayment &&
                          payDay.isAfter(today) &&
                          !faturaFutureMode.autoDebitOnDueDate;
                      if (!futureManual) {
                        if (financeAccounts.isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Cadastre ao menos uma conta em Bancos e cartões para confirmar.',
                              ),
                            ),
                          );
                          return;
                        }
                        if (selectedFinanceAccountId == null ||
                            selectedFinanceAccountId!.trim().isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text(
                                isIncome
                                    ? 'Selecione o banco/conta para todos os recebimentos.'
                                    : 'Selecione o banco/conta para todos os pagamentos.',
                              ),
                            ),
                          );
                          return;
                        }
                      }
                      Navigator.pop(ctx, true);
                    },
                    onCancel: () => Navigator.pop(ctx, false),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  if (confirmed != true) return null;

  final payDay = DateTime(
    dataConfirmacao.year,
    dataConfirmacao.month,
    dataConfirmacao.day,
  );
  final today = DateTime(now.year, now.month, now.day);
  final FaturaClosureSchedule? schedule = creditCardFaturaPayment && payDay.isAfter(today)
      ? faturaFutureMode
      : null;

  return FinanceConfirmPaymentSheetResult(
    paymentDate: dataConfirmacao,
    financeAccountId: selectedFinanceAccountId?.trim(),
    faturaSchedule: schedule,
  );
}

/// Grava confirmação em lote (mesma data/conta; sem comprovante).
Future<void> commitFinanceConfirmPaymentBatch({
  required CollectionReference<Map<String, dynamic>> txCol,
  required List<String> docIds,
  required String uid,
  required FinanceConfirmPaymentSheetResult result,
  bool creditCardFaturaPayment = false,
}) async {
  final unique = docIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
  if (unique.isEmpty) return;

  final confTs = Timestamp.fromDate(result.paymentDate);
  final updatedAt = FieldValue.serverTimestamp();
  final aid = result.financeAccountId?.trim() ?? '';
  final payDay = DateTime(
    result.paymentDate.year,
    result.paymentDate.month,
    result.paymentDate.day,
  );
  final today = DateTime.now();
  final todayDay = DateTime(today.year, today.month, today.day);
  final scheduleFuture = creditCardFaturaPayment &&
      result.faturaSchedule != null &&
      payDay.isAfter(todayDay);

  for (var i = 0; i < unique.length; i += 400) {
    final end = i + 400 < unique.length ? i + 400 : unique.length;
    final chunk = unique.sublist(i, end);
    final batch = FirebaseFirestore.instance.batch();
    for (final id in chunk) {
      final updateData = <String, dynamic>{
        'updatedAt': updatedAt,
      };
      if (scheduleFuture) {
        final sched = result.faturaSchedule!;
        updateData['status'] = 'pending';
        updateData['faturaPaymentScheduledAt'] = confTs;
        updateData['faturaClosedAt'] = Timestamp.fromDate(DateTime.now());
        updateData['faturaAutoDebit'] = sched.autoDebitOnDueDate;
        if (sched.autoDebitOnDueDate && aid.isNotEmpty) {
          updateData['paidFromFinanceAccountId'] = aid;
        } else if (!sched.autoDebitOnDueDate) {
          updateData['paidFromFinanceAccountId'] = FieldValue.delete();
        }
      } else {
        updateData['status'] = 'paid';
        updateData['paidAt'] = confTs;
        updateData['effectiveDate'] = confTs;
        updateData['faturaPaymentScheduledAt'] = FieldValue.delete();
        updateData['faturaClosedAt'] = FieldValue.delete();
        updateData['faturaAutoDebit'] = FieldValue.delete();
        if (creditCardFaturaPayment) {
          if (aid.isNotEmpty) {
            updateData['paidFromFinanceAccountId'] = aid;
          } else {
            updateData['paidFromFinanceAccountId'] = FieldValue.delete();
          }
        } else if (aid.isEmpty) {
          updateData['financeAccountId'] = FieldValue.delete();
        } else {
          updateData['financeAccountId'] = aid;
        }
      }
      batch.update(txCol.doc(id), updateData);
    }
    await batch.commit();
  }

  FinanceTransactionsHub.notifyMutated(
    uid: uid,
    effectiveDate: result.paymentDate,
    invalidateOpeningBalance: false,
  );
}

/// Confirma débitos de fatura agendados cuja data já chegou (ao abrir o Financeiro).
Future<int> processDueFaturaScheduledPayments({
  required CollectionReference<Map<String, dynamic>> txCol,
  required String uid,
}) async {
  final now = DateTime.now();
  final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
  final snap = await txCol
      .where('status', isEqualTo: 'pending')
      .where('faturaAutoDebit', isEqualTo: true)
      .limit(200)
      .get();
  var n = 0;
  for (final doc in snap.docs) {
    final d = doc.data();
    final sched = d['faturaPaymentScheduledAt'];
    if (sched is! Timestamp) continue;
    final due = sched.toDate();
    if (due.isAfter(todayEnd)) continue;
    final paidFrom = (d['paidFromFinanceAccountId'] ?? '').toString().trim();
    final confTs = Timestamp.fromDate(due);
    await doc.reference.update({
      'status': 'paid',
      'paidAt': confTs,
      'effectiveDate': confTs,
      'faturaPaymentScheduledAt': FieldValue.delete(),
      'faturaClosedAt': FieldValue.delete(),
      'faturaAutoDebit': FieldValue.delete(),
      if (paidFrom.isNotEmpty) 'paidFromFinanceAccountId': paidFrom,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    n++;
  }
  if (n > 0) {
    FinanceTransactionsHub.notifyMutated(uid: uid, invalidateOpeningBalance: false);
  }
  return n;
}

class _BatchConfirmCountCard extends StatelessWidget {
  const _BatchConfirmCountCard({
    required this.count,
    required this.isIncome,
    required this.accent,
    this.totalAmount,
  });

  final int count;
  final bool isIncome;
  final Color accent;
  final double? totalAmount;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.18),
            accent.withValues(alpha: 0.06),
            Colors.white,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(color: accent.withValues(alpha: 0.12), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [accent, accent.withValues(alpha: 0.75)]),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.layers_rounded, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count ${isIncome ? 'receita(s)' : 'despesa(s)'} selecionada(s)',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: accent,
                    ),
                  ),
                  if (totalAmount != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Total: ${CurrencyFormats.formatBRL(totalAmount!.abs())}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmAmountPreviewCard extends StatelessWidget {
  const _ConfirmAmountPreviewCard({
    required this.amount,
    required this.isIncome,
    required this.accent,
    this.category,
    this.description,
  });

  final double amount;
  final bool isIncome;
  final Color accent;
  final String? category;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final cat = (category ?? '').trim();
    final desc = (description ?? '').trim();
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.16),
            accent.withValues(alpha: 0.06),
            Colors.white,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(color: accent.withValues(alpha: 0.12), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              CurrencyFormats.formatBRL(amount.abs()),
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: accent,
                height: 1.05,
              ),
            ),
            if (cat.isNotEmpty || desc.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                [if (cat.isNotEmpty) cat, if (desc.isNotEmpty) desc].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
