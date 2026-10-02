import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../constants/admin_content_editor_config.dart';
import '../constants/admin_master_config.dart';
import '../constants/admin_partner_config.dart';
import '../models/user_profile.dart';
import '../theme/theme_context.dart';

/// Protege rotas admin. Com [trustedProfile] (sessão já carregada no app),
/// abre o painel na hora — sem tela branca aguardando Firestore.
class AdminGuard extends StatelessWidget {
  final Widget child;
  final UserProfile? trustedProfile;

  const AdminGuard({
    super.key,
    required this.child,
    this.trustedProfile,
  });

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.login_rounded,
                      size: 56, color: context.appDeepTitle),
                  const SizedBox(height: 16),
                  const Text(
                    'Faça login para acessar o painel admin.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context)
                        .pushNamedAndRemoveUntil('/admin', (r) => false),
                    icon: const Icon(Icons.admin_panel_settings_rounded),
                    label: const Text('Entrar no Admin'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Master = SÓ e-mail de dono verificado no login (02/10/2026): entra
    // mesmo que o doc não tenha `role` de admin.
    if (AdminMasterConfig.currentUserIsMaster()) return child;

    final trusted = trustedProfile;
    if (trusted != null) {
      if (trusted.canAccessAdminPanel) return child;
      return _restrictedAccess(context);
    }

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: SafeArea(child: Center(child: CircularProgressIndicator())),
          );
        }

        if (snapshot.hasError) {
          return const Scaffold(
            body: SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 48, color: Colors.orange),
                    SizedBox(height: 16),
                    Text(
                        'Não foi possível verificar o acesso. Tente novamente.'),
                  ],
                ),
              ),
            ),
          );
        }

        if (snapshot.hasData && snapshot.data!.exists) {
          final userData = snapshot.data!.data() as Map<String, dynamic>?;
          final role = (userData?['role'] ?? '').toString();
          final email = user.email?.trim().toLowerCase();

          if (role == 'admin' ||
              role == 'master' ||
              role == 'gestor' ||
              role == 'partner' ||
              role == 'socio' ||
              AdminContentEditorConfig.isContentEditorRole(role) ||
              AdminPartnerConfig.isPartnerEmail(email)) {
            return child;
          }
        }

        return _restrictedAccess(context);
      },
    );
  }

  static Widget restrictedAccess(BuildContext context) =>
      _restrictedAccess(context);

  static Widget _restrictedAccess(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_person_rounded,
                  size: 80, color: Colors.redAccent),
              const SizedBox(height: 24),
              const Text(
                'ACESSO RESTRITO',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5),
              ),
              const SizedBox(height: 8),
              const Text('Esta área é exclusiva para administradores.'),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('VOLTAR'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
