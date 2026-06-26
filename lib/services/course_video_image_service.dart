import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

/// Upload de capa/imagem para dicas do módulo Cursos.
class CourseVideoImageService {
  CourseVideoImageService._();

  /// Até ~12 MB — capas Full HD (1080p) para dicas e cursos.
  static const maxBytes = 12 * 1024 * 1024;

  static Future<String> uploadCover({
    required Uint8List bytes,
    required String mimeType,
    String? docId,
  }) async {
    if (bytes.isEmpty) throw StateError('Imagem vazia.');
    if (bytes.lengthInBytes > maxBytes) throw StateError('Imagem acima de 12 MB.');
    final ext = mimeType.contains('png') ? 'png' : 'jpg';
    final id = docId ?? DateTime.now().millisecondsSinceEpoch.toString();
    final path = 'wisdomapp/course_videos/$id/cover_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final ref = FirebaseStorage.instance.ref(path);
    await ref.putData(
      bytes,
      SettableMetadata(
        contentType: mimeType,
        cacheControl: 'public, max-age=31536000',
      ),
    );
    return ref.getDownloadURL();
  }
}
