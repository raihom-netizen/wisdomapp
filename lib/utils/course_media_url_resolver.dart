import 'dart:async';

import 'package:firebase_storage/firebase_storage.dart';

import 'course_thumb_resolver.dart';
import 'youtube_url_helper.dart';

/// Resultado de upload no Storage (URL pública + caminho interno).
class CourseMediaUploadResult {
  const CourseMediaUploadResult({
    required this.downloadUrl,
    required this.storagePath,
    this.posterUrl,
    this.posterStoragePath,
  });

  final String downloadUrl;
  final String storagePath;

  /// Vídeo: quadro do próprio vídeo (JPEG) gerado no envio — capa «prévia»
  /// quando o curso não tem capa própria. `null` se não deu para gerar.
  final String? posterUrl;
  final String? posterStoragePath;
}

/// Entrada de vídeo MP4 hospedado no Storage.
class CourseVideoEntry {
  const CourseVideoEntry({
    required this.url,
    this.storagePath,
    this.label,
    this.posterUrl,
  });

  final String url;
  final String? storagePath;
  final String? label;

  /// Quadro do vídeo gravado no envio (ver [CourseMediaUploadResult.posterUrl]).
  final String? posterUrl;
}

class _ImageUrlsMemo {
  _ImageUrlsMemo(this.future, this.at);

  final Future<List<String>> future;
  final DateTime at;
  List<String>? result;
}

/// Resolve URLs HTTP e caminhos `wisdomapp/course_videos/...` do Firestore.
class CourseMediaUrlResolver {
  CourseMediaUrlResolver._();

  static const maxGalleryPhotos = 10;
  static const maxCourseVideos = 5;

  static const _singleUrlKeys = [
    'imageUrl',
    'coverUrl',
    'thumbnailUrl',
    'posterUrl',
    'downloadUrl',
  ];

  static const _arrayUrlKeys = ['imageUrls', 'photoUrls', 'galleryUrls', 'gallery'];

  static const _singlePathKeys = [
    'coverStoragePath',
    'imageStoragePath',
    'storagePath',
  ];

  static const _arrayPathKeys = ['imageStoragePaths', 'photoStoragePaths'];

  static Map<String, dynamic> enrichWithDocId(
    Map<String, dynamic> data,
    String? docId,
  ) {
    if (docId == null || docId.trim().isEmpty) return data;
    if (data['id']?.toString() == docId) return data;
    return {...data, 'id': docId};
  }

  /// Evita gravar URLs vazias (quebram preview no painel).
  static Map<String, dynamic> stripEmptyMediaFields(Map<String, dynamic> fields) {
    final out = <String, dynamic>{};
    fields.forEach((key, value) {
      if (value is String && value.trim().isEmpty) return;
      out[key] = value;
    });
    return out;
  }

  /// thumbnailUrl sempre aponta para a primeira imagem publicada.
  static Map<String, dynamic> finalizeImageFields(Map<String, dynamic> fields) {
    final cleaned = stripEmptyMediaFields(fields);
    final urls = collectHttpUrls(cleaned);
    if (urls.isNotEmpty) {
      cleaned['thumbnailUrl'] = urls.first;
      cleaned['imageUrl'] ??= urls.first;
      cleaned['coverUrl'] ??= urls.first;
    }
    return cleaned;
  }

  static bool looksLikeHttpUrl(String raw) {
    final u = raw.trim().toLowerCase();
    return u.startsWith('http://') || u.startsWith('https://');
  }

  static String normalizeStoragePath(String raw) {
    var s = raw.trim();
    if (s.startsWith('gs://')) {
      final slash = s.indexOf('/', 5);
      if (slash > 0) s = s.substring(slash + 1);
    }
    while (s.startsWith('/')) {
      s = s.substring(1);
    }
    return s;
  }

  static bool looksLikeStoragePath(String raw) {
    final n = normalizeStoragePath(raw);
    return n.startsWith('wisdomapp/course_videos/');
  }

  static List<String> collectHttpUrls(Map<String, dynamic> data) {
    final seen = <String>{};
    final out = <String>[];

    void add(String? raw) {
      if (raw == null) return;
      final t = raw.trim();
      if (t.isEmpty || !looksLikeHttpUrl(t)) return;
      if (seen.add(t)) out.add(t);
    }

    for (final key in _singleUrlKeys) {
      add((data[key] ?? '').toString());
    }
    for (final key in _arrayUrlKeys) {
      final raw = data[key];
      if (raw is! List) continue;
      for (final item in raw) {
        if (item is String) {
          add(item);
        } else if (item is Map) {
          add((item['url'] ?? item['downloadUrl'] ?? '').toString());
        }
      }
    }
    return out;
  }

  static List<String> collectStoragePaths(Map<String, dynamic> data) {
    final seen = <String>{};
    final out = <String>[];

    void addPath(String? raw) {
      if (raw == null) return;
      final t = raw.trim();
      if (t.isEmpty || !looksLikeStoragePath(t)) return;
      final n = normalizeStoragePath(t);
      if (seen.add(n)) out.add(n);
    }

    for (final key in _singlePathKeys) {
      addPath((data[key] ?? '').toString());
    }
    for (final key in _arrayPathKeys) {
      final raw = data[key];
      if (raw is! List) continue;
      for (final item in raw) {
        if (item is String) addPath(item);
      }
    }

    // Campos legados podem ter guardado o path em vez da URL.
    for (final key in _singleUrlKeys) {
      final v = (data[key] ?? '').toString().trim();
      if (v.isNotEmpty && !looksLikeHttpUrl(v)) addPath(v);
    }
    for (final key in _arrayUrlKeys) {
      final raw = data[key];
      if (raw is! List) continue;
      for (final item in raw) {
        if (item is String && !looksLikeHttpUrl(item)) addPath(item);
      }
    }

    return out;
  }

  /// Prazo de cada ida ao Storage (getDownloadURL/listAll): sem resposta, a
  /// capa cai na reserva em vez de ficar no esqueleto cinza para sempre.
  static const _kStorageTimeout = Duration(seconds: 12);

  /// Quadros do vídeo gravados no envio (`videoPosterUrl` e `posterUrl` de
  /// cada item de `mp4Urls`), na ordem das aulas.
  static List<String> videoPosterUrls(Map<String, dynamic> data) {
    final out = <String>[];
    void add(Object? raw) {
      final t = (raw ?? '').toString().trim();
      if (t.isNotEmpty && looksLikeHttpUrl(t) && !out.contains(t)) out.add(t);
    }

    final list = data['mp4Urls'];
    if (list is List) {
      for (final item in list) {
        if (item is Map) add(item['posterUrl']);
      }
    }
    add(data['videoPosterUrl']);
    return out;
  }

  /// URL (ou caminho no Storage) do primeiro vídeo MP4 — base da prévia
  /// gerada na hora quando não há capa nem quadro gravado.
  static String? firstVideoRef(Map<String, dynamic> data) {
    final entries = collectVideoEntries(data);
    if (entries.isEmpty) return null;
    final e = entries.first;
    return looksLikeHttpUrl(e.url) ? e.url : (e.storagePath ?? e.url);
  }

  /// Resolve o link do primeiro MP4 (com prazo) — `null` se não houver.
  static Future<String?> resolveFirstVideoUrl(Map<String, dynamic> data) async {
    final entries = collectVideoEntries(data);
    if (entries.isEmpty) return null;
    final e = entries.first;
    if (looksLikeHttpUrl(e.url)) return e.url;
    final path = e.storagePath ?? normalizeStoragePath(e.url);
    try {
      return await FirebaseStorage.instance
          .ref(path)
          .getDownloadURL()
          .timeout(_kStorageTimeout);
    } catch (_) {
      return null;
    }
  }

  static bool hasResolvableImage(Map<String, dynamic> data) {
    if (collectHttpUrls(data).isNotEmpty) return true;
    if (collectStoragePaths(data).isNotEmpty) return true;
    return CourseThumbResolver.videoIdFromData(data) != null;
  }

  /// Memo das capas já resolvidas (getDownloadURL/listAll custam 1 ida ao
  /// servidor CADA). Antes, cada rebuild da lista (busca, progresso, rolagem)
  /// refazia tudo e a capa piscava no spinner.
  static final Map<String, _ImageUrlsMemo> _imageMemo = {};
  static const _imageMemoTtl = Duration(minutes: 15);
  static const _imageMemoMax = 400;

  /// Identidade estável da capa de um documento (não depende da instância do Map).
  static String imageFingerprint(Map<String, dynamic> data, {String? docId}) {
    final id = (docId ?? data['id'] ?? '').toString().trim();
    return [
      id,
      ...collectHttpUrls(data),
      ...collectStoragePaths(data),
      CourseThumbResolver.videoIdFromData(data) ?? '',
      // Prévia do MP4 (sem capa): o vídeo/quadro também identifica a capa.
      ...videoPosterUrls(data),
      firstVideoRef(data) ?? '',
    ].join('|');
  }

  static String _memoKey(Map<String, dynamic> data, String? docId, bool light) =>
      '${light ? 'L' : 'F'}#${imageFingerprint(data, docId: docId)}';

  /// URLs já resolvidas (sem ir à rede) — `null` se ainda não houver.
  static List<String>? cachedImageUrls(
    Map<String, dynamic> data, {
    String? docId,
    bool light = false,
  }) {
    final hit = _imageMemo[_memoKey(data, docId, light)];
    if (hit == null || hit.result == null) return null;
    if (DateTime.now().difference(hit.at) > _imageMemoTtl) return null;
    return hit.result;
  }

  /// Limpa o memo (ex.: admin trocou a capa de um conteúdo legado).
  static void clearImageMemo() => _imageMemo.clear();

  /// [light] = capa leve do YouTube (hq/mq) para listas, cards e pôster.
  static Future<List<String>> resolveImageUrls(
    Map<String, dynamic> data, {
    String? docId,
    bool light = false,
  }) {
    final key = _memoKey(data, docId, light);
    final now = DateTime.now();
    final hit = _imageMemo[key];
    if (hit != null && now.difference(hit.at) <= _imageMemoTtl) {
      return hit.future;
    }
    if (_imageMemo.length >= _imageMemoMax) _imageMemo.clear();
    final memo = _ImageUrlsMemo(
      _resolveImageUrlsUncached(data, docId: docId, light: light),
      now,
    );
    _imageMemo[key] = memo;
    memo.future.then((urls) {
      // Lista vazia pode ser falha de rede — não memoriza.
      if (urls.isEmpty) {
        _imageMemo.remove(key);
      } else {
        memo.result = urls;
      }
    }, onError: (_) => _imageMemo.remove(key));
    return memo.future;
  }

  static Future<List<String>> _resolveImageUrlsUncached(
    Map<String, dynamic> data, {
    String? docId,
    bool light = false,
  }) async {
    final seen = <String>{};
    final out = <String>[];
    final ytId = CourseThumbResolver.videoIdFromData(data);

    for (final u in collectHttpUrls(data)) {
      // Modo leve: capa gravada do YouTube (muitas vezes maxres) dá lugar à
      // cascata hq → mq logo abaixo.
      if (light && ytId != null && YoutubeUrlHelper.isYoutubeThumbUrl(u)) {
        continue;
      }
      if (seen.add(u)) out.add(u);
    }

    // Em paralelo (antes: uma ida ao Storage por vez), mantendo a ordem.
    final resolved = await Future.wait(
      collectStoragePaths(data).map((path) async {
        try {
          return await FirebaseStorage.instance
              .ref(path)
              .getDownloadURL()
              .timeout(_kStorageTimeout);
        } catch (_) {
          return null; // ignora path inválido (ou Storage sem resposta)
        }
      }),
    );
    for (final url in resolved) {
      if (url != null && seen.add(url)) out.add(url);
    }

    // Sem capa própria: quadro do vídeo gerado no envio (prévia do MP4).
    if (out.isEmpty && ytId == null) {
      for (final u in videoPosterUrls(data)) {
        if (seen.add(u)) out.add(u);
      }
    }

    final id = (docId ?? data['id'] ?? '').toString().trim();
    // Modo leve com YouTube: a capa do vídeo basta — não varre o Storage.
    if (out.isEmpty && id.isNotEmpty && !(light && ytId != null)) {
      for (final url in await _discoverImagesInStorage(id)) {
        if (seen.add(url)) out.add(url);
      }
    }

    // YouTube: sempre acrescenta a cascata (maxres → sd → hq → mq). A capa
    // gravada costuma ser `maxresdefault`, que dá 404 em vídeos sem HD — sem
    // a cascata o card ficava sem imagem.
    if (ytId != null) {
      final cascade = light
          ? YoutubeUrlHelper.lightThumbnailUrls(ytId)
          : YoutubeUrlHelper.thumbnailUrls(ytId);
      for (final u in cascade) {
        if (seen.add(u)) out.add(u);
      }
    }
    return out;
  }

  /// Conteúdos legados: arquivo no Storage sem URL gravada no Firestore.
  static Future<List<String>> _discoverImagesInStorage(String docId) async {
    try {
      final dir = FirebaseStorage.instance.ref('wisdomapp/course_videos/$docId');
      final list = await dir.listAll().timeout(_kStorageTimeout);
      final urls = <String>[];
      final items = list.items.where((ref) {
        final name = ref.name.toLowerCase();
        // Quadro do vídeo (poster_*) também serve de capa no legado.
        return name.startsWith('cover_') ||
            name.startsWith('poster_') ||
            name.startsWith('photo_') ||
            name.endsWith('.jpg') ||
            name.endsWith('.jpeg') ||
            name.endsWith('.png') ||
            name.endsWith('.webp');
      }).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      for (final ref in items) {
        try {
          urls.add(await ref.getDownloadURL().timeout(_kStorageTimeout));
        } catch (_) {}
      }
      return urls;
    } catch (_) {
      return const [];
    }
  }

  static Future<List<String>> resolveRawUrls(List<String> raw) async {
    final data = <String, dynamic>{};
    final http = <String>[];
    final paths = <String>[];
    for (final r in raw) {
      final t = r.trim();
      if (t.isEmpty) continue;
      if (looksLikeHttpUrl(t)) {
        http.add(t);
      } else if (looksLikeStoragePath(t)) {
        paths.add(normalizeStoragePath(t));
      }
    }
    if (http.isNotEmpty) data['imageUrls'] = http;
    if (paths.isNotEmpty) data['imageStoragePaths'] = paths;
    return resolveImageUrls(data);
  }

  static List<CourseVideoEntry> collectVideoEntries(Map<String, dynamic> data) {
    final seen = <String>{};
    final out = <CourseVideoEntry>[];

    void addEntry({
      required String url,
      String? path,
      String? label,
      String? poster,
    }) {
      final u = url.trim();
      if (u.isEmpty) return;
      final pu = (poster ?? '').trim();
      final posterUrl = looksLikeHttpUrl(pu) ? pu : null;
      if (!looksLikeHttpUrl(u) && looksLikeStoragePath(u)) {
        final p = normalizeStoragePath(u);
        if (seen.add('path:$p')) {
          out.add(CourseVideoEntry(
              url: u, storagePath: p, label: label, posterUrl: posterUrl));
        }
        return;
      }
      if (looksLikeHttpUrl(u) && seen.add(u)) {
        out.add(CourseVideoEntry(
            url: u, storagePath: path, label: label, posterUrl: posterUrl));
      }
    }

    final mp4Urls = data['mp4Urls'];
    if (mp4Urls is List && mp4Urls.isNotEmpty) {
      for (var i = 0; i < mp4Urls.length; i++) {
        final item = mp4Urls[i];
        if (item is String) {
          addEntry(url: item, label: 'Vídeo ${i + 1}');
        } else if (item is Map) {
          addEntry(
            url: (item['url'] ?? item['mp4Url'] ?? item['downloadUrl'] ?? '').toString(),
            path: (item['storagePath'] ?? '').toString().trim().isEmpty
                ? null
                : (item['storagePath'] ?? '').toString(),
            label: (item['label'] ?? item['title'] ?? 'Vídeo ${i + 1}').toString(),
            poster: (item['posterUrl'] ?? '').toString(),
          );
        }
      }
    } else {
      addEntry(
        url: (data['mp4Url'] ?? '').toString(),
        path: (data['mp4StoragePath'] ?? data['videoStoragePath'] ?? '').toString(),
        label: 'Vídeo 1',
        poster: (data['videoPosterUrl'] ?? '').toString(),
      );
    }

    return out.take(maxCourseVideos).toList();
  }

  static Future<List<CourseVideoEntry>> resolveVideoEntries(
    Map<String, dynamic> data, {
    String? docId,
  }) async {
    final raw = collectVideoEntries(data);
    final out = <CourseVideoEntry>[];
    for (final e in raw) {
      if (looksLikeHttpUrl(e.url)) {
        out.add(e);
        continue;
      }
      final path = e.storagePath ?? normalizeStoragePath(e.url);
      try {
        final url = await FirebaseStorage.instance
            .ref(path)
            .getDownloadURL()
            .timeout(_kStorageTimeout);
        out.add(CourseVideoEntry(
            url: url,
            storagePath: path,
            label: e.label,
            posterUrl: e.posterUrl));
      } catch (_) {}
    }

    final id = (docId ?? data['id'] ?? '').toString().trim();
    if (out.isEmpty && id.isNotEmpty) {
      for (final e in await _discoverVideosInStorage(id)) {
        out.add(e);
      }
    }
    return out;
  }

  static Future<List<CourseVideoEntry>> _discoverVideosInStorage(String docId) async {
    try {
      final dir = FirebaseStorage.instance.ref('wisdomapp/course_videos/$docId');
      final list = await dir.listAll().timeout(_kStorageTimeout);
      final out = <CourseVideoEntry>[];
      final items = list.items.where((ref) {
        final name = ref.name.toLowerCase();
        return name.startsWith('video_') ||
            name.endsWith('.mp4') ||
            name.endsWith('.webm') ||
            name.endsWith('.mov');
      }).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      for (var i = 0; i < items.length && i < maxCourseVideos; i++) {
        try {
          final url =
              await items[i].getDownloadURL().timeout(_kStorageTimeout);
          out.add(CourseVideoEntry(
            url: url,
            storagePath: items[i].fullPath,
            label: 'Vídeo ${i + 1}',
          ));
        } catch (_) {}
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Campos Firestore para salvar galeria (retrocompatível com campos únicos).
  static Map<String, dynamic> imageFieldsFromUploads(
    List<CourseMediaUploadResult> uploads,
  ) {
    if (uploads.isEmpty) return {};
    final urls = uploads.map((e) => e.downloadUrl).toList();
    final paths = uploads.map((e) => e.storagePath).toList();
    final first = urls.first;
    return finalizeImageFields({
      'imageUrls': urls,
      'imageStoragePaths': paths,
      'imageUrl': first,
      'coverUrl': first,
      'thumbnailUrl': first,
      'coverStoragePath': paths.first,
    });
  }

  static Map<String, dynamic> videoFieldsFromUploads(
    List<CourseMediaUploadResult> uploads,
  ) {
    if (uploads.isEmpty) return {};
    final entries = <Map<String, dynamic>>[];
    for (var i = 0; i < uploads.length; i++) {
      final u = uploads[i];
      entries.add({
        'url': u.downloadUrl,
        'storagePath': u.storagePath,
        'label': 'Vídeo ${i + 1}',
        if ((u.posterUrl ?? '').isNotEmpty) 'posterUrl': u.posterUrl,
        if ((u.posterStoragePath ?? '').isNotEmpty)
          'posterStoragePath': u.posterStoragePath,
      });
    }
    String? poster;
    for (final u in uploads) {
      if ((u.posterUrl ?? '').isNotEmpty) {
        poster = u.posterUrl;
        break;
      }
    }
    return {
      'mp4Urls': entries,
      'mp4Url': uploads.first.downloadUrl,
      'mp4StoragePath': uploads.first.storagePath,
      // Prévia do vídeo (quadro) para quem não enviou capa — NÃO entra nos
      // campos de imagem (`posterUrl` lá é tratado como foto da galeria).
      if (poster != null) 'videoPosterUrl': poster,
    };
  }

  static Map<String, dynamic> mergeImageFields({
    required Map<String, dynamic> existing,
    required List<CourseMediaUploadResult> newUploads,
    bool replaceAll = false,
  }) {
    if (replaceAll) {
      return newUploads.isEmpty ? {} : imageFieldsFromUploads(newUploads);
    }
    if (newUploads.isEmpty) return {};
    final prior = <CourseMediaUploadResult>[];
    final urls = collectHttpUrls(existing);
    final paths = collectStoragePaths(existing);
    for (var i = 0; i < urls.length; i++) {
      prior.add(CourseMediaUploadResult(
        downloadUrl: urls[i],
        storagePath: i < paths.length ? paths[i] : '',
      ));
    }
    final merged = [...prior, ...newUploads].take(maxGalleryPhotos).toList();
    return imageFieldsFromUploads(merged);
  }

  static Map<String, dynamic> mergeVideoFields({
    required Map<String, dynamic> existing,
    required List<CourseMediaUploadResult> newUploads,
    bool replaceAll = false,
  }) {
    if (replaceAll) {
      return newUploads.isEmpty ? {} : videoFieldsFromUploads(newUploads);
    }
    if (newUploads.isEmpty) return {};
    final prior = <CourseMediaUploadResult>[];
    for (final e in collectVideoEntries(existing)) {
      if (looksLikeHttpUrl(e.url)) {
        prior.add(CourseMediaUploadResult(
          downloadUrl: e.url,
          storagePath: e.storagePath ?? '',
          posterUrl: e.posterUrl,
        ));
      }
    }
    final merged = [...prior, ...newUploads].take(maxCourseVideos).toList();
    return videoFieldsFromUploads(merged);
  }
}
