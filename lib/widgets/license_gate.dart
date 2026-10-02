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
  int _tentativa = 0;

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
      key: ValueKey('perfil#$_tentativa'),
      stream: FirestoreService().watchProfile(fsUid),
      builder: (context, snap) {
        final profile = snap.data;
        if (profile == null) {
          return PerfilCarregando(
            erro: snap.hasError,
            onTentarDeNovo: () => setState(() => _tentativa++),
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
  int _tentativa = 0;

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
      key: ValueKey('perfil#$_tentativa'),
      stream: FirestoreService().watchProfile(fsUid),
      builder: (context, snap) {
        final profile = snap.data;
        if (profile == null) {
          return PerfilCarregando(
            erro: snap.hasError,
            onTentarDeNovo: () => setState(() => _tentativa++),
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

/// Carregando o perfil (licença): nada de girar para sempre. Com erro ou
/// passado o prazo, mostra o aviso e «Tentar de novo» (reabre a escuta).
class PerfilCarregando extends StatefulWidget {
  const PerfilCarregando({
    super.key,
    required this.erro,
    required this.onTentarDeNovo,
  });

  final bool erro;
  final VoidCallback onTentarDeNovo;

  @override
  State<PerfilCarregando> createState() => _PerfilCarregandoState();
}

class _PerfilCarregandoState extends State<PerfilCarregando> {
  Timer? _prazo;
  bool _demorou = false;

  @override
  void initState() {
    super.initState();
    _prazo = Timer(const Duration(seconds: 15), () {
      if (mounted) setState(() => _demorou = true);
    });
  }

  @override
  void dispose() {
    _prazo?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mostrarAviso = widget.erro || _demorou;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!mostrarAviso)
                  const CircularProgressIndicator()
                else ...[
                  Icon(Icons.cloud_off_rounded,
                      size: 44, color: Theme.of(context).colorScheme.error),
                  const SizedBox(height: 12),
                  Text(
                    widget.erro
                        ? 'Não foi possível abrir seus dados agora.'
                        : 'Está demorando mais que o normal para abrir.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Verifique a internet e toque em «Tentar de novo».',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () {
                      _prazo?.cancel();
                      setState(() => _demorou = false);
                      _prazo = Timer(const Duration(seconds: 15), () {
                        if (mounted) setState(() => _demorou = true);
                      });
                      widget.onTentarDeNovo();
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Tentar de novo'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
