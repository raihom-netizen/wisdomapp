import 'dart:io' as java_io;
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

/// Upload Storage com retry + URL timeout - padrao Controle Total / YAHWEH.
///
/// Caracteristicas:
/// - Retry com backoff exponencial (3 tentativas)
/// - URL timeout 5s (fallback: devolve path vazio, UI resolve depois)
/// - Cache-Control immutable (1 ano)
abstract final class WisdomStorageUpload {
  WisdomStorageUpload._();

  static const int _maxAttempts = 3;
  static const String _cacheControl = 'public, max-age=31536000, immutable';

  /// Upload generico com retry + URL timeout.
  ///
  /// Retorna URL de download (ou string vazia se timeout - UI resolve depois).
  static Future<String> putData({
    required String storagePath,
    required Uint8List bytes,
    required String mimeType,
    void Function(double progress)? onProgress,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      try {
        if (attempt > 0) {
          await Future<void>.delayed(Duration(seconds: attempt));
        }
        final ref = FirebaseStorage.instance.ref(storagePath);
        final task = ref.putData(
          bytes,
          SettableMetadata(
            contentType: mimeType,
            cacheControl: _cacheControl,
          ),
        );

        // Aguarda upload completo com progresso.
        await task.snapshotEvents.fold<void>(
          null,
          (previous, snapshot) {
            if (snapshot.totalBytes > 0) {
              onProgress?.call(
                snapshot.bytesTransferred / snapshot.totalBytes,
              );
            }
          },
        );

        // URL best-effort (5s). Se falhar, devolve path; UI resolve depois.
        try {
          final url = await ref.getDownloadURL().timeout(
            const Duration(seconds: 5),
            onTimeout: () => '',
          );
          return url;
        } catch (_) {
          return '';
        }
      } catch (e) {
        lastError = e;
        final raw = e.toString().toLowerCase();
        final canceled =
            (e is FirebaseException && e.code == 'canceled') ||
            raw.contains('cancelado');
        if (canceled || !isRetryableError(e)) {
          rethrow;
        }
      }
    }
    throw lastError ?? StateError('storage_upload_failed:$storagePath');
  }

  /// Upload de arquivo local (Android/iOS).
  static Future<String> putFile({
    required String storagePath,
    required String filePath,
    required String mimeType,
    void Function(double progress)? onProgress,
  }) async {
    final file = await java_io.File(filePath).readAsBytes();
    return putData(
      storagePath: storagePath,
      bytes: file,
      mimeType: mimeType,
      onProgress: onProgress,
    );
  }

  /// Verifica se erro e retryavel (rede, timeout, servidor).
  static bool isRetryableError(Object error) {
    if (error is FirebaseException) {
      final code = error.code.toLowerCase();
      return code == 'network' ||
          code == 'timeout' ||
          code == 'aborted' ||
          code == 'unavailable' ||
          code == 'deadline-exceeded' ||
          code.contains('network') ||
          code.contains('timeout');
    }
    final raw = error.toString().toLowerCase();
    return raw.contains('network') ||
        raw.contains('timeout') ||
        raw.contains('unavailable') ||
        raw.contains('connection');
  }

  /// Resolve URL de download a partir de path Storage (com timeout).
  static Future<String?> resolveUrl(String storagePath) async {
    if (storagePath.isEmpty) return null;
    try {
      final ref = FirebaseStorage.instance.ref(storagePath);
      return await ref
          .getDownloadURL()
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      return null;
    }
  }
}
