/// Extrai ID e URLs de embed/thumbnail a partir de links YouTube.
class YoutubeUrlHelper {
  YoutubeUrlHelper._();

  static String? extractVideoId(String raw) {
    final url = raw.trim();
    if (url.isEmpty) return null;

    final direct = RegExp(r'^([a-zA-Z0-9_-]{11})$').firstMatch(url);
    if (direct != null) return direct.group(1);

    final patterns = [
      RegExp(r'youtu\.be/([a-zA-Z0-9_-]{11})'),
      RegExp(r'youtube\.com/watch\?.*v=([a-zA-Z0-9_-]{11})'),
      RegExp(r'youtube\.com/embed/([a-zA-Z0-9_-]{11})'),
      RegExp(r'youtube\.com/shorts/([a-zA-Z0-9_-]{11})'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(url);
      if (m != null) return m.group(1);
    }
    return null;
  }

  static String watchUrl(String videoId) => 'https://www.youtube.com/watch?v=$videoId';

  static String embedUrl(String videoId) =>
      'https://www.youtube.com/embed/$videoId?rel=0&modestbranding=1';

  static String thumbnailUrl(String videoId) =>
      'https://img.youtube.com/vi/$videoId/hqdefault.jpg';

  static bool isValidYoutubeUrl(String raw) => extractVideoId(raw) != null;

  static String normalizeYoutubeUrl(String raw) {
    final id = extractVideoId(raw);
    return id == null ? raw.trim() : watchUrl(id);
  }
}
