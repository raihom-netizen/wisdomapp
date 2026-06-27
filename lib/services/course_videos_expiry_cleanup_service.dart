import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../utils/course_media_url_resolver.dart';
import '../utils/course_video_validity.dart';

/// Remove cursos/dicas expirados (`course_videos`) e arquivos no Storage.
class CourseVideosExpiryCleanupService {
  CourseVideosExpiryCleanupService._();

  static bool _running = false;

  static Future<int> purgeExpired() async {
    if (_running) return 0;
    _running = true;
    try {
      final snap =
          await FirebaseFirestore.instance.collection('course_videos').get();
      var removed = 0;
      for (final doc in snap.docs) {
        if (!CourseVideoValidity.shouldDeleteExpired(doc.data())) continue;
        await _deleteDocAndMedia(doc.reference, doc.data());
        removed++;
      }
      return removed;
    } catch (e, st) {
      debugPrint('CourseVideosExpiryCleanupService: $e\n$st');
      return 0;
    } finally {
      _running = false;
    }
  }

  static Future<void> _deleteDocAndMedia(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data,
  ) async {
    final paths = <String>{
      ...CourseMediaUrlResolver.collectStoragePaths(data),
      ...CourseMediaUrlResolver.collectVideoEntries(data)
          .map((e) => e.storagePath)
          .whereType<String>()
          .where((p) => p.trim().isNotEmpty),
    };
    for (final path in paths) {
      try {
        await FirebaseStorage.instance.ref(path).delete();
      } catch (_) {}
    }
    await ref.delete();
  }
}
