import 'course_media_url_resolver.dart';
import 'youtube_url_helper.dart';

/// Resolve a melhor URL de capa/thumbnail para cursos e dicas.
class CourseThumbResolver {
  CourseThumbResolver._();

  static String? videoIdFromData(Map<String, dynamic> data) {
    final stored = (data['youtubeVideoId'] ?? '').toString().trim();
    if (stored.isNotEmpty) return stored;
    final link = (data['linkUrl'] ??
            data['externalUrl'] ??
            data['youtubeUrl'] ??
            data['videoUrl'] ??
            '')
        .toString();
    return YoutubeUrlHelper.extractVideoId(link);
  }

  /// URL principal (imagem enviada ou thumbnail gravada).
  static String? primaryImageUrl(Map<String, dynamic> data) {
    final fromList = CourseMediaUrlResolver.collectHttpUrls(data);
    if (fromList.isNotEmpty) return fromList.first;
    for (final key in ['imageUrl', 'coverUrl', 'thumbnailUrl', 'posterUrl']) {
      final v = (data[key] ?? '').toString().trim();
      if (v.isNotEmpty && _looksLikeHttpUrl(v)) return v;
    }
    return null;
  }

  static bool _looksLikeHttpUrl(String raw) {
    final u = raw.toLowerCase();
    return u.startsWith('http://') || u.startsWith('https://');
  }

  /// Lista de URLs para tentar carregar (YouTube: maxres → hq; imagem: uma URL).
  static List<String> resolveUrls(Map<String, dynamic> data) {
    final primary = primaryImageUrl(data);
    if (primary != null) return [primary];

    final id = videoIdFromData(data);
    if (id != null) return YoutubeUrlHelper.thumbnailUrls(id);

    return const [];
  }

  static String? resolveBest(Map<String, dynamic> data) {
    final urls = resolveUrls(data);
    return urls.isEmpty ? null : urls.first;
  }

  static bool hasVisualThumb(Map<String, dynamic> data) =>
      CourseMediaUrlResolver.hasResolvableImage(data);

  static bool isDicaPhoto(Map<String, dynamic> data) {
    if ((data['type'] ?? 'curso').toString() != 'dica') return false;
    return CourseMediaUrlResolver.hasResolvableImage(data);
  }

  static bool isVideoContent(Map<String, dynamic> data) {
    if (CourseMediaUrlResolver.collectVideoEntries(data).isNotEmpty) return true;
    final mp4 = (data['mp4Url'] ?? '').toString().trim();
    if (mp4.isNotEmpty) return true;
    return videoIdFromData(data) != null;
  }
}
