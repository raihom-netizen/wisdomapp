import 'youtube_url_helper.dart';

/// Valida links de conteúdo (YouTube ou site) para Cursos/Dicas.
class CourseContentLinkHelper {
  CourseContentLinkHelper._();

  static bool isValidHttpUrl(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return false;
    try {
      final u = Uri.parse(t.startsWith('http') ? t : 'https://$t');
      return (u.scheme == 'http' || u.scheme == 'https') && u.host.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static String? normalizeLink(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    if (YoutubeUrlHelper.isValidYoutubeUrl(t)) {
      return YoutubeUrlHelper.normalizeYoutubeUrl(t);
    }
    if (isValidHttpUrl(t)) {
      return t.startsWith('http') ? t : 'https://$t';
    }
    final withHttps = 'https://$t';
    if (isValidHttpUrl(withHttps)) return withHttps;
    return null;
  }

  static bool isYoutubeLink(String raw) => YoutubeUrlHelper.isValidYoutubeUrl(raw);

  static String linkLabel(String raw) {
    if (raw.trim().isEmpty) return '';
    return isYoutubeLink(raw) ? 'YouTube' : 'Site';
  }
}
