import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

class LogsService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> saveLog({
    required String acao,
    required String modulo,
    String? detalhes,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _db.collection('activity_logs').add({
        'adminId': user.uid,
        'adminEmail': user.email,
        'acao': acao,
        'modulo': modulo,
        'detalhes': detalhes ?? '',
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Erro ao salvar log: $e');
    }
  }
}