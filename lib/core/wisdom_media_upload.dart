import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart' show UploadTask;

import 'wisdom_image_process.dart';
import 'wisdom_storage_upload.dart';

export 'wisdom_image_process.dart';
export 'wisdom_storage_upload.dart';

/// Resultado de upload no Storage (URL publica + caminho interno).
class WisdomUploadResult {
  const WisdomUploadResult({
    required this.downloadUrl,
    required this.storagePath,
  });

  final String downloadUrl;
  final String storagePath;
}

/// Pipeline unificado: comprimir -> Storage -> URL.
///
/// Padrao Controle Total / YAHWEH aplicado ao WisdomApp.
abstract final class WisdomMediaUpload {
  WisdomMediaUpload._();

  /// Prepara bytes (compressao) antes do upload.
  static Future<({Uint8List bytes, String mime})> _prepareBytes(
    Uint8List bytes,
    String contentType, {
    WisdomMediaProfile profile = WisdomMediaProfile.courseCover,
  }) async {
    final ct = contentType.toLowerCase();
    if (!ct.startsWith('image/')) {
      return (bytes: bytes, mime: contentType);
    }
    try {
      return await WisdomImageProcess.process(bytes, profile);
    } catch (_) {
      // Falha no decode/compressao - envia bytes originais.
      return (bytes: bytes, mime: ct.startsWith('image/') ? 'image/jpeg' : contentType);
    }
  }

  /// Upload generico - qualquer path `wisdomapp/...`.
  static Future<String> uploadBytes({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    WisdomMediaProfile profile = WisdomMediaProfile.courseCover,
    void Function(double progress)? onProgress,
  }) async {
    final prepared = await _prepareBytes(bytes, contentType, profile: profile);
    return WisdomStorageUpload.putData(
      storagePath: storagePath,
      bytes: prepared.bytes,
      mimeType: prepared.mime,
      onProgress: onProgress,
    );
  }

  /// Upload com resultado completo (URL + path).
  static Future<WisdomUploadResult> uploadBytesWithResult({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    WisdomMediaProfile profile = WisdomMediaProfile.courseCover,
    void Function(double progress)? onProgress,
  }) async {
    final url = await uploadBytes(
      storagePath: storagePath,
      bytes: bytes,
      contentType: contentType,
      profile: profile,
      onProgress: onProgress,
    );
    return WisdomUploadResult(downloadUrl: url, storagePath: storagePath);
  }

  /// Capa de curso - compressao + upload + metadados prontos.
  static Future<WisdomUploadResult> uploadCourseCover({
    required String courseId,
    required Uint8List bytes,
    required String mimeType,
    int index = 0,
    void Function(double progress)? onProgress,
  }) async {
    final prepared = await _prepareBytes(bytes, mimeType, profile: WisdomMediaProfile.courseCover);
    final ext = WisdomImageProcess.extensionFromMime(prepared.mime);
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = 'wisdomapp/course_videos/$courseId/photo_${index}_$ts.$ext';
    final url = await WisdomStorageUpload.putData(
      storagePath: path,
      bytes: prepared.bytes,
      mimeType: prepared.mime,
      onProgress: onProgress,
    );
    return WisdomUploadResult(downloadUrl: url, storagePath: path);
  }

  /// Thumbnail de curso.
  static Future<WisdomUploadResult> uploadCourseThumb({
    required String courseId,
    required Uint8List bytes,
    required String mimeType,
    int index = 0,
    void Function(double progress)? onProgress,
  }) async {
    final prepared = await _prepareBytes(bytes, mimeType, profile: WisdomMediaProfile.courseThumb);
    final ext = WisdomImageProcess.extensionFromMime(prepared.mime);
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = 'wisdomapp/course_videos/$courseId/thumb_${index}_$ts.$ext';
    final url = await WisdomStorageUpload.putData(
      storagePath: path,
      bytes: prepared.bytes,
      mimeType: prepared.mime,
      onProgress: onProgress,
    );
    return WisdomUploadResult(downloadUrl: url, storagePath: path);
  }

  /// Logo de provedor.
  static Future<WisdomUploadResult> uploadProviderLogo({
    required String userId,
    required Uint8List bytes,
    required String mimeType,
    void Function(double progress)? onProgress,
  }) async {
    final prepared = await _prepareBytes(bytes, mimeType, profile: WisdomMediaProfile.providerLogo);
    final ext = WisdomImageProcess.extensionFromMime(prepared.mime);
    final path = 'users/$userId/provider_logo.$ext';
    final url = await WisdomStorageUpload.putData(
      storagePath: path,
      bytes: prepared.bytes,
      mimeType: prepared.mime,
      onProgress: onProgress,
    );
    return WisdomUploadResult(downloadUrl: url, storagePath: path);
  }

  /// Anexo de ocorrencia.
  static Future<WisdomUploadResult> uploadOcorrencia({
    required String userId,
    required String ocorrenciaId,
    required Uint8List bytes,
    required String mimeType,
    void Function(double progress)? onProgress,
  }) async {
    final prepared = await _prepareBytes(bytes, mimeType, profile: WisdomMediaProfile.ocorrencia);
    final ext = WisdomImageProcess.extensionFromMime(prepared.mime);
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = 'users/$userId/ocorrencias/$ocorrenciaId/anexo_$ts.$ext';
    final url = await WisdomStorageUpload.putData(
      storagePath: path,
      bytes: prepared.bytes,
      mimeType: prepared.mime,
      onProgress: onProgress,
    );
    return WisdomUploadResult(downloadUrl: url, storagePath: path);
  }

  /// Oficio de audiencia (sem compressao - PDF).
  static Future<WisdomUploadResult> uploadOficio({
    required String userId,
    required String reminderId,
    required Uint8List bytes,
    required String mimeType,
    String extension = 'pdf',
    void Function(double progress)? onProgress,
  }) async {
    final path = 'users/$userId/audiencias/$reminderId/oficio.$extension';
    final url = await WisdomStorageUpload.putData(
      storagePath: path,
      bytes: bytes,
      mimeType: mimeType,
      onProgress: onProgress,
    );
    return WisdomUploadResult(downloadUrl: url, storagePath: path);
  }

  /// Comprovante financeiro (sem compressao - PDF/imagem).
  static Future<WisdomUploadResult> uploadReceipt({
    required String userId,
    required String transactionId,
    required Uint8List bytes,
    required String mimeType,
    String fileName = 'comprovante',
    void Function(double progress)? onProgress,
  }) async {
    final ext = WisdomImageProcess.extensionFromMime(mimeType);
    final path = 'users/$userId/transactions/$transactionId/$fileName.$ext';
    final url = await WisdomStorageUpload.putData(
      storagePath: path,
      bytes: bytes,
      mimeType: mimeType,
      onProgress: onProgress,
    );
    return WisdomUploadResult(downloadUrl: url, storagePath: path);
  }

  /// Resolve URL de display (fallback: path -> URL).
  static Future<String?> resolveDisplayUrl({
    String? httpsUrl,
    String? storagePath,
  }) async {
    final u = (httpsUrl ?? '').trim();
    if (u.startsWith('http')) return u;
    if (storagePath != null && storagePath.trim().isNotEmpty) {
      return WisdomStorageUpload.resolveUrl(storagePath);
    }
    return null;
  }
}
