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

  /// Embed otimizado — fullscreen, autoplay, qualidade máxima disponível (até 4K).
  static String embedUrl(
    String videoId, {
    bool autoplay = false,
    String? origin,
  }) {
    final params = <String, String>{
      'rel': '0',
      'modestbranding': '1',
      'playsinline': '1',
      'fs': '1',
      'enablejsapi': '1',
      'iv_load_policy': '3',
      'cc_load_policy': '0',
      'color': 'white',
      if (autoplay) 'autoplay': '1',
      if (origin != null && origin.isNotEmpty) 'origin': origin,
    };
    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return 'https://www.youtube-nocookie.com/embed/$videoId?$query';
  }

  /// Thumbnails em cascata (Full HD quando disponível no YouTube).
  static List<String> thumbnailUrls(String videoId) => [
        'https://img.youtube.com/vi/$videoId/maxresdefault.jpg',
        'https://img.youtube.com/vi/$videoId/sddefault.jpg',
        'https://img.youtube.com/vi/$videoId/hqdefault.jpg',
        'https://img.youtube.com/vi/$videoId/mqdefault.jpg',
      ];

  static String thumbnailUrl(String videoId) => thumbnailUrls(videoId).first;

  static bool isValidYoutubeUrl(String raw) => extractVideoId(raw) != null;

  static String normalizeYoutubeUrl(String raw) {
    final id = extractVideoId(raw);
    return id == null ? raw.trim() : watchUrl(id);
  }
}
