import 'package:cloud_firestore/cloud_firestore.dart';

/// Serviço para sugestões e críticas dos usuários. Admin lê e responde no painel.
class UserFeedbackService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('user_feedback');

  Future<void> sendFeedback({
    required String uid,
    required String? email,
    required String? name,
    required String message,
  }) async {
    await _col.add({
      'uid': uid,
      'email': email ?? '',
      'name': name ?? '',
      'message': message.trim(),
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Painel admin: as mais recentes (com teto — a coleção só cresce).
  /// Guarde o stream no State; nunca chamar dentro do build.
  Stream<QuerySnapshot<Map<String, dynamic>>> watchAllFeedback({int limit = 500}) {
    return _col.orderBy('createdAt', descending: true).limit(limit).snapshots();
  }

  /// Status de triagem no painel: `pending` (nova), `em_analise`, `replied`.
  Future<void> setStatus(String docId, String status) async {
    await _col.doc(docId).update({
      'status': status,
      'statusAt': FieldValue.serverTimestamp(),
    });
  }

  static bool isEmAnalise(Map<String, dynamic> data) =>
      (data['status'] ?? '').toString() == 'em_analise';

  Future<void> replyToFeedback(String docId, String adminReply) async {
    await _col.doc(docId).update({
      'adminReply': adminReply.trim(),
      'repliedAt': FieldValue.serverTimestamp(),
      'status': 'replied',
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchUserFeedback(String uid) {
    return _col.where('uid', isEqualTo: uid).orderBy('createdAt', descending: true).snapshots();
  }

  /// `pending` ou ausente = aberto; `replied` = respondido.
  static bool isReplied(Map<String, dynamic> data) =>
      (data['status'] ?? 'pending').toString() == 'replied';

  Future<void> deleteFeedback(String docId) async {
    await _col.doc(docId).delete();
  }

  /// Exclusão em lote (até 500 por commit Firestore).
  Future<int> deleteFeedbackBulk(Iterable<String> docIds) async {
    final ids = docIds.toList();
    if (ids.isEmpty) return 0;
    var deleted = 0;
    for (var i = 0; i < ids.length; i += 500) {
      final chunk = ids.skip(i).take(500);
      final batch = _db.batch();
      for (final id in chunk) {
        batch.delete(_col.doc(id));
      }
      await batch.commit();
      deleted += chunk.length;
    }
    return deleted;
  }
}
