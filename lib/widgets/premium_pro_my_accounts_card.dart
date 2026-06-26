import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/premium_pro_limits.dart';
import '../models/user_profile.dart';
import '../screens/bank_connection_screen.dart';
import '../theme/app_colors.dart';
import 'bank_card_widget.dart';
import 'pluggy_sync_schedule_banner.dart';
import 'premium_pro_value_copy.dart';

/// Bloco "Minhas contas" (Open Finance) no módulo Financeiro — Premium PRO.
class PremiumProMyAccountsCard extends StatelessWidget {
  final String uid;
  final UserProfile profile;

  const PremiumProMyAccountsCard({
    super.key,
    required this.uid,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    if (!profile.canUseOpenFinanceBanks) return const SizedBox.shrink();

    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('bank_connections');

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: ref.snapshots(),
          builder: (context, snap) {
            final n = snap.data?.docs.length ?? 0;
            final included = PremiumProLimits.includedBankConnections(
              email: profile.email,
              adminPerUserOverride: profile.premiumProIncludedBankConnections,
            );
            final lim = '$n/$included';
            final full = n >= included;

            Widget listSection;
            if (!snap.hasData) {
              listSection = const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
              );
            } else {
              final docs = snap.data!.docs;
              if (docs.isEmpty) {
                listSection = Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Nenhuma conta conectada. Toque em Adicionar para escolher seu banco.',
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                  ),
                );
              } else {
                listSection = Column(
                  children: docs.map((d) {
                    final m = d.data();
                    final name = (m['bankName'] ?? 'Banco').toString();
                    final status = (m['status'] ?? '').toString().toLowerCase();
                    final ok = status == 'connected';
                    final last = m['lastSync'];
                    String syncStr = '—';
                    if (last is Timestamp) {
                      syncStr = DateFormat('dd/MM/yyyy HH:mm').format(last.toDate());
                    }
                    return BankCardWidget(
                      bankName: name,
                      statusLabel: ok ? 'Banco conectado com sucesso' : 'Conectando…',
                      connected: ok,
                      balanceLabel: 'Saldo atual: em breve (API)',
                      lastSyncLabel: syncStr,
                    );
                  }).toList(),
                );
              }
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PluggySyncScheduleBanner(uid: uid),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.account_balance_wallet_rounded, color: AppColors.primary, size: 26),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Minhas contas · Open Finance · $lim',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: full
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      BankConnectionScreen(
                                        uid: uid,
                                        accountEmail: profile.email,
                                        includedBankSlotsOverride: profile.premiumProIncludedBankConnections,
                                      ),
                                ),
                              ),
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: Text(full ? 'Limite' : 'Adicionar'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const PremiumProDiferencialChips(),
                const SizedBox(height: 10),
                Text(
                  'Após conectar: compra aparece no app, categorização automática e controle sem esforço.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35),
                ),
                const SizedBox(height: 10),
                listSection,
              ],
            );
          },
        ),
      ),
    );
  }
}
