import 'package:firebase_storage/firebase_storage.dart';

import 'course_thumb_resolver.dart';
import 'youtube_url_helper.dart';

/// Resultado de upload no Storage (URL pública + caminho interno).
class CourseMediaUploadResult {
  const CourseMediaUploadResult({
    required this.downloadUrl,
    required this.storagePath,
  });

  final String downloadUrl;
  final String storagePath;
}

/// Entrada de vídeo MP4 hospedado no Storage.
class CourseVideoEntry {
  const CourseVideoEntry({
    required this.url,
    this.storagePath,
    this.label,
  });

  final String url;
  final String? storagePath;
  final String? label;
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

  static bool hasResolvableImage(Map<String, dynamic> data) {
    if (collectHttpUrls(data).isNotEmpty) return true;
    if (collectStoragePaths(data).isNotEmpty) return true;
    return CourseThumbResolver.videoIdFromData(data) != null;
  }

  static Future<List<String>> resolveImageUrls(
    Map<String, dynamic> data, {
    String? docId,
  }) async {
    final seen = <String>{};
    final out = <String>[];

    for (final u in collectHttpUrls(data)) {
      if (seen.add(u)) out.add(u);
    }

    for (final path in collectStoragePaths(data)) {
      try {
        final url = await FirebaseStorage.instance.ref(path).getDownloadURL();
        if (seen.add(url)) out.add(url);
      } catch (_) {
        // ignora path inválido
      }
    }

    final id = (docId ?? data['id'] ?? '').toString().trim();
    if (out.isEmpty && id.isNotEmpty) {
      for (final url in await _discoverImagesInStorage(id)) {
        if (seen.add(url)) out.add(url);
      }
    }

    if (out.isEmpty) {
      final yt = CourseThumbResolver.videoIdFromData(data);
      if (yt != null) {
        for (final u in YoutubeUrlHelper.thumbnailUrls(yt)) {
          if (seen.add(u)) out.add(u);
        }
      }
    }
    return out;
  }

  /// Conteúdos legados: arquivo no Storage sem URL gravada no Firestore.
  static Future<List<String>> _discoverImagesInStorage(String docId) async {
    try {
      final dir = FirebaseStorage.instance.ref('wisdomapp/course_videos/$docId');
      final list = await dir.listAll();
      final urls = <String>[];
      final items = list.items.where((ref) {
        final name = ref.name.toLowerCase();
        return name.startsWith('cover_') ||
            name.startsWith('photo_') ||
            name.endsWith('.jpg') ||
            name.endsWith('.jpeg') ||
            name.endsWith('.png') ||
            name.endsWith('.webp');
      }).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      for (final ref in items) {
        try {
          urls.add(await ref.getDownloadURL());
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

    void addEntry({required String url, String? path, String? label}) {
      final u = url.trim();
      if (u.isEmpty) return;
      if (!looksLikeHttpUrl(u) && looksLikeStoragePath(u)) {
        final p = normalizeStoragePath(u);
        if (seen.add('path:$p')) {
          out.add(CourseVideoEntry(url: u, storagePath: p, label: label));
        }
        return;
      }
      if (looksLikeHttpUrl(u) && seen.add(u)) {
        out.add(CourseVideoEntry(url: u, storagePath: path, label: label));
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
          );
        }
      }
    } else {
      addEntry(
        url: (data['mp4Url'] ?? '').toString(),
        path: (data['mp4StoragePath'] ?? data['videoStoragePath'] ?? '').toString(),
        label: 'Vídeo 1',
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
        final url = await FirebaseStorage.instance.ref(path).getDownloadURL();
        out.add(CourseVideoEntry(url: url, storagePath: path, label: e.label));
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
      final list = await dir.listAll();
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
          final url = await items[i].getDownloadURL();
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
      });
    }
    return {
      'mp4Urls': entries,
      'mp4Url': uploads.first.downloadUrl,
      'mp4StoragePath': uploads.first.storagePath,
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
        ));
      }
    }
    final merged = [...prior, ...newUploads].take(maxCourseVideos).toList();
    return videoFieldsFromUploads(merged);
  }
}
