import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/date_utils_cordex.dart';

/// Resultado da validação de um arquivo de backup.
class BackupPreview {
  final String exportedAt;
  final String? backupUid;
  final Map<String, int> collectionCounts;
  final bool isValid;

  const BackupPreview({
    required this.exportedAt,
    this.backupUid,
    required this.collectionCounts,
    required this.isValid,
  });
}

/// Serviço para restaurar dados a partir do arquivo JSON de backup.
class UserRestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Coleções que podem ser restauradas (mesma lista do backup).
  static const List<String> restorableCollections = [
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
  ];

  /// Valida o JSON e retorna prévia (data do backup, contagens). Retorna null se inválido.
  BackupPreview? previewFromJsonString(String jsonString) {
    try {
      final data = json.decode(jsonString) as Map<String, dynamic>?;
      if (data == null) return null;
      final exportedAt = data['exportedAt']?.toString() ?? '';
      final uid = data['uid']?.toString();
      final collections = data['collections'] as Map<String, dynamic>?;
      if (collections == null) return BackupPreview(exportedAt: exportedAt, collectionCounts: {}, isValid: false);

      final counts = <String, int>{};
      for (final col in restorableCollections) {
        final list = collections[col];
        if (list is List) counts[col] = list.length;
      }
      return BackupPreview(
        exportedAt: exportedAt,
        backupUid: uid,
        collectionCounts: counts,
        isValid: true,
      );
    } catch (_) {
      return null;
    }
  }

  /// Restaura os dados do backup no Firestore do usuário [uid].
  /// [jsonString] deve ser o conteúdo do arquivo de backup.
  /// Substitui/merge nas coleções conforme os documentos do backup.
  Future<void> restore(String uid, String jsonString) async {
    final data = json.decode(jsonString) as Map<String, dynamic>;
    final userRef = _db.collection('users').doc(uid);

    // Perfil (dados do doc do usuário) — merge para não apagar auth/plan se vier vazio
    final profile = data['profile'] as Map<String, dynamic>?;
    if (profile != null && profile.isNotEmpty) {
      final sanitized = _desanitizeMap(profile);
      await userRef.set(sanitized, SetOptions(merge: true));
    }

    final collections = data['collections'] as Map<String, dynamic>? ?? {};
    for (final colName in restorableCollections) {
      final list = collections[colName];
      if (list is! List || list.isEmpty) continue;

      final colRef = userRef.collection(colName);
      const batchSize = 500;
      for (var i = 0; i < list.length; i += batchSize) {
        final batch = _db.batch();
        final chunk = list.skip(i).take(batchSize).toList();
        for (final item in chunk) {
          if (item is! Map<String, dynamic>) continue;
          final id = item['id']?.toString();
          if (id == null || id.isEmpty) continue;
          final docData = Map<String, dynamic>.from(item)..remove('id');
          final docRef = colRef.doc(id);
          batch.set(docRef, _desanitizeMap(docData), SetOptions(merge: true));
        }
        await batch.commit();
      }
    }
  }

  /// Converte strings ISO de data de volta para Timestamp.
  static Map<String, dynamic> _desanitizeMap(Map<String, dynamic> data) {
    final result = <String, dynamic>{};
    for (final e in data.entries) {
      result[e.key] = _desanitizeValue(e.value);
    }
    return result;
  }

  static dynamic _desanitizeValue(dynamic v) {
    if (v == null) return null;
    if (v is Map) return _desanitizeMap(Map<String, dynamic>.from(v));
    if (v is List) return v.map(_desanitizeValue).toList();
    if (v is String && _looksLikeIso8601(v)) {
      try {
        final dt = DateUtilsCordex.parseDateSafe(v);
        return Timestamp.fromDate(dt);
      } catch (_) {}
    }
    return v;
  }

  static bool _looksLikeIso8601(String s) {
    if (s.length < 20) return false;
    return RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}').hasMatch(s);
  }
}
