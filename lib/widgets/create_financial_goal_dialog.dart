import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide showDatePicker;
import 'package:intl/intl.dart';

import '../constants/app_business_rules.dart';
import '../constants/currency_formats.dart';
import '../models/financial_goal.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';
import '../utils/date_picker_a11y.dart';
import '../utils/fifty_two_weeks_plan.dart';
import '../utils/firestore_user_doc_id.dart';
import '../utils/goal_objective_visuals.dart';
import '../utils/premium_upgrade.dart';
import '../widgets/brl_amount_text_field.dart';
import '../widgets/goal_finance_account_field.dart';
import '../widgets/fast_text_field.dart';

/// Abre o formulário «Criar objetivo» (mesmo do módulo Objetivo Financeiro).
Future<void> showCreateFinancialGoalDialog(
  BuildContext context, {
  required UserProfile profile,
  required String uid,
}) async {
  if (!profile.hasActiveLicense) {
    mostrarAvisoSeLicencaInativa(context, profile);
    return;
  }
  final userDocId = firestoreUserDocIdForAppShell(uid);
  if (userDocId.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A sincronizar sessão… tente novamente em instantes.'),
        ),
      );
    }
    return;
  }

  final goals = FirebaseFirestore.instance
      .collection('users')
      .doc(userDocId)
      .collection('goals');

  final titleCtrl = TextEditingController();
  final targetCtrl = TextEditingController();
  DateTime? dueDate;
  var reminderAporte = false;
  var category = GoalCategory.personalizada;
  var priority = GoalPriority.media;
  final interestCtrl = TextEditingController(text: '0.5');
  var hasInterest = false;
  var use52WeeksPlan = true;
  var selectedEmoji = '🎯';
  String? financeAccountId;
  Timer? metaSuggestDebounce;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final target = CurrencyFormats.parseBRLInput(targetCtrl.text) ?? 0;
        var monthsLeft = 0;
        if (dueDate != null && target > 0) {
          final d = dueDate!;
          final now = DateTime.now();
          var m = (d.year - now.year) * 12 + (d.month - now.month);
          if (d.day < now.day) m--;
          monthsLeft = m.clamp(1, 999);
        }
        String? suggestedMonthly;
        final rate = double.tryParse(interestCtrl.text.replaceAll(',', '.')) ?? 0;
        if (monthsLeft > 0 && target > 0) {
          if (hasInterest && rate > 0) {
            final i = rate / 100;
            final denom = math.pow(1 + i, monthsLeft).toDouble() - 1;
            suggestedMonthly = denom > 0
                ? (target * i / denom).toStringAsFixed(2)
                : (target / monthsLeft).toStringAsFixed(2);
          } else {
            suggestedMonthly = (target / monthsLeft).toStringAsFixed(2);
          }
        }
        const atalhosMeta = [
          (Icons.home_rounded, Color(0xFF0D9488), 'Compra Casa', 'casa'),
          (Icons.build_rounded, Color(0xFFB45309), 'Reforma de Casa', 'casa'),
          (Icons.flight_rounded, Color(0xFF2563EB), 'Viagem', 'viagem'),
          (Icons.school_rounded, Color(0xFF7C3AED), 'Escola', 'estudo'),
          (Icons.menu_book_rounded, Color(0xFF059669), 'Faculdade', 'estudo'),
          (Icons.directions_car_rounded, Color(0xFFDC2626), 'Comprar um carro', 'veiculo'),
          (Icons.edit_rounded, Color(0xFF64748B), 'Personalizado', 'personalizada'),
        ];
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 4),
          contentPadding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: goalFormDialogHeader(
            title: 'Novo objetivo financeiro',
            icon: Icons.savings_rounded,
            subtitle: 'Defina a meta e onde o dinheiro será guardado.',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'O que você quer conquistar?',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final at in atalhosMeta)
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            titleCtrl.text = at.$3;
                            category = GoalCategory.fromId(at.$4);
                            final preset = presetForCategory(at.$4);
                            selectedEmoji = preset?.visual.emoji ?? '🎯';
                            setState(() {});
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: at.$2.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: at.$2.withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(at.$1, size: 22, color: at.$2),
                                const SizedBox(width: 8),
                                Text(
                                  at.$3,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: at.$2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                FastTextField(
                  controller: titleCtrl,
                  decoration: _inputDecoration(
                    labelText: 'Nome da meta',
                    hintText: 'Ex: Comprar um carro, Reserva de emergência, Viagem',
                  ),
                ),
                const SizedBox(height: 12),
                BrlAmountTextField(
                  controller: targetCtrl,
                  decoration: _inputDecoration(
                    labelText: 'Valor alvo (R\$)',
                    hintText: 'Ex: 50.000,00',
                    prefixText: 'R\$ ',
                  ),
                  onChanged: (_) {
                    metaSuggestDebounce?.cancel();
                    metaSuggestDebounce = Timer(
                      Duration(milliseconds: AppBusinessRules.searchDebounceMs),
                      () {
                        if (ctx.mounted) setState(() {});
                      },
                    );
                  },
                ),
                if (suggestedMonthly != null && !use52WeeksPlan) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lightbulb_outline_rounded, size: 20, color: AppColors.success),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Sugestão: guarde ${CurrencyFormats.formatBRL(double.tryParse(suggestedMonthly) ?? 0)}/mês para atingir no prazo${hasInterest && rate > 0 ? " (com juros)" : ""}.',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF6366F1).withValues(alpha: 0.12),
                        const Color(0xFFEC4899).withValues(alpha: 0.10),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: use52WeeksPlan,
                        onChanged: (v) => setState(() => use52WeeksPlan = v),
                        title: const Text(
                          'Projeto 52 semanas',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                        ),
                        subtitle: const Text(
                          'Programação semanal automática (incremento progressivo até a meta).',
                          style: TextStyle(fontSize: 12),
                        ),
                        activeThumbColor: const Color(0xFF6366F1),
                      ),
                      if (use52WeeksPlan && target > 0) ...[
                        const Divider(height: 16),
                        Text(
                          'Semana 1: ${CurrencyFormats.formatBRL(FiftyTwoWeeksPlan.amountForWeek(target, 1))}',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                        Text(
                          'Semana 52: ${CurrencyFormats.formatBRL(FiftyTwoWeeksPlan.amountForWeek(target, 52))}',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                        Text(
                          'Total programado: ${CurrencyFormats.formatBRL(target)} em 52 semanas',
                          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!use52WeeksPlan) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          dueDate == null
                              ? 'Sem prazo'
                              : 'Prazo: ${DateFormat('dd/MM/yyyy').format(dueDate!)}',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: DateTime.now().add(const Duration(days: 365)),
                            firstDate: DateTime.now(),
                            lastDate: DateTime(2030, 12, 31),
                          );
                          if (picked != null) setState(() => dueDate = picked);
                        },
                        icon: const Icon(Icons.calendar_today_rounded, size: 18),
                        label: const Text('Definir prazo'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent.withValues(alpha: 0.16),
                          foregroundColor: AppColors.accent,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                GoalFinanceAccountField(
                  uid: uid,
                  selectedAccountId: financeAccountId,
                  onChanged: (v) => setState(() => financeAccountId = v),
                ),
                const SizedBox(height: 12),
                const Text('Prioridade', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: GoalPriority.values.map((p) {
                    final sel = priority == p;
                    return _priorityChip(
                      label: p.label,
                      selected: sel,
                      onTap: () => setState(() => priority = p),
                      active: _priorityColor(p),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: hasInterest,
                  onChanged: (v) => setState(() => hasInterest = v ?? false),
                  title: const Text(
                    'Meta com rendimento (juros compostos)',
                    style: TextStyle(fontSize: 14),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                if (hasInterest) ...[
                  const SizedBox(height: 8),
                  FastTextField(
                    controller: interestCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: _inputDecoration(
                      labelText: 'Taxa mensal estimada (%)',
                      hintText: 'Ex: 0.5 (CDI)',
                      suffixText: '%',
                      prefixIcon: const Icon(Icons.trending_up_rounded, size: 20),
                    ),
                    onChanged: (_) {
                      metaSuggestDebounce?.cancel();
                      metaSuggestDebounce = Timer(
                        Duration(milliseconds: AppBusinessRules.searchDebounceMs),
                        () {
                          if (ctx.mounted) setState(() {});
                        },
                      );
                    },
                  ),
                ],
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: reminderAporte,
                  onChanged: (v) => setState(() => reminderAporte = v ?? false),
                  title: const Text('Lembrar de aportar todo mês', style: TextStyle(fontSize: 14)),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Criar meta'),
                ),
              ],
            ),
          ],
        );
      },
    ),
  ).whenComplete(() => metaSuggestDebounce?.cancel());

  try {
    if (ok != true) return;
    final title = titleCtrl.text.trim();
    final target = CurrencyFormats.parseBRLInput(targetCtrl.text) ?? 0;
    if (title.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Informe o nome da meta.')),
        );
      }
      return;
    }
    if (target <= 0) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Informe o valor alvo.')),
        );
      }
      return;
    }
    if (financeAccountId == null || financeAccountId!.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selecione ou cadastre a conta onde o dinheiro será guardado.'),
          ),
        );
      }
      return;
    }

    final planStart = FiftyTwoWeeksPlan.normalizePlanStart(DateTime.now());
    await goals.add({
      'title': title,
      'targetAmount': target,
      'financeAccountId': financeAccountId,
      'dueDate': use52WeeksPlan
          ? Timestamp.fromDate(planStart.add(const Duration(days: 52 * 7)))
          : (dueDate != null ? Timestamp.fromDate(dueDate!) : null),
      'reminderAporte': reminderAporte,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'active',
      'category': category.id,
      'priority': priority.name,
      'interestRateMonthly':
          hasInterest ? (double.tryParse(interestCtrl.text.replaceAll(',', '.')) ?? 0) : 0,
      'planType': use52WeeksPlan ? '52weeks' : 'classic',
      if (use52WeeksPlan) ...{
        'planStartDate': Timestamp.fromDate(planStart),
        'weeklyIncrement': FiftyTwoWeeksPlan.weeklyIncrementForTarget(target),
        'weeksPaid': <int>[],
      },
      'emoji': selectedEmoji,
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            use52WeeksPlan
                ? 'Objetivo "$title" criado com Projeto 52 semanas!'
                : 'Objetivo "$title" criado! Acompanhe o progresso abaixo.',
          ),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao criar meta: ${e.toString().split('\n').first}')),
      );
    }
  } finally {
    titleCtrl.dispose();
    targetCtrl.dispose();
    interestCtrl.dispose();
  }
}

const _ctaGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF2563EB), Color(0xFF1D4ED8), Color(0xFF0D9488)],
);

Widget _dialogTitleRow({required IconData icon, required String title}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          gradient: _ctaGradient,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A237E),
            height: 1.2,
          ),
        ),
      ),
    ],
  );
}

InputDecoration _inputDecoration({
  required String labelText,
  String? hintText,
  Widget? prefixIcon,
  String? prefixText,
  String? suffixText,
}) {
  final r = BorderRadius.circular(14);
  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    prefixIcon: prefixIcon,
    prefixText: prefixText,
    suffixText: suffixText,
    filled: true,
    fillColor: const Color(0xFFF8FAFC),
    border: OutlineInputBorder(borderRadius: r),
    enabledBorder: OutlineInputBorder(
      borderRadius: r,
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: r,
      borderSide: const BorderSide(color: AppColors.accent, width: 2),
    ),
  );
}

Color _priorityColor(GoalPriority p) {
  return switch (p) {
    GoalPriority.alta => AppColors.error,
    GoalPriority.media => AppColors.primary,
    GoalPriority.baixa => const Color(0xFF64748B),
  };
}

Widget _priorityChip({
  required String label,
  required bool selected,
  required VoidCallback onTap,
  required Color active,
}) {
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? active : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? active : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
            color: selected ? Colors.white : Colors.grey.shade700,
          ),
        ),
      ),
    ),
  );
}
