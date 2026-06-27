import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import '../utils/course_media_url_resolver.dart';

/// Upload de vídeo MP4/WebM para o módulo Cursos (admin).
class CourseVideoFileService {
  CourseVideoFileService._();

  /// Limite por arquivo (250 MB).
  static const maxBytes = 250 * 1024 * 1024;

  static String _extFromMime(String mime) {
    final m = mime.toLowerCase();
    if (m.contains('webm')) return 'webm';
    if (m.contains('quicktime') || m.contains('mov')) return 'mov';
    return 'mp4';
  }

  static Future<CourseMediaUploadResult> uploadVideo({
    required Uint8List bytes,
    required String mimeType,
    String? docId,
    int index = 0,
    void Function(double progress)? onProgress,
  }) async {
    if (bytes.isEmpty) throw StateError('Vídeo vazio.');
    if (bytes.lengthInBytes > maxBytes) {
      throw StateError('Vídeo acima de 250 MB. Comprima ou use link YouTube.');
    }

    final ext = _extFromMime(mimeType);
    final id = docId ?? DateTime.now().millisecondsSinceEpoch.toString();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = 'wisdomapp/course_videos/$id/video_${index}_$ts.$ext';
    final ref = FirebaseStorage.instance.ref(path);
    final task = ref.putData(bytes, SettableMetadata(contentType: mimeType));

    if (onProgress != null) {
      await for (final snap in task.snapshotEvents) {
        final total = snap.totalBytes;
        if (total > 0) {
          onProgress(snap.bytesTransferred / total);
        }
      }
    }

    await task;
    return CourseMediaUploadResult(
      downloadUrl: await ref.getDownloadURL(),
      storagePath: path,
    );
  }
}
