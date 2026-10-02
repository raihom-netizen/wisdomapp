import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/currency_formats.dart';
import '../models/user_profile.dart';
import '../services/goal_52_weeks_pdf_service.dart';
import '../services/goal_deposit_service.dart';
import '../theme/app_colors.dart';
import '../theme/theme_context.dart';
import '../utils/fifty_two_weeks_plan.dart';
import '../utils/goal_objective_visuals.dart';
import '../utils/premium_upgrade.dart';
import '../widgets/goal_deposit_edit_sheet.dart';
import '../widgets/goal_deposit_ui.dart';
import '../widgets/keyed_stream_builder.dart';
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
  /// Depósitos da meta (última leitura da escuta) — para achar o depósito que
  /// pagou uma semana.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _contribDocs = const [];
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
      await _onPaidWeekTapped(week, paid, data);
      return;
    }
    final title = (data['title'] ?? 'Objetivo').toString();
    final goalAccountId = (data['financeAccountId'] ?? '').toString().trim();
    await showRegistrarDepositoDialog(
      context: context,
      goalRef: widget.goalDoc.reference,
      goalId: widget.goalDoc.id,
      goalTitle: title,
      uid: widget.uid,
      profile: widget.profile,
      initialAmount: amount,
      weekNumbers: [week],
      initialFinanceAccountId: goalAccountId.isEmpty ? null : goalAccountId,
    );
  }

  /// Semana paga tocada: antes só tirava a semana de `weeksPaid` e o dinheiro
  /// continuava contado (progresso incoerente). Agora a semana só sai junto
  /// com o depósito que a pagou — o usuário escolhe editar ou excluir esse
  /// depósito (o lançamento do Financeiro ligado acompanha) e as semanas são
  /// recalculadas. Semana marcada sem depósito (dado antigo) pode ser
  /// desmarcada direto.
  Future<void> _onPaidWeekTapped(
    int week,
    List<int> paid,
    Map<String, dynamic> data,
  ) async {
    QueryDocumentSnapshot<Map<String, dynamic>>? owner;
    for (final c in _contribDocs) {
      if (GoalDepositService.weeksFromContribData(c.data()).contains(week)) {
        owner = c;
        break;
      }
    }
    if (owner == null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Desmarcar semana $week?'),
          content: const Text(
            'Nenhum depósito registrado cobre esta semana. Ela será só '
            'desmarcada — nenhum valor muda.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Desmarcar'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      paid.remove(week);
      await widget.goalDoc.reference.update({'weeksPaid': paid});
      return;
    }
    final c = owner.data();
    final amount = ((c['amount'] as num?) ?? 0).toDouble().abs();
    final ts = c['date'];
    final when = ts is Timestamp
        ? DateFormat('dd/MM/yyyy', 'pt_BR').format(ts.toDate())
        : '';
    final weeks = GoalDepositService.weeksFromContribData(c);
    final linked = (c['transactionId'] ?? '').toString().trim().isNotEmpty;
    if (!mounted) return;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Semana $week já está paga'),
        content: Text(
          'Ela foi paga pelo depósito de ${CurrencyFormats.formatBRL(amount)}'
          '${when.isEmpty ? '' : ' em $when'}'
          '${weeks.length > 1 ? ' (semanas ${weeks.join(', ')})' : ''}.\n\n'
          'Para desmarcar, edite o valor ou exclua esse depósito'
          '${linked ? ' — o lançamento ligado no Financeiro acompanha' : ''}. '
          'As semanas são recalculadas em seguida.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Voltar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'edit'),
            child: const Text('Editar depósito'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, 'delete'),
            child: const Text('Excluir depósito'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    try {
      if (action == 'edit') {
        await showGoalDepositEditSheet(
          context: context,
          contribDoc: owner,
          goalDoc: widget.goalDoc,
          uid: widget.uid,
          goalTitle: (data['title'] ?? 'Objetivo').toString(),
          initialAccountId: (c['financeAccountId'] ?? '').toString(),
        );
      } else if (action == 'delete') {
        await GoalDepositService.deleteDeposit(
          uid: widget.uid,
          contribDoc: owner,
          goalRef: widget.goalDoc.reference,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Depósito excluído e semanas recalculadas.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: ${e.toString().split('\n').first}')),
        );
      }
    }
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
    final amount = CurrencyFormats.parseBRLInput(_amountCtrl.text) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um valor maior que zero.')),
      );
      return;
    }
    // Sem semana selecionada (valor menor que a próxima semana) o depósito
    // vale mesmo assim: o dinheiro fica guardado e completa a semana depois.
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
            weekCount == 0
                ? 'Depósito de ${CurrencyFormats.formatBRL(amount)} guardado — '
                    'completa a próxima semana quando somar o valor dela.'
                : 'Depósito de ${CurrencyFormats.formatBRL(amount)} registrado '
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
                      : (context.isDarkMode
                          ? context.appSurface
                          : Colors.white),
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
                                : context.appChipIdleBorder,
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
                          color: isPaid
                              ? AppColors.success
                              : (context.isDarkMode
                                  ? context.appTextPrimary
                                  : const Color(0xFF0B1B4B)),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dateLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: context.isDarkMode
                              ? context.appTextSecondary
                              : Colors.grey.shade600,
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
                                  : (context.isDarkMode
                                      ? context.appTextMuted
                                      : Colors.grey.shade400),
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

  static const Color _depositGreen = Color(0xFF16A34A);
  static const Color _depositGreenDark = Color(0xFF15803D);
  static const List<Color> _depositGradient = [
    Color(0xFF22C55E),
    Color(0xFF16A34A),
  ];

  Widget _selectionStickyBar({
    required List<FiftyTwoWeeksWeekEntry> schedule,
    required Color accent,
    required List<Color> gradient,
  }) {
    final selectedTotal =
        FiftyTwoWeeksPlan.sumWeekAmounts(schedule, _selectedWeeks);
    final count = _selectedWeeks.length;
    final navBottom = MediaQuery.viewPaddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: navBottom > 0 ? navBottom + 4 : 10),
      child: Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: context.isDarkMode ? context.appSurface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: _depositGreen.withValues(alpha: 0.22),
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
              gradient: const LinearGradient(colors: _depositGradient),
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
                            ? 'Nenhuma semana para depositar'
                            : '$count semana${count == 1 ? '' : 's'} para depositar',
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
          GoalDepositUi.depositPrimaryButton(
            onPressed: count == 0 ? null : () => _openDepositForm(),
            label: 'Depositar',
            icon: Icons.savings_rounded,
          ),
        ],
      ),
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
          GoalDepositAmountField(
            controller: _amountCtrl,
            label: 'Valor do depósito',
            hint: 'Digite o valor',
            onChanged: (_) => _onAmountFieldChanged(),
          ),
          const SizedBox(height: 6),
          Text(
            'Digite o valor depositado — o app ajusta as semanas automaticamente.',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: context.isDarkMode
                  ? context.appTextSecondary
                  : Colors.grey.shade700,
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
          GoalDepositUi.depositPrimaryButton(
            onPressed: _saving ? null : () => _registrarDepositoSelecionado(schedule, data),
            label: _saving ? 'Registrando...' : 'Depositar',
            icon: Icons.savings_rounded,
          ),
          sheetWideVoltarButton(context, footer: true),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Escutas guardadas no estado: rebuild (digitar valor, marcar semana) não
    // reabre a consulta no Firestore.
    final goalRef = widget.goalDoc.reference;
    return KeyedStreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      streamKey: goalRef.path,
      create: () => goalRef.snapshots(),
      builder: (context, goalSnap) {
        final data = goalSnap.data?.data() ?? widget.goalDoc.data();
        return KeyedStreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          streamKey: '${goalRef.path}/contributions',
          create: () => goalRef.collection('contributions').snapshots(),
          builder: (context, contribSnap) {
            _contribDocs = contribSnap.data?.docs ?? const [];
            var deposited = 0.0;
            for (final d in _contribDocs) {
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
        final navBottom = MediaQuery.viewPaddingOf(context).bottom;
        final bottomPad = inWeekSelection ? 168.0 + navBottom : 24.0;

        if (inDepositForm) {
          return Container(
            decoration: BoxDecoration(
              color: context.isDarkMode
                  ? context.appScaffold
                  : const Color(0xFFF8FAFC),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.isDarkMode
                        ? context.appBorderSubtle
                        : Colors.grey.shade300,
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
          decoration: BoxDecoration(
            color: context.isDarkMode
                ? context.appScaffold
                : const Color(0xFFF8FAFC),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                            color: context.isDarkMode
                                ? context.appBorderSubtle
                                : Colors.grey.shade300,
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
                                          ? 'Semanas para depositar'
                                          : 'Projeto 52 semanas',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 17,
                                        color: context.isDarkMode
                                            ? context.appTextPrimary
                                            : AppColors.deepBlueDark,
                                      ),
                                    ),
                                    Text(
                                      title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        color: context.isDarkMode
                                            ? context.appTextSecondary
                                            : Colors.grey.shade700,
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
                            child: GoalDepositUi.depositPrimaryButton(
                              onPressed: () => _openDepositForm(fromDirectAmount: true),
                              label: 'Informar valor direto',
                              icon: Icons.payments_rounded,
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
                                color: context.isDarkMode
                                    ? context.appTextSecondary
                                    : Colors.grey.shade700,
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
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                                color: context.isDarkMode
                                    ? context.appTextPrimary
                                    : const Color(0xFF0B1B4B),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${group.weeks.length} sem. - ${CurrencyFormats.formatBRL(group.weeks.fold<double>(0, (s, e) => s + e.amount))}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                                color: context.isDarkMode
                                    ? context.appTextSecondary
                                    : Colors.grey.shade700,
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
