import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils/youtube_url_helper.dart';

/// Dados públicos de um vídeo do YouTube (oEmbed — sem chave de API).
class YoutubeOembedInfo {
  const YoutubeOembedInfo({
    required this.videoId,
    this.title = '',
    this.author = '',
    this.thumbnailUrl,
  });

  final String videoId;
  final String title;
  final String author;
  final String? thumbnailUrl;

  /// Capa que sempre existe (oEmbed devolve hqdefault; sem ele, monta pelo ID).
  String get coverUrl =>
      (thumbnailUrl != null && thumbnailUrl!.isNotEmpty)
          ? thumbnailUrl!
          : YoutubeUrlHelper.safeThumbnailUrl(videoId);

  /// Interpreta o JSON do oEmbed (testável sem rede).
  static YoutubeOembedInfo? parse(String videoId, String body) {
    try {
      final m = jsonDecode(body);
      if (m is! Map) return null;
      return YoutubeOembedInfo(
        videoId: videoId,
        title: (m['title'] ?? '').toString().trim(),
        author: (m['author_name'] ?? '').toString().trim(),
        thumbnailUrl: (m['thumbnail_url'] ?? '').toString().trim(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Busca título/canal/capa pelo oEmbed público do YouTube (aceita CORS na web).
/// Falhou (rede, vídeo privado, 401/404)? devolve só o ID — o cadastro segue.
class YoutubeOembedService {
  YoutubeOembedService._();

  static final Map<String, YoutubeOembedInfo> _cache = {};

  static Uri endpointFor(String videoId) => Uri.https(
        'www.youtube.com',
        '/oembed',
        {'url': YoutubeUrlHelper.watchUrl(videoId), 'format': 'json'},
      );

  static Future<YoutubeOembedInfo> fetch(
    String videoId, {
    http.Client? client,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final cached = _cache[videoId];
    if (cached != null) return cached;
    final fallback = YoutubeOembedInfo(videoId: videoId);
    try {
      final c = client ?? http.Client();
      try {
        final res = await c.get(endpointFor(videoId)).timeout(timeout);
        if (res.statusCode != 200) return fallback;
        final info = YoutubeOembedInfo.parse(videoId, utf8.decode(res.bodyBytes));
        if (info == null) return fallback;
        _cache[videoId] = info;
        return info;
      } finally {
        if (client == null) c.close();
      }
    } catch (_) {
      return fallback;
    }
  }
}
