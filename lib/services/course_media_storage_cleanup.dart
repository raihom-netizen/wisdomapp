import 'package:firebase_storage/firebase_storage.dart';

import '../utils/course_media_url_resolver.dart';

/// Remove arquivos no Storage ao excluir ou substituir mídia de curso/dica.
class CourseMediaStorageCleanup {
  CourseMediaStorageCleanup._();

  static Future<void> deleteForCourseDoc(
    String docId, {
    Map<String, dynamic>? data,
  }) async {
    if (docId.trim().isEmpty) return;

    final paths = <String>{};
    if (data != null) {
      paths.addAll(collectAllStoragePaths(data));
    }

    try {
      final dir = FirebaseStorage.instance.ref('wisdomapp/course_videos/$docId');
      await _deleteRefRecursive(dir, paths);
    } catch (_) {}

    for (final path in paths) {
      try {
        await FirebaseStorage.instance.ref(path).delete();
      } catch (_) {}
    }
  }

  /// Remove só vídeos ou imagens antes de atualizar o documento.
  static Future<void> deleteMediaFromDoc(
    Map<String, dynamic> data, {
    bool videos = false,
    bool images = false,
  }) async {
    final paths = <String>{};
    if (videos) {
      for (final e in CourseMediaUrlResolver.collectVideoEntries(data)) {
        final p = e.storagePath?.trim();
        if (p != null && p.isNotEmpty) paths.add(p);
      }
      final mp4Path = (data['mp4StoragePath'] ?? '').toString().trim();
      if (mp4Path.isNotEmpty) paths.add(mp4Path);
    }
    if (images) {
      paths.addAll(CourseMediaUrlResolver.collectStoragePaths(data));
      for (final e in CourseMediaUrlResolver.collectVideoEntries(data)) {
        paths.remove(e.storagePath ?? '');
      }
    }
    for (final path in paths) {
      if (path.isEmpty) continue;
      try {
        await FirebaseStorage.instance.ref(path).delete();
      } catch (_) {}
    }
  }

  static Set<String> collectAllStoragePaths(Map<String, dynamic> data) {
    final paths = <String>{...CourseMediaUrlResolver.collectStoragePaths(data)};
    for (final e in CourseMediaUrlResolver.collectVideoEntries(data)) {
      final p = e.storagePath?.trim();
      if (p != null && p.isNotEmpty) paths.add(p);
    }
    final mp4Path = (data['mp4StoragePath'] ?? '').toString().trim();
    if (mp4Path.isNotEmpty) paths.add(mp4Path);
    return paths;
  }

  static Future<void> _deleteRefRecursive(Reference ref, Set<String> paths) async {
    try {
      final list = await ref.listAll();
      for (final item in list.items) {
        paths.add(item.fullPath);
        try {
          await item.delete();
        } catch (_) {}
      }
      for (final prefix in list.prefixes) {
        await _deleteRefRecursive(prefix, paths);
      }
    } catch (_) {}
  }
}
