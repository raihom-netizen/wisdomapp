import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'course_analytics_service.dart';

/// Progresso e «gostei» por curso — local (rápido) + Firestore (sincroniza entre aparelhos).
class CourseProgress {
  const CourseProgress({
    this.liked = false,
    this.positionSeconds = 0,
    this.durationSeconds = 0,
  });

  final bool liked;
  final double positionSeconds;
  final double durationSeconds;

  /// Resume automático desligado — o usuário controla a posição no player.
  bool get hasResume => false;

  double get progressFraction {
    if (durationSeconds <= 0) return 0;
    return (positionSeconds / durationSeconds).clamp(0.0, 1.0);
  }

  String get resumeLabel {
    final total = positionSeconds.round();
    final m = total ~/ 60;
    final s = total % 60;
    if (m <= 0) return 'Continuar · ${s}s';
    return 'Continuar · $m:${s.toString().padLeft(2, '0')}';
  }

  CourseProgress copyWith({
    bool? liked,
    double? positionSeconds,
    double? durationSeconds,
  }) {
    return CourseProgress(
      liked: liked ?? this.liked,
      positionSeconds: positionSeconds ?? this.positionSeconds,
      durationSeconds: durationSeconds ?? this.durationSeconds,
    );
  }

  Map<String, dynamic> toJson() => {
        'liked': liked,
        'positionSeconds': positionSeconds,
        'durationSeconds': durationSeconds,
      };

  factory CourseProgress.fromJson(Map<String, dynamic>? m) {
    if (m == null) return const CourseProgress();
    return CourseProgress(
      liked: m['liked'] == true,
      positionSeconds: (m['positionSeconds'] as num?)?.toDouble() ?? 0,
      durationSeconds: (m['durationSeconds'] as num?)?.toDouble() ?? 0,
    );
  }
}

class CourseProgressService {
  CourseProgressService._();
  static final CourseProgressService instance = CourseProgressService._();

  static const _prefsKey = 'course_progress_v1';

  final Map<String, CourseProgress> _cache = {};
  final _controller = StreamController<String>.broadcast();
  SharedPreferences? _prefs;
  var _loaded = false;
  DateTime? _lastCloudWrite;
  String? _uid;

  Stream<String> get changes => _controller.stream;

  Future<void> bindUser(String uid) async {
    if (_uid == uid && _loaded) return;
    _uid = uid;
    await _ensurePrefs();
    await _loadLocal();
    unawaited(_pullCloud());
  }

  CourseProgress of(String courseId) {
    if (courseId.isEmpty) return const CourseProgress();
    return _cache[courseId] ?? const CourseProgress();
  }

  Future<void> toggleLike(
    String courseId, {
    String? title,
    String? type,
  }) async {
    if (courseId.isEmpty) return;
    final cur = of(courseId);
    final next = !cur.liked;
    await _save(courseId, cur.copyWith(liked: next));
    final uid = _uid;
    if (uid != null && uid.isNotEmpty) {
      unawaited(
        CourseAnalyticsService.instance.reportLike(
          uid: uid,
          courseId: courseId,
          liked: next,
          title: title,
          type: type,
        ),
      );
    }
  }

  Future<void> setLiked(
    String courseId,
    bool liked, {
    String? title,
    String? type,
  }) async {
    if (courseId.isEmpty) return;
    final cur = of(courseId);
    if (cur.liked == liked) return;
    await _save(courseId, cur.copyWith(liked: liked));
    final uid = _uid;
    if (uid != null && uid.isNotEmpty) {
      unawaited(
        CourseAnalyticsService.instance.reportLike(
          uid: uid,
          courseId: courseId,
          liked: liked,
          title: title,
          type: type,
        ),
      );
    }
  }

  /// Memória/resume de posição desligada (travava o player ao remontar o embed).
  /// Mantém só telemetria leve para analytics admin — sem gravar posição local/cloud.
  Future<void> savePosition(
    String courseId, {
    required double positionSeconds,
    double? durationSeconds,
    String? title,
    String? type,
  }) async {
    if (courseId.isEmpty) return;
    if (positionSeconds < 12) return;
    final uid = _uid;
    if (uid == null || uid.isEmpty) return;
    final now = DateTime.now();
    if (_lastCloudWrite != null &&
        now.difference(_lastCloudWrite!) < const Duration(seconds: 20)) {
      return;
    }
    _lastCloudWrite = now;
    unawaited(
      CourseAnalyticsService.instance.reportWatch(
        uid: uid,
        courseId: courseId,
        positionSeconds: positionSeconds,
        durationSeconds: durationSeconds ?? 0,
        title: title,
        type: type,
      ),
    );
  }

  Future<void> clearPosition(String courseId) async {
    if (courseId.isEmpty) return;
    await _save(courseId, of(courseId).copyWith(positionSeconds: 0));
  }

  Future<void> _save(String courseId, CourseProgress p) async {
    _cache[courseId] = p;
    _controller.add(courseId);
    await _ensurePrefs();
    final map = <String, dynamic>{};
    for (final e in _cache.entries) {
      map[e.key] = e.value.toJson();
    }
    await _prefs!.setString(_prefsKey, jsonEncode(map));
    unawaited(_pushCloud(courseId, p));
  }

  Future<void> _ensurePrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<void> _loadLocal() async {
    await _ensurePrefs();
    final raw = _prefs!.getString(_prefsKey);
    _cache.clear();
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final e in decoded.entries) {
            final v = e.value;
            if (v is Map) {
              _cache[e.key.toString()] =
                  CourseProgress.fromJson(Map<String, dynamic>.from(v));
            }
          }
        }
      } catch (_) {}
    }
    _loaded = true;
  }

  Future<void> _pullCloud() async {
    final uid = _uid;
    if (uid == null || uid.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('course_progress')
          .get();
      var changed = false;
      for (final doc in snap.docs) {
        final cloud = CourseProgress.fromJson(doc.data());
        final local = _cache[doc.id];
        if (local == null ||
            cloud.positionSeconds > local.positionSeconds ||
            (cloud.liked && !local.liked)) {
          _cache[doc.id] = CourseProgress(
            liked: cloud.liked || (local?.liked ?? false),
            positionSeconds: cloud.positionSeconds >= (local?.positionSeconds ?? 0)
                ? cloud.positionSeconds
                : local!.positionSeconds,
            durationSeconds: cloud.durationSeconds > 0
                ? cloud.durationSeconds
                : (local?.durationSeconds ?? 0),
          );
          changed = true;
          _controller.add(doc.id);
        }
      }
      if (changed) {
        await _ensurePrefs();
        final map = <String, dynamic>{};
        for (final e in _cache.entries) {
          map[e.key] = e.value.toJson();
        }
        await _prefs!.setString(_prefsKey, jsonEncode(map));
      }
    } catch (_) {}
  }

  Future<void> _pushCloud(String courseId, CourseProgress p) async {
    final uid = _uid;
    if (uid == null || uid.isEmpty) return;
    final now = DateTime.now();
    if (_lastCloudWrite != null &&
        now.difference(_lastCloudWrite!) < const Duration(seconds: 2)) {
      // batch leve: ainda grava like imediatamente
      if (!p.liked && of(courseId).liked == p.liked) {
        // ok continue
      }
    }
    _lastCloudWrite = now;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('course_progress')
          .doc(courseId)
          .set({
        ...p.toJson(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }
}
