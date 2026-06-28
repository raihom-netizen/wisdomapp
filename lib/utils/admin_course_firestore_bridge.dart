import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/functions_service.dart';

/// Serializa payloads Firestore para Cloud Functions (Admin SDK).
class AdminCourseFirestoreBridge {
  AdminCourseFirestoreBridge._();

  static const cfDelete = '__DELETE__';

  static Map<String, dynamic> encodeMap(Map<String, dynamic> raw) {
    final out = <String, dynamic>{};
    for (final e in raw.entries) {
      final encoded = encodeValue(e.value);
      if (encoded == _skip) continue;
      out[e.key] = encoded;
    }
    return out;
  }

  static const Object _skip = Object();

  static dynamic encodeValue(dynamic value) {
    if (identical(value, FieldValue.serverTimestamp())) return _skip;
    if (identical(value, FieldValue.delete())) return cfDelete;
    if (value is Timestamp) return {'_tsMs': value.millisecondsSinceEpoch};
    if (value is Map) {
      return encodeMap(Map<String, dynamic>.from(value));
    }
    if (value is List) {
      return value.map(encodeValue).where((v) => v != _skip).toList();
    }
    return value;
  }

  static Future<String> upsertCourseVideo({
    required String docId,
    required Map<String, dynamic> data,
    bool create = false,
    bool merge = true,
  }) async {
    final res = await FunctionsService().adminUpsertCourseVideo(
      docId: docId,
      data: encodeMap(data),
      create: create,
      merge: merge,
    );
    return (res['docId'] ?? docId).toString();
  }

  static Future<void> deleteCourseVideos(List<String> docIds) async {
    if (docIds.isEmpty) return;
    await FunctionsService().adminDeleteCourseVideos(docIds: docIds);
  }

  static Future<void> saveWisdomCoursesModuleConfig(Map<String, dynamic> data) async {
    await FunctionsService().adminSaveWisdomCoursesModuleConfig(
      data: encodeMap(data),
    );
  }
}
