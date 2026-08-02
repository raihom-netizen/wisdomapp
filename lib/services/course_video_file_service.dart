import 'dart:io';
import 'dart:typed_data';

import '../core/wisdom_storage_upload.dart';
import '../utils/course_media_url_resolver.dart';

/// Upload de video MP4/WebM para o modulo Cursos (admin).
///
/// Usa [WisdomStorageUpload] com retry + URL timeout (padrao Controle Total).
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

  static String _mimeFromExt(String ext) {
    switch (ext) {
      case 'webm':
        return 'video/webm';
      case 'mov':
        return 'video/quicktime';
      default:
        return 'video/mp4';
    }
  }

  /// Upload via arquivo em disco (ideal para gravacao de camera e videos grandes).
  static Future<CourseMediaUploadResult> uploadVideoFile({
    required File file,
    String? docId,
    int index = 0,
    void Function(double progress)? onProgress,
  }) async {
    final size = await file.length();
    if (size == 0) throw StateError('Video vazio.');
    if (size > maxBytes) {
      throw StateError('Video acima de 250 MB. Comprima ou use link YouTube.');
    }

    final ext = _extFromPath(file.path);
    final mime = _mimeFromExt(ext);
    final id = docId ?? DateTime.now().millisecondsSinceEpoch.toString();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = 'wisdomapp/course_videos/$id/video_${index}_$ts.$ext';

    final url = await WisdomStorageUpload.putData(
      storagePath: path,
      bytes: await file.readAsBytes(),
      mimeType: mime,
      onProgress: onProgress,
    );
    return CourseMediaUploadResult(
      downloadUrl: url,
      storagePath: path,
    );
  }

  /// Upload via bytes (FilePicker tradicional).
  static Future<CourseMediaUploadResult> uploadVideo({
    required Uint8List bytes,
    required String mimeType,
    String? docId,
    int index = 0,
    void Function(double progress)? onProgress,
  }) async {
    if (bytes.isEmpty) throw StateError('Video vazio.');
    if (bytes.lengthInBytes > maxBytes) {
      throw StateError('Video acima de 250 MB. Comprima ou use link YouTube.');
    }

    final ext = _extFromMime(mimeType);
    final id = docId ?? DateTime.now().millisecondsSinceEpoch.toString();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = 'wisdomapp/course_videos/$id/video_${index}_$ts.$ext';

    final url = await WisdomStorageUpload.putData(
      storagePath: path,
      bytes: bytes,
      mimeType: mimeType,
      onProgress: onProgress,
    );
    return CourseMediaUploadResult(
      downloadUrl: url,
      storagePath: path,
    );
  }

  static String _extFromPath(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.webm')) return 'webm';
    if (p.endsWith('.mov')) return 'mov';
    if (p.endsWith('.mp4')) return 'mp4';
    return 'mp4';
  }
}
