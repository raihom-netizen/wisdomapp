import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

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
/// No celular usa `putFile` (lê do disco em partes, retomável); na web,
/// `putData`. Sem token: até 3 tentativas em erro de rede. Com
/// [CourseUploadCancelToken], uma tentativa (cancelável). O link de download
/// é buscado com novas tentativas e, se não vier, o envio FALHA com erro
/// visível — nunca devolve URL vazia.
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

  static SettableMetadata _metadata(String mime) => SettableMetadata(
        contentType: mime,
        cacheControl: 'public, max-age=31536000, immutable',
      );

  /// Envia com [startTask] (putFile no celular, putData na web/bytes).
  ///
  /// - Sem [cancelToken]: até 3 tentativas em erro de rede (backoff).
  /// - Com [cancelToken]: uma tentativa, cancelável pelo admin.
  /// Ao final SEMPRE devolve uma URL válida — nunca string vazia (ver
  /// [_downloadUrlWithRetry]); a aula não pode ser gravada sem link.
  static Future<String> _put({
    required String path,
    required UploadTask Function(Reference ref, SettableMetadata md) startTask,
    required String mime,
    void Function(double progress)? onProgress,
    CourseUploadCancelToken? cancelToken,
  }) async {
    final ref = FirebaseStorage.instance.ref(path);
    final maxAttempts = cancelToken == null ? 3 : 1;
    Object? lastError;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (cancelToken?.isCancelled == true) {
        throw const CourseUploadCancelledException();
      }
      if (attempt > 0) {
        await Future<void>.delayed(Duration(seconds: 2 * attempt));
      }
      final task = startTask(ref, _metadata(mime));
      cancelToken?._attach(task);
      try {
        await task.snapshotEvents.fold<void>(null, (_, s) {
          if (s.totalBytes > 0) {
            onProgress?.call(s.bytesTransferred / s.totalBytes);
          }
        });
        lastError = null;
        break;
      } catch (e) {
        if (cancelToken?.isCancelled == true ||
            (e is FirebaseException && e.code == 'canceled')) {
          throw const CourseUploadCancelledException();
        }
        lastError = e;
        if (!WisdomStorageUpload.isRetryableError(e)) rethrow;
      }
    }
    if (lastError != null) throw lastError;
    if (cancelToken?.isCancelled == true) {
      try {
        await ref.delete();
      } catch (_) {}
      throw const CourseUploadCancelledException();
    }
    return _downloadUrlWithRetry(ref);
  }

  /// Link de download com novas tentativas (1 s, 2 s, 4 s, 8 s).
  /// Falha com erro visível em vez de devolver '' (aula com URL vazia não toca).
  static Future<String> _downloadUrlWithRetry(Reference ref) async {
    Object? lastError;
    for (var attempt = 0; attempt < 5; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(seconds: 1 << (attempt - 1)));
      }
      try {
        final url =
            await ref.getDownloadURL().timeout(const Duration(seconds: 10));
        if (url.trim().isNotEmpty) return url;
      } catch (e) {
        lastError = e;
      }
    }
    throw StateError(
      'O vídeo foi enviado, mas não foi possível obter o link dele '
      '(${ref.fullPath}). Verifique a conexão e tente salvar de novo.'
      '${lastError == null ? '' : ' Detalhe: $lastError'}',
    );
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

    // Celular: putFile lê do disco em partes (retomável, sem carregar até
    // 250 MB na memória). Na web não existe File de disco → bytes.
    final Uint8List? webBytes = kIsWeb ? await file.readAsBytes() : null;
    final url = await _put(
      path: path,
      startTask: (ref, md) =>
          webBytes != null ? ref.putData(webBytes, md) : ref.putFile(file, md),
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
      startTask: (ref, md) => ref.putData(bytes, md),
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
