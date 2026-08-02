import 'dart:typed_data';

import '../core/wisdom_media_upload.dart';
import '../utils/course_media_url_resolver.dart';

/// Upload de capa/imagem para dicas do modulo Cursos.
///
/// Usa o pipeline centralizado [WisdomMediaUpload] (padrao Controle Total).
class CourseVideoImageService {
  CourseVideoImageService._();

  /// Ate ~12 MB na entrada - apos otimizacao costuma ficar bem menor (Full HD JPEG).
  static const maxBytes = 12 * 1024 * 1024;

  /// Redimensiona mantendo qualidade (1080p max.) para carregar rapido no app e painel.
  ///
  /// Delega para [WisdomImageProcess] (perfil courseCover).
  static Future<Uint8List> optimizeForUpload(Uint8List bytes, String mimeType) async {
    final result = await WisdomImageProcess.process(bytes, WisdomMediaProfile.courseCover);
    return result.bytes;
  }

  static Future<CourseMediaUploadResult> uploadCover({
    required Uint8List bytes,
    required String mimeType,
    String? docId,
    int index = 0,
  }) async {
    if (bytes.isEmpty) throw StateError('Imagem vazia.');
    if (bytes.lengthInBytes > maxBytes) throw StateError('Imagem acima de 12 MB.');

    final id = docId ?? DateTime.now().millisecondsSinceEpoch.toString();
    final result = await WisdomMediaUpload.uploadCourseCover(
      courseId: id,
      bytes: bytes,
      mimeType: mimeType,
      index: index,
    );
    return CourseMediaUploadResult(
      downloadUrl: result.downloadUrl,
      storagePath: result.storagePath,
    );
  }
}
