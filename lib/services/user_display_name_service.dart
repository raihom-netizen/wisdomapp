import 'package:characters/characters.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_profile.dart';
import '../utils/firestore_user_doc_id.dart';
import 'login_preferences.dart';
import 'user_profile_startup_cache.dart';

/// Grava nome/sobrenome exibidos no painel — sincroniza Firestore, cache e Auth.
class UserDisplayNameService {
  UserDisplayNameService._();
  static final UserDisplayNameService instance = UserDisplayNameService._();

  static const int maxPartLength = 40;

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String sanitizeNamePart(String raw) {
    var t = raw.trim();
    if (t.isEmpty) return '';
    if (t.characters.length > maxPartLength) {
      t = t.characters.take(maxPartLength).string;
    }
    return t;
  }

  Future<UserProfile?> saveDisplayNameParts({
    required String uid,
    required String firstName,
    required String lastName,
    UserProfile? currentProfile,
  }) async {
    final fn = sanitizeNamePart(firstName);
    final ln = sanitizeNamePart(lastName);
    final full = UserProfile.composeDisplayNameParts(fn, ln);
    if (full.isEmpty) {
      throw ArgumentError('Informe ao menos o nome ou sobrenome.');
    }

    final docId = firestoreUserDocIdForAppShell(uid);
    final ref = _db.collection('users').doc(docId);
    await ref.set(
      {
        'displayFirstName': fn,
        'displayLastName': ln,
        'name': full,
        'displayName': full,
        'displayNameUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    try {
      await FirebaseAuth.instance.currentUser?.updateDisplayName(full);
    } catch (_) {}

    await LoginPreferences.setLastDisplayName(full);

    if (currentProfile != null) {
      final updated = UserProfile(
        uid: currentProfile.uid,
        cpf: currentProfile.cpf,
        cpfMasked: currentProfile.cpfMasked,
        email: currentProfile.email,
        name: full,
        firstName: fn,
        lastName: ln,
        role: currentProfile.role,
        plan: currentProfile.plan,
        planStatus: currentProfile.planStatus,
        licenseExpiresAt: currentProfile.licenseExpiresAt,
        createdAt: currentProfile.createdAt,
        profileComplete: currentProfile.profileComplete,
        premiumPro: currentProfile.premiumPro,
        isPremiumPro: currentProfile.isPremiumPro,
        partnershipId: currentProfile.partnershipId,
        premiumProIncludedBankConnections:
            currentProfile.premiumProIncludedBankConnections,
        authorizedDelegateEmail: currentProfile.authorizedDelegateEmail,
      );
      await UserProfileStartupCache.save(docId, updated);
      return updated;
    }
    return null;
  }
}
