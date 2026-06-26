import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/currency_formats.dart';
import '../models/user_profile.dart';
import '../utils/fifty_two_weeks_plan.dart';
import '../utils/firestore_user_doc_id.dart';
import '../utils/goal_objective_visuals.dart';
import '../utils/premium_upgrade.dart';
import '../widgets/fifty_two_weeks_schedule_sheet.dart';
import '../widgets/registrar_aporte_dialog.dart';

/// Card «Objetivo Financeiro» no Início — Projeto 52 semanas + progresso.
class HomeObjectiveFinancePanel extends StatelessWidget {
  const HomeObjectiveFinancePanel({
    super.key,
    required this.uid,
    required this.profile,
    required this.onOpenObjetivoModule,
  });

  final String uid;
  final UserProfile profile;
  final VoidCallback onOpenObjetivoModule;

  String get _userFsId => firestoreUserDocIdForAppShell(uid);

  static bool _excludeGoal(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final title = ((doc.data()['title'] ?? '') as String).toLowerCase();
    return title.contains('banco de horas');
  }

  @override
  Widget build(BuildContext context) {
    if (_userFsId.isEmpty) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(_userFsId)
          .collection('goals')
          .where('status', isEqualTo: 'active')
          .snapshots(),
      builder: (context, snap) {
        final goals = (snap.data?.docs ?? [])
            .where((d) => !_excludeGoal(d))
            .toList();
        if (goals.isEmpty) {
          return _EmptyObjectiveCard(onOpen: onOpenObjetivoModule);
        }
        goals.sort((a, b) {
          final ta = (a.data()['createdAt'] as Timestamp?)?.toDate();
          final tb = (b.data()['createdAt'] as Timestamp?)?.toDate();
          if (ta == null && tb == null) return 0;
          if (ta == null) return 1;
          if (tb == null) return -1;
          return tb.compareTo(ta);
        });
        final primary = goals.first;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ActiveObjectiveCard(
              goalDoc: primary,
              profile: profile,
              onOpenModule: onOpenObjetivoModule,
            ),
            if (goals.length > 1) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: onOpenObjetivoModule,
                icon: const Icon(Icons.layers_rounded, size: 18),
                label: Text(
                  'Ver mais ${goals.length - 1} objetivo(s)',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _EmptyObjectiveCard extends StatelessWidget {
  const _EmptyObjectiveCard({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF7C3AED), Color(0xFFEC4899)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.flag_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Objetivo Financeiro',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      'Projeto 52 semanas — viagem, carro, casa, reforma…',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Informe sua meta e o valor. O app monta a programação semanal automaticamente.',
            style: TextStyle(color: Colors.white, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onOpen,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF4F46E5),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Criar objetivo',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveObjectiveCard extends StatelessWidget {
  const _ActiveObjectiveCard({
    required this.goalDoc,
    required this.profile,
    required this.onOpenModule,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> goalDoc;
  final UserProfile profile;
  final VoidCallback onOpenModule;

  @override
  Widget build(BuildContext context) {
    final data = goalDoc.data();
    final title = (data['title'] ?? 'Objetivo').toString();
    final target = (data['targetAmount'] as num?)?.toDouble() ?? 0;
    final visual = goalVisualForData(data);
    final is52 = FiftyTwoWeeksPlan.is52WeeksGoal(data);
    final planStart = FiftyTwoWeeksPlan.planStartFromData(data) ?? DateTime.now();
    final currentWeek = is52 ? FiftyTwoWeeksPlan.currentWeekNumber(planStart) : 0;
    final weekEntry = is52
        ? FiftyTwoWeeksPlan.currentWeekEntry(target: target, planStart: planStart)
        : null;
    final paidWeeks = FiftyTwoWeeksPlan.paidWeeksFromData(data);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: goalDoc.reference.collection('contributions').snapshots(),
      builder: (context, contribSnap) {
        var current = 0.0;
        for (final d in contribSnap.data?.docs ?? []) {
          current += (d.data()['amount'] as num?)?.toDouble() ?? 0;
        }
        final progress = target > 0 ? (current / target).clamp(0.0, 1.0) : 0.0;
        final faltam = (target - current).clamp(0.0, double.infinity);
        final schedule = is52
            ? FiftyTwoWeeksPlan.buildSchedule(target: target, planStart: planStart)
            : const <FiftyTwoWeeksWeekEntry>[];
        final chartBars = _monthlyBars(schedule, paidWeeks, currentWeek);

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              colors: visual.gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: visual.color.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(visual.icon, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${visual.emoji} $title',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                          ),
                        ),
                        Text(
                          is52
                              ? 'Projeto 52 semanas · semana $currentWeek de 52'
                              : 'Objetivo financeiro',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.88),
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${(progress * 100).round()}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 10,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    CurrencyFormats.formatBRL(current),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    'Meta ${CurrencyFormats.formatBRL(target)}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              if (is52 && weekEntry != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white30),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Esta semana (${DateFormat('dd/MM', 'pt_BR').format(weekEntry.dueDate)})',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              CurrencyFormats.formatBRL(weekEntry.amount),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (paidWeeks.contains(currentWeek))
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            '✓ Guardado',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              if (chartBars.isNotEmpty) ...[
                const SizedBox(height: 14),
                SizedBox(
                  height: 88,
                  child: BarChart(
                    BarChartData(
                      maxY: chartBars.map((e) => e.y).fold<double>(0, (a, b) => a > b ? a : b) * 1.2 + 1,
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (v, _) {
                              final i = v.toInt();
                              if (i < 0 || i >= chartBars.length) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  chartBars[i].label,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.85),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      barGroups: [
                        for (var i = 0; i < chartBars.length; i++)
                          BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: chartBars[i].y,
                                width: 12,
                                color: Colors.white.withValues(alpha: 0.92),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Faltam ${CurrencyFormats.formatBRL(faltam)}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: profile.hasActiveLicense
                          ? () => showFiftyTwoWeeksScheduleSheet(
                                context: context,
                                goalDoc: goalDoc,
                                profile: profile,
                              )
                          : () => mostrarAvisoSeLicencaInativa(context, profile),
                      icon: const Icon(Icons.calendar_view_week_rounded, size: 18, color: Colors.white),
                      label: const Text(
                        'Ver 52 semanas',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white70),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: profile.hasActiveLicense
                          ? () async {
                              await showRegistrarAporteDialog(
                                context: context,
                                goalRef: goalDoc.reference,
                                profile: profile,
                              );
                            }
                          : () => mostrarAvisoSeLicencaInativa(context, profile),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: visual.color,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.savings_rounded, size: 18),
                      label: const Text(
                        'Aporte',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onOpenModule,
                  icon: Icon(Icons.open_in_new_rounded, size: 16, color: Colors.white.withValues(alpha: 0.95)),
                  label: Text(
                    'Abrir Objetivo Financeiro',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.95),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<({double y, String label})> _monthlyBars(
    List<FiftyTwoWeeksWeekEntry> schedule,
    List<int> paidWeeks,
    int currentWeek,
  ) {
    if (schedule.isEmpty) return const [];
    final byMonth = <String, double>{};
    for (final e in schedule) {
      if (e.week > currentWeek) continue;
      byMonth[e.monthKey] = (byMonth[e.monthKey] ?? 0) + e.amount;
    }
    final keys = byMonth.keys.toList()..sort();
    final recent = keys.length > 6 ? keys.sublist(keys.length - 6) : keys;
    return recent.map((k) {
      final parts = k.split('-');
      final month = int.tryParse(parts.length > 1 ? parts[1] : '1') ?? 1;
      const names = ['', 'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];
      return (y: byMonth[k] ?? 0, label: names[month.clamp(1, 12)]);
    }).toList();
  }
}
