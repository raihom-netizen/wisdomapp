import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide showDatePicker;
import 'package:intl/intl.dart';

import '../constants/currency_formats.dart';
import '../services/goal_deposit_service.dart';
import '../theme/app_colors.dart';
import '../utils/date_picker_a11y.dart';
import '../utils/fifty_two_weeks_plan.dart';
import 'goal_deposit_ui.dart';
import 'goal_finance_account_field.dart';

/// Edição moderna de depósito (paridade com lançamento financeiro).
Future<bool> showGoalDepositEditSheet({
  required BuildContext context,
  required QueryDocumentSnapshot<Map<String, dynamic>> contribDoc,
  required QueryDocumentSnapshot<Map<String, dynamic>> goalDoc,
  required String uid,
  required String goalTitle,
  required String initialAccountId,
}) async {
  final d = contribDoc.data();
  final goalData = goalDoc.data();
  final is52 = FiftyTwoWeeksPlan.is52WeeksGoal(goalData);
  final target = (goalData['targetAmount'] as num?)?.toDouble() ?? 0;
  final planStart = FiftyTwoWeeksPlan.planStartFromData(goalData) ?? DateTime.now();
  final schedule = is52
      ? FiftyTwoWeeksPlan.buildSchedule(target: target, planStart: planStart)
      : const <FiftyTwoWeeksWeekEntry>[];

  final amountCtrl =
      TextEditingController(text: CurrencyFormats.formatBRLInput((d['amount'] ?? 0) as num));
  final focusNode = FocusNode();
  DateTime date = (d['date'] as Timestamp?)?.toDate() ?? DateTime.now();
  String? financeAccountId = initialAccountId.isEmpty ? null : initialAccountId;
  double? accountBalance;
  List<int> previewWeeks = _weeksFromContrib(d);
  var saving = false;

  Future<void> loadBalance(String? id, void Function(void Function()) setState) async {
    if (id != null && id.isNotEmpty) {
      final bal = await GoalDepositService.accountBalanceAllTime(
        uid: uid,
        financeAccountId: id,
      );
      if (context.mounted) setState(() => accountBalance = bal);
    } else {
      setState(() => accountBalance = null);
    }
  }

  if (financeAccountId != null && financeAccountId.isNotEmpty) {
    accountBalance = await GoalDepositService.accountBalanceAllTime(
      uid: uid,
      financeAccountId: financeAccountId,
    );
  }

  void recalcWeeks(void Function(void Function()) setState) {
    if (!is52) return;
    final amount = CurrencyFormats.parseBRLInput(amountCtrl.text) ?? 0;
    final oldWeeks = _weeksFromContrib(d);
    var paid = FiftyTwoWeeksPlan.paidWeeksFromData(goalData);
    paid.removeWhere(oldWeeks.contains);
    previewWeeks = amount > 0
        ? FiftyTwoWeeksPlan.weeksForDepositAmount(
            amount: amount,
            schedule: schedule,
            paidWeeks: paid,
          )
        : const [];
    setState(() {});
  }

  if (!context.mounted) return false;

  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (focusNode.canRequestFocus) focusNode.requestFocus();
      });
      return StatefulBuilder(
        builder: (ctx, setState) {
          final amount = CurrencyFormats.parseBRLInput(amountCtrl.text) ?? 0;
          final bottom = MediaQuery.viewPaddingOf(ctx).bottom;
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottom),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: GoalDepositUi.gradient),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.savings_rounded, color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Editar depósito',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              Text(
                                goalTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: saving ? null : () => Navigator.pop(ctx, false),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    GoalDepositAmountField(
                      controller: amountCtrl,
                      focusNode: focusNode,
                      label: 'Valor do depósito',
                      onChanged: (_) => recalcWeeks(setState),
                    ),
                    if (is52 && previewWeeks.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: GoalDepositUi.green.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: GoalDepositUi.green.withValues(alpha: 0.22)),
                        ),
                        child: Text(
                          previewWeeks.length == 1
                              ? 'Semana ${previewWeeks.first} será marcada automaticamente'
                              : 'Semanas ${previewWeeks.join(', ')} serão marcadas automaticamente',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: GoalDepositUi.greenDark,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    GoalFinanceAccountField(
                      uid: uid,
                      selectedAccountId: financeAccountId,
                      onChanged: (v) async {
                        setState(() => financeAccountId = v);
                        await loadBalance(v, setState);
                      },
                    ),
                    if (accountBalance != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Saldo atual: ${CurrencyFormats.formatBRL(accountBalance!)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: GoalDepositUi.greenDark,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Data do depósito',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: Colors.grey.shade800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  DateFormat('dd/MM/yyyy', 'pt_BR').format(date),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: ctx,
                                initialDate: date,
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now(),
                              );
                              if (picked != null) setState(() => date = picked);
                            },
                            child: const Text('Alterar'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    GoalDepositUi.depositPrimaryButton(
                      onPressed: saving || amount <= 0
                          ? null
                          : () async {
                              setState(() => saving = true);
                              try {
                                await GoalDepositService.updateDeposit(
                                  uid: uid,
                                  goalRef: goalDoc.reference,
                                  goalTitle: goalTitle,
                                  contribDoc: contribDoc,
                                  amount: amount,
                                  date: date,
                                  financeAccountId: financeAccountId,
                                );
                                if (ctx.mounted) Navigator.pop(ctx, true);
                              } catch (e) {
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Erro: ${e.toString().split('\n').first}',
                                      ),
                                    ),
                                  );
                                }
                                setState(() => saving = false);
                              }
                            },
                      label: saving ? 'Salvando...' : 'Salvar lançamento',
                      icon: Icons.check_rounded,
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: saving ? null : () => Navigator.pop(ctx, false),
                      child: const Text('Cancelar'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );

  amountCtrl.dispose();
  focusNode.dispose();
  return saved == true;
}

List<int> _weeksFromContrib(Map<String, dynamic> data) {
  final week = data['weekNumber'] as int?;
  final weeks = (data['weekNumbers'] as List?)?.whereType<int>().toList() ?? [];
  if (week != null) return [week];
  return weeks;
}
