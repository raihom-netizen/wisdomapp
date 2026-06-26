import 'dart:async';

import 'package:flutter/material.dart' hide showDatePicker;
import '../widgets/fast_text_field.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../constants/currency_formats.dart';
import '../constants/finance_category_visuals.dart';
import '../constants/app_business_rules.dart';
import '../services/fixed_expense_service.dart';
import '../services/fixed_expense_preferences_service.dart';
import '../services/user_categories_service.dart';
import '../utils/date_picker_a11y.dart';
import '../utils/firestore_user_doc_id.dart';
import '../widgets/brl_amount_text_field.dart';
/// Espaço extra para o [Scrollable] rolar o campo acima do teclado no sheet.
const EdgeInsets _kFixedFlowKeyboardScrollPad = EdgeInsets.fromLTRB(0, 0, 0, 260);

InputDecoration _fixedFlowPremiumInputDeco({
  required String labelText,
  String? hintText,
  String? helperText,
  Widget? prefixIcon,
}) {
  const radius = BorderRadius.all(Radius.circular(14));
  const side = BorderSide(color: Color(0xFFE2E8F0));
  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    helperText: helperText,
    filled: true,
    fillColor: const Color(0xFFF8FAFC),
    isDense: true,
    border: const OutlineInputBorder(borderRadius: radius, borderSide: side),
    enabledBorder: const OutlineInputBorder(borderRadius: radius, borderSide: side),
    focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: AppColors.primary, width: 2)),
    prefixIcon: prefixIcon,
  );
}

InputDecoration _fixedFlowPremiumDropdownDeco({required Widget prefixIcon}) {
  const radius = BorderRadius.all(Radius.circular(14));
  const side = BorderSide(color: Color(0xFFE2E8F0));
  return InputDecoration(
    filled: true,
    fillColor: const Color(0xFFF8FAFC),
    isDense: true,
    floatingLabelBehavior: FloatingLabelBehavior.never,
    border: const OutlineInputBorder(borderRadius: radius, borderSide: side),
    enabledBorder: const OutlineInputBorder(borderRadius: radius, borderSide: side),
    focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: AppColors.primary, width: 2)),
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
  final FixedExpensePreferencesService _prefsService = FixedExpensePreferencesService();
  List<String> _expenseCategories = [];
  Future<List<Map<String, dynamic>>>? _fixedExpensesFuture;
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
    final value = category == kIncluirNova || expenseCategories.contains(category)
        ? category
        : (expenseCategories.isNotEmpty ? expenseCategories.first : kIncluirNova);
    return DropdownButtonFormField<String>(
      isExpanded: true,
      value: options.contains(value) ? value : (expenseCategories.isNotEmpty ? expenseCategories.first : kIncluirNova),
      decoration: _fixedFlowPremiumDropdownDeco(
        prefixIcon: Icon(Icons.category_outlined, color: AppColors.primary.withValues(alpha: 0.88)),
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

  String _subtitleFixedExpense(Map<String, dynamic> e, int day, DateTime? start, DateTime? end, {bool includeCategory = true}) {
    final mode = (e['mode'] ?? FixedExpenseService.modePeriod).toString();
    final cat = e['category'] ?? 'Despesa';
    final periodTail =
        'Dia $day · ${start != null ? DateFormat("MM/yyyy").format(start) : '?'} até ${end != null ? DateFormat("MM/yyyy").format(end) : 'sem fim'}';
    late final String tail;
    if (mode == FixedExpenseService.modeInstallments) {
      final total = (e['totalParcelas'] as num?)?.toInt();
      final ini = (e['parcelaInicial'] as num?)?.toInt();
      if (total != null) {
        final parcelaInfo = ini != null && ini > 1 ? 'Da parcela $ini até $total' : '$total parcelas';
        tail = 'Dia $day · $parcelaInfo · ${start != null ? DateFormat("MM/yyyy").format(start) : "?"}';
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
    final descCtrl = TextEditingController(text: existing?['description']?.toString() ?? '');
    final amountCtrl = TextEditingController(
      text: existing != null && existing['amount'] != null
          ? CurrencyFormats.formatBRLInput((existing['amount'] as num).toDouble())
          : '',
    );
    String category = existing?['category']?.toString() ?? (_expenseCategories.isNotEmpty ? _expenseCategories.first : 'Despesa');
    int dayOfMonth = (existing?['dayOfMonth'] as num?)?.toInt() ?? 10;
    final now = DateTime.now();
    DateTime startDate = existing != null && existing['startDate'] is Timestamp
        ? (existing['startDate'] as Timestamp).toDate()
        : DateTime(now.year, now.month, 1);
    DateTime? endDate = existing != null && existing['endDate'] is Timestamp
        ? (existing['endDate'] as Timestamp).toDate()
        : DateTime(now.year + 1, now.month, 1);
    String mode = (existing?['mode'] ?? FixedExpenseService.modePeriod).toString();
    int totalParcelas = (existing?['totalParcelas'] as num?)?.toInt() ?? 12;
    int parcelaInicial = (existing?['parcelaInicial'] as num?)?.toInt() ?? 1;
    if (mode == FixedExpenseService.modeInstallments) {
      totalParcelas = totalParcelas.clamp(1, AppBusinessRules.maxFixedFlowInstallments);
      parcelaInicial = parcelaInicial.clamp(1, totalParcelas);
    }
    final isEdit = existing != null;
    final id = existing?['id']?.toString();
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
                backgroundColor: Colors.white,
                appBar: AppBar(
                  elevation: 0,
                  leading: IconButton(
                    tooltip: 'Fechar',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.maybePop(ctx, false),
                    style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                  ),
                  title: Row(
                    children: [
                      Icon(Icons.repeat_rounded, color: AppColors.primary, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isEdit ? 'Editar despesa fixa' : 'Nova despesa fixa',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xFF1A237E)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                body: SafeArea(
                  child: ListView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + MediaQuery.paddingOf(ctx).bottom),
                    children: [
                        RepaintBoundary(
                          child: FastTextField(
                            controller: descCtrl,
                            scrollPadding: _kFixedFlowKeyboardScrollPad,
                            decoration: _fixedFlowPremiumInputDeco(
                              labelText: 'Descrição',
                              hintText: 'Ex: Aluguel, Internet',
                              prefixIcon: Icon(Icons.description_outlined, color: AppColors.primary.withValues(alpha: 0.88)),
                            ),
                            textCapitalization: TextCapitalization.sentences,
                            enableSuggestions: false,
                            autocorrect: false,
                          ),
                        ),
                        const SizedBox(height: 16),
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
                                title: const Text('Nova categoria de despesa'),
                                content: FastTextField(
                                  controller: nameCtrl,
                                  decoration: const InputDecoration(
                                    hintText: 'Nome da categoria',
                                    border: OutlineInputBorder(),
                                  ),
                                  autofocus: true,
                                  textCapitalization: TextCapitalization.words,
                                ),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                                  FilledButton(
                                    onPressed: () {
                                      if (nameCtrl.text.trim().isEmpty) return;
                                      Navigator.pop(ctx, true);
                                    },
                                    child: const Text('Adicionar'),
                                  ),
                                ],
                              ),
                            );
                            if (added != true) return;
                            final name = nameCtrl.text.trim();
                            nameCtrl.dispose();
                            try {
                              await UserCategoriesService().addCustom(_fsUid, false, name);
                              if (!context.mounted) return;
                              final c = await UserCategoriesService().load(_fsUid);
                              if (!context.mounted) return;
                              final list =
                                  UserCategoriesService.sortedWithoutIncluirNova(c.expense);
                              setModalState(() {
                                category = name;
                                _expenseCategories = list;
                              });
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Categoria "$name" adicionada.')));
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Erro ao salvar: ${e.toString().split('\n').first}')),
                                );
                              }
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        RepaintBoundary(
                          child: BrlAmountTextField(
                            controller: amountCtrl,
                            scrollPadding: _kFixedFlowKeyboardScrollPad,
                            decoration: _fixedFlowPremiumInputDeco(
                              labelText: 'Valor (R\$)',
                              hintText: '0,00',
                              prefixIcon: Icon(Icons.attach_money_rounded, color: AppColors.primary.withValues(alpha: 0.88)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<int>(
                          value: dayOfMonth.clamp(1, 31),
                          decoration: _fixedFlowPremiumInputDeco(
                            labelText: 'Dia do mês do lançamento',
                            prefixIcon: Icon(Icons.calendar_today_rounded, color: AppColors.primary.withValues(alpha: 0.88)),
                          ),
                          items: List.generate(31, (i) => i + 1).map((d) => DropdownMenuItem(value: d, child: Text('Dia $d'))).toList(),
                          onChanged: (v) => setModalState(() => dayOfMonth = v ?? dayOfMonth),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.deepBlueDark.withValues(alpha: 0.92),
                                    AppColors.primary.withValues(alpha: 0.9),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: const Icon(Icons.tune_rounded, color: Colors.white, size: 18),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Tipo de controle',
                              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900, color: AppColors.textPrimary, letterSpacing: 0.15),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primary.withValues(alpha: 0.07),
                                AppColors.accent.withValues(alpha: 0.05),
                              ],
                            ),
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.14)),
                          ),
                          padding: const EdgeInsets.all(5),
                          child: SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: FixedExpenseService.modePeriod, label: Text('Por período'), icon: Icon(Icons.date_range_rounded, size: 20)),
                              ButtonSegment(value: FixedExpenseService.modeInstallments, label: Text('Por parcelas'), icon: Icon(Icons.receipt_long_rounded, size: 20)),
                            ],
                            selected: {mode},
                            onSelectionChanged: (Set<String> sel) => setModalState(() {
                              final prev = mode;
                              mode = sel.first;
                              if (mode == FixedExpenseService.modeInstallments) {
                                if (prev != FixedExpenseService.modeInstallments) {
                                  totalParcelas = 12;
                                  parcelaInicial = 1;
                                  totalParcelasCtrl.text = '12';
                                  parcelaIniCtrl.text = '1';
                                } else {
                                  parcelaInicial = parcelaInicial.clamp(1, totalParcelas);
                                  parcelaIniCtrl.text = '$parcelaInicial';
                                }
                              } else {
                                endDate ??= DateTime(startDate.year + 1, startDate.month, startDate.day);
                              }
                            }),
                            style: ButtonStyle(
                              visualDensity: VisualDensity.compact,
                              padding: WidgetStateProperty.all(const EdgeInsets.symmetric(vertical: 10, horizontal: 12)),
                            ),
                          ),
                        ),
                        if (mode == FixedExpenseService.modeInstallments) ...[
                          const SizedBox(height: 16),
                          FastTextField(
                            controller: totalParcelasCtrl,
                            focusNode: totalParcelasFocus,
                            keyboardType: TextInputType.number,
                            scrollPadding: _kFixedFlowKeyboardScrollPad,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: _fixedFlowPremiumInputDeco(
                              labelText: 'Total de parcelas',
                              hintText: 'Ex.: 12 ou 360',
                              helperText: 'Máximo ${AppBusinessRules.maxFixedFlowInstallments} parcelas',
                              prefixIcon: Icon(Icons.numbers_rounded, color: AppColors.primary.withValues(alpha: 0.88)),
                            ),
                            onTap: () => scrollFieldIntoView(totalParcelasFocus),
                            onChanged: (s) {
                              final v = int.tryParse(s.trim());
                              if (v == null || v < 1) return;
                              setModalState(() {
                                totalParcelas = v.clamp(1, AppBusinessRules.maxFixedFlowInstallments);
                                parcelaInicial = parcelaInicial.clamp(1, totalParcelas);
                                if (parcelaIniCtrl.text != '$parcelaInicial') parcelaIniCtrl.text = '$parcelaInicial';
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          FastTextField(
                            controller: parcelaIniCtrl,
                            focusNode: parcelaIniFocus,
                            keyboardType: TextInputType.number,
                            scrollPadding: _kFixedFlowKeyboardScrollPad,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: _fixedFlowPremiumInputDeco(
                              labelText: 'Começar da parcela nº',
                              helperText: 'Ex.: já pagou 3 de 12 — comece da 4ª',
                              prefixIcon: Icon(Icons.play_arrow_rounded, color: AppColors.primary.withValues(alpha: 0.88)),
                            ),
                            onTap: () => scrollFieldIntoView(parcelaIniFocus),
                            onChanged: (s) {
                              final v = int.tryParse(s.trim());
                              if (v == null || v < 1) return;
                              setModalState(() => parcelaInicial = v.clamp(1, totalParcelas));
                            },
                          ),
                        ],
                        const SizedBox(height: 16),
                        ListTile(
                          tileColor: const Color(0xFFF8FAFC),
                          title: Text(mode == FixedExpenseService.modeInstallments ? 'Data da primeira parcela (que você controla)' : 'Data início'),
                          subtitle: Text(DateFormat('dd/MM/yyyy').format(startDate)),
                          trailing: Icon(Icons.edit_calendar_rounded, color: AppColors.primary.withValues(alpha: 0.85)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(color: AppColors.primary.withValues(alpha: 0.18)),
                          ),
                          onTap: () async {
                            final p = await showDatePicker(context: context, initialDate: startDate, firstDate: DateTime(2020), lastDate: DateTime(2035));
                            if (p != null) setModalState(() => startDate = p);
                          },
                        ),
                        if (mode == FixedExpenseService.modePeriod) ...[
                          const SizedBox(height: 12),
                          ListTile(
                            tileColor: const Color(0xFFF8FAFC),
                            title: const Text('Data fim (opcional)'),
                            subtitle: Text(endDate == null ? 'Sem data fim' : DateFormat('dd/MM/yyyy').format(endDate!)),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              if (endDate != null)
                                IconButton(
                                  icon: const Icon(Icons.clear_rounded),
                                  onPressed: () => setModalState(() => endDate = null),
                                  tooltip: 'Remover data fim',
                                ),
                              Icon(Icons.edit_calendar_rounded, color: AppColors.primary.withValues(alpha: 0.85)),
                            ]),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(color: AppColors.primary.withValues(alpha: 0.18)),
                            ),
                            onTap: () async {
                              final p = await showDatePicker(
                                context: context,
                                initialDate: endDate ?? startDate.add(const Duration(days: 365)),
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
                              'Serão geradas ${totalParcelas - parcelaInicial + 1} parcelas (da $parcelaInicialª à ${totalParcelas}ª).',
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                            ),
                          ),
                        const SizedBox(height: 24),
                        _buildSuperPremiumActionButton(
                          ctx: context,
                          isEdit: isEdit,
                          onPressed: () async {
                            final desc = descCtrl.text.trim();
                            final amount = CurrencyFormats.parseBRLInput(amountCtrl.text) ?? 0;
                            if (mode == FixedExpenseService.modeInstallments) {
                              totalParcelas = (int.tryParse(totalParcelasCtrl.text.trim()) ?? totalParcelas)
                                  .clamp(1, AppBusinessRules.maxFixedFlowInstallments);
                              parcelaInicial = (int.tryParse(parcelaIniCtrl.text.trim()) ?? 1).clamp(1, totalParcelas);
                            }
                            if (desc.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe a descrição.')));
                              return;
                            }
                            if (amount <= 0) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe um valor maior que zero.')));
                              return;
                            }
                            if (mode == FixedExpenseService.modeInstallments && (totalParcelas < 1 || parcelaInicial < 1 || parcelaInicial > totalParcelas)) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Por parcelas: informe total de parcelas e parcela inicial válidos.')));
                              return;
                            }
                            DateTime? effectiveEnd = endDate;
                            if (mode == FixedExpenseService.modeInstallments) {
                              final meses = totalParcelas - parcelaInicial + 1;
                              effectiveEnd = DateTime(startDate.year, startDate.month + meses - 1, startDate.day);
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
                                  totalParcelas: mode == FixedExpenseService.modeInstallments ? totalParcelas : null,
                                  parcelaInicial: mode == FixedExpenseService.modeInstallments ? parcelaInicial : null,
                                );
                                if (context.mounted) {
                                  if (updatedCount > 0) {
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Despesa fixa atualizada. $updatedCount parcela(s) futura(s) ajustada(s) para o novo dia.')));
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Despesa fixa atualizada.')));
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
                                  totalParcelas: mode == FixedExpenseService.modeInstallments ? totalParcelas : null,
                                  parcelaInicial: mode == FixedExpenseService.modeInstallments ? parcelaInicial : null,
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Despesa fixa criada. Gerando lançamentos no Financeiro…')),
                                  );
                                }
                              }
                              // Parcelas só aqui (não ao reabrir o módulo Financeiro), para não duplicar mês já pago.
                              try {
                                final monthsAhead = await _prefsService.getPendingMonthsAhead(_fsUid);
                                final created = await _service.ensureMonthlyEntries(_fsUid, monthsAhead: monthsAhead);
                                if (context.mounted && created > 0) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('$created lançamento(s) criado(s) no Financeiro.')),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Erro ao gerar parcelas no Financeiro: ${e.toString().split('\n').first}'),
                                      backgroundColor: AppColors.error,
                                    ),
                                  );
                                }
                              }
                              if (context.mounted) Navigator.pop(context, true);
                            } catch (e) {
                              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: ${e.toString().split('\n').first}')));
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

  /// Card de preferências: mostrar nas contas pendentes e próximos X meses.
  Widget _buildPreferencesCard() {
    return StreamBuilder<Map<String, dynamic>>(
      stream: _prefsService.watch(_fsUid),
      builder: (context, snap) {
        final showInPending = snap.data?['showInPending'] as bool? ?? true;
        final monthsAhead = (snap.data?['pendingMonthsAhead'] as int?)?.clamp(1, 12) ?? AppBusinessRules.pendingMonthsAheadDefault;
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
            boxShadow: [
              BoxShadow(
                color: AppColors.deepBlueDark.withValues(alpha: 0.06),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.deepBlueDark.withValues(alpha: 0.95),
                          AppColors.primary.withValues(alpha: 0.95),
                          AppColors.accent.withValues(alpha: 0.9),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.tune_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Exibição nas contas pendentes',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.textPrimary, letterSpacing: 0.15),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SwitchListTile(
                value: showInPending,
                onChanged: (v) => _prefsService.set(_fsUid, showInPending: v),
                title: const Text('Mostrar despesas fixas nas contas pendentes', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                contentPadding: EdgeInsets.zero,
                activeTrackColor: AppColors.primary.withValues(alpha: 0.45),
                activeThumbColor: Colors.white,
                inactiveThumbColor: Colors.white,
                inactiveTrackColor: Colors.grey.shade300,
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('Próximos ', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                    DropdownButton<int>(
                      value: monthsAhead,
                      isDense: true,
                      underline: const SizedBox(),
                      items: List.generate(12, (i) => i + 1).map((m) => DropdownMenuItem(value: m, child: Text('$m mês(es)'))).toList(),
                      onChanged: (v) {
                        if (v != null) _prefsService.set(_fsUid, pendingMonthsAhead: v);
                      },
                    ),
                    const Text(' nas despesas pendentes', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openPreferencesSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.paddingOf(ctx).bottom),
        child: _buildPreferencesCard(),
      ),
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
                colors: [AppColors.deepBlueDark, AppColors.primary, AppColors.accent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
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
          BoxShadow(color: AppColors.deepBlueDark.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6)),
          BoxShadow(color: AppColors.accent.withValues(alpha: 0.22), blurRadius: 10, offset: const Offset(0, 3)),
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
                const Icon(Icons.check_rounded, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Text(
                  isEdit ? 'Salvar alterações' : 'Criar despesa fixa',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.white, letterSpacing: 0.25),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final removeParcelas = await showDialog<bool?>(
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
              'Deseja também remover todas as parcelas já criadas no Financeiro? (pendentes e pagas)',
              style: TextStyle(fontSize: 13, color: Colors.black87),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Excluir só a despesa'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Excluir e remover parcelas'),
          ),
        ],
      ),
    );
    if (removeParcelas == null || !mounted) return;
    try {
      final id = item['id'].toString();
      if (removeParcelas) {
        final count = await _service.deleteAllParcelas(_fsUid, id);
        await _service.delete(_fsUid, id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Despesa fixa excluída e $count lançamento(s) removido(s) do Financeiro.')),
          );
        }
      } else {
        await _service.delete(_fsUid, id);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Despesa fixa excluída. Os lançamentos já criados permanecem.')));
      }
      if (mounted) _refreshFixedExpenses();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: ${e.toString().split('\n').first}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    const scaffoldBg = Color(0xFFF4F7FA);
    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Despesas fixas Premium',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19, letterSpacing: 0.2),
        ),
        leading: IconButton(
          tooltip: 'Voltar',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.maybePop(context),
          style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
        ),
        actions: [
          IconButton(
            tooltip: 'Exibição nas contas pendentes',
            icon: const Icon(Icons.tune_rounded),
            onPressed: _openPreferencesSheet,
            style: IconButton.styleFrom(foregroundColor: Colors.white),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: () => Navigator.maybePop(context),
            child: const Text('Cancelar', style: TextStyle(fontWeight: FontWeight.w700)),
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
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: AppColors.primary.withValues(alpha: 0.9)));
          }
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, 0, 24, 120 + MediaQuery.paddingOf(context).bottom),
                child: Text(
                  'Nenhuma despesa fixa. Toque em «Nova despesa fixa» para adicionar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: AppColors.textSecondary.withValues(alpha: 0.95), height: 1.4),
                ),
              ),
            );
          }
          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final e = items[i];
              final amount = (e['amount'] as num?)?.toDouble() ?? 0;
              final catName = (e['category'] ?? 'Despesa').toString();
              final vis = financeCategoryVisualFor(catName, isIncome: false);
              final startTs = e['startDate'];
              final endTs = e['endDate'];
              final start = startTs is Timestamp ? startTs.toDate() : null;
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
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: vis.color.withValues(alpha: 0.22)),
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
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  leading: financeCategoryLeadingTile(catName, isIncome: false),
                  title: Text(
                    catName,
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary, fontSize: 15),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                    '${(e['description'] ?? '').toString()} · ${_subtitleFixedExpense(e, day, start, end, includeCategory: false)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary.withValues(alpha: 0.95), height: 1.35),
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(CurrencyFormats.formatBRL(amount), style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.error, fontSize: 15)),
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert_rounded, color: AppColors.textMuted.withValues(alpha: 0.9)),
                        padding: EdgeInsets.zero,
                        onSelected: (v) {
                          if (v == 'edit') _openForm(existing: e);
                          if (v == 'delete') _delete(e);
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_rounded, size: 20), SizedBox(width: 8), Text('Editar')])),
                          const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline_rounded, size: 20), SizedBox(width: 8), Text('Excluir')])),
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
              SliverPadding(padding: EdgeInsets.only(bottom: 120 + MediaQuery.paddingOf(context).bottom)),
            ],
          );
        },
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom > 0 ? 8 : 0),
        child: _buildSuperPremiumFab(context),
      ),
    );
  }
}
