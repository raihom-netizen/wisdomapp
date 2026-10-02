import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/admin_master_config.dart';
import '../models/user_profile.dart';
import '../services/app_session_cache.dart';
import '../services/firestore_service.dart';
import '../services/user_profile_startup_cache.dart';
import '../widgets/admin_guard.dart';
import 'admin_screen.dart';
import 'landing_screen.dart';
import 'login_screen.dart';

/// Rota `/admin`: login se necessário → verificação admin → [AdminScreen].
class AdminRouteGate extends StatelessWidget {
  const AdminRouteGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data ?? FirebaseAuth.instance.currentUser;

        if (snapshot.connectionState == ConnectionState.waiting &&
            user == null) {
          final cachedUid = AppSessionCache.cachedUidSync();
          if (cachedUid != null &&
              AppSessionCache.isShellReadyForSync(cachedUid)) {
            return _AdminScreenHost(uid: cachedUid);
          }
          return const Scaffold(
            body: SafeArea(
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (user == null) {
          return kIsWeb ? const LoginScreen() : const LandingScreen();
        }

        return _AdminScreenHost(uid: user.uid);
      },
    );
  }
}

class _AdminScreenHost extends StatefulWidget {
  final String uid;

  const _AdminScreenHost({required this.uid});

  @override
  State<_AdminScreenHost> createState() => _AdminScreenHostState();
}

class _AdminScreenHostState extends State<_AdminScreenHost> {
  /// Escuta do perfil guardada no State (Firestore Web: nunca `.snapshots()`
  /// criado no build — cada rebuild abria outra escuta).
  late Stream<UserProfile> _profileStream;

  @override
  void initState() {
    super.initState();
    _profileStream = FirestoreService().watchProfile(widget.uid);
    unawaited(UserProfileStartupCache.prefetch(widget.uid));
    unawaited(AppSessionCache.markShellReady(widget.uid));
  }

  @override
  void didUpdateWidget(covariant _AdminScreenHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      _profileStream = FirestoreService().watchProfile(widget.uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.uid;
    final cached = UserProfileStartupCache.getSync(uid);

    return StreamBuilder<UserProfile>(
      stream: _profileStream,
      builder: (context, snap) {
        if (snap.hasError && cached == null) {
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Não foi possível carregar o perfil admin.\n${snap.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          );
        }

        final profile = snap.data ?? cached;
        if (profile == null) {
          return const Scaffold(
            body: SafeArea(
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (snap.hasData) {
          unawaited(UserProfileStartupCache.save(uid, snap.data!));
        }

        if (!profile.canAccessAdminPanel &&
            !AdminMasterConfig.currentUserIsMaster()) {
          return AdminGuard.restrictedAccess(context);
        }

        return RepaintBoundary(
          child: AdminScreen(uid: uid, profile: profile),
        );
      },
    );
  }
}
