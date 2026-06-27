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
import '../widgets/goal_contributions_sheet.dart';
import '../widgets/create_financial_goal_dialog.dart';
import '../widgets/fifty_two_weeks_schedule_sheet.dart';
import '../widgets/goal_52_weeks_summary_panel.dart';
import '../widgets/registrar_deposito_dialog.dart';

/// Card «Objetivo Financeiro» no Início — Projeto 52 semanas + progresso.
class HomeObjectiveFinancePanel extends StatelessWidget {
  const HomeObjectiveFinancePanel({
    super.key,
    required this.uid,
    required this.profile,
    required this.onOpenObjetivoModule,
  });

  static const int maxGoalsOnHome = 3;

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
          return _EmptyObjectiveCard(uid: uid, profile: profile);
        }
        goals.sort((a, b) {
          final ta = (a.data()['createdAt'] as Timestamp?)?.toDate();
          final tb = (b.data()['createdAt'] as Timestamp?)?.toDate();
          if (ta == null && tb == null) return 0;
          if (ta == null) return 1;
          if (tb == null) return -1;
          return tb.compareTo(ta);
        });
        final visible = goals.take(maxGoalsOnHome).toList();
        final hiddenCount = goals.length - visible.length;
        final showModuleLinkOnCards = visible.length == 1 && hiddenCount == 0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < visible.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _ActiveObjectiveCard(
                goalDoc: visible[i],
                uid: uid,
                profile: profile,
                onOpenModule: onOpenObjetivoModule,
                showModuleLink: showModuleLinkOnCards,
              ),
            ],
            if (hiddenCount > 0) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onOpenObjetivoModule,
                icon: const Icon(Icons.flag_rounded, size: 20),
                label: Text(
                  hiddenCount == 1
                      ? 'Veja mais 1 objetivo no módulo Objetivo'
                      : 'Veja mais $hiddenCount objetivos no módulo Objetivo',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF4F46E5),
                  side: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
  const _EmptyObjectiveCard({
    required this.uid,
    required this.profile,
  });

  final String uid;
  final UserProfile profile;

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
                      'Projeto 52 semanas - viagem, carro, casa, reforma...',
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
              onPressed: () => showCreateFinancialGoalDialog(
                context,
                profile: profile,
                uid: uid,
              ),
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
    required this.uid,
    required this.profile,
    required this.onOpenModule,
    this.showModuleLink = true,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> goalDoc;
  final String uid;
  final UserProfile profile;
  final VoidCallback onOpenModule;
  final bool showModuleLink;

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
        final paidCount = paidWeeks.length;
        final remainingWeeks = (52 - paidCount).clamp(0, 52);

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
                              ? 'Projeto 52 semanas - semana $currentWeek de 52'
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
              if (is52) ...[
                Goal52WeeksSummaryPanel(
                  target: target,
                  deposited: current,
                  paidWeeks: paidCount,
                  currentWeek: currentWeek,
                  gradient: visual.gradient,
                  compact: true,
                ),
                const SizedBox(height: 12),
              ],
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
              if (target > 0) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white30),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 96,
                        height: 96,
                        child: PieChart(
                          PieChartData(
                            sectionsSpace: 2,
                            centerSpaceRadius: 26,
                            sections: [
                              if (current > 0)
                                PieChartSectionData(
                                  value: current,
                                  color: Colors.white,
                                  radius: 22,
                                  title: '${(progress * 100).round()}%',
                                  titleStyle: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    color: visual.color,
                                  ),
                                ),
                              if (faltam > 0)
                                PieChartSectionData(
                                  value: faltam,
                                  color: Colors.white.withValues(alpha: 0.28),
                                  radius: 22,
                                  title: '',
                                ),
                              if (current <= 0 && faltam <= 0)
                                PieChartSectionData(
                                  value: 1,
                                  color: Colors.white.withValues(alpha: 0.25),
                                  radius: 22,
                                  title: '0%',
                                  titleStyle: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                            ],
                          ),
                          duration: const Duration(milliseconds: 350),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Evolução dos depósitos',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.95),
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _legendDot(
                              color: Colors.white,
                              label: 'Depositado',
                              value: CurrencyFormats.formatBRLTight(current),
                            ),
                            const SizedBox(height: 4),
                            _legendDot(
                              color: Colors.white.withValues(alpha: 0.45),
                              label: 'Faltam',
                              value: CurrencyFormats.formatBRLTight(faltam),
                            ),
                            if (is52) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  _miniChip('$paidCount sem. ok'),
                                  _miniChip('$remainingWeeks faltam'),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
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
                    child: FilledButton.icon(
                      onPressed: profile.hasActiveLicense
                          ? () async {
                              if (is52) {
                                await showFiftyTwoWeeksScheduleSheet(
                                  context: context,
                                  goalDoc: goalDoc,
                                  profile: profile,
                                  uid: uid,
                                  depositMode: true,
                                );
                              } else {
                                await showRegistrarDepositoDialog(
                                  context: context,
                                  goalRef: goalDoc.reference,
                                  goalId: goalDoc.id,
                                  goalTitle: title,
                                  uid: uid,
                                  profile: profile,
                                );
                              }
                            }
                          : () => mostrarAvisoSeLicencaInativa(context, profile),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: visual.color,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: Icon(
                        is52 ? Icons.calendar_view_week_rounded : Icons.savings_rounded,
                        size: 18,
                      ),
                      label: Text(
                        is52 ? 'Selecionar semanas' : 'Depositar',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: profile.hasActiveLicense
                          ? () => showGoalContributionsSheet(
                                context: context,
                                goalDoc: goalDoc,
                                goalTitle: title,
                                uid: uid,
                                profile: profile,
                              )
                          : () => mostrarAvisoSeLicencaInativa(context, profile),
                      icon: const Icon(Icons.list_alt_rounded, size: 18, color: Colors.white),
                      label: const Text(
                        'Lançamentos',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white70),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
              if (is52) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: profile.hasActiveLicense
                        ? () => showFiftyTwoWeeksScheduleSheet(
                              context: context,
                              goalDoc: goalDoc,
                              profile: profile,
                              uid: uid,
                            )
                        : () => mostrarAvisoSeLicencaInativa(context, profile),
                    icon: const Icon(Icons.calendar_view_week_rounded, size: 18, color: Colors.white),
                    label: const Text(
                      'Ver 52 semanas',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.45)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Goal52WeeksPdfButton(
                  onPressed: profile.hasActiveLicense
                      ? () => exportFiftyTwoWeeksGoalPdf(context: context, goalDoc: goalDoc)
                      : () => mostrarAvisoSeLicencaInativa(context, profile),
                  label: 'Exportar PDF',
                ),
              ],
              if (showModuleLink) ...[
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
            ],
          ),
        );
      },
    );
  }

  Widget _legendDot({
    required Color color,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11.5,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _miniChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
