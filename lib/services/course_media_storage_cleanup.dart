import 'package:firebase_storage/firebase_storage.dart';

import '../utils/course_media_url_resolver.dart';

/// Remove arquivos no Storage ao excluir curso/dica.
class CourseMediaStorageCleanup {
  CourseMediaStorageCleanup._();

  static Future<void> deleteForCourseDoc(
    String docId, {
    Map<String, dynamic>? data,
  }) async {
    if (docId.trim().isEmpty) return;

    final paths = <String>{};
    if (data != null) {
      paths.addAll(CourseMediaUrlResolver.collectStoragePaths(data));
      for (final e in CourseMediaUrlResolver.collectVideoEntries(data)) {
        final p = e.storagePath?.trim();
        if (p != null && p.isNotEmpty) paths.add(p);
      }
    }

    try {
      final dir = FirebaseStorage.instance.ref('wisdomapp/course_videos/$docId');
      final list = await dir.listAll();
      for (final item in list.items) {
        paths.add(item.fullPath);
      }
    } catch (_) {}

    for (final path in paths) {
      try {
        await FirebaseStorage.instance.ref(path).delete();
      } catch (_) {}
    }
  }
}
