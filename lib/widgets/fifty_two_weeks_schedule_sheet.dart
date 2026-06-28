import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/currency_formats.dart';
import '../models/user_profile.dart';
import '../services/goal_52_weeks_pdf_service.dart';
import '../services/goal_deposit_service.dart';
import '../theme/app_colors.dart';
import '../utils/fifty_two_weeks_plan.dart';
import '../utils/goal_objective_visuals.dart';
import '../utils/premium_upgrade.dart';
import '../widgets/brl_amount_text_field.dart';
import '../widgets/goal_52_weeks_summary_panel.dart';
import '../widgets/goal_finance_account_field.dart';
import '../widgets/registrar_deposito_dialog.dart';
import 'sheet_voltar_controls.dart';

/// Exporta PDF depósitos × semanas (painel Início, módulo ou grade) — com preview.
Future<void> exportFiftyTwoWeeksGoalPdf({
  required BuildContext context,
  required QueryDocumentSnapshot<Map<String, dynamic>> goalDoc,
}) async {
  try {
    await Goal52WeeksPdfService.previewFromGoalDoc(
      context: context,
      goalRef: goalDoc.reference,
      goalData: goalDoc.data(),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF: ${e.toString().split('\n').first}')),
      );
    }
  }
}

Future<void> showFiftyTwoWeeksScheduleSheet({
  required BuildContext context,
  required QueryDocumentSnapshot<Map<String, dynamic>> goalDoc,
  required UserProfile profile,
  required String uid,
  bool depositMode = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: depositMode ? 0.88 : 0.9,
      minChildSize: 0.55,
      maxChildSize: 0.97,
      expand: false,
      builder: (ctx, scrollController) {
        return _FiftyTwoWeeksScheduleBody(
          goalDoc: goalDoc,
          profile: profile,
          uid: uid,
          scrollController: scrollController,
          depositMode: depositMode,
        );
      },
    ),
  );
}

enum _DepositFlowStep { selectWeeks, depositForm }

class _FiftyTwoWeeksScheduleBody extends StatefulWidget {
  const _FiftyTwoWeeksScheduleBody({
    required this.goalDoc,
    required this.profile,
    required this.uid,
    required this.scrollController,
    required this.depositMode,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> goalDoc;
  final UserProfile profile;
  final String uid;
  final ScrollController scrollController;
  final bool depositMode;

  @override
  State<_FiftyTwoWeeksScheduleBody> createState() =>
      _FiftyTwoWeeksScheduleBodyState();
}

class _FiftyTwoWeeksScheduleBodyState extends State<_FiftyTwoWeeksScheduleBody> {
  final Set<int> _selectedWeeks = {};
  final TextEditingController _amountCtrl = TextEditingController();
  String? _financeAccountId;
  double? _accountBalance;
  bool _saving = false;
  bool _pdfLoading = false;
  bool _syncingAmountFromSelection = false;
  _DepositFlowStep _depositStep = _DepositFlowStep.selectWeeks;

  @override
  void initState() {
    super.initState();
    final stored = (widget.goalDoc.data()['financeAccountId'] ?? '').toString().trim();
    if (stored.isNotEmpty) _financeAccountId = stored;
    _amountCtrl.addListener(_onAmountFieldChanged);
  }

  @override
  void dispose() {
    _amountCtrl.removeListener(_onAmountFieldChanged);
    _amountCtrl.dispose();
    super.dispose();
  }

  List<int> _paidWeeks(Map<String, dynamic> data) =>
      FiftyTwoWeeksPlan.paidWeeksFromData(data);

  void _onAmountFieldChanged() {
    if (!widget.depositMode || _syncingAmountFromSelection) return;
    final data = widget.goalDoc.data();
    final target = (data['targetAmount'] as num?)?.toDouble() ?? 0;
    final planStart =
        FiftyTwoWeeksPlan.planStartFromData(data) ?? DateTime.now();
    final schedule =
        FiftyTwoWeeksPlan.buildSchedule(target: target, planStart: planStart);
    final amount = CurrencyFormats.parseBRLInput(_amountCtrl.text) ?? 0;
    if (amount <= 0) {
      if (_selectedWeeks.isNotEmpty) {
        setState(() => _selectedWeeks.clear());
      }
      return;
    }
    final auto = FiftyTwoWeeksPlan.weeksForDepositAmount(
      amount: amount,
      schedule: schedule,
      paidWeeks: _paidWeeks(data),
    );
    setState(() {
      _selectedWeeks
        ..clear()
        ..addAll(auto);
    });
  }

  void _syncAmountFromSelection(List<FiftyTwoWeeksWeekEntry> schedule) {
    if (!widget.depositMode || _selectedWeeks.isEmpty) return;
    _syncingAmountFromSelection = true;
    final total = FiftyTwoWeeksPlan.sumWeekAmounts(schedule, _selectedWeeks);
    _amountCtrl.text = CurrencyFormats.formatBRLInput(total);
    _syncingAmountFromSelection = false;
  }

  Future<void> _loadBalance(String? accountId) async {
    if (accountId == null || accountId.isEmpty) {
      if (mounted) setState(() => _accountBalance = null);
      return;
    }
    final bal = await GoalDepositService.accountBalanceAllTime(
      uid: widget.uid,
      financeAccountId: accountId,
    );
    if (mounted) setState(() => _accountBalance = bal);
  }

  Future<void> _toggleWeekPaid(
    int week,
    double amount,
    Map<String, dynamic> data,
  ) async {
    if (widget.depositMode) return;
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final paid = List<int>.from(_paidWeeks(data));
    if (paid.contains(week)) {
      paid.remove(week);
      await widget.goalDoc.reference.update({'weeksPaid': paid});
      return;
    }
    final title = (data['title'] ?? 'Objetivo').toString();
    await showRegistrarDepositoDialog(
      context: context,
      goalRef: widget.goalDoc.reference,
      goalId: widget.goalDoc.id,
      goalTitle: title,
      uid: widget.uid,
      profile: widget.profile,
      initialAmount: amount,
      weekNumbers: [week],
    );
  }

  void _toggleSelection(int week, List<FiftyTwoWeeksWeekEntry> schedule, List<int> paid) {
    if (paid.contains(week)) return;
    setState(() {
      if (_selectedWeeks.contains(week)) {
        _selectedWeeks.remove(week);
      } else {
        _selectedWeeks.add(week);
      }
      _syncAmountFromSelection(schedule);
    });
  }

  void _selectAllPending(List<FiftyTwoWeeksWeekEntry> schedule, List<int> paid) {
    setState(() {
      _selectedWeeks
        ..clear()
        ..addAll(
          schedule.map((e) => e.week).where((w) => !paid.contains(w)),
        );
      _syncAmountFromSelection(schedule);
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedWeeks.clear();
      _syncingAmountFromSelection = true;
      _amountCtrl.clear();
      _syncingAmountFromSelection = false;
    });
  }

  void _openDepositForm({bool fromDirectAmount = false}) {
    if (!fromDirectAmount && _selectedWeeks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione ao menos uma semana na lista.')),
      );
      return;
    }
    setState(() => _depositStep = _DepositFlowStep.depositForm);
  }

  void _backToWeekSelection() {
    setState(() => _depositStep = _DepositFlowStep.selectWeeks);
  }

  Future<void> _exportPdf() async {
    setState(() => _pdfLoading = true);
    try {
      await Goal52WeeksPdfService.previewFromGoalDoc(
        context: context,
        goalRef: widget.goalDoc.reference,
        goalData: widget.goalDoc.data(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF: ${e.toString().split('\n').first}')),
        );
      }
    } finally {
      if (mounted) setState(() => _pdfLoading = false);
    }
  }

  Future<void> _registrarDepositoSelecionado(
    List<FiftyTwoWeeksWeekEntry> schedule,
    Map<String, dynamic> data,
  ) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    if (_selectedWeeks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione ao menos uma semana.')),
      );
      return;
    }
    final amount = CurrencyFormats.parseBRLInput(_amountCtrl.text) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um valor maior que zero.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final title = (data['title'] ?? 'Objetivo').toString();
      final weekCount = _selectedWeeks.length;
      await GoalDepositService.saveDeposit(
        uid: widget.uid,
        goalRef: widget.goalDoc.reference,
        goalId: widget.goalDoc.id,
        goalTitle: title,
        amount: amount,
        date: DateTime.now(),
        financeAccountId: _financeAccountId,
        weekNumbers: _selectedWeeks.toList()..sort(),
      );
      if (!mounted) return;
      setState(() {
        _selectedWeeks.clear();
        _amountCtrl.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Depósito de ${CurrencyFormats.formatBRL(amount)} registrado '
            '($weekCount semana${weekCount == 1 ? '' : 's'}).',
          ),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: ${e.toString().split('\n').first}')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _weekListTile({
    required FiftyTwoWeeksWeekEntry entry,
    required bool isPaid,
    required bool isSelected,
    required bool isCurrent,
    required bool isPast,
    required Color accent,
    required List<Color> gradient,
    required List<FiftyTwoWeeksWeekEntry> schedule,
    required List<int> paid,
  }) {
    final dateLabel = DateFormat('dd/MM/yyyy', 'pt_BR').format(entry.dueDate);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: widget.depositMode
              ? () => _toggleSelection(entry.week, schedule, paid)
              : () => _toggleWeekPaid(entry.week, entry.amount, widget.goalDoc.data()),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isPaid
                  ? AppColors.success.withValues(alpha: 0.1)
                  : isSelected
                      ? accent.withValues(alpha: 0.12)
                      : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isPaid
                    ? AppColors.success.withValues(alpha: 0.65)
                    : isSelected
                        ? accent
                        : isCurrent
                            ? accent.withValues(alpha: 0.55)
                            : isPast && !isPaid
                                ? AppColors.error.withValues(alpha: 0.35)
                                : const Color(0xFFE2E8F0),
                width: isSelected || isCurrent ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: (isSelected ? accent : Colors.black).withValues(alpha: isSelected ? 0.12 : 0.04),
                  blurRadius: isSelected ? 10 : 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isPaid
                          ? [AppColors.success, AppColors.success.withValues(alpha: 0.75)]
                          : gradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'S${entry.week}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Semana ${entry.week}',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: isPaid ? AppColors.success : const Color(0xFF0B1B4B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dateLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      CurrencyFormats.formatBRL(entry.amount),
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: isPaid ? AppColors.success : accent,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Icon(
                      isPaid
                          ? Icons.check_circle_rounded
                          : isSelected
                              ? Icons.check_box_rounded
                              : isCurrent
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.circle_outlined,
                      size: 20,
                      color: isPaid
                          ? AppColors.success
                          : isSelected
                              ? accent
                              : isCurrent
                                  ? accent.withValues(alpha: 0.7)
                                  : Colors.grey.shade400,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _selectionStickyBar({
    required List<FiftyTwoWeeksWeekEntry> schedule,
    required Color accent,
    required List<Color> gradient,
  }) {
    final selectedTotal =
        FiftyTwoWeeksPlan.sumWeekAmounts(schedule, _selectedWeeks);
    final count = _selectedWeeks.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: gradient),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        count == 0
                            ? 'Nenhuma semana selecionada'
                            : '$count semana${count == 1 ? '' : 's'} selecionada${count == 1 ? '' : 's'}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        count == 0
                            ? 'Toque nas semanas da lista acima'
                            : 'Total para depositar',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  CurrencyFormats.formatBRL(selectedTotal),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: count == 0 ? null : () => _openDepositForm(),
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text(
              'Continuar para depósito',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade300,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _depositFormPage({
    required List<FiftyTwoWeeksWeekEntry> schedule,
    required Map<String, dynamic> data,
    required Color accent,
    required List<Color> gradient,
  }) {
    final selectedTotal =
        FiftyTwoWeeksPlan.sumWeekAmounts(schedule, _selectedWeeks);
    return SingleChildScrollView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          sheetWideVoltarButton(
            context,
            label: 'Voltar às semanas',
            onPressed: _backToWeekSelection,
          ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: gradient),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Registrar depósito',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_selectedWeeks.length} semana(s) - ${CurrencyFormats.formatBRL(selectedTotal)}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          BrlAmountTextField(
            controller: _amountCtrl,
            decoration: const InputDecoration(
              labelText: 'Valor do depósito (R\$)',
              prefixText: 'R\$ ',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Digite o valor depositado - o app ajusta as semanas automaticamente.',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 14),
          GoalFinanceAccountField(
            uid: widget.uid,
            selectedAccountId: _financeAccountId,
            onChanged: (v) {
              setState(() => _financeAccountId = v);
              _loadBalance(v);
            },
          ),
          if (_accountBalance != null) ...[
            const SizedBox(height: 8),
            Text(
              'Saldo atual: ${CurrencyFormats.formatBRL(_accountBalance!)}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.teal.shade700,
              ),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _saving
                ? null
                : () => _registrarDepositoSelecionado(schedule, data),
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.savings_rounded),
            label: const Text(
              'Registrar depósito no banco',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          sheetWideVoltarButton(context, footer: true),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: widget.goalDoc.reference.snapshots(),
      builder: (context, goalSnap) {
        final data = goalSnap.data?.data() ?? widget.goalDoc.data();
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: widget.goalDoc.reference.collection('contributions').snapshots(),
          builder: (context, contribSnap) {
            var deposited = 0.0;
            for (final d in contribSnap.data?.docs ?? []) {
              deposited += (d.data()['amount'] as num?)?.toDouble() ?? 0;
            }
            return _buildScheduleContent(data, deposited);
          },
        );
      },
    );
  }

  Widget _buildScheduleContent(Map<String, dynamic> data, double deposited) {
        final title = (data['title'] ?? 'Objetivo').toString();
        final target = (data['targetAmount'] as num?)?.toDouble() ?? 0;
        final visual = goalVisualForData(data);
        final planStart =
            FiftyTwoWeeksPlan.planStartFromData(data) ?? DateTime.now();
        final schedule =
            FiftyTwoWeeksPlan.buildSchedule(target: target, planStart: planStart);
        final monthGroups = FiftyTwoWeeksPlan.groupScheduleByMonth(schedule);
        final currentWeek = FiftyTwoWeeksPlan.currentWeekNumber(planStart);
        final paid = _paidWeeks(data);
        final paidCount = paid.length;
        final inDepositForm = widget.depositMode &&
            _depositStep == _DepositFlowStep.depositForm;
        final inWeekSelection = widget.depositMode &&
            _depositStep == _DepositFlowStep.selectWeeks;
        final bottomPad = inWeekSelection ? 150.0 : 24.0;

        if (inDepositForm) {
          return Container(
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                previewSheetTopBar(context),
                Expanded(
                  child: _depositFormPage(
                    schedule: schedule,
                    data: data,
                    accent: visual.color,
                    gradient: visual.gradient,
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Stack(
            children: [
              CustomScrollView(
                controller: widget.scrollController,
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        const SizedBox(height: 10),
                        Container(
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        previewSheetTopBar(context),
                        sheetWideVoltarButton(context),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: visual.gradient),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(visual.icon, color: Colors.white, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.depositMode
                                          ? 'Selecionar semanas - depósito'
                                          : 'Projeto 52 semanas',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 17,
                                        color: AppColors.deepBlueDark,
                                      ),
                                    ),
                                    Text(
                                      title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_pdfLoading)
                                const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                )
                              else
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Goal52WeeksPdfButton(
                                    expand: false,
                                    loading: _pdfLoading,
                                    label: 'PDF',
                                    onPressed: _pdfLoading ? null : _exportPdf,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: Goal52WeeksSummaryPanel(
                            target: target,
                            deposited: deposited,
                            paidWeeks: paidCount,
                            currentWeek: currentWeek,
                            gradient: visual.gradient,
                          ),
                        ),
                        if (inWeekSelection) ...[
                          const SizedBox(height: 10),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            child: FilledButton.tonalIcon(
                              onPressed: () => _openDepositForm(fromDirectAmount: true),
                              icon: const Icon(Icons.payments_rounded, size: 20),
                              label: const Text(
                                'Informar valor direto',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: visual.color.withValues(alpha: 0.12),
                                foregroundColor: visual.color,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _selectAllPending(schedule, paid),
                                    icon: const Icon(Icons.select_all_rounded, size: 18),
                                    label: const Text('Todas pendentes'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _clearSelection,
                                    icon: const Icon(Icons.clear_all_rounded, size: 18),
                                    label: const Text('Limpar'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                            child: Text(
                              'Toque nas semanas para marcar. O total aparece embaixo.',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                  for (final group in monthGroups) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
                        child: Row(
                          children: [
                            Text(
                              group.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                                color: Color(0xFF0B1B4B),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${group.weeks.length} sem. - ${CurrencyFormats.formatBRL(group.weeks.fold<double>(0, (s, e) => s + e.amount))}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            final entry = group.weeks[i];
                            final isPaid = paid.contains(entry.week);
                            final isSelected = _selectedWeeks.contains(entry.week);
                            final isCurrent = entry.week == currentWeek;
                            final isPast = entry.week < currentWeek;
                            return _weekListTile(
                              entry: entry,
                              isPaid: isPaid,
                              isSelected: isSelected,
                              isCurrent: isCurrent,
                              isPast: isPast,
                              accent: visual.color,
                              gradient: visual.gradient,
                              schedule: schedule,
                              paid: paid,
                            );
                          },
                          childCount: group.weeks.length,
                        ),
                      ),
                    ),
                  ],
                  SliverToBoxAdapter(child: sheetWideVoltarButton(context, footer: true)),
                  SliverToBoxAdapter(child: SizedBox(height: bottomPad)),
                ],
              ),
              if (inWeekSelection)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _selectionStickyBar(
                    schedule: schedule,
                    accent: visual.color,
                    gradient: visual.gradient,
                  ),
                ),
            ],
          ),
        );
  }
}
