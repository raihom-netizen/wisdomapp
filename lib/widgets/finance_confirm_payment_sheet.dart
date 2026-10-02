import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide showDatePicker;
import '../theme/theme_context.dart';
import 'package:intl/intl.dart';

import '../constants/currency_formats.dart';
import '../models/finance_account.dart';
import '../services/functions_service.dart';
import '../theme/app_colors.dart';
import '../utils/date_picker_a11y.dart';
import '../utils/finance_transaction_datetime.dart';
import '../utils/finance_transactions_hub.dart';
import '../utils/firestore_user_doc_id.dart';
import '../utils/receipt_attachment_utils.dart';
import 'brl_amount_text_field.dart';
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
    this.paidIdsOverride,
    this.valorPagoInformado,
    this.deixaEmAbertoIds,
  });

  final DateTime paymentDate;

  /// Conta bancária vinculada ao lançamento (obrigatória na confirmação).
  final String? financeAccountId;
  final Uint8List? receiptBytes;
  final String receiptName;
  final String? receiptMime;

  /// Fechamento de fatura com data futura (só cartão de crédito).
  final FaturaClosureSchedule? faturaSchedule;

  /// Pagamento PARCIAL da fatura (pedido de 21/09/2026): quando o valor pago
  /// informado é menor que o total selecionado, só estes ids devem ser
  /// marcados como pagos — os demais ([deixaEmAbertoIds]) continuam em
  /// aberto. `null` = paga todos os ids selecionados, como antes.
  final List<String>? paidIdsOverride;

  /// O valor que o usuário disse que pagou de fato — pode ser diferente da
  /// soma dos lançamentos selecionados (pagou menos, uma parcela, etc.).
  final double? valorPagoInformado;

  /// Os lançamentos que ficam pendentes por causa do pagamento parcial.
  final List<String>? deixaEmAbertoIds;
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

  final confirmTitle =
      isIncome ? 'Confirmar recebimento' : 'Confirmar pagamento';
  final confirmDateLabel =
      isIncome ? 'Data do recebimento' : 'Data do pagamento';
  final confirmAccent =
      isIncome ? AppColors.financeReceita : AppColors.financeDespesa;
  final iconGradient = isIncome
      ? const [
          Color(0xFF14532D),
          Color(0xFF15803D),
          Color(0xFF22C55E),
          AppColors.accent
        ]
      : const [
          Color(0xFF7F1D1D),
          Color(0xFFB91C1C),
          Color(0xFFEF4444),
          AppColors.logoOrange
        ];

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
            decoration: financePremiumSheetDecoration(
                surfaceTint: confirmAccent, context: context),
            child: SafeArea(
              top: false,
              child: ListView(
                controller: scrollController,
                padding: EdgeInsets.fromLTRB(
                    20, 0, 20, 20 + MediaQuery.paddingOf(ctx).bottom),
                children: [
                  FinancePremiumSheetHeader(
                    title: confirmTitle,
                    subtitle: isIncome
                        ? 'Escolha banco/conta, data e comprovante se quiser'
                        : 'Escolha banco/conta, data do pagamento e comprovante',
                    icon: isIncome
                        ? Icons.arrow_downward_rounded
                        : Icons.payments_rounded,
                    iconGradient: iconGradient,
                    onBack: () => Navigator.pop(ctx, false),
                  ),
                  if (amountPreview != null) ...[
                    SizedBox(height: 14),
                    _ConfirmAmountPreviewCard(
                      amount: amountPreview,
                      category: categoryPreview,
                      description: descriptionPreview,
                      isIncome: isIncome,
                      accent: confirmAccent,
                    ),
                  ],
                  SizedBox(height: 16),
                  FinancePremiumFieldTile(
                    label: confirmDateLabel,
                    value: DateFormat('dd/MM/yyyy · HH:mm')
                        .format(dataConfirmacao),
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
                      if (p != null) {
                        setModalState(() => dataConfirmacao =
                            FinanceTransactionDatetime
                                .mergeCalendarDayWithExistingTime(
                                    p, dataConfirmacao));
                      }
                    },
                  ),
                  SizedBox(height: 10),
                  FinancePremiumFieldTile(
                    label: 'Horário',
                    value: DateFormat('HH:mm').format(dataConfirmacao),
                    icon: Icons.schedule_rounded,
                    accent: confirmAccent,
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: ctx,
                        initialTime: TimeOfDay(
                          hour: dataConfirmacao.hour,
                          minute: dataConfirmacao.minute,
                        ),
                        helpText: 'Horário',
                        hourLabelText: 'Hora',
                        minuteLabelText: 'Minuto',
                        builder: (context, child) {
                          return MediaQuery(
                            data: MediaQuery.of(context)
                                .copyWith(alwaysUse24HourFormat: true),
                            child: child ?? const SizedBox.shrink(),
                          );
                        },
                      );
                      if (picked != null) {
                        setModalState(() => dataConfirmacao =
                                FinanceTransactionDatetime
                                    .mergeCalendarDayWithTimeOfDay(
                              dataConfirmacao,
                              picked.hour,
                              picked.minute,
                            ));
                      }
                    },
                  ),
                  SizedBox(height: 14),
                  Text(
                    'Banco / conta',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color: confirmAccent.withValues(alpha: 0.92),
                    ),
                  ),
                  SizedBox(height: 8),
                  if (financeAccounts.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.logoOrange.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color:
                                AppColors.logoOrange.withValues(alpha: 0.28)),
                      ),
                      child: Text(
                        rawOrphan.isNotEmpty
                            ? 'Conta anterior removida. Cadastre em Bancos e cartões para vincular.'
                            : 'Cadastre ao menos uma conta em Bancos e cartões para vincular o lançamento.',
                        style: TextStyle(
                            fontSize: 12.5,
                            color: context.appTextPrimary,
                            height: 1.35),
                      ),
                    )
                  else
                    DropdownButtonFormField<String?>(
                      key: ValueKey<String?>(selectedFinanceAccountId),
                      initialValue: selectedFinanceAccountId,
                      decoration: financePremiumDropdownDecoration(
                        context,
                        label: isIncome
                            ? 'Banco / conta de recebimento'
                            : 'Banco / conta de pagamento',
                        prefixIcon: Icons.account_balance_rounded,
                        accent: confirmAccent,
                      ),
                      items: [
                        ...financeAccounts.map(
                          (a) => DropdownMenuItem<String?>(
                            value: a.id,
                            child: Text(a.displayName,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ),
                        if (orphan && rawOrphan.isNotEmpty)
                          DropdownMenuItem<String?>(
                            value: rawOrphan,
                            child: Text('Manter vínculo antigo'),
                          ),
                      ],
                      onChanged: (v) =>
                          setModalState(() => selectedFinanceAccountId = v),
                    ),
                  if (canAttachReceipt) ...[
                    SizedBox(height: 16),
                    Text(
                      'Comprovante',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        color: confirmAccent.withValues(alpha: 0.92),
                      ),
                    ),
                    SizedBox(height: 8),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () async {
                          final picked =
                              await ReceiptAttachmentUtils.pickValidated(ctx);
                          if (picked == null) return;
                          setModalState(() {
                            receiptBytes = picked.bytes;
                            receiptName = picked.name;
                            receiptMime = picked.mime;
                          });
                        },
                        child: Ink(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: LinearGradient(
                              colors: [
                                confirmAccent.withValues(alpha: 0.10),
                                context.appDarkModuleSurface,
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 18),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: receiptBytes != null
                                        ? [
                                            AppColors.success,
                                            Color.lerp(AppColors.success,
                                                AppColors.accent, 0.3)!
                                          ]
                                        : [
                                            confirmAccent,
                                            Color.lerp(confirmAccent,
                                                AppColors.accent, 0.35)!
                                          ],
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
                              SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      receiptBytes != null
                                          ? 'Comprovante anexado'
                                          : 'Anexar comprovante',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 14,
                                        color: confirmAccent.withValues(
                                            alpha: 0.95),
                                      ),
                                    ),
                                    SizedBox(height: 3),
                                    Text(
                                      receiptBytes != null
                                          ? receiptName
                                          : 'PDF, PNG ou JPG · até 5 MB (opcional)',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: context.appTextSecondary,
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
                                  icon: Icon(Icons.close_rounded,
                                      color: context.appTextSecondary),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  SizedBox(height: 22),
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
    paymentDate: FinanceTransactionDatetime.withoutSeconds(dataConfirmacao),
    financeAccountId: selectedFinanceAccountId?.trim(),
    receiptBytes: receiptBytes,
    receiptName: receiptName,
    receiptMime: receiptMime,
  );
}

/// Grava confirmação no Firestore (+ comprovante Premium no Storage).
///
/// Retorna a mensagem ESPECIAL para o usuário (ou null = mensagem normal do
/// chamador). No WISDOMAPP (sem Finance Pro) é sempre null: não existe a
/// quitação «só de controle» do Controle Total.
Future<String?> commitFinanceConfirmPayment({
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
  const String? mensagem = null;
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
    final fsId = firestoreUserDocIdForAppShell(uid);
    await FunctionsService().uploadReceiptToStorage(
      txPath: 'users/$fsId/transactions/${txRef.id}',
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
  return mensagem;
}

/// Um lançamento selecionado para pagar em lote — usado só para calcular o
/// pagamento PARCIAL da fatura (quais ids ficam pagos quando o valor pago é
/// menor que o total).
class FinanceBatchPayableItem {
  const FinanceBatchPayableItem({required this.id, required this.amount, required this.date});
  final String id;
  final double amount;
  final DateTime date;
}

/// Sheet premium em lote: mesma data + mesmo banco para todos (sem comprovante).
///
/// [payableItems]: só para `creditCardFaturaPayment` — habilita o campo
/// «Valor pago» (o usuário às vezes não paga a fatura inteira: parcela,
/// pagamento parcial). Menor que o total → só os lançamentos mais antigos,
/// até esse valor, saem como pagos; o resto continua em aberto.
Future<FinanceConfirmPaymentSheetResult?> showFinanceConfirmPaymentBatchSheet({
  required BuildContext context,
  required bool isIncome,
  required List<FinanceAccount> financeAccounts,
  required int itemCount,
  double? totalAmountPreview,
  bool creditCardFaturaPayment = false,
  String? cardDisplayName,
  List<FinanceBatchPayableItem>? payableItems,
  /// Fatura ATUAL informada pelo banco (`FinanceAccount.faturaAtualBanco`) —
  /// só passada quando [payableItems] representa TODO o pendente do cartão
  /// (o botão principal «Gerar fechamento / Pagar fatura»). Some/é nula em
  /// pagamento parcial manual ou cartão sem sincronização — nesse caso o
  /// comportamento é o de sempre (default = soma de tudo em aberto).
  double? bankOfficialTotal,
  /// De qual conta o dinheiro provavelmente sai (pedido de 22/09/2026) —
  /// detectado pelo chamador (ex.: mesma instituição do cartão, conectada
  /// via Open Finance). Só define o valor INICIAL do seletor; o usuário
  /// sempre pode trocar no dropdown abaixo (nunca é travado).
  String? preferredFinanceAccountId,
}) async {
  final now = DateTime.now();
  final preferredId = preferredFinanceAccountId?.trim();
  final hasPreferred = preferredId != null &&
      preferredId.isNotEmpty &&
      financeAccounts.any((a) => a.id == preferredId);
  var selectedFinanceAccountId = hasPreferred
      ? preferredId
      : (financeAccounts.isNotEmpty ? financeAccounts.first.id : null);
  var dataConfirmacao = now;
  final totalSelecionado = totalAmountPreview ?? 0;
  final permiteValorPago = creditCardFaturaPayment && payableItems != null && payableItems.isNotEmpty;
  // Valor oficial do banco (fatura fechada) × soma de tudo em aberto no
  // cartão (inclui compras já previstas para faturas futuras). Pedido de
  // 22/09/2026: deixar o usuário escolher qual dos dois valores pagar — o
  // default passa a ser o do banco (o correto), preservando a edição manual.
  final bankTotal = (permiteValorPago && bankOfficialTotal != null && bankOfficialTotal > 0.005)
      ? bankOfficialTotal
      : null;
  final mostrarEscolhaValor = bankTotal != null && (bankTotal - totalSelecionado).abs() > 0.01;
  final valorInicial = bankTotal ?? totalSelecionado;
  var origemValorPago = bankTotal != null ? _OrigemValorPago.banco : _OrigemValorPago.todos;
  final valorPagoCtrl = TextEditingController(
    text: CurrencyFormats.formatBRLInputFromCents((valorInicial * 100).round()),
  );
  var valorPago = valorInicial;
  // Ids que ficam de fora quando o valor pago é menor que o total — oldest
  // first (o mais antigo é o primeiro a ser dado como pago).
  List<String> calcularDeixaEmAberto(double valorPago) {
    if (!permiteValorPago) return const [];
    if (valorPago >= totalSelecionado - 0.005) return const [];
    final ordenados = [...payableItems]..sort((a, b) => a.date.compareTo(b.date));
    var acumulado = 0.0;
    final foraDoPagamento = <String>[];
    for (final item in ordenados) {
      acumulado += item.amount;
      if (acumulado > valorPago + 0.005) foraDoPagamento.add(item.id);
    }
    return foraDoPagamento;
  }

  final confirmTitle = creditCardFaturaPayment
      ? 'Pagar fatura do cartão'
      : (isIncome
          ? 'Confirmar recebimentos em lote'
          : 'Confirmar pagamentos em lote');
  final confirmDateLabel =
      isIncome ? 'Data do recebimento' : 'Data do pagamento';
  final confirmAccent = creditCardFaturaPayment
      ? const Color(0xFF4F46E5)
      : (isIncome ? AppColors.financeReceita : AppColors.financeDespesa);
  final iconGradient = creditCardFaturaPayment
      ? const [Color(0xFF312E81), Color(0xFF4F46E5), Color(0xFF6366F1)]
      : (isIncome
          ? const [
              Color(0xFF14532D),
              Color(0xFF15803D),
              Color(0xFF22C55E),
              AppColors.accent
            ]
          : const [
              Color(0xFF7F1D1D),
              Color(0xFFB91C1C),
              Color(0xFFEF4444),
              AppColors.logoOrange
            ]);
  final cardLabel = (cardDisplayName ?? '').trim();
  var faturaFutureMode = const FaturaClosureSchedule(autoDebitOnDueDate: true);

  List<Widget> construirCampos(BuildContext ctx, StateSetter setModalState) {
    return [
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
                  SizedBox(height: 14),
                  _BatchConfirmCountCard(
                    count: itemCount,
                    isIncome: isIncome,
                    accent: confirmAccent,
                    totalAmount: totalAmountPreview,
                  ),
                  // Valor pago de fato (pedido de 21/09/2026): às vezes o
                  // usuário não paga a fatura inteira — parcela, pagamento
                  // parcial. Menor que o total selecionado só dá como pago
                  // os lançamentos mais antigos até esse valor; o resto
                  // continua em aberto (nunca soma como se tivesse pago tudo).
                  if (permiteValorPago) ...[
                    SizedBox(height: 16),
                    Text(
                      'Quanto você pagou de fato?',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        color: confirmAccent.withValues(alpha: 0.92),
                      ),
                    ),
                    if (mostrarEscolhaValor) ...[
                      SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _ValorPagoQuickPick(
                              label: 'Fatura do banco',
                              sublabel: 'o que fecha agora',
                              value: bankTotal,
                              icon: Icons.account_balance_rounded,
                              accent: confirmAccent,
                              selected: origemValorPago == _OrigemValorPago.banco,
                              onTap: () => setModalState(() {
                                origemValorPago = _OrigemValorPago.banco;
                                valorPago = bankTotal;
                                valorPagoCtrl.text =
                                    CurrencyFormats.formatBRLInputFromCents((bankTotal * 100).round());
                              }),
                            ),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: _ValorPagoQuickPick(
                              label: 'Tudo em aberto',
                              sublabel: 'inclui faturas futuras',
                              value: totalSelecionado,
                              icon: Icons.layers_rounded,
                              accent: confirmAccent,
                              selected: origemValorPago == _OrigemValorPago.todos,
                              onTap: () => setModalState(() {
                                origemValorPago = _OrigemValorPago.todos;
                                valorPago = totalSelecionado;
                                valorPagoCtrl.text =
                                    CurrencyFormats.formatBRLInputFromCents((totalSelecionado * 100).round());
                              }),
                            ),
                          ),
                        ],
                      ),
                    ],
                    SizedBox(height: 8),
                    BrlAmountTextField(
                      controller: valorPagoCtrl,
                      labelText: 'Valor pago',
                      decoration: InputDecoration(
                        labelText: 'Valor pago',
                        prefixIcon: const Icon(Icons.payments_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onChanged: (_) {
                        final novo = CurrencyFormats.parseBRLInput(valorPagoCtrl.text);
                        setModalState(() {
                          valorPago = novo ?? valorPago;
                          // Editou à mão: não corresponde mais a nenhum dos
                          // atalhos — os dois cartões ficam sem destaque.
                          origemValorPago = _OrigemValorPago.manual;
                        });
                      },
                    ),
                    SizedBox(height: 8),
                    Builder(builder: (context) {
                      if (valorPago > totalSelecionado + 0.005) {
                        return _avisoValorPago(
                          context,
                          icon: Icons.error_outline_rounded,
                          texto:
                              'O valor pago não pode passar do total selecionado (${CurrencyFormats.formatBRL(totalSelecionado)}). Selecione mais lançamentos ou ajuste o valor.',
                          cor: AppColors.error,
                        );
                      }
                      final fora = calcularDeixaEmAberto(valorPago);
                      if (fora.isEmpty) {
                        return _avisoValorPago(
                          context,
                          icon: Icons.check_circle_rounded,
                          texto: 'Paga a fatura selecionada por inteiro.',
                          cor: const Color(0xFF16A34A),
                        );
                      }
                      final diferenca = totalSelecionado - valorPago;
                      if (origemValorPago == _OrigemValorPago.banco) {
                        return _avisoValorPago(
                          context,
                          icon: Icons.account_balance_rounded,
                          texto:
                              'Pagando a fatura fechada pelo banco. ${CurrencyFormats.formatBRL(diferenca)} em ${fora.length} lançamento(s) já são de fatura(s) futuras e continuam em aberto.',
                          cor: confirmAccent,
                        );
                      }
                      return _avisoValorPago(
                        context,
                        icon: Icons.info_outline_rounded,
                        texto:
                            'Pagamento parcial: ${CurrencyFormats.formatBRL(diferenca)} continua(m) em aberto em ${fora.length} lançamento(s) — os mais antigos entram como pagos primeiro.',
                        cor: AppColors.logoOrange,
                      );
                    }),
                  ],
                  SizedBox(height: 16),
                  FinancePremiumFieldTile(
                    label: creditCardFaturaPayment
                        ? 'Data do pagamento / fechamento'
                        : confirmDateLabel,
                    value: DateFormat('dd/MM/yyyy · HH:mm')
                        .format(dataConfirmacao),
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
                      if (p != null) {
                        setModalState(() => dataConfirmacao =
                            FinanceTransactionDatetime
                                .mergeCalendarDayWithExistingTime(
                                    p, dataConfirmacao));
                      }
                    },
                  ),
                  SizedBox(height: 10),
                  FinancePremiumFieldTile(
                    label: 'Horário',
                    value: DateFormat('HH:mm').format(dataConfirmacao),
                    icon: Icons.schedule_rounded,
                    accent: confirmAccent,
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: ctx,
                        initialTime: TimeOfDay(
                          hour: dataConfirmacao.hour,
                          minute: dataConfirmacao.minute,
                        ),
                        helpText: 'Horário',
                        hourLabelText: 'Hora',
                        minuteLabelText: 'Minuto',
                        builder: (context, child) {
                          return MediaQuery(
                            data: MediaQuery.of(context)
                                .copyWith(alwaysUse24HourFormat: true),
                            child: child ?? const SizedBox.shrink(),
                          );
                        },
                      );
                      if (picked != null) {
                        setModalState(() => dataConfirmacao =
                                FinanceTransactionDatetime
                                    .mergeCalendarDayWithTimeOfDay(
                              dataConfirmacao,
                              picked.hour,
                              picked.minute,
                            ));
                      }
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
                        if (!payDay.isAfter(today)) {
                          return const SizedBox.shrink();
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: context.appAccentSurface(
                                  const Color(0xFF4F46E5),
                                ),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFF4F46E5)
                                      .withValues(alpha: 0.28),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Pagamento em ${DateFormat('dd/MM/yyyy').format(payDay)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                      color: context.isDarkMode
                                          ? const Color(0xFFA5B4FC)
                                          : const Color(0xFF312E81),
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Escolha como registrar o fechamento da fatura:',
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.35,
                                      color: context.appTextPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: 10),
                            SegmentedButton<bool>(
                              segments: const [
                                ButtonSegment(
                                  value: true,
                                  label: Text('Débito automático',
                                      style: TextStyle(fontSize: 11)),
                                  icon: Icon(Icons.schedule_send_rounded,
                                      size: 18),
                                ),
                                ButtonSegment(
                                  value: false,
                                  label: Text('Confirmar no dia',
                                      style: TextStyle(fontSize: 11)),
                                  icon: Icon(Icons.touch_app_rounded, size: 18),
                                ),
                              ],
                              selected: {faturaFutureMode.autoDebitOnDueDate},
                              onSelectionChanged: (s) {
                                setModalState(
                                  () =>
                                      faturaFutureMode = FaturaClosureSchedule(
                                    autoDebitOnDueDate: s.first,
                                  ),
                                );
                              },
                            ),
                            SizedBox(height: 8),
                            Text(
                              faturaFutureMode.autoDebitOnDueDate
                                  ? 'Em ${DateFormat('dd/MM/yyyy').format(payDay)} o valor sairá automaticamente da conta escolhida (ao abrir o app nessa data).'
                                  : 'Os lançamentos ficam na fatura até ${DateFormat('dd/MM/yyyy').format(payDay)} para você confirmar o pagamento manualmente.',
                              style: TextStyle(
                                fontSize: 11.5,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                                color: context.appTextSecondary,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                  SizedBox(height: 14),
                  Text(
                    creditCardFaturaPayment
                        ? 'Banco que paga a fatura'
                        : 'Banco / conta (todos)',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color: confirmAccent.withValues(alpha: 0.92),
                    ),
                  ),
                  if (creditCardFaturaPayment &&
                      hasPreferred &&
                      selectedFinanceAccountId == preferredId) ...[
                    SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.auto_awesome_rounded,
                            size: 13, color: confirmAccent.withValues(alpha: 0.8)),
                        SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Detectado automaticamente (mesmo banco do cartão) · pode trocar abaixo',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: confirmAccent.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  SizedBox(height: 8),
                  if (financeAccounts.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.logoOrange.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color:
                                AppColors.logoOrange.withValues(alpha: 0.28)),
                      ),
                      child: Text(
                        'Cadastre ao menos uma conta em Bancos e cartões para confirmar.',
                        style: TextStyle(
                            fontSize: 12.5,
                            color: context.appTextPrimary,
                            height: 1.35),
                      ),
                    )
                  else
                    DropdownButtonFormField<String?>(
                      key: ValueKey<String?>(selectedFinanceAccountId),
                      initialValue: selectedFinanceAccountId,
                      decoration: financePremiumDropdownDecoration(
                        ctx,
                        label: isIncome
                            ? 'Banco / conta de recebimento (todos)'
                            : 'Banco / conta de pagamento (todos)',
                        prefixIcon: Icons.account_balance_rounded,
                        accent: confirmAccent,
                      ),
                      items: [
                        ...financeAccounts.map(
                          (a) => DropdownMenuItem<String?>(
                            value: a.id,
                            child: Text(a.displayName,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                      onChanged: (v) =>
                          setModalState(() => selectedFinanceAccountId = v),
                    ),
                  SizedBox(height: 10),
                  Text(
                    'Comprovantes não estão disponíveis em lote. Confirme um a um se precisar anexar.',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: ctx.appTextSecondary,
                      height: 1.35,
                    ),
                  ),
                  SizedBox(height: 22),
                  FinancePremiumSheetActions(
                    confirmLabel: creditCardFaturaPayment
                        ? 'Gerar fechamento ($itemCount)'
                        : 'Confirmar todos ($itemCount)',
                    confirmColor: confirmAccent,
                    confirmIcon: Icons.done_all_rounded,
                    onConfirm: () {
                      if (permiteValorPago) {
                        final digitado = CurrencyFormats.parseBRLInput(valorPagoCtrl.text);
                        if (digitado == null || digitado <= 0) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('Informe quanto você pagou.')),
                          );
                          return;
                        }
                        if (digitado > totalSelecionado + 0.005) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text(
                                'O valor pago não pode passar de ${CurrencyFormats.formatBRL(totalSelecionado)} (o total selecionado).',
                              ),
                            ),
                          );
                          return;
                        }
                        valorPago = digitado;
                      }
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
    ];
  }

  Widget construirConteudo(
    BuildContext ctx,
    StateSetter setModalState,
    ScrollController? scrollController,
  ) {
    return ListView(
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.paddingOf(ctx).bottom),
      children: construirCampos(ctx, setModalState),
    );
  }

  // Pagar fatura do cartão sempre em tela cheia (pedido de 21/09/2026) — a
  // folha pela metade ficava apertada com o campo de valor pago e o resumo.
  // Os outros lotes (recebimentos/despesas em lote) continuam em folha.
  final confirmed = creditCardFaturaPayment
      ? await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(
            fullscreenDialog: true,
            builder: (ctx) => Scaffold(
              backgroundColor: Colors.transparent,
              body: Container(
                decoration: financePremiumSheetDecoration(surfaceTint: confirmAccent, context: context),
                child: SafeArea(
                  child: StatefulBuilder(
                    builder: (context, setModalState) => construirConteudo(ctx, setModalState, null),
                  ),
                ),
              ),
            ),
          ),
        )
      : await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Colors.transparent,
          builder: (ctx) => StatefulBuilder(
            builder: (context, setModalState) => DraggableScrollableSheet(
              initialChildSize: 0.58,
              minChildSize: 0.42,
              maxChildSize: 0.88,
              expand: false,
              builder: (ctx, scrollController) => Container(
                decoration: financePremiumSheetDecoration(surfaceTint: confirmAccent, context: context),
                child: SafeArea(
                  top: false,
                  child: construirConteudo(ctx, setModalState, scrollController),
                ),
              ),
            ),
          ),
        );

  valorPagoCtrl.dispose();
  if (confirmed != true) return null;

  final payDay = DateTime(
    dataConfirmacao.year,
    dataConfirmacao.month,
    dataConfirmacao.day,
  );
  final today = DateTime(now.year, now.month, now.day);
  final FaturaClosureSchedule? schedule =
      creditCardFaturaPayment && payDay.isAfter(today)
          ? faturaFutureMode
          : null;

  // Pagamento parcial: só os ids mais antigos até o valor informado saem
  // como pagos — o resto (`deixaEmAbertoIds`) continua pendente.
  List<String>? paidIdsOverride;
  List<String>? deixaEmAbertoIds;
  double? valorPagoInformado;
  if (permiteValorPago) {
    valorPagoInformado = valorPago;
    final fora = calcularDeixaEmAberto(valorPago);
    if (fora.isNotEmpty) {
      deixaEmAbertoIds = fora;
      final foraSet = fora.toSet();
      paidIdsOverride = payableItems.map((e) => e.id).where((id) => !foraSet.contains(id)).toList();
    }
  }

  return FinanceConfirmPaymentSheetResult(
    paymentDate: FinanceTransactionDatetime.withoutSeconds(dataConfirmacao),
    financeAccountId: selectedFinanceAccountId?.trim(),
    faturaSchedule: schedule,
    paidIdsOverride: paidIdsOverride,
    valorPagoInformado: valorPagoInformado,
    deixaEmAbertoIds: deixaEmAbertoIds,
  );
}

/// Grava confirmação em lote (mesma data/conta; sem comprovante).
///
/// Retorna quantos foram quitados como CONTROLE — sempre 0 no WISDOMAPP
/// (sem Finance Pro; mantido para a assinatura ficar igual à do CT).
Future<int> commitFinanceConfirmPaymentBatch({
  required CollectionReference<Map<String, dynamic>> txCol,
  required List<String> docIds,
  required String uid,
  required FinanceConfirmPaymentSheetResult result,
  bool creditCardFaturaPayment = false,
}) async {
  final unique =
      docIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
  if (unique.isEmpty) return 0;

  final controleIds = <String>{};

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
  return controleIds.length;
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
    FinanceTransactionsHub.notifyMutated(
        uid: uid, invalidateOpeningBalance: false);
  }
  return n;
}

/// Aviso do campo «Valor pago» — igual, paga menos ou passou do total.
Widget _avisoValorPago(
  BuildContext context, {
  required IconData icon,
  required String texto,
  required Color cor,
}) {
  return Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: cor.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: cor.withValues(alpha: 0.35)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: cor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            texto,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cor, height: 1.3),
          ),
        ),
      ],
    ),
  );
}

/// Qual atalho de «Valor pago» está ativo (ou nenhum, quando editado à mão).
enum _OrigemValorPago { banco, todos, manual }

/// Atalho de valor: «Fatura do banco» × «Tudo em aberto». Tocar preenche o
/// campo «Valor pago»; o usuário ainda pode editar à mão depois (pagamento
/// parcial continua funcionando normalmente).
class _ValorPagoQuickPick extends StatelessWidget {
  const _ValorPagoQuickPick({
    required this.label,
    required this.sublabel,
    required this.value,
    required this.icon,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String sublabel;
  final double value;
  final IconData icon;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: selected
                ? LinearGradient(
                    colors: [accent, Color.lerp(accent, Colors.black, 0.15)!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: selected ? null : context.appDarkModuleSurface,
            border: Border.all(
              color: selected ? Colors.transparent : accent.withValues(alpha: 0.28),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 15, color: selected ? Colors.white : accent),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: selected ? Colors.white : context.appTextPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 4),
              Text(
                CurrencyFormats.formatBRL(value),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w900,
                  color: selected ? Colors.white : accent,
                ),
              ),
              SizedBox(height: 2),
              Text(
                sublabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white.withValues(alpha: 0.85) : context.appTextSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
            context.appDarkModuleSurface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
              color: accent.withValues(alpha: 0.12),
              blurRadius: 14,
              offset: const Offset(0, 4)),
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
                gradient: LinearGradient(
                    colors: [accent, accent.withValues(alpha: 0.75)]),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.layers_rounded, color: Colors.white, size: 26),
            ),
            SizedBox(width: 14),
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
                    SizedBox(height: 4),
                    Text(
                      'Total: ${CurrencyFormats.formatBRL(totalAmount!.abs())}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: context.appTextPrimary,
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
            context.appDarkModuleSurface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
              color: accent.withValues(alpha: 0.12),
              blurRadius: 14,
              offset: const Offset(0, 4)),
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
              SizedBox(height: 6),
              Text(
                [if (cat.isNotEmpty) cat, if (desc.isNotEmpty) desc]
                    .join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.appTextPrimary,
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
