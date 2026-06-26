import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../screens/admin_screen.dart';
import '../widgets/admin_guard.dart';

/// Abre o Painel Admin com perfil já em memória (sem round-trip Firestore no guard).
void openAdminPanel(
  BuildContext context, {
  required String uid,
  required UserProfile profile,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AdminGuard(
        trustedProfile: profile,
        child: AdminScreen(uid: uid, profile: profile),
      ),
    ),
  );
}
