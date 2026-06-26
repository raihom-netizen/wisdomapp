import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/currency_formats.dart';
import '../models/finance_account.dart';
import '../models/user_profile.dart';
import '../services/finance_accounts_service.dart';
import '../services/goal_deposit_service.dart';
import '../theme/app_colors.dart';
import '../utils/fifty_two_weeks_plan.dart';
import '../utils/goal_objective_visuals.dart';
import '../utils/premium_upgrade.dart';
import '../widgets/brl_amount_text_field.dart';
import '../widgets/registrar_deposito_dialog.dart';

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
      initialChildSize: depositMode ? 0.92 : 0.88,
      minChildSize: 0.45,
      maxChildSize: 0.96,
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

  List<int> get _paidWeeks =>
      FiftyTwoWeeksPlan.paidWeeksFromData(widget.goalDoc.data());

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  void _syncAmountFromSelection(List<FiftyTwoWeeksWeekEntry> schedule) {
    if (!widget.depositMode || _selectedWeeks.isEmpty) return;
    var total = 0.0;
    for (final e in schedule) {
      if (_selectedWeeks.contains(e.week)) total += e.amount;
    }
    _amountCtrl.text = CurrencyFormats.formatBRLInput(total);
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

  Future<void> _toggleWeekPaid(int week, double amount) async {
    if (widget.depositMode) return;
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final paid = List<int>.from(_paidWeeks);
    if (paid.contains(week)) {
      paid.remove(week);
      await widget.goalDoc.reference.update({'weeksPaid': paid});
      return;
    }
    final data = widget.goalDoc.data();
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

  void _toggleSelection(int week, List<FiftyTwoWeeksWeekEntry> schedule) {
    if (_paidWeeks.contains(week)) return;
    setState(() {
      if (_selectedWeeks.contains(week)) {
        _selectedWeeks.remove(week);
      } else {
        _selectedWeeks.add(week);
      }
      _syncAmountFromSelection(schedule);
    });
  }

  double _selectedTotal(List<FiftyTwoWeeksWeekEntry> schedule) {
    var total = 0.0;
    for (final e in schedule) {
      if (_selectedWeeks.contains(e.week)) total += e.amount;
    }
    return total;
  }

  Future<void> _registrarDepositoSelecionado(
    List<FiftyTwoWeeksWeekEntry> schedule,
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
      final data = widget.goalDoc.data();
      final title = (data['title'] ?? 'Objetivo').toString();
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
        const SnackBar(content: Text('Depósito registrado!')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro: ${e.toString().split('\n').first}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.goalDoc.data();
    final title = (data['title'] ?? 'Objetivo').toString();
    final target = (data['targetAmount'] as num?)?.toDouble() ?? 0;
    final visual = goalVisualForData(data);
    final planStart =
        FiftyTwoWeeksPlan.planStartFromData(data) ?? DateTime.now();
    final schedule =
        FiftyTwoWeeksPlan.buildSchedule(target: target, planStart: planStart);
    final currentWeek = FiftyTwoWeeksPlan.currentWeekNumber(planStart);
    final paidCount = _paidWeeks.length;
    final remainingWeeks = (52 - paidCount).clamp(0, 52);
    var monthTotal = 0.0;
    String? lastMonthKey;
    final selectedTotal = _selectedTotal(schedule);

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
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
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
                            ? 'Registrar depósito · 52 semanas'
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
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: visual.gradient),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Meta: ${CurrencyFormats.formatBRL(target)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _statChip('Sem. $currentWeek/52', Colors.white24),
                      _statChip('$paidCount guardadas', Colors.white24),
                      _statChip('$remainingWeeks faltam', Colors.white24),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (widget.depositMode) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Text(
                'Toque nas semanas para selecionar uma ou mais. O total sugerido aparece abaixo.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              controller: widget.scrollController,
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                widget.depositMode ? 8 : 24,
              ),
              itemCount: schedule.length,
              itemBuilder: (context, index) {
                final entry = schedule[index];
                final showMonthHeader = entry.monthKey != lastMonthKey;
                if (showMonthHeader) {
                  lastMonthKey = entry.monthKey;
                  monthTotal = 0;
                  for (final e in schedule) {
                    if (e.monthKey == entry.monthKey) monthTotal += e.amount;
                  }
                }
                final isPaid = _paidWeeks.contains(entry.week);
                final isSelected = _selectedWeeks.contains(entry.week);
                final isCurrent = entry.week == currentWeek;
                final isPast = entry.week < currentWeek;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showMonthHeader) ...[
                      if (index > 0) const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 6),
                        child: Row(
                          children: [
                            Text(
                              _monthLabel(entry.dueDate),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                                color: Color(0xFF0B1B4B),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'Total ${CurrencyFormats.formatBRL(monthTotal)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    Material(
                      color: isSelected
                          ? visual.color.withValues(alpha: 0.08)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: widget.depositMode
                            ? () => _toggleSelection(entry.week, schedule)
                            : () => _toggleWeekPaid(entry.week, entry.amount),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected
                                  ? visual.color
                                  : isCurrent
                                      ? visual.color
                                      : isPaid
                                          ? AppColors.success
                                              .withValues(alpha: 0.45)
                                          : const Color(0xFFE2E8F0),
                              width: isSelected || isCurrent ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: (isPaid
                                          ? AppColors.success
                                          : visual.color)
                                      .withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${entry.week}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: isPaid
                                        ? AppColors.success
                                        : visual.color,
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
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      DateFormat('dd/MM/yyyy', 'pt_BR')
                                          .format(entry.dueDate),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                CurrencyFormats.formatBRL(entry.amount),
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                  color: isPast && !isPaid
                                      ? AppColors.error
                                      : AppColors.deepBlueDark,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                isPaid
                                    ? Icons.check_circle_rounded
                                    : isSelected
                                        ? Icons.check_box_rounded
                                        : Icons
                                            .radio_button_unchecked_rounded,
                                color: isPaid
                                    ? AppColors.success
                                    : isSelected
                                        ? visual.color
                                        : Colors.grey.shade400,
                                size: 22,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (widget.depositMode)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: visual.color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: visual.color.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_selectedWeeks.length} semana(s) selecionada(s)',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          'Total sugerido: ${CurrencyFormats.formatBRL(selectedTotal)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: visual.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  BrlAmountTextField(
                    controller: _amountCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Valor do depósito (R\$)',
                      prefixText: 'R\$ ',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  StreamBuilder<List<FinanceAccount>>(
                    stream: FinanceAccountsService().streamAccounts(widget.uid),
                    builder: (context, snap) {
                      final accounts = snap.data ?? const <FinanceAccount>[];
                      return DropdownButtonFormField<String?>(
                        value: _financeAccountId,
                        decoration: const InputDecoration(
                          labelText: 'Conta que recebe o depósito',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Sem conta vinculada'),
                          ),
                          for (final a in accounts)
                            DropdownMenuItem<String?>(
                              value: a.id,
                              child: Text(a.displayName),
                            ),
                        ],
                        onChanged: (v) {
                          setState(() => _financeAccountId = v);
                          _loadBalance(v);
                        },
                      );
                    },
                  ),
                  if (_accountBalance != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Saldo atual: ${CurrencyFormats.formatBRL(_accountBalance!)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.teal.shade700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _registrarDepositoSelecionado(schedule),
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.savings_rounded),
                    label: const Text(
                      'Registrar depósito',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: visual.color,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _statChip(String label, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  String _monthLabel(DateTime d) {
    final raw = DateFormat('MMMM yyyy', 'pt_BR').format(d);
    return raw[0].toUpperCase() + raw.substring(1);
  }
}
