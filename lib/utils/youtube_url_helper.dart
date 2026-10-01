/// Extrai ID e URLs de embed/thumbnail a partir de links YouTube.
///
/// Aceita todos os formatos comuns e grava sempre no formato canônico
/// (`youtubeVideoId` de 11 caracteres + `https://www.youtube.com/watch?v=ID`):
/// - `https://www.youtube.com/watch?v=ID` (com `&t=`, `&list=`, `&si=`…)
/// - `https://m.youtube.com/watch?v=ID`, `music.youtube.com/watch?v=ID`
/// - `https://youtu.be/ID` (com `?si=`, `?t=`)
/// - `youtube.com/shorts/ID`, `/embed/ID`, `/live/ID`, `/v/ID`, `/e/ID`
/// - `youtube-nocookie.com/embed/ID`
/// - código `<iframe src="…">` colado inteiro
/// - ID puro (11 caracteres)
class YoutubeUrlHelper {
  YoutubeUrlHelper._();

  static final RegExp _idRe = RegExp(r'^[A-Za-z0-9_-]{11}$');

  /// Segmentos de caminho com 11 letras que NÃO são vídeo (playlist/live de canal).
  static const Set<String> _reservedSegments = {
    'videoseries',
    'live_stream',
  };

  static const Set<String> _idPathHeads = {
    'embed',
    'shorts',
    'live',
    'v',
    'e',
    'vi',
  };

  static bool isValidVideoId(String? id) {
    if (id == null) return false;
    final t = id.trim();
    return _idRe.hasMatch(t) && !_reservedSegments.contains(t.toLowerCase());
  }

  static String? extractVideoId(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;

    // Código de incorporação colado inteiro: <iframe src="...">.
    final src = RegExp('src\\s*=\\s*["\']([^"\']+)["\']').firstMatch(s);
    if (src != null) s = src.group(1)!.trim();

    // Aspas / sinais em volta (colagem de chat/e-mail).
    while (s.isNotEmpty && '<>"\''.contains(s[0])) {
      s = s.substring(1);
    }
    while (s.isNotEmpty && '<>"\''.contains(s[s.length - 1])) {
      s = s.substring(0, s.length - 1);
    }
    s = s.trim();
    if (s.isEmpty) return null;

    if (isValidVideoId(s)) return s;

    if (s.startsWith('//')) s = 'https:$s';
    if (!s.contains('://')) s = 'https://$s';

    Uri uri;
    try {
      uri = Uri.parse(s);
    } catch (_) {
      return null;
    }

    var host = uri.host.toLowerCase();
    for (final p in const ['www.', 'm.', 'music.', 'gaming.']) {
      if (host.startsWith(p)) {
        host = host.substring(p.length);
        break;
      }
    }

    final segs = uri.pathSegments.where((p) => p.trim().isNotEmpty).toList();
    Map<String, String> query;
    try {
      query = uri.queryParameters;
    } catch (_) {
      query = const {};
    }

    String? cand;
    if (host == 'youtu.be') {
      if (segs.isNotEmpty) cand = segs.first;
    } else if (host == 'youtube.com' ||
        host == 'youtube-nocookie.com' ||
        host.endsWith('.youtube.com')) {
      if (segs.isEmpty) {
        cand = query['v'];
      } else {
        final head = segs.first.toLowerCase();
        if (head == 'watch') {
          cand = query['v'];
          // Formato antigo: /watch/ID
          if (cand == null && segs.length > 1) cand = segs[1];
        } else if (_idPathHeads.contains(head) && segs.length > 1) {
          cand = segs[1];
        } else if (head == 'attribution_link' || head == 'oembed') {
          final inner = query['u'] ?? query['url'];
          if (inner != null && inner.isNotEmpty) {
            final innerUrl = inner.startsWith('/')
                ? 'https://www.youtube.com$inner'
                : inner;
            if (innerUrl != raw) return extractVideoId(innerUrl);
          }
        } else {
          cand = query['v'];
        }
      }
    } else {
      return null;
    }

    if (cand == null) return null;
    cand = cand.trim();
    return isValidVideoId(cand) ? cand : null;
  }

  /// Segundos de início indicados no link (`t=90`, `t=1m30s`, `start=45`).
  static int startSecondsFromUrl(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return 0;
    Uri uri;
    try {
      uri = Uri.parse(s.contains('://') ? s : 'https://$s');
    } catch (_) {
      return 0;
    }
    String? t;
    try {
      t = uri.queryParameters['t'] ?? uri.queryParameters['start'];
    } catch (_) {
      t = null;
    }
    if ((t == null || t.isEmpty) && uri.fragment.startsWith('t=')) {
      t = uri.fragment.substring(2);
    }
    if (t == null || t.isEmpty) return 0;
    final plain = int.tryParse(t.replaceAll('s', ''));
    if (plain != null && !t.contains('m') && !t.contains('h')) {
      return plain < 0 ? 0 : plain;
    }
    final m = RegExp(r'^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s?)?$').firstMatch(t);
    if (m == null) return 0;
    final h = int.tryParse(m.group(1) ?? '') ?? 0;
    final min = int.tryParse(m.group(2) ?? '') ?? 0;
    final sec = int.tryParse(m.group(3) ?? '') ?? 0;
    return h * 3600 + min * 60 + sec;
  }

  /// Mensagem clara para o cadastro; `null` quando o link é válido.
  static String? validationMessage(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 'Informe o link do vídeo do YouTube.';
    if (extractVideoId(t) != null) return null;
    final low = t.toLowerCase();
    final isYoutubeHost = low.contains('youtube.com') ||
        low.contains('youtu.be') ||
        low.contains('youtube-nocookie.com');
    if (isYoutubeHost && low.contains('list=')) {
      return 'Este é um link de playlist. Abra o vídeo desejado na playlist '
          'e copie o link dele (precisa ter «watch?v=» ou «youtu.be/»).';
    }
    if (isYoutubeHost &&
        (low.contains('/@') ||
            low.contains('/channel/') ||
            low.contains('/c/') ||
            low.contains('/user/'))) {
      return 'Este é um link de canal, não de vídeo. Abra o vídeo e copie o '
          'link dele.';
    }
    return 'Link do YouTube inválido. Exemplos aceitos: '
        'https://www.youtube.com/watch?v=XXXXXXXXXXX, '
        'https://youtu.be/XXXXXXXXXXX, youtube.com/shorts/XXXXXXXXXXX '
        'ou só o ID de 11 caracteres.';
  }

  /// Lê o ID de um documento `course_videos` (limpa IDs gravados sujos).
  static String? videoIdFromData(Map<String, dynamic> data) {
    final stored = (data['youtubeVideoId'] ?? '').toString().trim();
    if (stored.isNotEmpty) {
      final clean = extractVideoId(stored);
      if (clean != null) return clean;
    }
    for (final key in const [
      'youtubeUrl',
      'videoUrl',
      'linkUrl',
      'externalUrl',
    ]) {
      final v = (data[key] ?? '').toString().trim();
      if (v.isEmpty) continue;
      final id = extractVideoId(v);
      if (id != null) return id;
    }
    return null;
  }

  /// Campos canônicos para gravar no Firestore (`null` se o link for inválido).
  static Map<String, String>? canonicalFields(String raw) {
    final id = extractVideoId(raw);
    if (id == null) return null;
    final url = watchUrl(id);
    return {
      'youtubeVideoId': id,
      'youtubeUrl': url,
      'videoUrl': url,
    };
  }

  static String watchUrl(String videoId) => 'https://www.youtube.com/watch?v=$videoId';

  /// Embed otimizado — fullscreen, autoplay, qualidade máxima disponível (até 4K).
  /// [startSeconds] retoma de onde o usuário parou (`start` do YouTube).
  static String embedUrl(
    String videoId, {
    bool autoplay = false,
    String? origin,
    int startSeconds = 0,
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
      if (origin != null && origin.isNotEmpty) 'widget_referrer': origin,
      if (startSeconds > 0) 'start': '$startSeconds',
    };
    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return 'https://www.youtube-nocookie.com/embed/$videoId?$query';
  }

  /// Thumbnails em cascata (Full HD quando disponível no YouTube).
  /// `maxresdefault` nem sempre existe (404) — por isso as demais na sequência.
  static List<String> thumbnailUrls(String videoId) => [
        'https://img.youtube.com/vi/$videoId/maxresdefault.jpg',
        'https://img.youtube.com/vi/$videoId/sddefault.jpg',
        'https://img.youtube.com/vi/$videoId/hqdefault.jpg',
        'https://img.youtube.com/vi/$videoId/mqdefault.jpg',
      ];

  static String thumbnailUrl(String videoId) => thumbnailUrls(videoId).first;

  /// Capa LEVE para listas e cards: `mqdefault` (320×180, 16:9 nativo, sem
  /// tarjas, ~10 KB, sempre existe) → `hqdefault` (4:3 com tarjas embutidas,
  /// só como reserva). Evita baixar o maxres (~150 KB) só para um card.
  static List<String> lightThumbnailUrls(String videoId) => [
        'https://img.youtube.com/vi/$videoId/mqdefault.jpg',
        'https://img.youtube.com/vi/$videoId/hqdefault.jpg',
      ];

  static String lightThumbnailUrl(String videoId) =>
      lightThumbnailUrls(videoId).first;

  /// Cascata escolhida pelo tamanho REAL do quadro em pixels físicos
  /// (largura lógica × devicePixelRatio).
  ///
  /// - [light] (listas) ou quadro ≤ 400 px → `mqdefault` primeiro.
  /// - Senão → a MAIOR que o YouTube fornece, `maxresdefault` (1280×720,
  ///   16:9 — não existe thumbnail 4K), com reserva sd → hq → mq (sd/hq são
  ///   4:3 com tarjas pretas embutidas: só se o maxres não existir).
  static List<String> thumbnailUrlsForWidth(
    String videoId,
    int targetPx, {
    bool light = false,
  }) {
    if (light || targetPx <= 400) return lightThumbnailUrls(videoId);
    return [
      'https://img.youtube.com/vi/$videoId/maxresdefault.jpg',
      'https://img.youtube.com/vi/$videoId/sddefault.jpg',
      'https://img.youtube.com/vi/$videoId/hqdefault.jpg',
      'https://img.youtube.com/vi/$videoId/mqdefault.jpg',
    ];
  }

  /// `true` quando [url] é uma capa gerada pelo YouTube (img.youtube.com/ytimg).
  static bool isYoutubeThumbUrl(String url) {
    final u = url.toLowerCase();
    return (u.contains('img.youtube.com/vi/') || u.contains('ytimg.com/vi/')) &&
        u.endsWith('.jpg');
  }

  /// Thumbnail que sempre existe (para gravar no Firestore).
  static String safeThumbnailUrl(String videoId) =>
      'https://img.youtube.com/vi/$videoId/hqdefault.jpg';

  static bool isValidYoutubeUrl(String raw) => extractVideoId(raw) != null;

  static String normalizeYoutubeUrl(String raw) {
    final id = extractVideoId(raw);
    return id == null ? raw.trim() : watchUrl(id);
  }
}
