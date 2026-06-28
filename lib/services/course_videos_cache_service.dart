import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/wisdom_courses_module_config.dart';
import 'course_videos_expiry_cleanup_service.dart';

/// Documento leve de `course_videos` (sem depender de [QueryDocumentSnapshot]).
class CourseVideoDoc {
  const CourseVideoDoc({required this.id, required this.data});

  final String id;
  final Map<String, dynamic> data;
}

/// Cache + carregamento cache-first do módulo Cursos (Web / iOS / Android).
class CourseVideosCacheService extends ChangeNotifier {
  CourseVideosCacheService._();
  static final CourseVideosCacheService instance = CourseVideosCacheService._();

  static const _kConfigJson = 'course_videos_cfg_v1';
  static const _kDocsJson = 'course_videos_docs_v1';
  static const _kSavedAt = 'course_videos_saved_at_v1';

  List<CourseVideoDoc> _docs = const [];
  WisdomCoursesModuleConfig _config = WisdomCoursesModuleConfig.defaults;
  bool _refreshing = false;
  bool _hydratedFromDisk = false;
  bool _hasServerSync = false;
  Future<void>? _inFlight;
  String _docsSignature = '';
  String _configSignature = '';

  List<CourseVideoDoc> get docs => _docs;
  WisdomCoursesModuleConfig get config => _config;
  bool get refreshing => _refreshing;
  bool get hasCachedData => _docs.isNotEmpty;
  bool get hasServerSync => _hasServerSync;

  /// Indica spinner só quando não há nada em cache ainda.
  bool get showInitialLoading => _refreshing && _docs.isEmpty;

  static Future<void> warmUp() => instance._warmUpFromDisk();

  static Future<void> prefetch() => instance.ensureLoaded();

  void _notifyIfMeaningfulChange({bool force = false}) {
    final docSig = _computeDocsSignature(_docs);
    final cfgSig = jsonEncode(_config.toFirestore());
    if (!force &&
        docSig == _docsSignature &&
        cfgSig == _configSignature &&
        !_refreshing) {
      return;
    }
    _docsSignature = docSig;
    _configSignature = cfgSig;
    notifyListeners();
  }

  static String _computeDocsSignature(List<CourseVideoDoc> docs) {
    if (docs.isEmpty) return '';
    final buf = StringBuffer();
    for (final d in docs) {
      buf.write(d.id);
      buf.write('|');
      buf.write(d.data['updatedAt'] ?? d.data['createdAt'] ?? '');
      buf.write(';');
    }
    return buf.toString();
  }

  Future<void> ensureLoaded({bool forceServer = false}) {
    if (_inFlight != null && !forceServer) return _inFlight!;
    if (forceServer && _inFlight != null) {
      return _inFlight!.then((_) => ensureLoaded(forceServer: true));
    }
    _inFlight = _load(forceServer: forceServer).whenComplete(() {
      _inFlight = null;
    });
    return _inFlight!;
  }

  Future<void> _warmUpFromDisk() async {
    if (_hydratedFromDisk) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final cfgRaw = prefs.getString(_kConfigJson);
      if (cfgRaw != null && cfgRaw.isNotEmpty) {
        _config = WisdomCoursesModuleConfig.fromMap(
          Map<String, dynamic>.from(jsonDecode(cfgRaw) as Map),
        );
      }
      final docsRaw = prefs.getString(_kDocsJson);
      if (docsRaw != null && docsRaw.isNotEmpty) {
        final list = jsonDecode(docsRaw) as List<dynamic>;
        _docs = list
            .map((e) => _docFromCacheMap(Map<String, dynamic>.from(e as Map)))
            .where((d) => d.id.isNotEmpty)
            .toList(growable: false);
      }
    } catch (e, st) {
      debugPrint('CourseVideosCacheService.warmUp: $e\n$st');
    }
    _hydratedFromDisk = true;
    if (_docs.isNotEmpty) _notifyIfMeaningfulChange(force: true);
  }

  Future<void> _load({required bool forceServer}) async {
    await _warmUpFromDisk();
    if (_docs.isNotEmpty) _notifyIfMeaningfulChange();

    _refreshing = true;
    if (_docs.isEmpty) _notifyIfMeaningfulChange(force: true);

    try {
      if (!forceServer) {
        await _tryFirestoreCache();
      }
      await Future.wait<void>([
        _fetchConfig(forceServer: forceServer),
        _fetchVideos(forceServer: forceServer),
      ]);
      _hasServerSync = true;
      await _persistToDisk();
    } catch (e, st) {
      debugPrint('CourseVideosCacheService.load: $e\n$st');
    } finally {
      _refreshing = false;
      _notifyIfMeaningfulChange(force: true);
    }

    unawaited(_maybePurgeExpired());
  }

  Future<void> _tryFirestoreCache() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('course_videos')
          .get(const GetOptions(source: Source.cache));
      if (snap.docs.isEmpty) return;
      _docs = snap.docs
          .map((d) => CourseVideoDoc(id: d.id, data: d.data()))
          .toList(growable: false);
      _notifyIfMeaningfulChange();
    } catch (_) {}
    try {
      final cfg = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('wisdom_courses_module')
          .get(const GetOptions(source: Source.cache));
      if (cfg.exists) {
        _config = WisdomCoursesModuleConfig.fromMap(cfg.data());
        _notifyIfMeaningfulChange();
      }
    } catch (_) {}
  }

  Future<void> _fetchConfig({required bool forceServer}) async {
    final source = forceServer ? Source.server : Source.serverAndCache;
    final snap = await FirebaseFirestore.instance
        .collection('app_config')
        .doc('wisdom_courses_module')
        .get(GetOptions(source: source));
    _config = WisdomCoursesModuleConfig.fromMap(snap.data());
  }

  Future<void> _fetchVideos({required bool forceServer}) async {
    final source = forceServer ? Source.server : Source.serverAndCache;
    final snap = await FirebaseFirestore.instance
        .collection('course_videos')
        .get(GetOptions(source: source));
    _docs = snap.docs
        .map((d) => CourseVideoDoc(id: d.id, data: d.data()))
        .toList(growable: false);
  }

  Future<void> _persistToDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kConfigJson, jsonEncode(_config.toFirestore()));
      await prefs.setString(
        _kDocsJson,
        jsonEncode(_docs.map(_docToCacheMap).toList()),
      );
      await prefs.setInt(_kSavedAt, DateTime.now().millisecondsSinceEpoch);
    } catch (e, st) {
      debugPrint('CourseVideosCacheService.persist: $e\n$st');
    }
  }

  static bool _purgeScheduled = false;
  static DateTime? _lastPurge;

  Future<void> _maybePurgeExpired() async {
    if (_purgeScheduled) return;
    final last = _lastPurge;
    if (last != null && DateTime.now().difference(last).inHours < 12) return;
    _purgeScheduled = true;
    try {
      await Future<void>.delayed(const Duration(seconds: 4));
      final n = await CourseVideosExpiryCleanupService.purgeExpired();
      _lastPurge = DateTime.now();
      if (n > 0) await ensureLoaded(forceServer: true);
    } catch (_) {
    } finally {
      _purgeScheduled = false;
    }
  }

  static Map<String, dynamic> _docToCacheMap(CourseVideoDoc d) => {
        'id': d.id,
        'data': _encodeFirestoreMap(d.data),
      };

  static CourseVideoDoc _docFromCacheMap(Map<String, dynamic> raw) {
    final id = (raw['id'] ?? '').toString();
    final dataRaw = raw['data'];
    final data = dataRaw is Map
        ? _decodeFirestoreMap(Map<String, dynamic>.from(dataRaw))
        : <String, dynamic>{};
    return CourseVideoDoc(id: id, data: data);
  }

  static dynamic _encodeFirestoreValue(dynamic v) {
    if (v is Timestamp) return {'_tsMs': v.millisecondsSinceEpoch};
    if (v is Map) {
      return v.map((k, val) => MapEntry(k.toString(), _encodeFirestoreValue(val)));
    }
    if (v is List) return v.map(_encodeFirestoreValue).toList();
    return v;
  }

  static Map<String, dynamic> _encodeFirestoreMap(Map<String, dynamic> m) =>
      m.map((k, v) => MapEntry(k, _encodeFirestoreValue(v)));

  static dynamic _decodeFirestoreValue(dynamic v) {
    if (v is Map && v.containsKey('_tsMs') && v.length == 1) {
      final ms = v['_tsMs'];
      if (ms is num) return Timestamp.fromMillisecondsSinceEpoch(ms.toInt());
    }
    if (v is Map) {
      return v.map(
        (k, val) => MapEntry(k.toString(), _decodeFirestoreValue(val)),
      );
    }
    if (v is List) return v.map(_decodeFirestoreValue).toList();
    return v;
  }

  static Map<String, dynamic> _decodeFirestoreMap(Map<String, dynamic> m) =>
      m.map((k, v) => MapEntry(k, _decodeFirestoreValue(v)));
}
