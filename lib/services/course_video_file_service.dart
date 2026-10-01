import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import '../core/wisdom_storage_upload.dart';
import '../utils/course_media_url_resolver.dart';

/// Permite cancelar o envio em andamento (botão «Cancelar» do admin).
class CourseUploadCancelToken {
  UploadTask? _task;
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void _attach(UploadTask task) {
    _task = task;
    if (_cancelled) task.cancel();
  }

  Future<void> cancel() async {
    _cancelled = true;
    try {
      await _task?.cancel();
    } catch (_) {}
  }
}

/// Envio cancelado pelo admin.
class CourseUploadCancelledException implements Exception {
  const CourseUploadCancelledException();
  @override
  String toString() => 'Envio cancelado.';
}

/// Upload de video MP4/WebM para o modulo Cursos (admin).
///
/// Usa [WisdomStorageUpload] com retry + URL timeout (padrao Controle Total).
/// Com [CourseUploadCancelToken], envia direto (uma tentativa) para poder cancelar.
class CourseVideoFileService {
  CourseVideoFileService._();

  /// Limite por arquivo (250 MB).
  static const maxBytes = 250 * 1024 * 1024;

  /// Formatos aceitos no cadastro.
  static const allowedExtensions = ['mp4', 'mov', 'webm'];

  /// Valida antes de enviar; `null` = ok, senão a mensagem em português.
  static String? validate({required String name, required int sizeBytes}) {
    final lower = name.toLowerCase();
    final ext = lower.contains('.') ? lower.split('.').last : '';
    if (ext.isNotEmpty && !allowedExtensions.contains(ext)) {
      return '$name: formato .$ext não aceito (use MP4, MOV ou WebM).';
    }
    if (sizeBytes <= 0) return '$name: arquivo vazio.';
    if (sizeBytes > maxBytes) {
      return '$name: ${(sizeBytes / (1024 * 1024)).toStringAsFixed(0)} MB — '
          'acima de 250 MB. Comprima ou use link do YouTube.';
    }
    return null;
  }

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

  static Future<String> _put({
    required String path,
    required Uint8List bytes,
    required String mime,
    void Function(double progress)? onProgress,
    CourseUploadCancelToken? cancelToken,
  }) async {
    if (cancelToken == null) {
      return WisdomStorageUpload.putData(
        storagePath: path,
        bytes: bytes,
        mimeType: mime,
        onProgress: onProgress,
      );
    }
    if (cancelToken.isCancelled) throw const CourseUploadCancelledException();
    final ref = FirebaseStorage.instance.ref(path);
    final task = ref.putData(
      bytes,
      SettableMetadata(
        contentType: mime,
        cacheControl: 'public, max-age=31536000, immutable',
      ),
    );
    cancelToken._attach(task);
    try {
      await task.snapshotEvents.fold<void>(null, (_, s) {
        if (s.totalBytes > 0) onProgress?.call(s.bytesTransferred / s.totalBytes);
      });
    } catch (e) {
      if (cancelToken.isCancelled ||
          (e is FirebaseException && e.code == 'canceled')) {
        throw const CourseUploadCancelledException();
      }
      rethrow;
    }
    if (cancelToken.isCancelled) {
      try {
        await ref.delete();
      } catch (_) {}
      throw const CourseUploadCancelledException();
    }
    try {
      return await ref
          .getDownloadURL()
          .timeout(const Duration(seconds: 5), onTimeout: () => '');
    } catch (_) {
      return '';
    }
  }

  /// Upload via arquivo em disco (ideal para gravacao de camera e videos grandes).
  static Future<CourseMediaUploadResult> uploadVideoFile({
    required File file,
    String? docId,
    int index = 0,
    void Function(double progress)? onProgress,
    CourseUploadCancelToken? cancelToken,
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

    final url = await _put(
      path: path,
      bytes: await file.readAsBytes(),
      mime: mime,
      onProgress: onProgress,
      cancelToken: cancelToken,
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
    CourseUploadCancelToken? cancelToken,
  }) async {
    if (bytes.isEmpty) throw StateError('Video vazio.');
    if (bytes.lengthInBytes > maxBytes) {
      throw StateError('Video acima de 250 MB. Comprima ou use link YouTube.');
    }

    final ext = _extFromMime(mimeType);
    final id = docId ?? DateTime.now().millisecondsSinceEpoch.toString();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = 'wisdomapp/course_videos/$id/video_${index}_$ts.$ext';

    final url = await _put(
      path: path,
      bytes: bytes,
      mime: mimeType,
      onProgress: onProgress,
      cancelToken: cancelToken,
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
