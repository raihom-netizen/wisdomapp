import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'course_media_url_resolver.dart';
import 'youtube_url_helper.dart';

/// Uma aula do curso — o vídeo do YouTube e/ou cada MP4 enviado pelo admin.
class CourseLesson {
  const CourseLesson({
    required this.key,
    required this.index,
    required this.title,
    this.youtubeId,
    this.mp4Url,
    this.storagePath,
    this.posterUrl,
  });

  /// Chave estável (progresso por aula).
  final String key;
  final int index;
  final String title;
  final String? youtubeId;
  final String? mp4Url;
  final String? storagePath;

  /// Quadro do vídeo gravado no envio (capa da aula na lista).
  final String? posterUrl;

  bool get isYoutube => youtubeId != null;

  /// Dados para a capa da aula ([CourseMediaThumbnail.fromData]): YouTube →
  /// miniatura em alta; MP4 → quadro gravado ou prévia do próprio vídeo.
  Map<String, dynamic> get thumbData => isYoutube
      ? {'youtubeVideoId': youtubeId}
      : {
          if ((mp4Url ?? storagePath) != null) 'mp4Url': mp4Url ?? storagePath,
          if (storagePath != null) 'mp4StoragePath': storagePath,
          if (posterUrl != null) 'videoPosterUrl': posterUrl,
        };

  String get sourceLabel => isYoutube ? 'YouTube' : 'Vídeo';
}

/// Monta a lista de aulas a partir do documento `course_videos`
/// (sem mudar o formato gravado pelo admin).
class CourseLessons {
  CourseLessons._();

  static List<CourseLesson> fromData(Map<String, dynamic> data) {
    final out = <CourseLesson>[];
    final yt = YoutubeUrlHelper.videoIdFromData(data);
    final entries = CourseMediaUrlResolver.collectVideoEntries(data);
    final total = entries.length + (yt != null ? 1 : 0);

    if (yt != null) {
      out.add(CourseLesson(
        key: 'yt:$yt',
        index: 0,
        title: total > 1 ? 'Aula 1 · vídeo principal' : 'Vídeo do curso',
        youtubeId: yt,
      ));
    }
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final n = out.length + 1;
      final path = (e.storagePath ?? '').trim();
      final label = (e.label ?? '').trim();
      final generic = label.isEmpty || RegExp(r'^Vídeo \d+$').hasMatch(label);
      out.add(CourseLesson(
        key: path.isNotEmpty ? 'mp4:$path' : 'mp4:$i',
        index: out.length,
        title: total > 1
            ? (generic ? 'Aula $n' : 'Aula $n · $label')
            : (generic ? 'Vídeo do curso' : label),
        mp4Url: CourseMediaUrlResolver.looksLikeHttpUrl(e.url) ? e.url : null,
        storagePath: path.isNotEmpty
            ? path
            : (CourseMediaUrlResolver.looksLikeStoragePath(e.url)
                ? CourseMediaUrlResolver.normalizeStoragePath(e.url)
                : null),
        posterUrl: e.posterUrl,
      ));
    }
    return out;
  }

  static List<String> keysOf(Map<String, dynamic> data) =>
      fromData(data).map((l) => l.key).toList();

  /// Chave da aula que um player «avulso» (feed, painel do módulo, tela de
  /// assistir) está tocando — mesma chave da tela do curso, para o progresso
  /// ser um só. O player prefere o YouTube quando existe; senão o MP4 [mp4Url]
  /// (ou o primeiro). [storagePath] cobre o legado descoberto no Storage.
  static String? lessonKeyFor(
    Map<String, dynamic> data, {
    String? mp4Url,
    String? storagePath,
  }) {
    final lessons = fromData(data);
    if (lessons.isEmpty) {
      final path = (storagePath ?? '').trim();
      if (path.isNotEmpty) return 'mp4:$path';
      return (mp4Url ?? '').trim().isNotEmpty ? 'mp4:0' : null;
    }
    if (lessons.first.isYoutube) return lessons.first.key;
    final url = (mp4Url ?? '').trim();
    if (url.isNotEmpty) {
      for (final l in lessons) {
        if (l.mp4Url == url) return l.key;
      }
    }
    final path = (storagePath ?? '').trim();
    if (path.isNotEmpty) {
      for (final l in lessons) {
        if (l.storagePath == path) return l.key;
      }
    }
    return lessons.first.key;
  }

  /// URL tocável do MP4 (resolve caminho do Storage quando preciso).
  static Future<String?> resolveMp4(CourseLesson lesson) async {
    if (lesson.isYoutube) return null;
    final direct = lesson.mp4Url?.trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final path = lesson.storagePath;
    if (path == null || path.isEmpty) return null;
    try {
      // Com prazo: sem resposta do Storage o player mostra «indisponível»
      // em vez de girar para sempre.
      return await FirebaseStorage.instance
          .ref(path)
          .getDownloadURL()
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      return null;
    }
  }

  /// Conteúdo legado: vídeos só no Storage, sem URL no documento.
  static Future<List<CourseLesson>> discoverFromStorage(
    Map<String, dynamic> data, {
    String? docId,
  }) async {
    final entries = await CourseMediaUrlResolver.resolveVideoEntries(
      data,
      docId: docId,
    );
    return [
      for (var i = 0; i < entries.length; i++)
        CourseLesson(
          key: (entries[i].storagePath ?? '').isNotEmpty
              ? 'mp4:${entries[i].storagePath}'
              : 'mp4:$i',
          index: i,
          title: entries.length > 1 ? 'Aula ${i + 1}' : 'Vídeo do curso',
          mp4Url: entries[i].url,
          storagePath: entries[i].storagePath,
          posterUrl: entries[i].posterUrl,
        ),
    ];
  }

  /// Duração informada pelo admin (`durationMinutes`), se houver.
  static int? declaredMinutes(Map<String, dynamic> data) {
    final raw = data['durationMinutes'] ?? data['duracaoMinutos'];
    if (raw is num && raw > 0) return raw.round();
    final parsed = int.tryParse((raw ?? '').toString().trim());
    return (parsed != null && parsed > 0) ? parsed : null;
  }

  /// Selo «Novo» — publicado nos últimos [days] dias.
  static bool isNew(Map<String, dynamic> data, {int days = 14}) {
    final c = data['createdAt'];
    DateTime? when;
    if (c is Timestamp) when = c.toDate();
    if (c is DateTime) when = c;
    if (when == null) return false;
    return DateTime.now().difference(when).inDays < days;
  }

  static String formatDuration(double seconds) {
    final total = seconds.round();
    if (total <= 0) return '';
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) return '${h}h${m.toString().padLeft(2, '0')}';
    if (m > 0) return '$m:${s.toString().padLeft(2, '0')}';
    return '${s}s';
  }

  static String formatMinutes(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h${m.toString().padLeft(2, '0')}';
  }
}
