import 'dart:async';

import 'package:flutter/material.dart' hide showDatePicker;
import '../widgets/fixas_visao_geral.dart';
import '../widgets/fixas_a_pagar_painel.dart';
import '../widgets/fixas_mes_a_mes.dart';
import '../theme/theme_context.dart';
import '../widgets/fast_text_field.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../widgets/modern_module_ui.dart';
import '../constants/currency_formats.dart';
import '../constants/finance_category_visuals.dart';
import '../constants/app_business_rules.dart';
import '../services/finance_accounts_service.dart';
import '../services/finance_advanced_settings_service.dart';
import '../services/fixed_expense_service.dart';
import '../services/fixed_expense_preferences_service.dart';
import '../services/finance_month_cache.dart';
import '../services/user_categories_service.dart';
import '../utils/date_picker_a11y.dart';
import '../utils/finance_transactions_hub.dart';
import '../utils/firestore_user_doc_id.dart';
import '../widgets/brl_amount_text_field.dart';
import '../widgets/finance_load_error_box.dart';
import '../widgets/fixas_totalizador_card.dart';
import '../widgets/finance_calendar_color_picker.dart';
import '../widgets/fixed_flow_finance_account_field.dart';
import '../widgets/fixed_pending_prefs_sheet.dart';
import '../utils/fixed_flow_schedule.dart';
import '../widgets/navy_back_app_bar.dart';

/// Espaço extra para o [Scrollable] rolar o campo acima do teclado no sheet.
const EdgeInsets _kFixedFlowKeyboardScrollPad =
    EdgeInsets.fromLTRB(0, 0, 0, 260);

InputDecoration _fixedFlowPremiumInputDeco(
  BuildContext context, {
  required String labelText,
  String? hintText,
  String? helperText,
  Widget? prefixIcon,
}) {
  const radius = BorderRadius.all(Radius.circular(14));
  final side = BorderSide(color: context.appChipIdleBorder);
  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    helperText: helperText,
    filled: true,
    fillColor: context.appInputFill,
    isDense: true,
    border: OutlineInputBorder(borderRadius: radius, borderSide: side),
    enabledBorder:
        OutlineInputBorder(borderRadius: radius, borderSide: side),
    focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: AppColors.primary, width: 2)),
    prefixIcon: prefixIcon,
  );
}

InputDecoration _fixedFlowPremiumDropdownDeco(BuildContext context,
    {required Widget prefixIcon}) {
  const radius = BorderRadius.all(Radius.circular(14));
  final side = BorderSide(color: context.appChipIdleBorder);
  return InputDecoration(
    filled: true,
    fillColor: context.appInputFill,
    isDense: true,
    floatingLabelBehavior: FloatingLabelBehavior.never,
    border: OutlineInputBorder(borderRadius: radius, borderSide: side),
    enabledBorder:
        OutlineInputBorder(borderRadius: radius, borderSide: side),
    focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: AppColors.primary, width: 2)),
    prefixIcon: prefixIcon,
  );
}

/// Despesas fixas: lista por **categoria** + FAB; preferências de pendentes no ícone de afinação da AppBar.
class DespesasFixasScreen extends StatefulWidget {
  final String uid;

  const DespesasFixasScreen({super.key, required this.uid});

  @override
  State<DespesasFixasScreen> createState() => _DespesasFixasScreenState();
}

class _DespesasFixasScreenState extends State<DespesasFixasScreen> {
  final FixedExpenseService _service = FixedExpenseService();
  final FixedExpensePreferencesService _prefsService =
      FixedExpensePreferencesService();
  List<String> _expenseCategories = [];
  Future<List<Map<String, dynamic>>>? _fixedExpensesFuture;
  List<Map<String, dynamic>>? _ultimasFixas;
  StreamSubscription<fa.User?>? _authUidSub;

  String get _fsUid => firestoreUserDocIdForAppShell(widget.uid);

  @override
  void initState() {
    super.initState();
    _authUidSub = fa.FirebaseAuth.instance.authStateChanges().listen((_) {
      if (mounted) setState(() {});
    });
    _loadCategories();
    _refreshFixedExpenses();
  }

  @override
  void dispose() {
    _authUidSub?.cancel();
    super.dispose();
  }

  void _refreshFixedExpenses() {
    setState(() {
      _fixedExpensesFuture = _service.list(_fsUid);
    });
  }

  Future<void> _loadCategories() async {
    final c = await UserCategoriesService().load(_fsUid);
    if (mounted) {
      setState(() {
        _expenseCategories =
            UserCategoriesService.sortedWithoutIncluirNova(c.expense);
      });
    }
  }

  /// Dropdown de categoria com opção "Incluir nova" e lista em ordem alfabética.
  static Widget _buildCategoryDropdown({
    required BuildContext context,
    required String category,
    required List<String> expenseCategories,
    required void Function(void Function()) setModalState,
    required void Function(String) onCategoryChanged,
    required Future<void> Function() onCategoryAdded,
  }) {
    const kIncluirNova = UserCategoriesService.kIncluirNova;
    final options = [kIncluirNova, ...expenseCategories];
    final value =
        category == kIncluirNova || expenseCategories.contains(category)
            ? category
            : (expenseCategories.isNotEmpty
                ? expenseCategories.first
                : kIncluirNova);
    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: options.contains(value)
          ? value
          : (expenseCategories.isNotEmpty
              ? expenseCategories.first
              : kIncluirNova),
      decoration: _fixedFlowPremiumDropdownDeco(
        context,
        prefixIcon: Icon(Icons.category_outlined,
            color: AppColors.primary.withValues(alpha: 0.88)),
      ),
      items: options.map((c) {
        final isNew = c == kIncluirNova;
        return DropdownMenuItem<String>(
          value: c,
          child: financeCategoryDropdownMenuRow(
            c,
            isIncome: false,
            isIncluirNovaOption: isNew,
          ),
        );
      }).toList(),
      onChanged: (v) {
        if (v == null) return;
        if (v == kIncluirNova) {
          onCategoryAdded();
          return;
        }
        onCategoryChanged(v);
        setModalState(() {});
      },
    );
  }

  String _subtitleFixedExpense(
      Map<String, dynamic> e, int day, DateTime? start, DateTime? end,
      {bool includeCategory = true}) {
    final mode = (e['mode'] ?? FixedExpenseService.modePeriod).toString();
    final cat = e['category'] ?? 'Despesa';
    final periodTail =
        'Dia $day · ${start != null ? DateFormat("MM/yyyy").format(start) : '?'} até ${end != null ? DateFormat("MM/yyyy").format(end) : 'sem fim'}';
    late final String tail;
    if (mode == FixedExpenseService.modeInstallments) {
      final total = (e['totalParcelas'] as num?)?.toInt();
      final ini = (e['parcelaInicial'] as num?)?.toInt();
      if (total != null) {
        final parcelaInfo = ini != null && ini > 1
            ? 'Da parcela $ini até $total'
            : '$total parcelas';
        tail =
            'Dia $day · $parcelaInfo · ${start != null ? DateFormat("MM/yyyy").format(start) : "?"}';
      } else {
        tail = periodTail;
      }
    } else {
      tail = periodTail;
    }
    if (!includeCategory) return tail;
    return '$cat · $tail';
  }

  Future<void> _openForm({Map<String, dynamic>? existing}) async {
    final descCtrl =
        TextEditingController(text: existing?['description']?.toString() ?? '');
    final amountCtrl = TextEditingController(
      text: existing != null && existing['amount'] != null
          ? CurrencyFormats.formatBRLInput(
              (existing['amount'] as num).toDouble())
          : '',
    );
    String category = existing?['category']?.toString() ??
        (_expenseCategories.isNotEmpty ? _expenseCategories.first : 'Despesa');
    int dayOfMonth = (existing?['dayOfMonth'] as num?)?.toInt() ?? 10;
    final now = DateTime.now();
    DateTime startDate = existing != null && existing['startDate'] is Timestamp
        ? (existing['startDate'] as Timestamp).toDate()
        : DateTime(now.year, now.month, 1);
    DateTime? endDate = existing != null && existing['endDate'] is Timestamp
        ? (existing['endDate'] as Timestamp).toDate()
        : DateTime(now.year + 1, now.month, 1);
    String mode =
        (existing?['mode'] ?? FixedExpenseService.modePeriod).toString();
    int totalParcelas = (existing?['totalParcelas'] as num?)?.toInt() ?? 12;
    int parcelaInicial = (existing?['parcelaInicial'] as num?)?.toInt() ?? 1;
    if (mode == FixedExpenseService.modeInstallments) {
      totalParcelas =
          totalParcelas.clamp(1, AppBusinessRules.maxFixedFlowInstallments);
      parcelaInicial = parcelaInicial.clamp(1, totalParcelas);
    }
    // Só ligado com opt-in explícito (ausente = desligado; regra 01/10/2026).
    bool addToCalendar = existing != null && existing['addToCalendar'] == true;
    String? calendarColorHex = existing?['calendarColorHex']?.toString();
    final isEdit = existing != null;
    final id = existing?['id']?.toString();
    String? financeAccountId =
        (existing?['financeAccountId'] ?? '').toString().trim();
    if (financeAccountId.isEmpty) {
      financeAccountId = null;
    }
    // Nova despesa: pré-seleciona o banco/caixa padrão do cadastro.
    if (!isEdit) {
      try {
        final accounts = await FinanceAccountsService().listOnce(_fsUid);
        final defId = await FinanceAdvancedSettingsService()
            .getDefaultFinanceAccountId(_fsUid);
        if (defId != null && accounts.any((a) => a.id == defId)) {
          financeAccountId = defId;
        } else if (accounts.isNotEmpty) {
          financeAccountId = accounts.first.id;
        }
      } catch (_) {}
    }
    final totalParcelasCtrl = TextEditingController(text: '$totalParcelas');
    final parcelaIniCtrl = TextEditingController(text: '$parcelaInicial');
    final totalParcelasFocus = FocusNode();
    final parcelaIniFocus = FocusNode();

    bool sheetDisposed = false;
    void disposeFormCtrls() {
      if (sheetDisposed) return;
      sheetDisposed = true;
      descCtrl.dispose();
      amountCtrl.dispose();
      totalParcelasCtrl.dispose();
      parcelaIniCtrl.dispose();
      totalParcelasFocus.dispose();
      parcelaIniFocus.dispose();
    }

    if (!mounted) {
      disposeFormCtrls();
      return;
    }

    bool ok = false;
    try {
      // Tela full-screen (antes era bottom sheet com DraggableScrollableSheet).
      // O Scaffold trata viewInsets sozinho — sem KeyboardViewInsetPad.
      ok = await Navigator.of(context).push<bool>(
            MaterialPageRoute<bool>(
              fullscreenDialog: true,
              builder: (ctx) => StatefulBuilder(
                builder: (context, setModalState) {
                  void scrollFieldIntoView(FocusNode node) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!context.mounted) return;
                      final bx = node.context;
                      if (bx != null) {
                        Scrollable.ensureVisible(
                          bx,
                          alignment: 0.12,
                          duration: const Duration(milliseconds: 320),
                          curve: Curves.easeOutCubic,
                        );
                      }
                    });
                  }

                  return Scaffold(
                    backgroundColor: context.appSurface,
                    appBar: AppBar(
                      elevation: 0,
                      leading: IconButton(
                        tooltip: 'Fechar',
                        icon: Icon(Icons.close_rounded),
                        onPressed: () => Navigator.maybePop(ctx, false),
                        style: IconButton.styleFrom(
                            minimumSize: const Size(48, 48)),
                      ),
                      title: Row(
                        children: [
                          Icon(Icons.repeat_rounded,
                              color: AppColors.primary, size: 22),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isEdit
                                  ? 'Editar despesa fixa'
                                  : 'Nova despesa fixa',
                              style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: context.appDeepTitle),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    body: SafeArea(
                      child: ListView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: EdgeInsets.fromLTRB(
                            20, 12, 20, 24 + MediaQuery.paddingOf(ctx).bottom),
                        children: [
                          RepaintBoundary(
                            child: FastTextField(
                              controller: descCtrl,
                              scrollPadding: _kFixedFlowKeyboardScrollPad,
                              decoration: _fixedFlowPremiumInputDeco(
                                context,
                                labelText: 'Descrição',
                                hintText: 'Ex: Aluguel, Internet',
                                prefixIcon: Icon(Icons.description_outlined,
                                    color: AppColors.primary
                                        .withValues(alpha: 0.88)),
                              ),
                              textCapitalization: TextCapitalization.sentences,
                              enableSuggestions: false,
                              autocorrect: false,
                            ),
                          ),
                          SizedBox(height: 16),
                          _buildCategoryDropdown(
                            context: context,
                            category: category,
                            expenseCategories: _expenseCategories,
                            setModalState: setModalState,
                            onCategoryChanged: (v) => category = v,
                            onCategoryAdded: () async {
                              final nameCtrl = TextEditingController();
                              final added = await showDialog<bool>(
                                context: context,
                                barrierDismissible: false,
                                builder: (ctx) => AlertDialog(
                                  title: Text('Nova categoria de despesa'),
                                  content: FastTextField(
                                    controller: nameCtrl,
                                    decoration: const InputDecoration(
                                      hintText: 'Nome da categoria',
                                      border: OutlineInputBorder(),
                                    ),
                                    autofocus: true,
                                    textCapitalization:
                                        TextCapitalization.words,
                                  ),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: Text('Cancelar')),
                                    FilledButton(
                                      onPressed: () {
                                        if (nameCtrl.text.trim().isEmpty) {
                                          return;
                                        }
                                        Navigator.pop(ctx, true);
                                      },
                                      child: Text('Adicionar'),
                                    ),
                                  ],
                                ),
                              );
                              if (added != true) return;
                              final name = nameCtrl.text.trim();
                              nameCtrl.dispose();
                              try {
                                await UserCategoriesService()
                                    .addCustom(_fsUid, false, name);
                                if (!context.mounted) return;
                                final c =
                                    await UserCategoriesService().load(_fsUid);
                                if (!context.mounted) return;
                                final list = UserCategoriesService
                                    .sortedWithoutIncluirNova(c.expense);
                                setModalState(() {
                                  category = name;
                                  _expenseCategories = list;
                                });
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(
                                              'Categoria "$name" adicionada.')));
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            'Erro ao salvar: ${e.toString().split('\n').first}')),
                                  );
                                }
                              }
                            },
                          ),
                          SizedBox(height: 16),
                          RepaintBoundary(
                            child: BrlAmountTextField(
                              controller: amountCtrl,
                              scrollPadding: _kFixedFlowKeyboardScrollPad,
                              decoration: _fixedFlowPremiumInputDeco(
                                context,
                                labelText: 'Valor (R\$)',
                                hintText: '0,00',
                                prefixIcon: Icon(Icons.attach_money_rounded,
                                    color: AppColors.primary
                                        .withValues(alpha: 0.88)),
                              ),
                            ),
                          ),
                          SizedBox(height: 16),
                          DropdownButtonFormField<int>(
                            initialValue: dayOfMonth.clamp(1, 31),
                            decoration: _fixedFlowPremiumInputDeco(
                              context,
                              labelText: 'Dia do mês do lançamento',
                              prefixIcon: Icon(Icons.calendar_today_rounded,
                                  color: AppColors.primary
                                      .withValues(alpha: 0.88)),
                            ),
                            items: List.generate(31, (i) => i + 1)
                                .map((d) => DropdownMenuItem(
                                    value: d, child: Text('Dia $d')))
                                .toList(),
                            onChanged: (v) => setModalState(
                                () => dayOfMonth = v ?? dayOfMonth),
                          ),
                          SizedBox(height: 16),
                          FixedFlowFinanceAccountField(
                            uid: _fsUid,
                            selectedAccountId: financeAccountId,
                            decorationBuilder: (ctx, {required prefixIcon}) =>
                                _fixedFlowPremiumDropdownDeco(ctx,
                                    prefixIcon: prefixIcon),
                            onChanged: (v) =>
                                setModalState(() => financeAccountId = v),
                          ),
                          SizedBox(height: 18),
                          _buildAddToCalendarToggle(
                            context: context,
                            isIncome: false,
                            value: addToCalendar,
                            onChanged: (v) async {
                              setModalState(() => addToCalendar = v);
                              if (!v) return;
                              // Ao ativar: paleta padrão com a cor sugerida.
                              final hex = await FinanceCalendarColorPicker
                                  .escolherAoAtivar(
                                context,
                                isIncome: false,
                                currentHex: calendarColorHex,
                              );
                              if (!context.mounted) return;
                              setModalState(() => calendarColorHex = hex);
                            },
                          ),
                          if (addToCalendar) ...[
                            SizedBox(height: 10),
                            _buildCalendarColorButton(
                              context: context,
                              isIncome: false,
                              currentHex: calendarColorHex,
                              onChanged: (v) =>
                                  setModalState(() => calendarColorHex = v),
                            ),
                          ],
                          SizedBox(height: 20),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      AppColors.deepBlueDark
                                          .withValues(alpha: 0.92),
                                      AppColors.primary.withValues(alpha: 0.9),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: Icon(Icons.tune_rounded,
                                    color: Colors.white, size: 18),
                              ),
                              SizedBox(width: 10),
                              Text(
                                'Tipo de controle',
                                style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w900,
                                    color: context.appTextPrimary,
                                    letterSpacing: 0.15),
                              ),
                            ],
                          ),
                          SizedBox(height: 10),
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.primary.withValues(alpha: 0.07),
                                  AppColors.accent.withValues(alpha: 0.05),
                                ],
                              ),
                              border: Border.all(
                                  color: AppColors.primary
                                      .withValues(alpha: 0.14)),
                            ),
                            padding: const EdgeInsets.all(5),
                            child: SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(
                                    value: FixedExpenseService.modePeriod,
                                    label: Text('Por período'),
                                    icon: Icon(Icons.date_range_rounded,
                                        size: 20)),
                                ButtonSegment(
                                    value: FixedExpenseService.modeInstallments,
                                    label: Text('Por parcelas'),
                                    icon: Icon(Icons.receipt_long_rounded,
                                        size: 20)),
                              ],
                              selected: {mode},
                              onSelectionChanged: (Set<String> sel) =>
                                  setModalState(() {
                                final prev = mode;
                                mode = sel.first;
                                if (mode ==
                                    FixedExpenseService.modeInstallments) {
                                  if (prev !=
                                      FixedExpenseService.modeInstallments) {
                                    totalParcelas = 12;
                                    parcelaInicial = 1;
                                    totalParcelasCtrl.text = '12';
                                    parcelaIniCtrl.text = '1';
                                  } else {
                                    parcelaInicial =
                                        parcelaInicial.clamp(1, totalParcelas);
                                    parcelaIniCtrl.text = '$parcelaInicial';
                                  }
                                } else {
                                  endDate ??= DateTime(startDate.year + 1,
                                      startDate.month, startDate.day);
                                }
                              }),
                              style: ButtonStyle(
                                visualDensity: VisualDensity.compact,
                                padding: WidgetStateProperty.all(
                                    const EdgeInsets.symmetric(
                                        vertical: 10, horizontal: 12)),
                              ),
                            ),
                          ),
                          if (mode == FixedExpenseService.modeInstallments) ...[
                            SizedBox(height: 16),
                            FastTextField(
                              controller: totalParcelasCtrl,
                              focusNode: totalParcelasFocus,
                              keyboardType: TextInputType.number,
                              scrollPadding: _kFixedFlowKeyboardScrollPad,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              decoration: _fixedFlowPremiumInputDeco(
                                context,
                                labelText: 'Total de parcelas',
                                hintText: 'Ex.: 12 ou 360',
                                helperText:
                                    'Máximo ${AppBusinessRules.maxFixedFlowInstallments} parcelas',
                                prefixIcon: Icon(Icons.numbers_rounded,
                                    color: AppColors.primary
                                        .withValues(alpha: 0.88)),
                              ),
                              onTap: () =>
                                  scrollFieldIntoView(totalParcelasFocus),
                              onChanged: (s) {
                                final v = int.tryParse(s.trim());
                                if (v == null || v < 1) return;
                                setModalState(() {
                                  totalParcelas = v.clamp(
                                      1,
                                      AppBusinessRules
                                          .maxFixedFlowInstallments);
                                  parcelaInicial =
                                      parcelaInicial.clamp(1, totalParcelas);
                                  if (parcelaIniCtrl.text !=
                                      '$parcelaInicial') {
                                    parcelaIniCtrl.text = '$parcelaInicial';
                                  }
                                });
                              },
                            ),
                            SizedBox(height: 12),
                            FastTextField(
                              controller: parcelaIniCtrl,
                              focusNode: parcelaIniFocus,
                              keyboardType: TextInputType.number,
                              scrollPadding: _kFixedFlowKeyboardScrollPad,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              decoration: _fixedFlowPremiumInputDeco(
                                context,
                                labelText: 'Começar da parcela nº',
                                helperText:
                                    'Ex.: já pagou 3 de 12 — comece da 4ª',
                                prefixIcon: Icon(Icons.play_arrow_rounded,
                                    color: AppColors.primary
                                        .withValues(alpha: 0.88)),
                              ),
                              onTap: () => scrollFieldIntoView(parcelaIniFocus),
                              onChanged: (s) {
                                final v = int.tryParse(s.trim());
                                if (v == null || v < 1) return;
                                setModalState(() =>
                                    parcelaInicial = v.clamp(1, totalParcelas));
                              },
                            ),
                          ],
                          SizedBox(height: 16),
                          ListTile(
                            tileColor: context.appChipIdleBg,
                            title: Text(mode ==
                                    FixedExpenseService.modeInstallments
                                ? 'Data da primeira parcela (que você controla)'
                                : 'Data início'),
                            subtitle: Text(
                                DateFormat('dd/MM/yyyy').format(startDate)),
                            trailing: Icon(Icons.edit_calendar_rounded,
                                color:
                                    AppColors.primary.withValues(alpha: 0.85)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                  color: AppColors.primary
                                      .withValues(alpha: 0.18)),
                            ),
                            onTap: () async {
                              final p = await showDatePicker(
                                  context: context,
                                  initialDate: startDate,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2035));
                              if (p != null) setModalState(() => startDate = p);
                            },
                          ),
                          if (mode == FixedExpenseService.modePeriod) ...[
                            SizedBox(height: 12),
                            ListTile(
                              tileColor: context.appChipIdleBg,
                              title: Text('Data fim (opcional)'),
                              subtitle: Text(endDate == null
                                  ? 'Sem data fim'
                                  : DateFormat('dd/MM/yyyy').format(endDate!)),
                              trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (endDate != null)
                                      IconButton(
                                        icon: Icon(Icons.clear_rounded),
                                        onPressed: () =>
                                            setModalState(() => endDate = null),
                                        tooltip: 'Remover data fim',
                                      ),
                                    Icon(Icons.edit_calendar_rounded,
                                        color: AppColors.primary
                                            .withValues(alpha: 0.85)),
                                  ]),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.18)),
                              ),
                              onTap: () async {
                                final p = await showDatePicker(
                                  context: context,
                                  initialDate: endDate ??
                                      startDate.add(const Duration(days: 365)),
                                  firstDate: startDate,
                                  lastDate: DateTime(2040),
                                );
                                if (p != null) setModalState(() => endDate = p);
                              },
                            ),
                          ] else
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                'Serão geradas ${totalParcelas - parcelaInicial + 1} parcelas (da $parcelaInicialª à $totalParcelasª).',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: context.appTextSecondary),
                              ),
                            ),
                          SizedBox(height: 24),
                          _buildSuperPremiumActionButton(
                            ctx: context,
                            isEdit: isEdit,
                            onPressed: () async {
                              final desc = descCtrl.text.trim();
                              final amount = CurrencyFormats.parseBRLInput(
                                      amountCtrl.text) ??
                                  0;
                              if (mode ==
                                  FixedExpenseService.modeInstallments) {
                                totalParcelas = (int.tryParse(
                                            totalParcelasCtrl.text.trim()) ??
                                        totalParcelas)
                                    .clamp(
                                        1,
                                        AppBusinessRules
                                            .maxFixedFlowInstallments);
                                parcelaInicial =
                                    (int.tryParse(parcelaIniCtrl.text.trim()) ??
                                            1)
                                        .clamp(1, totalParcelas);
                              }
                              if (desc.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Informe a descrição.')));
                                return;
                              }
                              if (amount <= 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Informe um valor maior que zero.')));
                                return;
                              }
                              if (mode ==
                                      FixedExpenseService.modeInstallments &&
                                  (totalParcelas < 1 ||
                                      parcelaInicial < 1 ||
                                      parcelaInicial > totalParcelas)) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Por parcelas: informe total de parcelas e parcela inicial válidos.')));
                                return;
                              }
                              DateTime? effectiveEnd = endDate;
                              if (mode ==
                                  FixedExpenseService.modeInstallments) {
                                // Último dia do mês final (início dia 29–31
                                // não transborda para o mês seguinte).
                                effectiveEnd =
                                    FixedFlowSchedule.installmentsEndDate(
                                  start: startDate,
                                  totalParcelas: totalParcelas,
                                  parcelaInicial: parcelaInicial,
                                );
                              }
                              try {
                                if (isEdit && id != null) {
                                  final updatedCount = await _service.update(
                                    uid: _fsUid,
                                    id: id,
                                    description: desc,
                                    category: category,
                                    amount: amount,
                                    dayOfMonth: dayOfMonth,
                                    startDate: startDate,
                                    endDate: effectiveEnd,
                                    mode: mode,
                                    totalParcelas: mode ==
                                            FixedExpenseService.modeInstallments
                                        ? totalParcelas
                                        : null,
                                    parcelaInicial: mode ==
                                            FixedExpenseService.modeInstallments
                                        ? parcelaInicial
                                        : null,
                                    addToCalendar: addToCalendar,
                                    calendarColorHex: calendarColorHex,
                                    financeAccountId: financeAccountId,
                                    clearFinanceAccount:
                                        (financeAccountId ?? '').isEmpty,
                                  );
                                  if (context.mounted) {
                                    if (updatedCount > 0) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                              content: Text(
                                                  'Despesa fixa atualizada. $updatedCount parcela(s) futura(s) ajustada(s) para o novo dia.')));
                                    } else {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                              content: Text(
                                                  'Despesa fixa atualizada.')));
                                    }
                                  }
                                } else {
                                  await _service.add(
                                    uid: _fsUid,
                                    description: desc,
                                    category: category,
                                    amount: amount,
                                    dayOfMonth: dayOfMonth,
                                    startDate: startDate,
                                    endDate: effectiveEnd,
                                    mode: mode,
                                    totalParcelas: mode ==
                                            FixedExpenseService.modeInstallments
                                        ? totalParcelas
                                        : null,
                                    parcelaInicial: mode ==
                                            FixedExpenseService.modeInstallments
                                        ? parcelaInicial
                                        : null,
                                    addToCalendar: addToCalendar,
                                    calendarColorHex: calendarColorHex,
                                    financeAccountId: financeAccountId,
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Despesa fixa criada. Gerando lançamentos no Financeiro…')),
                                    );
                                  }
                                }
                                // Parcelas só aqui (não ao reabrir o módulo Financeiro), para não duplicar mês já pago.
                                try {
                                  final monthsAhead = await _prefsService
                                      .getPendingMonthsAhead(_fsUid);
                                  final created = await _service
                                      .ensureMonthlyEntries(_fsUid,
                                          monthsAhead: monthsAhead);
                                  if (context.mounted && created > 0) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(
                                              '$created lançamento(s) criado(s) no Financeiro.')),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            'Erro ao gerar parcelas no Financeiro: ${e.toString().split('\n').first}'),
                                        backgroundColor: AppColors.error,
                                      ),
                                    );
                                  }
                                }
                                // Banco/caixa e demais campos nos pendentes já propagados no update.
                                FinanceMonthCache.clearUid(_fsUid);
                                FinanceTransactionsHub.notifyMutated(
                                    uid: _fsUid);
                                if (context.mounted) {
                                  Navigator.pop(context, true);
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(
                                              'Erro: ${e.toString().split('\n').first}')));
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ) ??
          false;
    } finally {
      disposeFormCtrls();
    }
    if (ok == true && mounted) _refreshFixedExpenses();
  }

  Future<void> _openPreferencesSheet() async {
    Map<String, dynamic>? current;
    try {
      current = await _prefsService.watch(_fsUid).first;
    } catch (_) {}
    if (!mounted) return;
    final result = await showFixedPendingPrefsSheet(
      context: context,
      initialShowInPending: fixedPendingShowFromMap(current),
      initialMonthsAhead: fixedPendingMonthsAheadFromMap(current),
      isExpense: true,
    );
    if (result == null || !mounted) return;
    await _prefsService.set(
      _fsUid,
      showInPending: result.showInPending,
      pendingMonthsAhead: result.pendingMonthsAhead,
    );
  }

  /// Botão flutuante super premium: gradiente, sombra, bordas arredondadas.
  Widget _buildSuperPremiumFab(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: AppColors.deepBlueDark.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () => _openForm(),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  AppColors.deepBlueDark,
                  AppColors.primary,
                  AppColors.accent
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, color: Colors.white, size: 26),
                SizedBox(width: 12),
                Text(
                  'Nova despesa fixa',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Botão de ação (Salvar / Criar) no formulário — estilo super premium.
  Widget _buildSuperPremiumActionButton({
    required BuildContext ctx,
    required bool isEdit,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: AppColors.logoGradient,
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
              color: AppColors.deepBlueDark.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6)),
          BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.22),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_rounded, color: Colors.white, size: 22),
                SizedBox(width: 10),
                Text(
                  isEdit ? 'Salvar alterações' : 'Criar despesa fixa',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: Colors.white,
                      letterSpacing: 0.25),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    // 'pendentes' = padrão Controle Total (pendentes saem da Agenda e do
    // Financeiro; pagos ficam). 'todas' = opção que o WISDOMAPP já tinha:
    // remover também os lançamentos pagos desta fixa.
    final escolha = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir despesa fixa?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${item['description']} não gerará mais lançamentos.'),
            const SizedBox(height: 16),
            const Text(
              'Todos os lançamentos pendentes serão removidos do Financeiro, da Agenda e do calendário. Lançamentos já pagos permanecem.',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'todas'),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Remover também os pagos'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'pendentes'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    final confirm = escolha != null;
    if (confirm != true || !mounted) return;
    try {
      final id = item['id'].toString();
      final todas = await (escolha == 'todas'
          ? _service.deleteAllParcelas(_fsUid, id)
          : Future<int>.value(0));
      final removed = todas + await _service.delete(_fsUid, id);
      FinanceMonthCache.clearUid(_fsUid);
      FinanceTransactionsHub.notifyMutated(uid: _fsUid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              removed > 0
                  ? 'Despesa fixa excluída. $removed lançamento(s) pendente(s) removido(s) da Agenda e do Financeiro.'
                  : 'Despesa fixa excluída. Nenhum pendente restante na Agenda.',
            ),
          ),
        );
      }
      if (mounted) _refreshFixedExpenses();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro: ${e.toString().split('\n').first}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ModernModuleUI.scaffoldBgOf(context),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Despesas fixas Premium',
          style: TextStyle(
              fontWeight: FontWeight.w900, fontSize: 19, letterSpacing: 0.2),
        ),
        leadingWidth: 118,
        leading: const NavyBackButton(),
        actions: [
          IconButton(
            tooltip: 'Exibição nas contas pendentes',
            icon: Icon(Icons.tune_rounded),
            onPressed: _openPreferencesSheet,
            style: IconButton.styleFrom(foregroundColor: Colors.white),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: () => Navigator.maybePop(context),
            child:
                Text('Cancelar', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: AppColors.logoGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
        ),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _fixedExpensesFuture,
        builder: (context, snap) {
          // Recarga (depois de salvar/pagar) mantém a lista anterior na tela
          // em vez de trocar tudo por um spinner; erro/prazo estourado mostra
          // «Tentar de novo» — antes caía em «Nenhuma … fixa», como se as
          // fixas tivessem sumido.
          if (snap.hasData) _ultimasFixas = snap.data;
          if (snap.connectionState == ConnectionState.waiting &&
              _ultimasFixas == null) {
            return Center(
                child: CircularProgressIndicator(
                    color: AppColors.primary.withValues(alpha: 0.9)));
          }
          if (snap.hasError && _ultimasFixas == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: FinanceLoadErrorBox(
                  error: snap.error,
                  onRetry: _refreshFixedExpenses,
                ),
              ),
            );
          }
          final items = snap.data ?? _ultimasFixas ?? const <Map<String, dynamic>>[];
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    24, 0, 24, 120 + MediaQuery.paddingOf(context).bottom),
                child: Text(
                  'Nenhuma despesa fixa. Toque em «Nova despesa fixa» para adicionar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 15,
                      color: context.appTextSecondary.withValues(alpha: 0.95),
                      height: 1.4),
                ),
              ),
            );
          }
          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Visão geral no topo: total do período, pago × a vencer,
              // gráfico mês a mês e rateio por categoria. A lista das
              // fixas cadastradas continua logo abaixo, para editar.
              // «Suas despesas fixas por mês: R$ X» — abre o relatório
              // mês a mês (pedido do dono, 30/09/2026).
              // «O que tenho que pagar» do mês: vencidas, próximos 7
              // dias e pagas, com o botão de quitar (pedido do dono, 01/10/2026).
              // Totalizador das fixas cadastradas (pedido do dono, 30/09/2026).
              SliverToBoxAdapter(
                child: FixasTotalizadorCard(items: items, receita: false, uid: _fsUid),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: Text(
                    'Suas despesas fixas (${items.length})',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: context.appTextPrimary),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final e = items[i];
                      final amount = (e['amount'] as num?)?.toDouble() ?? 0;
                      final catName = (e['category'] ?? 'Despesa').toString();
                      final vis =
                          financeCategoryVisualFor(catName, isIncome: false);
                      final startTs = e['startDate'];
                      final endTs = e['endDate'];
                      final start =
                          startTs is Timestamp ? startTs.toDate() : null;
                      final end = endTs is Timestamp ? endTs.toDate() : null;
                      final day = (e['dayOfMonth'] as num?)?.toInt() ?? 1;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => _openForm(existing: e),
                            child: Container(
                              decoration: BoxDecoration(
                                color: ModernModuleUI.cardBg(context),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                    color: vis.color.withValues(alpha: 0.22)),
                                boxShadow: [
                                  BoxShadow(
                                    color: vis.color.withValues(alpha: 0.12),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: ListTile(
                                visualDensity: VisualDensity.compact,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 6),
                                leading: financeCategoryLeadingTile(catName,
                                    isIncome: false),
                                title: Text(
                                  catName,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: context.appTextPrimary,
                                      fontSize: 15),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${(e['description'] ?? '').toString()} · ${_subtitleFixedExpense(e, day, start, end, includeCategory: false)}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: context.appTextSecondary
                                                .withValues(alpha: 0.95),
                                            height: 1.35),
                                      ),
                                    ],
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(CurrencyFormats.formatBRL(amount),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            color: AppColors.error,
                                            fontSize: 15)),
                                    PopupMenuButton<String>(
                                      icon: Icon(Icons.more_vert_rounded,
                                          color: context.appTextMuted
                                              .withValues(alpha: 0.9)),
                                      padding: EdgeInsets.zero,
                                      onSelected: (v) {
                                        if (v == 'edit') _openForm(existing: e);
                                        if (v == 'delete') _delete(e);
                                      },
                                      itemBuilder: (_) => [
                                        const PopupMenuItem(
                                            value: 'edit',
                                            child: Row(children: [
                                              Icon(Icons.edit_rounded,
                                                  size: 20),
                                              SizedBox(width: 8),
                                              Text('Editar')
                                            ])),
                                        const PopupMenuItem(
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
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                    childCount: items.length,
                  ),
                ),
              ),
              // Depois da lista: pesquisa por mês/ano/período, relatório mês a
              // mês e «o que tenho que pagar» (ordem pedida pelo dono, 01/10/2026:
              // primeiro o total com gráfico, depois as fixas cadastradas).
              SliverToBoxAdapter(
                child: FixasVisaoGeral(uid: _fsUid, receita: false),
              ),
              SliverToBoxAdapter(
                child: FixasPorMesCard(uid: _fsUid, receita: false),
              ),
              SliverToBoxAdapter(
                child: FixasAPagarPainel(uid: _fsUid, receita: false),
              ),
              SliverPadding(
                  padding: EdgeInsets.only(
                      bottom: 120 + MediaQuery.paddingOf(context).bottom)),
            ],
          );
        },
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom > 0 ? 8 : 0),
        child: _buildSuperPremiumFab(context),
      ),
    );
  }

  Widget _buildAddToCalendarToggle({
    required BuildContext context,
    required bool isIncome,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final accent = isIncome ? const Color(0xFF2E7D32) : const Color(0xFFE53935);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(
            value ? Icons.event_available_rounded : Icons.event_busy_rounded,
            size: 20,
            color: accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
            value: value,
            activeThumbColor: accent,
            activeTrackColor: accent.withValues(alpha: 0.5),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarColorButton({
    required BuildContext context,
    required bool isIncome,
    required String? currentHex,
    required ValueChanged<String?> onChanged,
  }) {
    final defaultHex = FinanceCalendarColorPicker.defaultHexFor(isIncome);
    final effectiveHex = currentHex ?? defaultHex;
    var clean = effectiveHex
        .replaceFirst('#', '')
        .replaceFirst(RegExp(r'^0x', caseSensitive: false), '');
    if (clean.length > 6) clean = clean.substring(clean.length - 6);
    final color = Color(int.parse('FF$clean', radix: 16));
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(14),
      elevation: 2,
      shadowColor: color.withValues(alpha: 0.45),
      child: InkWell(
        onTap: () async {
          final picked = await FinanceCalendarColorPicker.show(
            context,
            isIncome: isIncome,
            currentHex: currentHex,
          );
          onChanged(picked);
        },
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 44,
          width: double.infinity,
          child: Center(
            child: Text(
              'Cor no calendário',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.25,
                fontSize: 13.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
