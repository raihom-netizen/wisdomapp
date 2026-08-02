import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Perfis de compressao de imagem - padrao Controle Total / YAHWEH.
enum WisdomMediaProfile {
  /// Capa de curso (1920px max, JPEG q88).
  courseCover,

  /// Thumbnail de curso (640px, JPEG q75).
  courseThumb,

  /// Logo de provedor (512px, PNG).
  providerLogo,

  /// Anexo de ocorrencia (1280px, JPEG q80).
  ocorrencia,

  /// Comprovante financeiro (sem compressao - PDF/imagen).
  receipt,

  /// Oficio de audiencia (sem compressao - PDF).
  oficio,
}

/// Compressao/crop **antes** do upload - padrao Controle Total.
///
/// Decode/resize/encode rodam com fallback: se o decode falhar, retorna bytes
/// originais (o Storage rejeita se invalido).
abstract final class WisdomImageProcess {
  WisdomImageProcess._();

  static const int courseCoverMaxEdge = 1920;
  static const int courseThumbMaxEdge = 640;
  static const int providerLogoMaxEdge = 512;
  static const int ocorrenciaMaxEdge = 1280;

  static const int courseCoverQuality = 88;
  static const int courseThumbQuality = 75;
  static const int ocorrenciaQuality = 80;

  static Future<({Uint8List bytes, String mime})> process(
    Uint8List inputBytes,
    WisdomMediaProfile profile,
  ) async {
    return switch (profile) {
      WisdomMediaProfile.courseCover => await _processCourseCover(inputBytes),
      WisdomMediaProfile.courseThumb => await _processCourseThumb(inputBytes),
      WisdomMediaProfile.providerLogo => await _processProviderLogo(inputBytes),
      WisdomMediaProfile.ocorrencia => await _processOcorrencia(inputBytes),
      WisdomMediaProfile.receipt || WisdomMediaProfile.oficio =>
        (bytes: inputBytes, mime: 'application/octet-stream'),
    };
  }

  static Future<({Uint8List bytes, String mime})> _processCourseCover(
    Uint8List inputBytes,
  ) async {
    try {
      final decoded = img.decodeImage(inputBytes);
      if (decoded == null) return (bytes: inputBytes, mime: 'image/jpeg');

      final resized = _resizeKeepAspect(decoded, courseCoverMaxEdge);
      final encoded = Uint8List.fromList(
        img.encodeJpg(resized, quality: courseCoverQuality),
      );
      return (bytes: encoded, mime: 'image/jpeg');
    } catch (_) {
      return (bytes: inputBytes, mime: 'image/jpeg');
    }
  }

  static Future<({Uint8List bytes, String mime})> _processCourseThumb(
    Uint8List inputBytes,
  ) async {
    try {
      final decoded = img.decodeImage(inputBytes);
      if (decoded == null) return (bytes: inputBytes, mime: 'image/jpeg');

      final resized = _resizeKeepAspect(decoded, courseThumbMaxEdge);
      final encoded = Uint8List.fromList(
        img.encodeJpg(resized, quality: courseThumbQuality),
      );
      return (bytes: encoded, mime: 'image/jpeg');
    } catch (_) {
      return (bytes: inputBytes, mime: 'image/jpeg');
    }
  }

  static Future<({Uint8List bytes, String mime})> _processProviderLogo(
    Uint8List inputBytes,
  ) async {
    try {
      final decoded = img.decodeImage(inputBytes);
      if (decoded == null) return (bytes: inputBytes, mime: 'image/png');

      final resized = _resizeKeepAspect(decoded, providerLogoMaxEdge);
      final encoded = Uint8List.fromList(img.encodePng(resized));
      return (bytes: encoded, mime: 'image/png');
    } catch (_) {
      return (bytes: inputBytes, mime: 'image/png');
    }
  }

  static Future<({Uint8List bytes, String mime})> _processOcorrencia(
    Uint8List inputBytes,
  ) async {
    try {
      final decoded = img.decodeImage(inputBytes);
      if (decoded == null) return (bytes: inputBytes, mime: 'image/jpeg');

      final resized = _resizeKeepAspect(decoded, ocorrenciaMaxEdge);
      final encoded = Uint8List.fromList(
        img.encodeJpg(resized, quality: ocorrenciaQuality),
      );
      return (bytes: encoded, mime: 'image/jpeg');
    } catch (_) {
      return (bytes: inputBytes, mime: 'image/jpeg');
    }
  }

  static img.Image _resizeKeepAspect(img.Image source, int maxSide) {
    final w = source.width;
    final h = source.height;
    final m = w > h ? w : h;
    if (m <= maxSide) return source;
    final scale = maxSide / m;
    return img.copyResize(
      source,
      width: (w * scale).round(),
      height: (h * scale).round(),
      interpolation: img.Interpolation.linear,
    );
  }

  static String extensionFromMime(String mimeType) {
    final m = mimeType.toLowerCase();
    if (m.contains('webp')) return 'webp';
    if (m.contains('png')) return 'png';
    if (m.contains('jpeg') || m.contains('jpg')) return 'jpg';
    if (m.contains('pdf')) return 'pdf';
    if (m.contains('mp4')) return 'mp4';
    return 'bin';
  }
}
