import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Notas internas visíveis só no painel admin (campo no doc `users/{uid}`).
class AdminUserInternalNotesService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<String> watchNote(String uid) {
    return _db.collection('users').doc(uid).snapshots().map((snap) {
      if (!snap.exists) return '';
      final data = snap.data();
      return (data?['adminInternalNote'] ?? '').toString();
    });
  }

  Future<void> saveNote(String uid, String note) async {
    final admin = _auth.currentUser;
    await _db.collection('users').doc(uid).set({
      'adminInternalNote': note.trim(),
      'adminInternalNoteUpdatedAt': FieldValue.serverTimestamp(),
      if (admin != null) 'adminInternalNoteBy': admin.uid,
      if (admin?.email != null && admin!.email!.trim().isNotEmpty)
        'adminInternalNoteByEmail': admin.email!.trim(),
    }, SetOptions(merge: true));
  }
}
