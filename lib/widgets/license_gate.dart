import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/delegate_access_service.dart';
import '../services/firestore_service.dart';
import '../utils/firestore_user_doc_id.dart';
import '../screens/license_expired_screen.dart';

/// Guarda de rota: bloqueio total **somente** se `isPastGracePeriod` (venceu + passaram os 3 dias de carência).
/// Quem está em carência ou com licença válida não é redirecionado. Pagamento/checkout em outras rotas pode ser fechado sem travar o app.
/// Redireciona para /licenca-expirada e impede acesso a Dashboard, Escalas, Configurações.
/// Quando o pagamento for aprovado, o onSnapshot em LicencaExpiradaRoute detecta e redireciona de volta.
class LicenseGate extends StatefulWidget {
  final String uid;
  final Widget child;

  const LicenseGate({super.key, required this.uid, required this.child});

  @override
  State<LicenseGate> createState() => _LicenseGateState();
}

class _LicenseGateState extends State<LicenseGate> {
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fsUid = firestoreUserDocIdStrictFromSession();
    if (fsUid.isEmpty) {
      return const Scaffold(
        body: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }
    return StreamBuilder<UserProfile>(
      stream: FirestoreService().watchProfile(fsUid),
      builder: (context, snap) {
        final profile = snap.data;
        if (profile == null) {
          return const Scaffold(
            body: SafeArea(child: Center(child: CircularProgressIndicator())),
          );
        }

        // Admin ignora bloqueio
        if (profile.isAdmin) return widget.child;

        // Cálculo de bloqueio: data_atual > validade + 3 dias
        if (profile.isPastGracePeriod && profile.licenseExpiresAt != null) {
          // Redireciona para página de planos (mesma URL que aparece na barra ao bloquear)
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              Navigator.of(context).pushNamedAndRemoveUntil(
                '/licenca-expirada',
                (route) => false,
              );
            }
          });
          return const Scaffold(
            body: SafeArea(child: Center(child: CircularProgressIndicator())),
          );
        }

        return widget.child;
      },
    );
  }
}

/// Rota /licenca-expirada: única página acessível quando bloqueado.
/// Listener (onSnapshot): assim que validade for atualizada no Firebase, redireciona para Dashboard.
class LicencaExpiradaRoute extends StatefulWidget {
  const LicencaExpiradaRoute({super.key});

  @override
  State<LicencaExpiradaRoute> createState() => _LicencaExpiradaRouteState();
}

class _LicencaExpiradaRouteState extends State<LicencaExpiradaRoute> {
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
        }
      });
      return const Scaffold(body: SafeArea(child: Center(child: CircularProgressIndicator())));
    }

    final fsUid = firestoreUserDocIdStrictFromSession();
    if (fsUid.isEmpty) {
      return const Scaffold(
        body: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    return StreamBuilder<UserProfile>(
      stream: FirestoreService().watchProfile(fsUid),
      builder: (context, snap) {
        final profile = snap.data;
        if (profile == null) {
          return const Scaffold(
            body: SafeArea(child: Center(child: CircularProgressIndicator())),
          );
        }

        // Liberação em tempo real: titular renovou → sub-login também entra.
        if (!profile.isPastGracePeriod || profile.isAdmin) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            await AuthService().refreshToken();
            if (!mounted) return;
            Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
          });
          return const Scaffold(
            body: SafeArea(child: Center(child: CircularProgressIndicator())),
          );
        }

        return LicenseExpiredScreen(
          expirationDate: profile.licenseExpiresAt!,
          userEmail: profile.email.isNotEmpty ? profile.email : null,
          blockedPlan: profile.plan,
          isDelegateSession: DelegateAccessService.isActingAsDelegate,
          principalEmail: DelegateAccessService.principalEmail,
        );
      },
    );
  }
}
