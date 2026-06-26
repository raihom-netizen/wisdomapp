import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../screens/escolha_plano_page.dart';
import '../theme/app_colors.dart';

/// Garante que o fluxo Pluggy/Open Finance **não** abre para quem não tem
/// [UserProfile.canUseOpenFinanceBanks], mesmo via link direto.
///
/// **Onde a UI passa por aqui (rotas/fluxos reais):** `BankConnectionScreen`,
/// `OpenFinanceConnectionsScreen` e, na vitrine de bancos, pré-check
/// + `UserProfile` antes de abrir `BankConnectionScreen` (não se abre
/// o Pluggy manualmente a partir dali).
class OpenFinanceEntitlementGuard extends StatelessWidget {
  const OpenFinanceEntitlementGuard({
    super.key,
    required this.uid,
    required this.entitledBuilder,
    this.appBarTitle = 'Conexões bancárias',
  });

  final String uid;
  final String appBarTitle;
  final Widget Function(BuildContext context, UserProfile profile) entitledBuilder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(title: Text(appBarTitle)),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Não foi possível carregar o perfil. ${snap.error}', textAlign: TextAlign.center),
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return Scaffold(
            appBar: AppBar(title: Text(appBarTitle)),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final profile = UserProfile.fromFirestoreMap(uid, snap.data!.data() ?? {});
        if (!profile.canUseOpenFinanceBanks) {
          return _OpenFinanceUnavailableScaffold(appBarTitle: appBarTitle);
        }
        return entitledBuilder(context, profile);
      },
    );
  }
}

class _OpenFinanceUnavailableScaffold extends StatelessWidget {
  const _OpenFinanceUnavailableScaffold({required this.appBarTitle});

  final String appBarTitle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(appBarTitle)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_balance_wallet_outlined, size: 56, color: AppColors.primary.withValues(alpha: 0.85)),
            const SizedBox(height: 16),
            const Text(
              'Ligação automática a bancos indisponível',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(
              'O WISDOMAPP funciona com o plano Premium: finanças, metas e agenda com lançamentos à mão. '
              'Não vendemos nem ativamos novas integrações automáticas com instituições a partir desta versão.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: Colors.grey.shade800,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const EscolhaPlanoPage()),
                );
              },
              child: const Text('Ver plano Premium'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Voltar'),
            ),
          ],
        ),
      ),
    );
  }
}
