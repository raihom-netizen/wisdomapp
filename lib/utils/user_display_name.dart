import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_profile.dart';
import '../services/login_preferences.dart';
import '../services/user_profile_startup_cache.dart';

/// Nome amigável para header/Início — evita «Gestor» após reload ou perfil ainda a carregar.
String resolveUserDisplayName(UserProfile? profile, {String? uid}) {
  final cleanUid = (uid ?? profile?.uid ?? '').trim();
  if (profile != null) {
    final n = profile.name.trim();
    if (n.isNotEmpty) return n;
  }
  if (cleanUid.isNotEmpty) {
    final cached = UserProfileStartupCache.getSync(cleanUid);
    final cn = cached?.name.trim() ?? '';
    if (cn.isNotEmpty) return cn;
  }
  final authName = FirebaseAuth.instance.currentUser?.displayName?.trim();
  if (authName != null && authName.isNotEmpty) return authName;
  final prefsName = LoginPreferences.startupLastDisplayName?.trim() ?? '';
  if (prefsName.isNotEmpty) return prefsName;
  if (profile != null) {
    final email = profile.email.trim();
    if (email.contains('@')) {
      final local = email.split('@').first.trim();
      if (local.isNotEmpty) return local;
    }
  }
  final authEmail = FirebaseAuth.instance.currentUser?.email?.trim();
  if (authEmail != null && authEmail.contains('@')) {
    final local = authEmail.split('@').first.trim();
    if (local.isNotEmpty) return local;
  }
  return 'Usuário';
}
