import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../constants/date_time_formats.dart';
import '../constants/currency_formats.dart';
import '../constants/finance_category_visuals.dart';
import '../models/finance_account.dart';
import '../models/user_profile.dart';
import '../screens/anexo_viewer_screen.dart';
import '../utils/anexo_viewer_helper.dart';
import '../utils/receipt_attachment_utils.dart';
import '../services/finance_accounts_service.dart';
import '../services/functions_service.dart';
import '../services/logs_service.dart';
import '../services/user_categories_service.dart';
import '../theme/app_colors.dart';
import '../utils/finance_line_opening.dart';
import '../utils/finance_transaction_datetime.dart';
import '../utils/firestore_user_doc_id.dart';
import '../utils/premium_upgrade.dart';
import 'brl_amount_text_field.dart';
import 'fast_text_field.dart';
import 'finance_category_picker.dart';
import 'finance_premium_ui.dart';
import 'finance_transfer_bottom_sheet.dart';

typedef FinanceTxEditOnSaved = void Function(
  String docId,
  Map<String, dynamic> patch,
  DateTime effectiveDate,
);

/// Modal premium de edição — verde (receita) / vermelho (despesa), igual ao Financeiro.
Future<bool> showFinanceTransactionEditDialog({
  required BuildContext context,
  required String uid,
  required UserProfile profile,
  required String docId,
  required Map<String, dynamic> current,
  required String type,
  List<FinanceAccount>? financeAccountsPreloaded,
  String logModulo = 'Financeiro',
  FinanceTxEditOnSaved? onSaved,
}) async {
  if (!profile.hasActiveLicense) {
    mostrarAvisoSeLicencaInativa(context, profile);
    return false;
  }
  final fsUid = firestoreUserDocIdForAppShell(uid);
  final pairId = (current['transferPairId'] ?? '').toString().trim();
  if (pairId.isNotEmpty) {
    final accounts = financeAccountsPreloaded ??
        await FinanceAccountsService().listOnce(fsUid);
    if (!context.mounted) return false;
    return FinanceTransferBottomSheet.showEdit(
      context,
      uid: uid,
      profile: profile,
      pairId: pairId,
      accounts: accounts,
      logModulo: logModulo,
    );
  }

  final loaded = await UserCategoriesService().load(fsUid);
  var categoryList = UserCategoriesService.sortedWithoutIncluirNova(
    type == 'income' ? loaded.income : loaded.expense,
  );
  final incluirNovaCat = UserCategoriesService.kIncluirNova;
  if (!context.mounted) return false;

  final amountCtrl = TextEditingController(
    text: CurrencyFormats.formatBRLInput((current['amount'] ?? 0).toDouble()),
  );
  final descCtrl = TextEditingController(text: (current['description'] ?? '').toString());
  final currentCat = (current['category'] ?? '').toString().trim();

  String pickFirstSelectable() {
    final real = categoryList.where((c) => c != incluirNovaCat).toList();
    return real.isNotEmpty ? real.first : '__outra__';
  }

  late String selectedCategory;
  if (currentCat.isNotEmpty) {
    final match = categoryList.where((c) => c.toLowerCase() == currentCat.toLowerCase()).toList();
    selectedCategory = match.isNotEmpty ? match.first : '__outra__';
  } else {
    selectedCategory = pickFirstSelectable();
  }

  final catCtrl = TextEditingController(
    text: currentCat.isNotEmpty ? currentCat : (selectedCategory == '__outra__' ? '' : selectedCategory),
  );
  String status = (current['status'] ?? 'paid').toString();
  DateTime date = (current['date'] is Timestamp) ? (current['date'] as Timestamp).toDate() : DateTime.now();
  final fromOpenFinance = FinanceTransactionDatetime.isOpenFinanceBacked(current);

  final receipt = Map<String, dynamic>.from(current['receipt'] ?? {});
  final hasExistingReceiptLink = ReceiptAttachmentUtils.hasViewableReceipt(receipt);
  var removeReceipt = false;
  Uint8List? newReceiptBytes;
  var newReceiptName = '';
  String? newReceiptMime;

  final financeAccounts = financeAccountsPreloaded ??
      await FinanceAccountsService().listOnce(fsUid);
  final rawAid = (current['financeAccountId'] ?? '').toString().trim();
  var selectedFinanceAccountId = rawAid.isEmpty ? null : rawAid;
  if (type == 'expense' &&
      financeAccounts.isNotEmpty &&
      (selectedFinanceAccountId == null || selectedFinanceAccountId.trim().isEmpty)) {
    selectedFinanceAccountId = financeAccounts.first.id;
  }
  if (!context.mounted) return false;

  final ok = await showDialog<bool>(
    context: context,
    barrierColor: AppColors.deepBlueDark.withValues(alpha: 0.55),
    builder: (ctx) => StatefulBuilder(
      builder: (context, setState) {
        final hasExistingReceipt = hasExistingReceiptLink && !removeReceipt && newReceiptBytes == null;
        final hasNewReceipt = newReceiptBytes != null;
        final showComprovante = profile.temAcessoPremium;
        final orphan = selectedFinanceAccountId != null &&
            selectedFinanceAccountId!.isNotEmpty &&
            !financeAccounts.any((a) => a.id == selectedFinanceAccountId);
        final editAccent = type == 'income' ? AppColors.financeReceita : AppColors.financeDespesa;

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.9),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(colors: [Color(0xFFF8FAFC), Colors.white]),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.deepBlueDark.withValues(alpha: 0.22),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(18, 16, 12, 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [editAccent, Color.lerp(editAccent, AppColors.accent, 0.4)!],
                      ),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            type == 'income' ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            type == 'income' ? 'Editar Receita' : 'Editar Despesa',
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          icon: const Icon(Icons.close_rounded, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              gradient: LinearGradient(
                                colors: [editAccent.withValues(alpha: 0.12), Colors.white],
                              ),
                              border: Border.all(color: editAccent.withValues(alpha: 0.28)),
                            ),
                            child: BrlAmountTextField(
                              controller: amountCtrl,
                              decoration: InputDecoration(
                                labelText: 'Valor',
                                isDense: true,
                                border: InputBorder.none,
                                labelStyle: TextStyle(fontWeight: FontWeight.w800, color: editAccent),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Categoria',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.grey.shade800),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () async {
                                final picked = await showFinanceCategoryPicker(
                                  context: context,
                                  uid: fsUid,
                                  isIncome: type == 'income',
                                  initialQuery:
                                      selectedCategory == '__outra__' ? catCtrl.text.trim() : selectedCategory,
                                );
                                if (picked == null || !ctx.mounted) return;
                                if (picked == '__outra__') {
                                  setState(() => selectedCategory = '__outra__');
                                  return;
                                }
                                final reloaded = await UserCategoriesService().load(fsUid);
                                if (!ctx.mounted) return;
                                setState(() {
                                  categoryList = UserCategoriesService.sortedWithoutIncluirNova(
                                    type == 'income' ? reloaded.income : reloaded.expense,
                                  );
                                  selectedCategory = picked;
                                  catCtrl.text = picked;
                                });
                              },
                              child: Ink(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.22)),
                                  color: const Color(0xFFF8FAFC),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  child: Row(
                                    children: [
                                      Builder(
                                        builder: (_) {
                                          final vis = selectedCategory != '__outra__'
                                              ? financeCategoryVisualFor(selectedCategory, isIncome: type == 'income')
                                              : financeCategoryVisualFor(
                                                  catCtrl.text.trim().isEmpty ? 'Outros' : catCtrl.text.trim(),
                                                  isIncome: type == 'income',
                                                );
                                          return Container(
                                            width: 38,
                                            height: 38,
                                            decoration: BoxDecoration(
                                              color: vis.color.withValues(alpha: 0.14),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Icon(vis.icon, color: vis.color, size: 22),
                                          );
                                        },
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          selectedCategory == '__outra__'
                                              ? (catCtrl.text.trim().isEmpty
                                                  ? 'Outra — toque para lista ou digite abaixo'
                                                  : catCtrl.text.trim())
                                              : selectedCategory,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14,
                                            color: Color(0xFF0F172A),
                                          ),
                                        ),
                                      ),
                                      Icon(Icons.unfold_more_rounded, color: Colors.grey.shade600, size: 22),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (selectedCategory == '__outra__') ...[
                            const SizedBox(height: 8),
                            FastTextField(
                              controller: catCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Nome da categoria',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              textCapitalization: TextCapitalization.words,
                            ),
                          ],
                          const SizedBox(height: 12),
                          FastTextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Descrição')),
                          const SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      fromOpenFinance ? 'Data e horário (Open Finance)' : 'Data do lançamento',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: Colors.grey.shade800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${DateFormat('dd/MM/yyyy', 'pt_BR').format(date)} · ${DateTimeFormats.formatTimeOnly(date)}',
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ],
                                ),
                              ),
                              if (!fromOpenFinance)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed: () async {
                                        final picked = await showDatePicker(
                                          context: context,
                                          initialDate: date,
                                          firstDate: DateTime(2020),
                                          lastDate: DateTime(2100),
                                        );
                                        if (picked != null) {
                                          setState(() => date =
                                              FinanceTransactionDatetime.mergeCalendarDayWithExistingTime(picked, date));
                                        }
                                      },
                                      child: const Text('Alterar dia'),
                                    ),
                                    TextButton(
                                      onPressed: () async {
                                        final picked = await showTimePicker(
                                          context: context,
                                          initialTime: TimeOfDay.fromDateTime(date),
                                        );
                                        if (picked != null) {
                                          setState(() => date = FinanceTransactionDatetime.mergeCalendarDayWithTime(
                                                DateTime(date.year, date.month, date.day),
                                                picked,
                                              ));
                                        }
                                      },
                                      child: const Text('Alterar hora'),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            key: ValueKey<String>(status),
                            value: status,
                            decoration: financePremiumDropdownDecoration(
                              label: 'Status',
                              prefixIcon: Icons.flag_rounded,
                              accent: editAccent,
                            ),
                            items: const [
                              DropdownMenuItem(value: 'paid', child: Text('Pago')),
                              DropdownMenuItem(value: 'pending', child: Text('Pendente')),
                            ],
                            onChanged: (v) => setState(() => status = v ?? 'paid'),
                          ),
                          const SizedBox(height: 12),
                          const Text('Conta', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          const SizedBox(height: 6),
                          if (financeAccounts.isEmpty)
                            Text(
                              'Cadastre ao menos uma conta em Financeiro → Bancos e cartões.',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.35),
                            )
                          else
                            DropdownButtonFormField<String?>(
                              key: ValueKey<String?>(selectedFinanceAccountId),
                              value: selectedFinanceAccountId,
                              decoration: financePremiumDropdownDecoration(
                                label: 'Conta do lançamento',
                                prefixIcon: Icons.account_balance_rounded,
                                accent: editAccent,
                              ),
                              items: [
                                if (type == 'income')
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('Sem conta vinculada (opcional)'),
                                  ),
                                ...financeAccounts.map(
                                  (a) => DropdownMenuItem<String?>(
                                    value: a.id,
                                    child: Text(a.displayName, overflow: TextOverflow.ellipsis),
                                  ),
                                ),
                                if (orphan)
                                  DropdownMenuItem<String?>(value: rawAid, child: const Text('Manter vínculo antigo')),
                              ],
                              onChanged: (v) => setState(() {
                                selectedFinanceAccountId = v;
                                if (type == 'expense' && v != null) {
                                  FinanceAccount? acc;
                                  for (final a in financeAccounts) {
                                    if (a.id == v) {
                                      acc = a;
                                      break;
                                    }
                                  }
                                  if (acc?.expenseDefaultsToPending == true) {
                                    status = 'pending';
                                  } else if (acc?.isDebitBankProduct == true) {
                                    status = 'paid';
                                  }
                                }
                              }),
                            ),
                          if (showComprovante) ...[
                            const SizedBox(height: 16),
                            const Divider(),
                            const Text('Comprovante', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                            const SizedBox(height: 8),
                            if (hasExistingReceipt)
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.visibility_rounded, size: 18),
                                      label: const Text('Ver anexo'),
                                      onPressed: () async {
                                        if (!hasExistingReceiptLink) return;
                                        await Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) => AnexoViewerScreen(
                                              url: ReceiptAttachmentUtils.viewUrl(receipt),
                                              fileName: ReceiptAttachmentUtils.fileName(receipt),
                                              storagePath: ReceiptAttachmentUtils.storagePath(receipt),
                                              mimeType: ReceiptAttachmentUtils.mimeType(receipt),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                                    label: const Text('Remover'),
                                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                                    onPressed: () => setState(() {
                                      removeReceipt = true;
                                      newReceiptBytes = null;
                                    }),
                                  ),
                                ],
                              ),
                            OutlinedButton.icon(
                              icon: Icon(
                                hasExistingReceipt || hasNewReceipt
                                    ? Icons.swap_horiz_rounded
                                    : Icons.attach_file_rounded,
                                size: 18,
                              ),
                              label: Text(
                                hasExistingReceipt || hasNewReceipt ? 'Trocar comprovante' : 'Anexar comprovante',
                              ),
                              onPressed: () async {
                                final picked = await ReceiptAttachmentUtils.pickValidated(context);
                                if (picked == null) return;
                                setState(() {
                                  removeReceipt = false;
                                  newReceiptBytes = picked.bytes;
                                  newReceiptName = picked.name;
                                  newReceiptMime = picked.mime;
                                });
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + MediaQuery.paddingOf(ctx).bottom),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: BorderSide(color: editAccent.withValues(alpha: 0.4)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: Text('Cancelar', style: TextStyle(fontWeight: FontWeight.w800, color: editAccent)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: LinearGradient(
                                colors: [editAccent, Color.lerp(editAccent, AppColors.secondary, 0.35)!],
                              ),
                            ),
                            child: FilledButton(
                              onPressed: () {
                                if (type == 'expense' &&
                                    financeAccounts.isNotEmpty &&
                                    (selectedFinanceAccountId == null ||
                                        selectedFinanceAccountId!.trim().isEmpty)) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(content: Text('Selecione a conta da despesa.')),
                                  );
                                  return;
                                }
                                Navigator.pop(ctx, true);
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              child: const Text('Salvar', style: TextStyle(fontWeight: FontWeight.w900)),
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

  if (ok != true || !context.mounted) {
    amountCtrl.dispose();
    descCtrl.dispose();
    catCtrl.dispose();
    return false;
  }

  final amount = CurrencyFormats.parseBRLInput(amountCtrl.text) ?? 0;
  var categoryFinal = selectedCategory == '__outra__' ? catCtrl.text.trim() : selectedCategory;
  if (categoryFinal.isEmpty || categoryFinal == incluirNovaCat) {
    categoryFinal = type == 'income' ? 'Receita' : 'Despesa';
  }
  if (amount.isNaN || amount.isInfinite || amount <= 0) {
    amountCtrl.dispose();
    descCtrl.dispose();
    catCtrl.dispose();
    return false;
  }

  final updateData = <String, dynamic>{
    'amount': amount,
    'category': categoryFinal,
    'description': descCtrl.text.trim(),
    'status': status,
    'date': Timestamp.fromDate(date),
    'updatedAt': FieldValue.serverTimestamp(),
  };
  final paidForEffective = status == 'paid'
      ? (current['paidAt'] is Timestamp ? current['paidAt'] as Timestamp : Timestamp.fromDate(date))
      : null;
  updateData['effectiveDate'] = FinanceLineOpening.effectiveTimestampForWrite(
    date: date,
    paidAt: paidForEffective,
  );

  final aid = selectedFinanceAccountId?.trim() ?? '';
  if (aid.isEmpty) {
    updateData['financeAccountId'] = FieldValue.delete();
  } else {
    updateData['financeAccountId'] = aid;
  }

  if (profile.temAcessoPremium) {
    if (removeReceipt) {
      updateData['receipt'] = FieldValue.delete();
      updateData['hasReceipt'] = false;
    } else if (newReceiptBytes != null &&
        newReceiptBytes!.isNotEmpty &&
        newReceiptName.isNotEmpty &&
        newReceiptMime != null) {
      try {
        final fn = FunctionsService();
        final txPath = 'users/$fsUid/transactions/$docId';
        await fn.uploadReceiptToStorage(
          txPath: txPath,
          filename: newReceiptName,
          bytes: newReceiptBytes!,
          mimeType: newReceiptMime!,
        );
        updateData['hasReceipt'] = true;
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao anexar comprovante: $e')));
        }
      }
    }
  }

  try {
    await FirebaseFirestore.instance.collection('users').doc(fsUid).collection('transactions').doc(docId).update(updateData);
    final effectiveDate = date;
    onSaved?.call(docId, {
      'type': type,
      'amount': amount,
      'category': categoryFinal,
      'description': descCtrl.text.trim(),
      'status': status,
      'date': Timestamp.fromDate(date),
      'financeAccountId': aid,
    }, effectiveDate);
    if (context.mounted) {
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lançamento atualizado.')));
    }
    unawaited(
      LogsService()
          .saveLog(
            modulo: logModulo,
            acao: type == 'income' ? 'Editou receita' : 'Editou despesa',
            detalhes: '$categoryFinal • ${CurrencyFormats.formatBRL(amount)}',
          )
          .catchError((_) {}),
    );
    amountCtrl.dispose();
    descCtrl.dispose();
    catCtrl.dispose();
    return true;
  } catch (err) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erro ao atualizar: ${err.toString().split('\n').first}'),
        backgroundColor: AppColors.error,
      ));
    }
    amountCtrl.dispose();
    descCtrl.dispose();
    catCtrl.dispose();
    return false;
  }
}
