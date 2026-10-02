import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide showDatePicker;
import '../theme/theme_context.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../constants/currency_formats.dart';
import '../constants/finance_category_visuals.dart';
import '../models/despertar_item.dart';
import '../models/finance_account.dart';
import '../models/user_profile.dart';
import '../screens/anexo_viewer_screen.dart';
import '../services/finance_accounts_service.dart';
import '../services/goal_deposit_service.dart';
import '../services/functions_service.dart';
import '../services/logs_service.dart';
import '../services/transaction_save_service.dart';
import '../services/user_categories_service.dart';
import '../theme/app_colors.dart';
import '../widgets/modern_module_ui.dart';
import '../utils/finance_line_opening.dart';
import '../utils/finance_goal_tx_delete.dart';
import '../utils/finance_transaction_datetime.dart';
import '../utils/firestore_user_doc_id.dart';
import '../utils/date_picker_a11y.dart';
import '../utils/fifty_two_weeks_plan.dart';
import '../utils/premium_upgrade.dart';
import '../utils/receipt_attachment_utils.dart';
import 'brl_amount_text_field.dart';
import 'despertar_item_card.dart';
import 'fast_text_field.dart';
import 'finance_bank_brand_thumb.dart';
import 'finance_calendar_color_picker.dart';
import 'finance_category_picker.dart';
import 'finance_premium_ui.dart';
import 'finance_transfer_bottom_sheet.dart';
import 'goal_deposit_ui.dart';

typedef FinanceTxEditOnSaved = void Function(
  String docId,
  Map<String, dynamic> patch,
  DateTime effectiveDate,
);

typedef FinanceTxEditOnDeleted = void Function(
  String docId,
  DateTime? effectiveDate,
);

/// Copia o conteúdo inteiro do campo — mesmo botão usado em outros
/// formulários do app, não depende de selecionar texto na mão (toque e
/// segure no iPhone).
Future<void> _copyWholeField(
    BuildContext context, TextEditingController ctrl) async {
  final text = ctrl.text;
  if (text.isEmpty) return;
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copiado.'), duration: Duration(seconds: 1)),
    );
  }
}

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
  FinanceTxEditOnDeleted? onDeleted,
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
  final descCtrl =
      TextEditingController(text: (current['description'] ?? '').toString());
  final currentCat = (current['category'] ?? '').toString().trim();

  String pickFirstSelectable() {
    final real = categoryList.where((c) => c != incluirNovaCat).toList();
    return real.isNotEmpty ? real.first : '__outra__';
  }

  late String selectedCategory;
  if (currentCat.isNotEmpty) {
    final match = categoryList
        .where((c) => c.toLowerCase() == currentCat.toLowerCase())
        .toList();
    selectedCategory = match.isNotEmpty ? match.first : '__outra__';
  } else {
    selectedCategory = pickFirstSelectable();
  }

  final catCtrl = TextEditingController(
    text: currentCat.isNotEmpty
        ? currentCat
        : (selectedCategory == '__outra__' ? '' : selectedCategory),
  );
  String status = (current['status'] ?? 'paid').toString();
  // Calendário: reflete o gravado — só ligado com opt-in explícito
  // (ausente = desligado; regra do dono 01/10/2026).
  var addToCalendar = status == 'pending' &&
      FinanceCalendarColorPicker.calendarioLigado(current);
  String? calendarColorHex = current['calendarColorHex']?.toString();
  // «Despertar» da conta pendente (padrão desligado; paga não desperta).
  var despertar = DespertarItem.doDocumento(current);
  DateTime date = (current['date'] is Timestamp)
      ? (current['date'] as Timestamp).toDate()
      : DateTime.now();
  final fromOpenFinance =
      FinanceTransactionDatetime.isOpenFinanceBacked(current);

  final receipt = Map<String, dynamic>.from(current['receipt'] ?? {});
  final hasExistingReceiptLink =
      ReceiptAttachmentUtils.hasViewableReceipt(receipt);
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
      (selectedFinanceAccountId == null ||
          selectedFinanceAccountId.trim().isEmpty)) {
    selectedFinanceAccountId = financeAccounts.first.id;
  }
  if (!context.mounted) return false;

  final goalIdFromTx = (current['goalId'] ?? '').toString().trim();
  // Depósito antigo (receita) ou reserva/resgate novo (02/10/2026): qualquer
  // lançamento com goalId é movimento de meta.
  final metaEdit = goalIdFromTx.isNotEmpty
      ? await _loadGoalFinanceEditContext(
          fsUid: fsUid,
          goalId: goalIdFromTx,
          txId: docId,
        )
      : null;
  if (!context.mounted) return false;

  var metaPreviewWeeks = metaEdit?.initialWeeks ?? const <int>[];
  if (metaEdit != null && metaEdit.is52) {
    final initialAmount = CurrencyFormats.parseBRLInput(amountCtrl.text) ?? 0;
    metaPreviewWeeks = computeGoalDepositPreviewWeeks(
      goalData: metaEdit.goalData,
      schedule: metaEdit.schedule,
      oldWeeks: metaEdit.initialWeeks,
      amount: initialAmount,
    );
  }

  void recalcMetaWeeks(void Function(void Function()) setState) {
    if (metaEdit == null || !metaEdit.is52) return;
    final amount = CurrencyFormats.parseBRLInput(amountCtrl.text) ?? 0;
    metaPreviewWeeks = computeGoalDepositPreviewWeeks(
      goalData: metaEdit.goalData,
      schedule: metaEdit.schedule,
      oldWeeks: metaEdit.initialWeeks,
      amount: amount,
    );
    setState(() {});
  }

  final ok = await showDialog<bool>(
    context: context,
    barrierColor: AppColors.deepBlueDark.withValues(alpha: 0.55),
    builder: (ctx) => StatefulBuilder(
      builder: (context, setState) {
        final hasExistingReceipt =
            hasExistingReceiptLink && !removeReceipt && newReceiptBytes == null;
        final hasNewReceipt = newReceiptBytes != null;
        final showComprovante = profile.temAcessoPremium;
        final orphan = selectedFinanceAccountId != null &&
            selectedFinanceAccountId!.isNotEmpty &&
            !financeAccounts.any((a) => a.id == selectedFinanceAccountId);
        final editAccent = type == 'income'
            ? AppColors.financeReceita
            : AppColors.financeDespesa;
        final typeGradient = type == 'income'
            ? const [Color(0xFF15803D), Color(0xFF16A34A), Color(0xFF0D9488)]
            : const [Color(0xFFDC2626), Color(0xFFEF4444), Color(0xFFF97316)];
        Widget dateChip({
          required IconData icon,
          required String caption,
          required String value,
          required List<Color> colors,
          VoidCallback? onTap,
        }) {
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: Ink(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(
                  color: context.appAccentSurface(colors.first,
                      darkAlpha: 0.20, lightAlpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: colors.first.withValues(
                          alpha: context.isDarkMode ? 0.55 : 0.35)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: colors),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(icon, color: Colors.white, size: 17),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(caption,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: context.appTextSecondary)),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(value,
                                style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w900,
                                    color: context.appTextPrimary)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        Widget statusPill(String value, String label, IconData icon,
            List<Color> colors) {
          final sel = status == value;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => status = value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                padding:
                    const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
                decoration: BoxDecoration(
                  gradient: sel ? LinearGradient(colors: colors) : null,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: sel
                      ? [
                          BoxShadow(
                            color: colors.first.withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon,
                        size: 19,
                        color: sel ? Colors.white : colors.first),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              color: sel
                                  ? Colors.white
                                  : context.appTextSecondary)),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
          child: ConstrainedBox(
            constraints:
                BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.9),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(colors: [
                  ctx.appChipIdleBg,
                  ModernModuleUI.cardBg(ctx),
                ]),
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
                    padding: const EdgeInsets.fromLTRB(18, 18, 12, 18),
                    decoration: BoxDecoration(
                      // Despesa vermelho→laranja; Receita verde→teal.
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: typeGradient,
                      ),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(24)),
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
                            type == 'income'
                                ? Icons.arrow_downward_rounded
                                : Icons.arrow_upward_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            type == 'income'
                                ? 'Editar Receita'
                                : 'Editar Despesa',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          icon: Icon(Icons.close_rounded, color: Colors.white),
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
                          // Valor em destaque no gradiente do tipo.
                          Container(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(22),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: typeGradient,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: typeGradient.first
                                      .withValues(alpha: 0.30),
                                  blurRadius: 14,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Valor',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12.5,
                                    color:
                                        Colors.white.withValues(alpha: 0.9),
                                  ),
                                ),
                                BrlAmountTextField(
                                  controller: amountCtrl,
                                  onChanged: metaEdit?.is52 == true
                                      ? (_) => recalcMetaWeeks(setState)
                                      : null,
                                  style: const TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: -0.5,
                                  ),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    filled: false,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    contentPadding:
                                        const EdgeInsets.only(top: 4),
                                    prefixText: 'R\$ ',
                                    prefixStyle: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color:
                                          Colors.white.withValues(alpha: 0.85),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Categoria',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: context.appTextPrimary),
                            ),
                          ),
                          SizedBox(height: 6),
                          Material(
                            color: context.appSurface,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () async {
                                final picked = await showFinanceCategoryPicker(
                                  context: context,
                                  uid: fsUid,
                                  isIncome: type == 'income',
                                  initialQuery: selectedCategory == '__outra__'
                                      ? catCtrl.text.trim()
                                      : selectedCategory,
                                );
                                if (picked == null || !ctx.mounted) return;
                                if (picked == '__outra__') {
                                  setState(
                                      () => selectedCategory = '__outra__');
                                  return;
                                }
                                final reloaded =
                                    await UserCategoriesService().load(fsUid);
                                if (!ctx.mounted) return;
                                setState(() {
                                  categoryList = UserCategoriesService
                                      .sortedWithoutIncluirNova(
                                    type == 'income'
                                        ? reloaded.income
                                        : reloaded.expense,
                                  );
                                  selectedCategory = picked;
                                  catCtrl.text = picked;
                                });
                              },
                              child: Ink(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.22)),
                                  color: ctx.appChipIdleBg,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                  child: Row(
                                    children: [
                                      Builder(
                                        builder: (_) {
                                          final vis = selectedCategory !=
                                                  '__outra__'
                                              ? financeCategoryVisualFor(
                                                  selectedCategory,
                                                  isIncome: type == 'income')
                                              : financeCategoryVisualFor(
                                                  catCtrl.text.trim().isEmpty
                                                      ? 'Outros'
                                                      : catCtrl.text.trim(),
                                                  isIncome: type == 'income',
                                                );
                                          return Container(
                                            width: 38,
                                            height: 38,
                                            decoration: BoxDecoration(
                                              color: vis.color
                                                  .withValues(alpha: 0.14),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Icon(vis.icon,
                                                color: vis.color, size: 22),
                                          );
                                        },
                                      ),
                                      SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          selectedCategory == '__outra__'
                                              ? (catCtrl.text.trim().isEmpty
                                                  ? 'Outra — toque para lista ou digite abaixo'
                                                  : catCtrl.text.trim())
                                              : selectedCategory,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14,
                                            color: context.appTextPrimary,
                                          ),
                                        ),
                                      ),
                                      Icon(Icons.unfold_more_rounded,
                                          color: context.appTextSecondary,
                                          size: 22),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (selectedCategory == '__outra__') ...[
                            SizedBox(height: 8),
                            FastTextField(
                              controller: catCtrl,
                              decoration: InputDecoration(
                                labelText: 'Nome da categoria',
                                border: const OutlineInputBorder(),
                                isDense: true,
                                suffixIcon: IconButton(
                                  tooltip: 'Copiar',
                                  icon: const Icon(Icons.copy_rounded,
                                      size: 18),
                                  color: AppColors.primary,
                                  onPressed: () =>
                                      _copyWholeField(context, catCtrl),
                                  splashRadius: 22,
                                  constraints: const BoxConstraints(
                                      minWidth: 44, minHeight: 44),
                                ),
                              ),
                              textCapitalization: TextCapitalization.words,
                            ),
                          ],
                          SizedBox(height: 12),
                          FastTextField(
                              controller: descCtrl,
                              decoration: InputDecoration(
                                labelText: 'Descrição',
                                suffixIcon: IconButton(
                                  tooltip: 'Copiar',
                                  icon: const Icon(Icons.copy_rounded,
                                      size: 18),
                                  color: AppColors.primary,
                                  onPressed: () =>
                                      _copyWholeField(context, descCtrl),
                                  splashRadius: 22,
                                  constraints: const BoxConstraints(
                                      minWidth: 44, minHeight: 44),
                                ),
                              )),
                          SizedBox(height: 10),
                          Text(
                            fromOpenFinance
                                ? 'Data e horário (Open Finance)'
                                : 'Data e horário do lançamento',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: context.appTextPrimary,
                            ),
                          ),
                          SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: dateChip(
                                  icon: Icons.calendar_month_rounded,
                                  caption: fromOpenFinance
                                      ? 'Dia'
                                      : 'Dia · toque para alterar',
                                  value: DateFormat('dd/MM/yyyy', 'pt_BR')
                                      .format(date),
                                  colors: const [
                                    Color(0xFF14B8A6),
                                    Color(0xFF0F766E)
                                  ],
                                  onTap: fromOpenFinance
                                      ? null
                                      : () async {
                                          final picked = await showDatePicker(
                                            context: context,
                                            initialDate: date,
                                            firstDate: DateTime(2020),
                                            lastDate: DateTime(2100),
                                          );
                                          if (picked != null) {
                                            setState(() => date =
                                                FinanceTransactionDatetime
                                                    .mergeCalendarDayWithExistingTime(
                                                        picked, date));
                                          }
                                        },
                                ),
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: dateChip(
                                  icon: Icons.schedule_rounded,
                                  caption: 'Hora',
                                  value:
                                      DateFormat('HH:mm', 'pt_BR').format(date),
                                  colors: const [
                                    Color(0xFF6366F1),
                                    Color(0xFF4338CA)
                                  ],
                                  onTap: fromOpenFinance
                                      ? null
                                      : () async {
                                          final picked = await showTimePicker(
                                            context: context,
                                            initialTime: TimeOfDay(
                                                hour: date.hour,
                                                minute: date.minute),
                                            helpText: 'Horário do lançamento',
                                            hourLabelText: 'Hora',
                                            minuteLabelText: 'Minuto',
                                            builder: (context, child) {
                                              return MediaQuery(
                                                data: MediaQuery.of(context)
                                                    .copyWith(
                                                        alwaysUse24HourFormat:
                                                            true),
                                                child: child ??
                                                    const SizedBox.shrink(),
                                              );
                                            },
                                          );
                                          if (picked != null) {
                                            setState(() => date =
                                                FinanceTransactionDatetime
                                                    .mergeCalendarDayWithTimeOfDay(
                                                  date,
                                                  picked.hour,
                                                  picked.minute,
                                                ));
                                          }
                                        },
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Status',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: context.appTextPrimary,
                            ),
                          ),
                          SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: context.appChipIdleBg,
                              borderRadius: BorderRadius.circular(18),
                              border:
                                  Border.all(color: context.appChipIdleBorder),
                            ),
                            child: Row(
                              children: [
                                statusPill(
                                  'paid',
                                  type == 'income' ? 'Recebido' : 'Pago',
                                  Icons.check_circle_rounded,
                                  const [Color(0xFF16A34A), Color(0xFF0D9488)],
                                ),
                                const SizedBox(width: 4),
                                statusPill(
                                  'pending',
                                  'Pendente',
                                  Icons.schedule_rounded,
                                  const [Color(0xFFF59E0B), Color(0xFFEA580C)],
                                ),
                              ],
                            ),
                          ),
                          if (status == 'pending') ...[
                            SizedBox(height: 12),
                            DespertarItemCard(
                              value: despertar,
                              descricaoItem: type == 'income'
                                  ? 'esta conta a receber (enquanto pendente)'
                                  : 'esta conta a pagar (enquanto pendente)',
                              onChanged: (v) => setState(() => despertar = v),
                            ),
                            SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: editAccent.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: editAccent.withValues(alpha: 0.28),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    addToCalendar
                                        ? Icons.event_available_rounded
                                        : Icons.event_busy_rounded,
                                    size: 20,
                                    color: editAccent,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Mostrar no calendário',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: context.appTextPrimary,
                                          ),
                                        ),
                                        Text(
                                          'Agenda/Escala',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: context.appTextSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch.adaptive(
                                    value: addToCalendar,
                                    activeThumbColor: editAccent,
                                    activeTrackColor:
                                        editAccent.withValues(alpha: 0.5),
                                    onChanged: (v) async {
                                      setState(() => addToCalendar = v);
                                      if (!v) return;
                                      final hex = await FinanceCalendarColorPicker
                                          .escolherAoAtivar(
                                        context,
                                        isIncome: type == 'income',
                                        currentHex: calendarColorHex,
                                      );
                                      if (!context.mounted) return;
                                      setState(() => calendarColorHex = hex);
                                    },
                                  ),
                                ],
                              ),
                            ),
                            if (addToCalendar) ...[
                              SizedBox(height: 10),
                              Builder(builder: (ctx) {
                                final hex = (calendarColorHex ??
                                        FinanceCalendarColorPicker
                                            .defaultHexFor(type == 'income'))
                                    .replaceFirst('#', '')
                                    .replaceFirst(
                                        RegExp(r'^0x', caseSensitive: false),
                                        '');
                                final six = hex.length > 6
                                    ? hex.substring(hex.length - 6)
                                    : hex.padLeft(6, '0');
                                final bg =
                                    Color(int.parse('FF$six', radix: 16));
                                return Material(
                                  color: bg,
                                  borderRadius: BorderRadius.circular(14),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: () async {
                                      final picked =
                                          await FinanceCalendarColorPicker.show(
                                        context,
                                        isIncome: type == 'income',
                                        currentHex: calendarColorHex,
                                      );
                                      if (picked != null) {
                                        setState(
                                            () => calendarColorHex = picked);
                                      }
                                    },
                                    child: const SizedBox(
                                      height: 44,
                                      width: double.infinity,
                                      child: Center(
                                        child: Text(
                                          'Cor no calendário',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 13.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ],
                          SizedBox(height: 12),
                          Text('Conta',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 13)),
                          SizedBox(height: 6),
                          if (financeAccounts.isEmpty)
                            Text(
                              'Cadastre ao menos uma conta em Financeiro → Bancos e cartões.',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: context.appTextSecondary,
                                  height: 1.35),
                            )
                          else
                            DropdownButtonFormField<String?>(
                              key: ValueKey<String?>(selectedFinanceAccountId),
                              initialValue: selectedFinanceAccountId,
                              decoration: financePremiumDropdownDecoration(
                              context,
                              label: 'Conta do lançamento',
                                prefixIcon: Icons.account_balance_rounded,
                                accent: editAccent,
                              ),
                              items: [
                                if (type == 'income')
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child:
                                        Text('Sem conta vinculada (opcional)'),
                                  ),
                                ...financeAccounts.map(
                                  (a) => DropdownMenuItem<String?>(
                                    value: a.id,
                                    child: Row(
                                      children: [
                                        FinanceBankBrandThumb(
                                            preset: a.preset, size: 22),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(a.displayName,
                                              overflow: TextOverflow.ellipsis),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (orphan)
                                  DropdownMenuItem<String?>(
                                      value: rawAid,
                                      child: Text('Manter vínculo antigo')),
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
                          if (metaEdit != null) ...[
                            SizedBox(height: 12),
                            if (metaEdit.is52)
                              GoalDepositWeeksPreviewBanner(
                                oldWeeks: metaEdit.initialWeeks,
                                previewWeeks: metaPreviewWeeks,
                              )
                            else
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: GoalDepositUi.green
                                      .withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: GoalDepositUi.green
                                        .withValues(alpha: 0.22),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.savings_rounded,
                                        size: 18,
                                        color: context.isDarkMode
                                            ? context.appNeonSoft
                                            : GoalDepositUi.greenDark),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Lançamento vinculado à meta «${metaEdit.goalTitle}». '
                                        'Ao salvar, o depósito na meta será atualizado.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: context.isDarkMode
                                              ? context.appNeonSoft
                                              : GoalDepositUi.greenDark,
                                          height: 1.35,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                          if (showComprovante) ...[
                            SizedBox(height: 16),
                            const Divider(),
                            Text('Comprovante',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 14)),
                            SizedBox(height: 8),
                            if (hasExistingReceipt)
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      icon: Icon(Icons.visibility_rounded,
                                          size: 18),
                                      label: Text('Ver anexo'),
                                      onPressed: () async {
                                        if (!hasExistingReceiptLink) return;
                                        await Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) => AnexoViewerScreen(
                                              url: ReceiptAttachmentUtils
                                                  .viewUrl(receipt),
                                              fileName: ReceiptAttachmentUtils
                                                  .fileName(receipt),
                                              storagePath:
                                                  ReceiptAttachmentUtils
                                                      .storagePath(receipt),
                                              mimeType: ReceiptAttachmentUtils
                                                  .mimeType(receipt),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    icon: Icon(Icons.delete_outline_rounded,
                                        size: 18),
                                    label: Text('Remover'),
                                    style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.red),
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
                                hasExistingReceipt || hasNewReceipt
                                    ? 'Trocar comprovante'
                                    : 'Anexar comprovante',
                              ),
                              onPressed: () async {
                                final picked = await ReceiptAttachmentUtils
                                    .pickValidated(context);
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
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Align(
                      alignment: Alignment.center,
                      child: TextButton.icon(
                        icon: Icon(Icons.delete_outline_rounded, size: 20),
                        label: Text('Excluir lançamento'),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFEF4444),
                        ),
                        onPressed: () async {
                          final metaInfo =
                              await GoalDepositService.linkedInfoForTransaction(
                            uid: uid,
                            txId: docId,
                            txData: current,
                          );
                          if (!ctx.mounted) return;
                          final ok = await confirmFinanceTransactionDelete(
                            context: ctx,
                            metaInfo: metaInfo,
                          );
                          if (ok != true || !ctx.mounted) return;
                          final txCol = FirebaseFirestore.instance
                              .collection('users')
                              .doc(fsUid)
                              .collection('transactions');
                          await deleteFinanceTransactionRecord(
                            uid: uid,
                            docId: docId,
                            txData: current,
                            txCol: txCol,
                          );
                          final effectiveDate =
                              FinanceLineOpening.effectiveDateTimeFromMap(
                                      current) ??
                                  (current['date'] as Timestamp?)?.toDate();
                          final typeLog =
                              (current['type'] ?? 'expense').toString();
                          final amountLog = (current['amount'] ?? 0).toDouble();
                          final categoryLog =
                              (current['category'] ?? '').toString();
                          await LogsService().saveLog(
                            modulo: logModulo,
                            acao: typeLog == 'income'
                                ? 'Excluiu receita'
                                : 'Excluiu despesa',
                            detalhes:
                                '${categoryLog.isEmpty ? 'Categoria' : categoryLog} • ${CurrencyFormats.formatBRL(amountLog)}',
                          );
                          onDeleted?.call(docId, effectiveDate);
                          if (ctx.mounted) {
                            Navigator.pop(ctx, false);
                            final extra = metaInfo?.hasWeeksImpact == true
                                ? ' Semanas da meta atualizadas.'
                                : '';
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('Lançamento excluído.$extra')),
                            );
                          }
                        },
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                        16, 8, 16, 12 + MediaQuery.paddingOf(ctx).bottom),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: BorderSide(
                                  color: editAccent.withValues(alpha: 0.4)),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            child: Text('Cancelar',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: editAccent)),
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: LinearGradient(
                                colors: [
                                  editAccent,
                                  Color.lerp(
                                      editAccent, AppColors.secondary, 0.35)!
                                ],
                              ),
                            ),
                            child: FilledButton(
                              onPressed: () {
                                if (type == 'expense' &&
                                    financeAccounts.isNotEmpty &&
                                    (selectedFinanceAccountId == null ||
                                        selectedFinanceAccountId!
                                            .trim()
                                            .isEmpty)) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Selecione a conta da despesa.')),
                                  );
                                  return;
                                }
                                Navigator.pop(ctx, true);
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                              ),
                              child: Text('Salvar',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w900)),
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

  final messenger = ScaffoldMessenger.maybeOf(context);
  final amount = CurrencyFormats.parseBRLInput(amountCtrl.text) ?? 0;
  var categoryFinal =
      selectedCategory == '__outra__' ? catCtrl.text.trim() : selectedCategory;
  if (categoryFinal.isEmpty || categoryFinal == incluirNovaCat) {
    categoryFinal = type == 'income' ? 'Receita' : 'Despesa';
  }
  if (amount.isNaN || amount.isInfinite || amount <= 0) {
    amountCtrl.dispose();
    descCtrl.dispose();
    catCtrl.dispose();
    return false;
  }

  // Lançamento que veio do banco (Open Finance) com a categoria trocada: vira
  // escolha do usuário e, depois de salvar, o app oferece aplicar nos iguais.
  final categoriaAnterior = (current['category'] ?? '').toString().trim();
  final veioDoBanco = current['source'] == 'open_finance' ||
      (current['openFinanceExternalId'] ?? '').toString().trim().isNotEmpty;
  final categoriaMudou = categoryFinal != categoriaAnterior;

  final updateData = <String, dynamic>{
    'amount': amount,
    'category': categoryFinal,
    if (veioDoBanco && categoriaMudou) 'categoriaOrigem': 'manual',
    'description': descCtrl.text.trim(),
    // A observação é editada na ficha do lançamento; aqui ela só é
    // preservada — salvar sem este campo apagaria o que a pessoa escreveu.
    if ((current['observacao'] ?? '').toString().trim().isNotEmpty)
      'observacao': current['observacao'],
    'status': status,
    'date': Timestamp.fromDate(FinanceTransactionDatetime.withoutSeconds(date)),
    'updatedAt': FieldValue.serverTimestamp(),
  };
  final paidForEffective = status == 'paid'
      ? (current['paidAt'] is Timestamp
          ? current['paidAt'] as Timestamp
          : Timestamp.fromDate(date))
      : null;
  updateData['effectiveDate'] = FinanceLineOpening.effectiveTimestampForWrite(
    date: FinanceTransactionDatetime.withoutSeconds(date),
    paidAt: paidForEffective,
  );

  final aid = selectedFinanceAccountId?.trim() ?? '';
  if (aid.isEmpty) {
    updateData['financeAccountId'] = FieldValue.delete();
  } else {
    updateData['financeAccountId'] = aid;
  }

  if (status == 'pending') {
    updateData.addAll(despertar.campos);
    updateData['addToCalendar'] = addToCalendar;
    updateData['hideFromCalendar'] = !addToCalendar;
    if (addToCalendar &&
        calendarColorHex != null &&
        calendarColorHex!.trim().isNotEmpty) {
      updateData['calendarColorHex'] = calendarColorHex!.trim();
    } else {
      updateData['calendarColorHex'] = FieldValue.delete();
    }
  } else {
    updateData['addToCalendar'] = false;
    updateData['hideFromCalendar'] = FieldValue.delete();
    updateData['calendarColorHex'] = FieldValue.delete();
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
        await FunctionsService().uploadReceiptToStorage(
          txPath: 'users/$fsUid/transactions/$docId',
          filename: newReceiptName,
          bytes: newReceiptBytes!,
          mimeType: newReceiptMime!,
        );
        updateData['hasReceipt'] = true;
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Erro ao anexar comprovante: $e')));
        }
      }
    }
  }

  try {
    // Local primeiro (WISDOMAPP 01/10/2026): a edição já vale no cache; não
    // espera o servidor confirmar para fechar e atualizar a lista/saldos.
    // Sem Finance Pro: não há quitação «só de controle» (baixaSemSaldo).
    await TransactionSaveService.writeLocalFirst(
      () => FirebaseFirestore.instance
          .collection('users')
          .doc(fsUid)
          .collection('transactions')
          .doc(docId)
          .update(updateData),
      messenger: messenger,
      failureMessage: 'Não foi possível sincronizar a edição',
    );
    final goalId = (current['goalId'] ?? '').toString().trim();
    if (goalId.isNotEmpty) {
      unawaited(
        GoalDepositService.syncFromTransaction(
          uid: uid,
          goalId: goalId,
          txId: docId,
          amount: amount,
          date: date,
          financeAccountId: aid.isEmpty ? null : aid,
        ).catchError((_) {}),
      );
    }
    final effectiveDate = FinanceTransactionDatetime.withoutSeconds(date);
    onSaved?.call(
        docId,
        {
          'type': type,
          'amount': amount,
          'category': categoryFinal,
          'description': descCtrl.text.trim(),
          'status': status,
          'date': Timestamp.fromDate(effectiveDate),
          'financeAccountId': aid,
          'addToCalendar': status == 'pending' && addToCalendar,
          'hideFromCalendar': status == 'pending' && !addToCalendar,
          if (status == 'pending' &&
              addToCalendar &&
              calendarColorHex != null &&
              calendarColorHex!.trim().isNotEmpty)
            'calendarColorHex': calendarColorHex!.trim(),
        },
        effectiveDate);
    if (context.mounted) {
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Lançamento atualizado.')));
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

class _GoalFinanceEditContext {
  const _GoalFinanceEditContext({
    required this.is52,
    required this.goalData,
    required this.schedule,
    required this.initialWeeks,
    required this.goalTitle,
  });

  final bool is52;
  final Map<String, dynamic> goalData;
  final List<FiftyTwoWeeksWeekEntry> schedule;
  final List<int> initialWeeks;
  final String goalTitle;
}

Future<_GoalFinanceEditContext?> _loadGoalFinanceEditContext({
  required String fsUid,
  required String goalId,
  required String txId,
}) async {
  try {
    final goalRef = FirebaseFirestore.instance
        .collection('users')
        .doc(fsUid)
        .collection('goals')
        .doc(goalId);
    final goalSnap = await goalRef.get();
    if (!goalSnap.exists) return null;
    final goalData = goalSnap.data() ?? {};
    final is52 = FiftyTwoWeeksPlan.is52WeeksGoal(goalData);
    final target = (goalData['targetAmount'] as num?)?.toDouble() ?? 0;
    final planStart =
        FiftyTwoWeeksPlan.planStartFromData(goalData) ?? DateTime.now();
    final schedule = is52
        ? FiftyTwoWeeksPlan.buildSchedule(target: target, planStart: planStart)
        : const <FiftyTwoWeeksWeekEntry>[];
    var initialWeeks = <int>[];
    final contribQ = await goalRef
        .collection('contributions')
        .where('transactionId', isEqualTo: txId)
        .limit(1)
        .get();
    if (contribQ.docs.isNotEmpty) {
      initialWeeks =
          GoalDepositService.weeksFromContribData(contribQ.docs.first.data());
    }
    return _GoalFinanceEditContext(
      is52: is52,
      goalData: goalData,
      schedule: schedule,
      initialWeeks: initialWeeks,
      goalTitle: (goalData['title'] ?? 'Meta').toString(),
    );
  } catch (_) {
    return null;
  }
}
