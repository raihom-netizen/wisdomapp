import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../utils/firestore_user_doc_id.dart';
import '../widgets/create_financial_goal_dialog.dart';
import '../widgets/goal_52_weeks_objective_card.dart';

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
              Goal52WeeksObjectiveCard(
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
                      ? 'Veja mais 1 objetivo em Objetivos Financeiros'
                      : 'Veja mais $hiddenCount objetivos em Objetivos Financeiros',
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
                      'Objetivos Financeiros',
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
