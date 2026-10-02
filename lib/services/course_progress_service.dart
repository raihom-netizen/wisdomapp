import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'course_analytics_service.dart';

/// Progresso de uma aula (vídeo) dentro do curso.
class CourseLessonProgress {
  const CourseLessonProgress({
    this.positionSeconds = 0,
    this.durationSeconds = 0,
    this.done = false,
  });

  final double positionSeconds;
  final double durationSeconds;
  final bool done;

  /// A partir de 92% assistido a aula conta como concluída.
  static const doneThreshold = 0.92;

  double get fraction {
    if (done) return 1;
    if (durationSeconds <= 0) return 0;
    return (positionSeconds / durationSeconds).clamp(0.0, 1.0);
  }

  /// Retomar só quando faz sentido (passou de 10 s e não terminou).
  bool get canResume => !done && positionSeconds >= 10;

  Map<String, dynamic> toJson() => {
        'p': positionSeconds,
        'd': durationSeconds,
        // Sempre grava (merge do Firestore é profundo: omitir manteria `true`).
        'done': done,
      };

  factory CourseLessonProgress.fromJson(Map<String, dynamic>? m) {
    if (m == null) return const CourseLessonProgress();
    return CourseLessonProgress(
      positionSeconds: (m['p'] as num?)?.toDouble() ?? 0,
      durationSeconds: (m['d'] as num?)?.toDouble() ?? 0,
      done: m['done'] == true,
    );
  }

  CourseLessonProgress mergeWith(CourseLessonProgress other) {
    return CourseLessonProgress(
      positionSeconds: positionSeconds >= other.positionSeconds
          ? positionSeconds
          : other.positionSeconds,
      durationSeconds:
          durationSeconds > 0 ? durationSeconds : other.durationSeconds,
      done: done || other.done,
    );
  }
}

/// Progresso e «gostei» por curso — local (rápido) + Firestore (sincroniza entre aparelhos).
class CourseProgress {
  const CourseProgress({
    this.liked = false,
    this.positionSeconds = 0,
    this.durationSeconds = 0,
    this.lessons = const {},
    this.lastLessonKey,
    this.lastOpenedMs = 0,
  });

  final bool liked;
  final double positionSeconds;
  final double durationSeconds;

  /// Aulas assistidas (chave = id estável da aula, ver `CourseLessons`).
  final Map<String, CourseLessonProgress> lessons;

  /// Última aula aberta — base do «Continuar de onde parou».
  final String? lastLessonKey;
  final int lastOpenedMs;

  /// Resume automático do embed desligado — o «Continuar» é explícito na tela do curso.
  bool get hasResume => false;

  bool get hasActivity => lastOpenedMs > 0 || lessons.isNotEmpty;

  CourseLessonProgress lesson(String key) =>
      lessons[key] ?? const CourseLessonProgress();

  /// Fração do curso (média das aulas) dado o conjunto de aulas.
  double courseFraction(Iterable<String> lessonKeys) {
    final keys = lessonKeys.toList();
    if (keys.isEmpty) return 0;
    var sum = 0.0;
    for (final k in keys) {
      sum += lesson(k).fraction;
    }
    return (sum / keys.length).clamp(0.0, 1.0);
  }

  int doneCount(Iterable<String> lessonKeys) =>
      lessonKeys.where((k) => lessons[k]?.done == true).length;

  bool isCompleted(Iterable<String> lessonKeys) {
    final keys = lessonKeys.toList();
    if (keys.isEmpty) return false;
    return keys.every((k) => lessons[k]?.done == true);
  }

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
    Map<String, CourseLessonProgress>? lessons,
    String? lastLessonKey,
    int? lastOpenedMs,
  }) {
    return CourseProgress(
      liked: liked ?? this.liked,
      positionSeconds: positionSeconds ?? this.positionSeconds,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      lessons: lessons ?? this.lessons,
      lastLessonKey: lastLessonKey ?? this.lastLessonKey,
      lastOpenedMs: lastOpenedMs ?? this.lastOpenedMs,
    );
  }

  Map<String, dynamic> toJson() => {
        'liked': liked,
        'positionSeconds': positionSeconds,
        'durationSeconds': durationSeconds,
        if (lessons.isNotEmpty)
          'lessons': {
            for (final e in lessons.entries) e.key: e.value.toJson(),
          },
        if (lastLessonKey != null) 'lastLessonKey': lastLessonKey,
        if (lastOpenedMs > 0) 'lastOpenedMs': lastOpenedMs,
      };

  factory CourseProgress.fromJson(Map<String, dynamic>? m) {
    if (m == null) return const CourseProgress();
    final rawLessons = m['lessons'];
    final lessons = <String, CourseLessonProgress>{};
    if (rawLessons is Map) {
      for (final e in rawLessons.entries) {
        final v = e.value;
        if (v is Map) {
          lessons[e.key.toString()] =
              CourseLessonProgress.fromJson(Map<String, dynamic>.from(v));
        }
      }
    }
    final last = (m['lastLessonKey'] ?? '').toString().trim();
    return CourseProgress(
      liked: m['liked'] == true,
      positionSeconds: (m['positionSeconds'] as num?)?.toDouble() ?? 0,
      durationSeconds: (m['durationSeconds'] as num?)?.toDouble() ?? 0,
      lessons: lessons,
      lastLessonKey: last.isEmpty ? null : last,
      lastOpenedMs: (m['lastOpenedMs'] as num?)?.toInt() ?? 0,
    );
  }

  /// União local × nuvem (maior posição, concluída vence, acesso mais recente).
  CourseProgress mergeWith(CourseProgress other) {
    final merged = <String, CourseLessonProgress>{...lessons};
    for (final e in other.lessons.entries) {
      final cur = merged[e.key];
      merged[e.key] = cur == null ? e.value : cur.mergeWith(e.value);
    }
    final newer = other.lastOpenedMs > lastOpenedMs ? other : this;
    return CourseProgress(
      liked: liked || other.liked,
      positionSeconds: positionSeconds >= other.positionSeconds
          ? positionSeconds
          : other.positionSeconds,
      durationSeconds:
          durationSeconds > 0 ? durationSeconds : other.durationSeconds,
      lessons: merged,
      lastLessonKey:
          newer.lastLessonKey ?? lastLessonKey ?? other.lastLessonKey,
      lastOpenedMs:
          lastOpenedMs > other.lastOpenedMs ? lastOpenedMs : other.lastOpenedMs,
    );
  }
}

class CourseProgressService with WidgetsBindingObserver {
  CourseProgressService._();
  static final CourseProgressService instance = CourseProgressService._();

  /// Chave antiga (sem dono) — de antes da separação por conta. Não dá para
  /// saber de quem era, então é DESCARTADA (o progresso real está na nuvem).
  static const _legacyPrefsKey = 'course_progress_v1';

  /// Progresso local é por conta: duas contas no mesmo aparelho não se misturam.
  static String _prefsKeyFor(String uid) => 'course_progress_v1_$uid';

  final Map<String, CourseProgress> _cache = {};
  final _controller = StreamController<String>.broadcast();
  SharedPreferences? _prefs;
  var _loaded = false;
  DateTime? _lastCloudWrite;
  DateTime? _lastLessonPersist;
  String? _uid;

  /// Cursos com progresso em memória ainda não gravado (gravação espaçada).
  final Set<String> _dirty = {};
  StreamSubscription<User?>? _authSub;
  var _observing = false;

  Stream<String> get changes => _controller.stream;

  /// Conta atualmente vinculada (null = ninguém logado / após logout).
  String? get boundUid => _uid;

  Future<void> bindUser(String uid) async {
    _ensureWatchers();
    if (uid.isEmpty) return;
    if (_uid == uid && _loaded) return;
    if (_uid != null && _uid != uid) {
      // Troca de conta: grava o pendente da conta anterior e zera a memória.
      await flushAll();
      _resetMemory();
    }
    _uid = uid;
    await _ensurePrefs();
    if (_uid != uid) return;
    await _loadLocal(uid);
    if (_uid != uid) return; // trocou de conta durante a leitura
    unawaited(_pullCloud());
  }

  /// Logout / troca de conta: memória zerada (nada da conta anterior aparece
  /// nem sobe para a nuvem da próxima).
  Future<void> unbind() async {
    if (_uid == null) return;
    await flushAll();
    _resetMemory();
  }

  void _resetMemory() {
    final ids = _cache.keys.toList();
    _cache.clear();
    _dirty.clear();
    _uid = null;
    _loaded = false;
    _lastCloudWrite = null;
    _lastLessonPersist = null;
    for (final id in ids) {
      _controller.add(id);
    }
  }

  void _ensureWatchers() {
    try {
      _authSub ??= FirebaseAuth.instance.authStateChanges().listen((user) {
        final cur = _uid;
        if (cur == null) return;
        if (user == null || user.uid != cur) unawaited(unbind());
      });
    } catch (_) {
      // Firebase não inicializado (testes) — segue sem o vigia de logout.
    }
    if (!_observing) {
      _observing = true;
      WidgetsBinding.instance.addObserver(this);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App indo para segundo plano / fechando: grava o que estava em memória.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(flushAll());
    }
  }

  /// Grava já (local + nuvem) o progresso pendente do curso — chamar ao sair
  /// da tela do curso/player, para não perder os últimos segundos.
  Future<void> flush(String courseId) async {
    if (courseId.isEmpty || !_dirty.contains(courseId)) return;
    final uid = _uid;
    final p = _cache[courseId];
    _dirty.remove(courseId);
    if (uid == null || p == null) return;
    _lastLessonPersist = DateTime.now();
    await _persistLocal();
    await _pushCloud(courseId, p, ownerUid: uid);
  }

  /// Grava todos os cursos com progresso pendente.
  Future<void> flushAll() async {
    if (_dirty.isEmpty) return;
    final uid = _uid;
    final ids = _dirty.toList();
    _dirty.clear();
    if (uid == null) return;
    _lastLessonPersist = DateTime.now();
    await _persistLocal();
    for (final id in ids) {
      final p = _cache[id];
      if (p != null) await _pushCloud(id, p, ownerUid: uid);
    }
  }

  CourseProgress of(String courseId) {
    if (courseId.isEmpty) return const CourseProgress();
    return _cache[courseId] ?? const CourseProgress();
  }

  /// Cursos com atividade, do acesso mais recente para o mais antigo.
  List<MapEntry<String, CourseProgress>> recentCourses() {
    final list = _cache.entries.where((e) => e.value.lastOpenedMs > 0).toList()
      ..sort((a, b) => b.value.lastOpenedMs.compareTo(a.value.lastOpenedMs));
    return list;
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

  /// Marca a aula aberta (base do «Continuar de onde parou»).
  Future<void> markLessonOpened(String courseId, String lessonKey) async {
    if (courseId.isEmpty || lessonKey.isEmpty) return;
    final cur = of(courseId);
    await _save(
      courseId,
      cur.copyWith(
        lastLessonKey: lessonKey,
        lastOpenedMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// Marca/desmarca aula como concluída (manual pelo aluno).
  Future<void> setLessonDone(
    String courseId,
    String lessonKey,
    bool done,
  ) async {
    if (courseId.isEmpty || lessonKey.isEmpty) return;
    final cur = of(courseId);
    final l = cur.lesson(lessonKey);
    final next = CourseLessonProgress(
      positionSeconds: done ? l.positionSeconds : 0,
      durationSeconds: l.durationSeconds,
      done: done,
    );
    await _save(
      courseId,
      cur.copyWith(lessons: {...cur.lessons, lessonKey: next}),
    );
  }

  /// Zera o progresso do curso (mantém o «gostei»).
  Future<void> resetCourse(String courseId) async {
    if (courseId.isEmpty) return;
    final p = CourseProgress(liked: of(courseId).liked);
    _cache[courseId] = p;
    _dirty.remove(courseId);
    _controller.add(courseId);
    await _persistLocal();
    final uid = _uid;
    if (uid == null || uid.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('course_progress')
          .doc(courseId)
          .set({
        ...p.toJson(),
        'lessons': FieldValue.delete(),
        'lastLessonKey': FieldValue.delete(),
        'lastOpenedMs': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Progresso vindo do player (a cada ~4 s). Memória imediata + gravação
  /// espaçada. Quem escuta NÃO deve trocar parâmetros do embed (remontaria).
  Future<void> recordLessonProgress(
    String courseId,
    String lessonKey, {
    required double positionSeconds,
    required double durationSeconds,
    String? title,
    String? type,
  }) async {
    if (courseId.isEmpty || lessonKey.isEmpty) return;
    final uid = _uid;
    if (uid == null || uid.isEmpty) return;
    if (positionSeconds.isNaN || durationSeconds.isNaN) return;
    if (positionSeconds <= 0 && durationSeconds <= 0) return;
    final cur = of(courseId);
    final prev = cur.lesson(lessonKey);
    final dur = durationSeconds > 0 ? durationSeconds : prev.durationSeconds;
    final reachedEnd =
        dur > 0 && positionSeconds / dur >= CourseLessonProgress.doneThreshold;
    final next = CourseLessonProgress(
      positionSeconds: positionSeconds,
      durationSeconds: dur,
      done: prev.done || reachedEnd,
    );
    final updated = cur.copyWith(
      lessons: {...cur.lessons, lessonKey: next},
      lastLessonKey: lessonKey,
      lastOpenedMs: DateTime.now().millisecondsSinceEpoch,
    );
    _cache[courseId] = updated;
    _dirty.add(courseId);
    _controller.add(courseId);

    final now = DateTime.now();
    final justFinished = next.done && !prev.done;
    if (justFinished ||
        _lastLessonPersist == null ||
        now.difference(_lastLessonPersist!) >= const Duration(seconds: 15)) {
      _lastLessonPersist = now;
      _dirty.remove(courseId);
      await _persistLocal();
      unawaited(_pushCloud(courseId, updated, ownerUid: uid));
    }
    unawaited(savePosition(
      courseId,
      positionSeconds: positionSeconds,
      durationSeconds: dur,
      title: title,
      type: type,
    ));
  }

  Future<void> clearPosition(String courseId) async {
    if (courseId.isEmpty) return;
    await _save(courseId, of(courseId).copyWith(positionSeconds: 0));
  }

  Future<void> _save(String courseId, CourseProgress p) async {
    final uid = _uid;
    // Sem conta vinculada não há onde guardar (evita misturar contas).
    if (uid == null || uid.isEmpty) return;
    _cache[courseId] = p;
    _dirty.remove(courseId);
    _controller.add(courseId);
    await _persistLocal();
    unawaited(_pushCloud(courseId, p, ownerUid: uid));
  }

  Future<void> _persistLocal() async {
    final uid = _uid;
    if (uid == null || uid.isEmpty) return;
    await _ensurePrefs();
    // A conta pode ter mudado durante o await acima.
    if (_uid != uid) return;
    final map = <String, dynamic>{};
    for (final e in _cache.entries) {
      map[e.key] = e.value.toJson();
    }
    await _prefs!.setString(_prefsKeyFor(uid), jsonEncode(map));
  }

  Future<void> _ensurePrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<void> _loadLocal(String uid) async {
    await _ensurePrefs();
    // Chave antiga sem dono: descarta (podia ser de outra conta do aparelho).
    if (_prefs!.containsKey(_legacyPrefsKey)) {
      try {
        await _prefs!.remove(_legacyPrefsKey);
      } catch (_) {}
    }
    final raw = _prefs!.getString(_prefsKeyFor(uid));
    _cache.clear();
    _dirty.clear();
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
      // Trocou de conta enquanto buscava: não mistura.
      if (_uid != uid) return;
      var changed = false;
      for (final doc in snap.docs) {
        final cloud = CourseProgress.fromJson(doc.data());
        final local = _cache[doc.id];
        final merged = local == null ? cloud : local.mergeWith(cloud);
        if (local == null ||
            jsonEncode(merged.toJson()) != jsonEncode(local.toJson())) {
          _cache[doc.id] = merged;
          changed = true;
          _controller.add(doc.id);
        }
      }
      if (changed) await _persistLocal();
    } catch (_) {}
  }

  /// Sobe o progresso de [ownerUid] — e só se essa ainda for a conta ativa
  /// (nunca grava progresso de uma conta na nuvem de outra).
  Future<void> _pushCloud(
    String courseId,
    CourseProgress p, {
    String? ownerUid,
  }) async {
    final uid = _uid;
    if (uid == null || uid.isEmpty) return;
    if (ownerUid != null && ownerUid != uid) return;
    try {
      final authUid = FirebaseAuth.instance.currentUser?.uid;
      if (authUid != null && authUid != uid) return;
    } catch (_) {}
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
