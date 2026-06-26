import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/currency_formats.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';
import '../utils/fifty_two_weeks_plan.dart';
import '../utils/goal_objective_visuals.dart';
import '../utils/premium_upgrade.dart';
import '../widgets/registrar_aporte_dialog.dart';

Future<void> showFiftyTwoWeeksScheduleSheet({
  required BuildContext context,
  required QueryDocumentSnapshot<Map<String, dynamic>> goalDoc,
  required UserProfile profile,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.45,
      maxChildSize: 0.96,
      expand: false,
      builder: (ctx, scrollController) {
        return _FiftyTwoWeeksScheduleBody(
          goalDoc: goalDoc,
          profile: profile,
          scrollController: scrollController,
        );
      },
    ),
  );
}

class _FiftyTwoWeeksScheduleBody extends StatefulWidget {
  const _FiftyTwoWeeksScheduleBody({
    required this.goalDoc,
    required this.profile,
    required this.scrollController,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> goalDoc;
  final UserProfile profile;
  final ScrollController scrollController;

  @override
  State<_FiftyTwoWeeksScheduleBody> createState() => _FiftyTwoWeeksScheduleBodyState();
}

class _FiftyTwoWeeksScheduleBodyState extends State<_FiftyTwoWeeksScheduleBody> {
  List<int> get _paidWeeks => FiftyTwoWeeksPlan.paidWeeksFromData(widget.goalDoc.data());

  Future<void> _toggleWeekPaid(int week, double amount) async {
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
    await showRegistrarAporteDialog(
      context: context,
      goalRef: widget.goalDoc.reference,
      profile: widget.profile,
      initialAmount: amount,
      weekNumber: week,
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.goalDoc.data();
    final title = (data['title'] ?? 'Objetivo').toString();
    final target = (data['targetAmount'] as num?)?.toDouble() ?? 0;
    final visual = goalVisualForData(data);
    final planStart = FiftyTwoWeeksPlan.planStartFromData(data) ?? DateTime.now();
    final schedule = FiftyTwoWeeksPlan.buildSchedule(target: target, planStart: planStart);
    final currentWeek = FiftyTwoWeeksPlan.currentWeekNumber(planStart);
    var monthTotal = 0.0;
    String? lastMonthKey;

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
                        'Projeto 52 semanas',
                        style: TextStyle(
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
                    'Meta total: ${CurrencyFormats.formatBRL(target)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Semana atual: $currentWeek · incremento base ${CurrencyFormats.formatBRL(FiftyTwoWeeksPlan.weeklyIncrementForTarget(target))}/semana',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              controller: widget.scrollController,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
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
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _toggleWeekPaid(entry.week, entry.amount),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isCurrent
                                  ? visual.color
                                  : isPaid
                                      ? AppColors.success.withValues(alpha: 0.45)
                                      : const Color(0xFFE2E8F0),
                              width: isCurrent ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: (isPaid ? AppColors.success : visual.color)
                                      .withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${entry.week}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: isPaid ? AppColors.success : visual.color,
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
                                      DateFormat('dd/MM/yyyy', 'pt_BR').format(entry.dueDate),
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
                                  color: isPast && !isPaid ? AppColors.error : AppColors.deepBlueDark,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                isPaid ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                color: isPaid ? AppColors.success : Colors.grey.shade400,
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
        ],
      ),
    );
  }

  String _monthLabel(DateTime d) {
    final raw = DateFormat('MMMM yyyy', 'pt_BR').format(d);
    return raw[0].toUpperCase() + raw.substring(1);
  }
}
