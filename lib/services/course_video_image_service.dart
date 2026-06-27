import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:image/image.dart' as img;

import '../utils/course_media_url_resolver.dart';

/// Upload de capa/imagem para dicas do módulo Cursos.
class CourseVideoImageService {
  CourseVideoImageService._();

  /// Até ~12 MB na entrada — após otimização costuma ficar bem menor (Full HD JPEG).
  static const maxBytes = 12 * 1024 * 1024;
  static const maxSidePx = 1920;
  static const jpegQuality = 88;

  /// Redimensiona mantendo qualidade (1080p máx.) para carregar rápido no app e painel.
  static Uint8List optimizeForUpload(Uint8List bytes, String mimeType) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return bytes;

      img.Image out = decoded;
      if (decoded.width > maxSidePx || decoded.height > maxSidePx) {
        out = img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? maxSidePx : null,
          height: decoded.height > decoded.width ? maxSidePx : null,
          interpolation: img.Interpolation.average,
        );
      }

      if (mimeType.contains('png') && bytes.lengthInBytes < 800 * 1024) {
        return Uint8List.fromList(img.encodePng(out, level: 6));
      }
      return Uint8List.fromList(img.encodeJpg(out, quality: jpegQuality));
    } catch (_) {
      return bytes;
    }
  }

  static String _contentTypeForUpload(String mimeType, Uint8List optimized) {
    if (mimeType.contains('png') &&
        optimized.lengthInBytes < 800 * 1024 &&
        !mimeType.contains('jpeg')) {
      return 'image/png';
    }
    return 'image/jpeg';
  }

  static String _extForContentType(String contentType) {
    if (contentType.contains('png')) return 'png';
    if (contentType.contains('webp')) return 'webp';
    return 'jpg';
  }

  static Future<CourseMediaUploadResult> uploadCover({
    required Uint8List bytes,
    required String mimeType,
    String? docId,
    int index = 0,
  }) async {
    if (bytes.isEmpty) throw StateError('Imagem vazia.');
    if (bytes.lengthInBytes > maxBytes) throw StateError('Imagem acima de 12 MB.');

    final optimized = optimizeForUpload(bytes, mimeType);
    final contentType = _contentTypeForUpload(mimeType, optimized);
    final ext = _extForContentType(contentType);

    final id = docId ?? DateTime.now().millisecondsSinceEpoch.toString();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = 'wisdomapp/course_videos/$id/photo_${index}_$ts.$ext';
    final ref = FirebaseStorage.instance.ref(path);
    await ref.putData(
      optimized,
      SettableMetadata(
        contentType: contentType,
        cacheControl: 'public, max-age=31536000, immutable',
      ),
    );
    return CourseMediaUploadResult(
      downloadUrl: await ref.getDownloadURL(),
      storagePath: path,
    );
  }
}
