import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

/// Estatísticas agregadas de um curso/dica (painel admin).
class CourseStatSummary {
  const CourseStatSummary({
    required this.courseId,
    this.title = '',
    this.type = 'curso',
    this.viewCount = 0,
    this.likeCount = 0,
    this.playCount = 0,
    this.lastActivityAt,
    this.daily = const {},
  });

  final String courseId;
  final String title;
  final String type;
  final int viewCount;
  final int likeCount;
  final int playCount;
  final DateTime? lastActivityAt;
  final Map<String, int> daily;

  factory CourseStatSummary.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? {};
    final dailyRaw = d['daily'];
    final daily = <String, int>{};
    if (dailyRaw is Map) {
      for (final e in dailyRaw.entries) {
        daily[e.key.toString()] = (e.value as num?)?.toInt() ?? 0;
      }
    }
    DateTime? last;
    final ts = d['lastActivityAt'];
    if (ts is Timestamp) last = ts.toDate();
    return CourseStatSummary(
      courseId: doc.id,
      title: (d['title'] ?? '').toString(),
      type: (d['type'] ?? 'curso').toString(),
      viewCount: (d['viewCount'] as num?)?.toInt() ?? 0,
      likeCount: (d['likeCount'] as num?)?.toInt() ?? 0,
      playCount: (d['playCount'] as num?)?.toInt() ?? 0,
      lastActivityAt: last,
      daily: daily,
    );
  }
}

/// Um usuário que assistiu / curtiu o conteúdo.
class CourseViewerRow {
  const CourseViewerRow({
    required this.uid,
    this.name = '',
    this.liked = false,
    this.positionSeconds = 0,
    this.durationSeconds = 0,
    this.watchCount = 0,
    this.lastWatchedAt,
  });

  final String uid;
  final String name;
  final bool liked;
  final double positionSeconds;
  final double durationSeconds;
  final int watchCount;
  final DateTime? lastWatchedAt;

  double get progressFraction {
    if (durationSeconds <= 0) return 0;
    return (positionSeconds / durationSeconds).clamp(0.0, 1.0);
  }

  factory CourseViewerRow.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? {};
    DateTime? last;
    final ts = d['lastWatchedAt'];
    if (ts is Timestamp) last = ts.toDate();
    return CourseViewerRow(
      uid: doc.id,
      name: (d['name'] ?? '').toString(),
      liked: d['liked'] == true,
      positionSeconds: (d['positionSeconds'] as num?)?.toDouble() ?? 0,
      durationSeconds: (d['durationSeconds'] as num?)?.toDouble() ?? 0,
      watchCount: (d['watchCount'] as num?)?.toInt() ?? 0,
      lastWatchedAt: last,
    );
  }
}

/// Agrega visualizações e curtidas em `course_stats` para o painel admin.
class CourseAnalyticsService {
  CourseAnalyticsService._();
  static final CourseAnalyticsService instance = CourseAnalyticsService._();

  final _db = FirebaseFirestore.instance;
  final Set<String> _viewCountedLocal = {};
  final Set<String> _dailyCountedLocal = {};
  DateTime? _lastWatchReport;

  CollectionReference<Map<String, dynamic>> get _stats =>
      _db.collection('course_stats');

  Stream<List<CourseStatSummary>> watchAllStats() {
    return _stats.snapshots().map(
          (s) => s.docs.map(CourseStatSummary.fromDoc).toList(),
        );
  }

  Stream<CourseStatSummary?> watchStat(String courseId) {
    if (courseId.isEmpty) return Stream.value(null);
    return _stats.doc(courseId).snapshots().map((d) {
      if (!d.exists) return null;
      return CourseStatSummary.fromDoc(d);
    });
  }

  Stream<List<CourseViewerRow>> watchViewers(String courseId) {
    if (courseId.isEmpty) return Stream.value(const []);
    return _stats
        .doc(courseId)
        .collection('viewers')
        .orderBy('lastWatchedAt', descending: true)
        .limit(80)
        .snapshots()
        .map((s) => s.docs.map(CourseViewerRow.fromDoc).toList());
  }

  Future<List<CourseStatSummary>> fetchAllStats() async {
    final snap = await _stats.get();
    return snap.docs.map(CourseStatSummary.fromDoc).toList();
  }

  String _dayKey([DateTime? at]) {
    final d = at ?? DateTime.now();
    return DateFormat('yyyy-MM-dd').format(d);
  }

  Future<String> _resolveUserName(String uid) async {
    try {
      final authName = FirebaseAuth.instance.currentUser?.displayName?.trim();
      if (authName != null && authName.isNotEmpty) return authName;
      final doc = await _db.collection('users').doc(uid).get();
      final d = doc.data();
      if (d == null) return uid;
      final name = (d['name'] ?? d['displayName'] ?? '').toString().trim();
      if (name.isNotEmpty) return name;
      final email = (d['email'] ?? '').toString().trim();
      if (email.contains('@')) return email.split('@').first;
    } catch (_) {}
    return uid.length > 8 ? uid.substring(0, 8) : uid;
  }

  /// Registra curtida (±1) no agregado e no doc do viewer.
  Future<void> reportLike({
    required String uid,
    required String courseId,
    required bool liked,
    String? title,
    String? type,
  }) async {
    if (uid.isEmpty || courseId.isEmpty) return;
    final name = await _resolveUserName(uid);
    final viewerRef = _stats.doc(courseId).collection('viewers').doc(uid);
    final statsRef = _stats.doc(courseId);

    try {
      await _db.runTransaction((tx) async {
        final viewerSnap = await tx.get(viewerRef);
        final prevLiked = viewerSnap.data()?['liked'] == true;
        if (prevLiked == liked) {
          tx.set(
            viewerRef,
            {
              'liked': liked,
              'name': name,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
          return;
        }
        final delta = liked ? 1 : -1;
        tx.set(
          statsRef,
          {
            if (title != null && title.isNotEmpty) 'title': title,
            if (type != null && type.isNotEmpty) 'type': type,
            'likeCount': FieldValue.increment(delta),
            'lastActivityAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        tx.set(
          viewerRef,
          {
            'liked': liked,
            'name': name,
            'uid': uid,
            'updatedAt': FieldValue.serverTimestamp(),
            'lastWatchedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });
    } catch (_) {
      // fallback sem transaction (regras / offline)
      try {
        await statsRef.set({
          if (title != null && title.isNotEmpty) 'title': title,
          if (type != null && type.isNotEmpty) 'type': type,
          'likeCount': FieldValue.increment(liked ? 1 : -1),
          'lastActivityAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        await viewerRef.set({
          'liked': liked,
          'name': name,
          'uid': uid,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {}
    }
  }

  /// Registra visualização / progresso (throttle no caller).
  Future<void> reportWatch({
    required String uid,
    required String courseId,
    required double positionSeconds,
    double durationSeconds = 0,
    String? title,
    String? type,
  }) async {
    if (uid.isEmpty || courseId.isEmpty) return;
    if (positionSeconds < 8) return;

    final now = DateTime.now();
    if (_lastWatchReport != null &&
        now.difference(_lastWatchReport!) < const Duration(seconds: 8)) {
      // ainda permite like; aqui só reduz spam de watch
    }
    _lastWatchReport = now;

    final name = await _resolveUserName(uid);
    final day = _dayKey(now);
    final localViewKey = '$uid|$courseId';
    final localDailyKey = '$uid|$courseId|$day';
    final viewerRef = _stats.doc(courseId).collection('viewers').doc(uid);
    final statsRef = _stats.doc(courseId);

    try {
      final viewerSnap = await viewerRef.get();
      final exists = viewerSnap.exists;
      final data = viewerSnap.data() ?? {};
      final lastDaily = (data['lastDailyKey'] ?? '').toString();
      final isNewViewer = !exists && !_viewCountedLocal.contains(localViewKey);
      final isNewDay = lastDaily != day && !_dailyCountedLocal.contains(localDailyKey);

      if (isNewViewer) _viewCountedLocal.add(localViewKey);
      if (isNewDay) _dailyCountedLocal.add(localDailyKey);

      final updates = <String, dynamic>{
        if (title != null && title.isNotEmpty) 'title': title,
        if (type != null && type.isNotEmpty) 'type': type,
        'lastActivityAt': FieldValue.serverTimestamp(),
        // reprodução = nova sessão do dia (evita inflar a cada timeupdate)
        if (isNewDay || isNewViewer) 'playCount': FieldValue.increment(1),
        if (isNewViewer) 'viewCount': FieldValue.increment(1),
        if (isNewDay) 'daily.$day': FieldValue.increment(1),
      };

      await statsRef.set(updates, SetOptions(merge: true));
      await viewerRef.set({
        'uid': uid,
        'name': name,
        'positionSeconds': positionSeconds,
        'durationSeconds': durationSeconds,
        'lastWatchedAt': FieldValue.serverTimestamp(),
        'lastDailyKey': day,
        'watchCount': FieldValue.increment(1),
        if (!exists) 'firstWatchedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Garante metadados do conteúdo no doc de stats (título/tipo).
  Future<void> ensureCourseMeta({
    required String courseId,
    required String title,
    required String type,
  }) async {
    if (courseId.isEmpty) return;
    try {
      await _stats.doc(courseId).set({
        'title': title,
        'type': type,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }
}
