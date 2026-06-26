import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/firestore_user_doc_id.dart';

/// Serviço para o usuário exportar seus próprios dados (backup local).
/// Os dados são salvos em um arquivo JSON que ele pode guardar na pasta que quiser.
class UserBackupService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Coleções e subcoleções do usuário que entram no backup.
  static const List<String> _userCollections = [
    'settings',
    'locations',
    'reminders',
    'transactions',
    'scales',
    'budgets',
    'quotes',
    'goals',
    'payments',
    'category_types',
    'ocorrencias',
    'finance_accounts',
  ];

  /// Gera um mapa com todos os dados do usuário para exportação.
  Future<Map<String, dynamic>> exportUserData(String uid) async {
    final id = firestoreUserDocIdForAppShell(uid);
    final userRef = _db.collection('users').doc(id);
    final userSnap = await userRef.get();
    final Map<String, dynamic> out = {
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'uid': id,
      'profile': userSnap.exists ? _sanitizeMap(userSnap.data()!) : null,
      'collections': {},
    };

    for (final col in _userCollections) {
      final snap = await userRef.collection(col).get();
      out['collections']![col] = snap.docs.map((d) => _sanitizeMap({'id': d.id, ...?d.data()})).toList();
    }

    return out;
  }

  /// Converte Timestamps e outros tipos não-JSON para formato serializável.
  static Map<String, dynamic> _sanitizeMap(Map<String, dynamic> data) {
    final result = <String, dynamic>{};
    for (final e in data.entries) {
      result[e.key] = _sanitizeValue(e.value);
    }
    return result;
  }

  static dynamic _sanitizeValue(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate().toUtc().toIso8601String();
    if (v is DateTime) return v.toUtc().toIso8601String();
    if (v is Map) return _sanitizeMap(Map<String, dynamic>.from(v));
    if (v is List) return v.map(_sanitizeValue).toList();
    return v;
  }

  /// Retorna o JSON do backup como string (para download/share).
  Future<String> exportUserDataAsJson(String uid) async {
    final data = await exportUserData(uid);
    return const JsonEncoder.withIndent('  ').convert(data);
  }
}
