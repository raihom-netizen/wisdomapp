import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Preferências de exportação programada (execução server-side futura).
class AdminScheduledExportPrefsService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const docPath = 'app_config/admin_scheduled_exports';

  Future<Map<String, dynamic>?> load() async {
    final snap = await _db.doc(docPath).get();
    if (!snap.exists) return null;
    return snap.data();
  }

  Future<void> save({
    required bool enabled,
    required String email,
    required String frequency, // daily | weekly | monthly
  }) async {
    final user = _auth.currentUser;
    await _db.doc(docPath).set({
      'enabled': enabled,
      'email': email.trim(),
      'frequency': frequency,
      'updatedAt': FieldValue.serverTimestamp(),
      if (user != null) 'updatedBy': user.uid,
    }, SetOptions(merge: true));
  }
}
