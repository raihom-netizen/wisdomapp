import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../services/firestore_service.dart';
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

class _AdminScreenHost extends StatelessWidget {
  final String uid;

  const _AdminScreenHost({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UserProfile>(
      stream: FirestoreService().watchProfile(uid),
      builder: (context, snap) {
        if (snap.hasError) {
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
        if (!snap.hasData) {
          return const Scaffold(
            body: SafeArea(
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        if (!snap.data!.canAccessAdminPanel) {
          return AdminGuard.restrictedAccess(context);
        }
        return AdminScreen(uid: uid, profile: snap.data!);
      },
    );
  }
}
