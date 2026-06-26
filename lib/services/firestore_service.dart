import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_profile.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> userDoc(String uid) {
    final clean = uid.trim();
    assert(clean.isNotEmpty, 'Firestore userDoc: uid vazio');
    return _db.collection('users').doc(clean);
  }

  DocumentReference<Map<String, dynamic>> _legacyUserDoc(String uid) =>
      _db.collection('users_uid').doc(uid);

  /// Listener em tempo real (equivalente a onSnapshot). Assim que o webhook do MP atualiza
  /// licenseExpiresAt/plan no Firestore, o Stream emite o novo perfil e a UI libera instantaneamente.
  Stream<UserProfile> watchProfile(String uid) {
    final clean = uid.trim();
    if (clean.isEmpty) {
      return const Stream<UserProfile>.empty();
    }
    return userDoc(clean).snapshots().map((snap) {
      final d = snap.data() ?? {};
      return UserProfile.fromFirestoreMap(clean, d);
    });
  }

  Future<void> ensureUserProfile({
    required String uid,
    required String email,
    required String name,
  }) async {
    final now = FieldValue.serverTimestamp();
    final ref = userDoc(uid);

    // 1) tenta criar/atualizar em users/{uid} (estrutura: name, plan, licenseExpiresAt, planStatus)
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        final trialEnd = DateTime.now().add(Duration(days: UserProfile.newUserTrialDays));
        tx.set(ref, {
          'email': email,
          'name': name,
          'role': 'user',
          'plan': 'premium',
          'planStatus': 'active',
          'licenseExpiresAt': Timestamp.fromDate(trialEnd),
          'createdAt': now,
          'updatedAt': now,
        }, SetOptions(merge: true));
      } else {
        final existingEmail = (snap.data()?['email'] ?? '').toString().trim();
        final patch = <String, dynamic>{'updatedAt': now};
        if (existingEmail.isEmpty && email.trim().isNotEmpty) {
          patch['email'] = email.trim().toLowerCase();
        }
        final existingName = (snap.data()?['name'] ?? '').toString().trim();
        if (existingName.isEmpty && name.trim().isNotEmpty) {
          patch['name'] = name.trim();
        }
        tx.set(ref, patch, SetOptions(merge: true));
      }
    });

    // 2) migra legado (se existir) users_uid/{uid} -> users/{uid} — apenas uma vez
    try {
      final snap = await ref.get();
      if (snap.exists && (snap.data()?['migratedFromLegacy'] == true)) return;
      final legacy = await _legacyUserDoc(uid).get();
      if (legacy.exists) {
        final data = legacy.data() ?? {};
        if (data.isNotEmpty) {
          await ref.set({
            'cpf': (data['cpf'] ?? ''),
            'cpfMasked': (data['cpfMasked'] ?? ''),
            'email': (data['email'] ?? email),
            'name': (data['name'] ?? name),
            'role': (data['role'] ?? 'user'),
            'plan': (data['plan'] ?? 'premium'),
            'planStatus': (data['planStatus'] ?? 'active'),
            'migratedFromLegacy': true,
            'updatedAt': now,
          }, SetOptions(merge: true));
        }
      }
    } catch (_) {
      // ignora
    }
  }
}
