import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/course_certificate_service.dart';
import '../services/course_progress_service.dart';
import '../utils/course_lessons.dart';
import '../utils/course_share.dart';
import '../widgets/course_media_preview.dart';
import '../widgets/course_video/course_comments_section.dart';
import '../widgets/course_video/course_video_controller.dart';
import '../widgets/course_video/course_video_player_shell.dart';
import '../widgets/course/course_yt_palette.dart';

// Fundo/superfícies seguem o tema (claro = branco estilo YouTube; escuro = #0F0F0F)
// via [CourseYt]. Só o player e a tela cheia continuam pretos.
const _kRed = CourseYt.red;
const _kGreen = Color(0xFF22C55E);

/// «Voltar» das telas de curso/vídeo: fecha a tela; se não houver tela
/// anterior (aberta por link direto ou após recarregar na web), vai ao início.
void courseScreenGoBack(BuildContext context) {
  final nav = Navigator.of(context);
  if (nav.canPop()) {
    nav.pop();
  } else {
    nav.pushNamedAndRemoveUntil('/', (_) => false);
  }
}

/// Abre a tela do curso (aulas, progresso, continuar de onde parou).
Future<void> openCourseDetail(
  BuildContext context, {
  required Map<String, dynamic> data,
  required String uid,
  bool continueWhereStopped = false,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CourseDetailScreen(
        data: data,
        uid: uid,
        continueWhereStopped: continueWhereStopped,
      ),
    ),
  );
}

/// Tela do curso — player no topo (mesmo `CourseVideoPlayerShell` do módulo),
/// lista de aulas com progresso, «Continuar» e tela cheia.
class CourseDetailScreen extends StatefulWidget {
  const CourseDetailScreen({
    super.key,
    required this.data,
    required this.uid,
    this.continueWhereStopped = false,
  });

  final Map<String, dynamic> data;
  final String uid;
  final bool continueWhereStopped;

  @override
  State<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends State<CourseDetailScreen> {
  final _svc = CourseProgressService.instance;
  StreamSubscription<String>? _sub;

  /// Mapa estável — o player compara por identidade (trocar remontaria o vídeo).
  late final Map<String, dynamic> _posterData = Map.unmodifiable(widget.data);

  List<CourseLesson> _lessons = const [];
  var _loadingLessons = true;
  int _current = 0;
  String? _currentMp4;
  var _resolvingMp4 = false;

  /// Parâmetros do player fixados ao abrir a aula (nunca mudam durante a reprodução).
  var _autoplay = false;
  double _startAt = 0;
  int _playNonce = 0;

  var _descExpanded = true;
  CourseProgress _progress = const CourseProgress();

  String get _courseId => (widget.data['id'] ?? '').toString();
  String get _title => (widget.data['title'] ?? 'Curso').toString();

  String get _description {
    final body = (widget.data['bodyText'] ?? '').toString().trim();
    if (body.isNotEmpty) return body;
    return (widget.data['description'] ?? '').toString().trim();
  }

  CourseLesson? get _lesson =>
      _lessons.isEmpty ? null : _lessons[_current.clamp(0, _lessons.length - 1)];

  Iterable<String> get _keys => _lessons.map((l) => l.key);

  @override
  void initState() {
    super.initState();
    unawaited(_svc.bindUser(widget.uid));
    _progress = _svc.of(_courseId);
    _sub = _svc.changes.listen((id) {
      if (id != _courseId || !mounted) return;
      setState(() => _progress = _svc.of(_courseId));
    });
    unawaited(_loadLessons());
  }

  @override
  void dispose() {
    _sub?.cancel();
    // Grava os últimos segundos assistidos (a gravação normal é espaçada).
    unawaited(_svc.flush(_courseId));
    super.dispose();
  }

  /// Carga horária (min): a informada pelo admin ou a soma das aulas.
  int get _workloadMinutes {
    final declared = CourseLessons.declaredMinutes(widget.data);
    if (declared != null) return declared;
    var secs = 0.0;
    for (final k in _keys) {
      final d = _progress.lesson(k).durationSeconds;
      if (d <= 0) return 0;
      secs += d;
    }
    return (secs / 60).ceil();
  }

  Future<void> _openCertificate() async {
    final keys = _keys.toList();
    if (!_progress.isCompleted(keys)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('O certificado sai quando todas as aulas estiverem concluídas.'),
      ));
      return;
    }
    await CourseCertificateService.openCertificate(
      context,
      uid: widget.uid,
      courseId: _courseId,
      courseTitle: _title,
      lessonCount: keys.length,
      workloadMinutes: _workloadMinutes,
    );
  }

  void _share() => CourseShare.share(context, widget.data);

  Future<void> _loadLessons() async {
    var lessons = CourseLessons.fromData(widget.data);
    if (lessons.isEmpty) {
      try {
        lessons = await CourseLessons.discoverFromStorage(
          widget.data,
          docId: _courseId,
        ).timeout(const Duration(seconds: 30));
      } catch (_) {
        lessons = const [];
      }
    }
    if (!mounted) return;
    var start = 0;
    final last = _progress.lastLessonKey;
    if (last != null) {
      final i = lessons.indexWhere((l) => l.key == last);
      if (i >= 0) start = i;
    } else {
      final i = lessons.indexWhere((l) => !_progress.lesson(l.key).done);
      if (i >= 0) start = i;
    }
    setState(() {
      _lessons = lessons;
      _loadingLessons = false;
    });
    await _openLesson(
      start,
      autoplay: widget.continueWhereStopped,
      // Mesmo sem autoplay, tocar na capa retoma de onde parou.
      resume: true,
      markOpened: false,
    );
  }

  Future<void> _openLesson(
    int index, {
    bool autoplay = true,
    bool resume = true,
    bool markOpened = true,
  }) async {
    if (_lessons.isEmpty) return;
    final lesson = _lessons[index.clamp(0, _lessons.length - 1)];
    final lp = _progress.lesson(lesson.key);
    setState(() {
      _current = index;
      _autoplay = autoplay;
      _startAt = (resume && lp.canResume) ? lp.positionSeconds : 0;
      _playNonce++;
      _currentMp4 = null;
      _resolvingMp4 = !lesson.isYoutube;
    });
    if (markOpened || autoplay) {
      unawaited(_svc.markLessonOpened(_courseId, lesson.key));
    }
    if (!lesson.isYoutube) {
      final url = await CourseLessons.resolveMp4(lesson);
      if (!mounted || _lesson?.key != lesson.key) return;
      setState(() {
        _currentMp4 = url;
        _resolvingMp4 = false;
      });
    }
  }

  void _onProgress(double position, double duration) {
    final lesson = _lesson;
    if (lesson == null) return;
    unawaited(_svc.recordLessonProgress(
      _courseId,
      lesson.key,
      positionSeconds: position,
      durationSeconds: duration,
      title: _title,
      type: 'curso',
    ));
  }

  Future<void> _continue() async {
    if (_lessons.isEmpty) return;
    final last = _progress.lastLessonKey;
    var i = last == null ? -1 : _lessons.indexWhere((l) => l.key == last);
    if (i < 0 || _progress.lesson(_lessons[i].key).done) {
      final next = _lessons.indexWhere((l) => !_progress.lesson(l.key).done);
      i = next >= 0 ? next : 0;
    }
    await _openLesson(i, autoplay: true, resume: true);
  }

  Future<void> _toggleDone(CourseLesson l) async {
    final done = !_progress.lesson(l.key).done;
    await _svc.setLessonDone(_courseId, l.key, done);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(done ? 'Aula marcada como concluída.' : 'Aula desmarcada.'),
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recomeçar o curso?'),
        content: const Text(
            'O progresso das aulas deste curso será zerado neste e nos outros aparelhos.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Recomeçar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _svc.resetCourse(_courseId);
    if (!mounted) return;
    await _openLesson(0, autoplay: false, resume: false);
  }

  Future<void> _openFullscreen() async {
    final lesson = _lesson;
    if (lesson == null) return;
    if (!lesson.isYoutube && _currentMp4 == null) return;
    final lp = _svc.of(_courseId).lesson(lesson.key);
    // Sai do player inline para não tocar dois ao mesmo tempo.
    setState(() {
      _autoplay = false;
      _playNonce++;
    });
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => CourseFullscreenPlayer(
          title: '${lesson.title} · $_title',
          posterData: _posterData,
          youtubeVideoId: lesson.youtubeId,
          mp4Url: _currentMp4,
          startAt: lp.canResume ? lp.positionSeconds : 0,
          onProgress: _onProgress,
        ),
      ),
    );
    unawaited(_svc.flush(_courseId));
    if (!mounted) return;
    // Volta mostrando a capa; o «Continuar» retoma da posição salva.
    setState(() {
      _startAt = _svc.of(_courseId).lesson(lesson.key).canResume
          ? _svc.of(_courseId).lesson(lesson.key).positionSeconds
          : 0;
      _playNonce++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final bg = CourseYt.background(context);
    final fg = CourseYt.text(context);
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: CourseYt.isDark(context) ? bg : CourseYt.card(context),
        surfaceTintColor: Colors.transparent,
        foregroundColor: fg,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        // Seta explícita: a implícita do AppBar não aparecia na web (topo só
        // com «Gostei» e ⋮). Sem tela anterior (link direto/recarga), volta
        // para o início do app.
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Voltar',
          icon: const Icon(Icons.arrow_back_rounded),
          color: fg,
          onPressed: () => courseScreenGoBack(context),
        ),
        title: Text(
          _title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: _progress.liked ? 'Remover «Gostei»' : 'Gostei',
            icon: Icon(
              _progress.liked
                  ? Icons.thumb_up_alt_rounded
                  : Icons.thumb_up_off_alt_rounded,
              color: _progress.liked ? _kRed : fg,
            ),
            onPressed: () => _svc.toggleLike(_courseId, title: _title, type: 'curso'),
          ),
          IconButton(
            tooltip: 'Compartilhar curso',
            icon: const Icon(Icons.share_rounded),
            onPressed: _share,
          ),
          IconButton(
            tooltip: 'Tela cheia',
            icon: const Icon(Icons.fullscreen_rounded),
            onPressed: _openFullscreen,
          ),
          PopupMenuButton<String>(
            iconColor: fg,
            onSelected: (v) {
              if (v == 'reset') _reset();
              if (v == 'share') _share();
              if (v == 'cert') _openCertificate();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'share', child: Text('Compartilhar curso')),
              if (_progress.isCompleted(_keys))
                const PopupMenuItem(
                    value: 'cert', child: Text('Certificado de conclusão')),
              const PopupMenuItem(value: 'reset', child: Text('Recomeçar o curso')),
            ],
          ),
        ],
      ),
      body: wide ? _wideLayout() : _narrowLayout(),
    );
  }

  Widget _narrowLayout() {
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _player(),
        _header(),
        _lessonsSection(),
        _commentsSection(),
        _descriptionSection(),
      ],
    );
  }

  /// Comentários da aula aberta.
  Widget _commentsSection() {
    final lesson = _lesson;
    if (_loadingLessons || lesson == null || _courseId.isEmpty) {
      return const SizedBox.shrink();
    }
    return CourseCommentsSection(
      courseId: _courseId,
      lessonKey: lesson.key,
      uid: widget.uid,
      lessonTitle: lesson.title,
    );
  }

  Widget _wideLayout() {
    // Player limitado a ~62% da altura visível: em monitor largo o 16:9 da
    // coluna ocupava a tela toda e título, botão e descrição ficavam fora.
    final maxPlayerH = (MediaQuery.sizeOf(context).height - kToolbarHeight) * 0.62;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1400),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 13,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 32),
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: ColoredBox(
                      color: Colors.black,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: maxPlayerH < 220 ? 220 : maxPlayerH,
                          ),
                          child: _player(),
                        ),
                      ),
                    ),
                  ),
                  _header(),
                  _descriptionSection(),
                  _commentsSection(),
                ],
              ),
            ),
            Expanded(
              flex: 7,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 32),
                children: [_lessonsSection()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _player() {
    final lesson = _lesson;
    Widget child;
    if (_loadingLessons || _resolvingMp4) {
      child = const ColoredBox(
        color: Colors.black,
        child: Center(
          child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2.5),
        ),
      );
    } else if (lesson == null || (!lesson.isYoutube && _currentMp4 == null)) {
      child = CourseMediaThumbnail.fromData(
        _posterData,
        fit: BoxFit.cover,
        showPlayButton: false,
        light: false,
        fallback: const ColoredBox(
          color: Colors.black,
          child: Center(
            child: Text(
              'Vídeo indisponível no momento.',
              style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      );
    } else {
      child = CourseVideoPlayerShell(
        key: ValueKey('detail-shell-${lesson.key}-$_playNonce'),
        embedKey: ValueKey('detail-$_courseId-${lesson.key}-$_playNonce'),
        posterData: _posterData,
        youtubeVideoId: lesson.youtubeId,
        mp4Url: lesson.isYoutube ? null : _currentMp4,
        autoplay: _autoplay,
        startAtSeconds: _startAt,
        courseId: _courseId,
        contentTitle: _title,
        contentType: 'curso',
        onProgress: _onProgress,
        accent: _kRed,
        accent2: CourseYt.redDark,
      );
    }
    return AspectRatio(aspectRatio: 16 / 9, child: child);
  }

  Widget _header() {
    final keys = _keys.toList();
    final frac = _progress.courseFraction(keys);
    final done = _progress.doneCount(keys);
    final completed = _progress.isCompleted(keys);
    final declared = CourseLessons.declaredMinutes(widget.data);
    var knownSeconds = 0.0;
    var allKnown = keys.isNotEmpty;
    for (final k in keys) {
      final d = _progress.lesson(k).durationSeconds;
      if (d > 0) {
        knownSeconds += d;
      } else {
        allKnown = false;
      }
    }
    final durationLabel = declared != null
        ? CourseLessons.formatMinutes(declared)
        : (allKnown && knownSeconds > 0
            ? CourseLessons.formatMinutes((knownSeconds / 60).ceil())
            : null);

    final lesson = _lesson;
    final lp = lesson == null ? null : _progress.lesson(lesson.key);
    final started = _progress.hasActivity;
    final ctaLabel = completed
        ? 'Rever curso'
        : (!started
            ? 'Começar curso'
            : (lp != null && lp.canResume
                ? 'Continuar · ${CourseLessons.formatDuration(lp.positionSeconds)}'
                : 'Continuar de onde parei'));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (completed)
                const _Badge(label: 'CONCLUÍDO', color: _kGreen, icon: Icons.verified_rounded)
              else if (CourseLessons.isNew(widget.data))
                const _Badge(label: 'NOVO', color: _kRed, icon: Icons.fiber_new_rounded),
              _Badge(
                label: '${keys.length} ${keys.length == 1 ? 'aula' : 'aulas'}',
                color: const Color(0xFF3B82F6),
                icon: Icons.video_library_rounded,
              ),
              if (durationLabel != null)
                _Badge(
                  label: durationLabel,
                  color: const Color(0xFF8B5CF6),
                  icon: Icons.schedule_rounded,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _title,
            style: TextStyle(
              color: CourseYt.text(context),
              fontSize: 20,
              fontWeight: FontWeight.w900,
              height: 1.2,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: frac,
                    minHeight: 7,
                    color: completed ? _kGreen : _kRed,
                    backgroundColor: CourseYt.track(context),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${(frac * 100).round()}% · $done/${keys.length}',
                style: TextStyle(
                  color: CourseYt.textSecondary(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _lessons.isEmpty ? null : _continue,
                  style: FilledButton.styleFrom(
                    backgroundColor: _kRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: Icon(completed ? Icons.replay_rounded : Icons.play_arrow_rounded),
                  label: Text(
                    ctaLabel,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Tela cheia',
                onPressed: _openFullscreen,
                style: IconButton.styleFrom(
                  backgroundColor: CourseYt.surfaceAlt(context),
                  foregroundColor: CourseYt.text(context),
                ),
                icon: const Icon(Icons.fullscreen_rounded),
              ),
            ],
          ),
          if (completed) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openCertificate,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kGreen,
                  side: const BorderSide(color: _kGreen, width: 1.4),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.workspace_premium_rounded),
                label: const Text(
                  'Baixar certificado de conclusão',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _lessonsSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.fromLTRB(6, 12, 6, 6),
      decoration: CourseYt.cardDecoration(context, radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: Row(
              children: [
                const Icon(Icons.playlist_play_rounded, color: _kRed),
                const SizedBox(width: 6),
                Text(
                  'Aulas',
                  style: TextStyle(
                    color: CourseYt.text(context),
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_progress.doneCount(_keys)} de ${_lessons.length} concluídas',
                  style: TextStyle(
                    color: CourseYt.textSecondary(context),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (_loadingLessons)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: CircularProgressIndicator(color: _kRed, strokeWidth: 2),
              ),
            )
          else if (_lessons.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Este curso ainda não tem vídeo publicado.',
                style: TextStyle(color: CourseYt.textSecondary(context)),
              ),
            )
          else
            for (var i = 0; i < _lessons.length; i++)
              _LessonTile(
                lesson: _lessons[i],
                progress: _progress.lesson(_lessons[i].key),
                selected: i == _current,
                onTap: () => _openLesson(i, autoplay: true, resume: true),
                onToggleDone: () => _toggleDone(_lessons[i]),
              ),
        ],
      ),
    );
  }

  Widget _descriptionSection() {
    final d = _description;
    if (d.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(14),
      decoration: CourseYt.cardDecoration(context, radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.description_outlined,
                  color: CourseYt.textSecondary(context), size: 18),
              const SizedBox(width: 6),
              Text(
                'Sobre o curso',
                style: TextStyle(
                  color: CourseYt.text(context),
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              if (d.length > 220)
                TextButton(
                  onPressed: () => setState(() => _descExpanded = !_descExpanded),
                  style: TextButton.styleFrom(foregroundColor: _kRed),
                  child: Text(_descExpanded ? 'Ver menos' : 'Ver tudo'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            d,
            maxLines: _descExpanded ? null : 5,
            style: TextStyle(
              color: CourseYt.textSecondary(context),
              fontSize: 13.5,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _LessonTile extends StatelessWidget {
  const _LessonTile({
    required this.lesson,
    required this.progress,
    required this.selected,
    required this.onTap,
    required this.onToggleDone,
  });

  final CourseLesson lesson;
  final CourseLessonProgress progress;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onToggleDone;

  @override
  Widget build(BuildContext context) {
    final done = progress.done;
    final dur = CourseLessons.formatDuration(progress.durationSeconds);
    final subtitleParts = <String>[
      lesson.sourceLabel,
      if (dur.isNotEmpty) dur,
      if (progress.canResume)
        'parou em ${CourseLessons.formatDuration(progress.positionSeconds)}',
    ];
    return Material(
      color: selected ? _kRed.withValues(alpha: 0.12) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
          child: Row(
            children: [
              // Capa da aula (padrão playlist do YouTube): miniatura em alta
              // ou quadro do próprio vídeo, nº da aula, duração e progresso.
              SizedBox(
                width: 118,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CourseMediaThumbnail.fromData(
                          lesson.thumbData,
                          fit: BoxFit.cover,
                          showPlayButton: false,
                          fallback: ColoredBox(
                            color: CourseYt.surfaceAlt(context),
                            child: Icon(Icons.play_circle_outline_rounded,
                                color: CourseYt.textMuted(context), size: 28),
                          ),
                        ),
                        if (selected || done)
                          ColoredBox(
                            color: Colors.black.withValues(alpha: 0.45),
                            child: Icon(
                              done
                                  ? Icons.check_circle_rounded
                                  : Icons.equalizer_rounded,
                              color: done ? _kGreen : Colors.white,
                              size: 26,
                            ),
                          ),
                        Positioned(
                          left: 4,
                          top: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.72),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${lesson.index + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                        if (dur.isNotEmpty)
                          Positioned(
                            right: 4,
                            bottom: 5,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.78),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                dur,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        if (progress.fraction > 0 && !done)
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: LinearProgressIndicator(
                              value: progress.fraction,
                              minHeight: 3,
                              color: _kRed,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.25),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lesson.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: CourseYt.text(context),
                        fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitleParts.join(' · '),
                      style: TextStyle(
                        color: CourseYt.textSecondary(context),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (progress.fraction > 0 && !done) ...[
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: progress.fraction,
                          minHeight: 3,
                          color: _kRed,
                          backgroundColor: CourseYt.track(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: done ? 'Desmarcar concluída' : 'Marcar como concluída',
                onPressed: onToggleDone,
                icon: Icon(
                  done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                  color: done ? _kGreen : CourseYt.textMuted(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color, required this.icon});

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Player em tela cheia (paisagem + modo imersivo no celular; volta ao normal
/// ao sair). Usado pela tela do curso e pela tela de assistir.
class CourseFullscreenPlayer extends StatefulWidget {
  const CourseFullscreenPlayer({
    super.key,
    required this.title,
    required this.posterData,
    this.youtubeVideoId,
    this.mp4Url,
    this.startAt = 0,
    this.onProgress,
    this.controller,
    this.accent = _kRed,
    this.accent2 = CourseYt.redDark,
  });

  final String title;
  final Map<String, dynamic> posterData;
  final String? youtubeVideoId;
  final String? mp4Url;
  final double startAt;
  final void Function(double position, double duration)? onProgress;

  /// Mantém a velocidade escolhida e informa a posição ao voltar.
  final CourseVideoController? controller;
  final Color accent;
  final Color accent2;

  @override
  State<CourseFullscreenPlayer> createState() => _CourseFullscreenPlayerState();
}

class _CourseFullscreenPlayerState extends State<CourseFullscreenPlayer> {
  bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    if (_isMobile) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  void dispose() {
    if (_isMobile) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: CourseVideoPlayerShell(
                embedKey: ValueKey(
                    'fs-${widget.youtubeVideoId ?? ''}|${widget.mp4Url ?? ''}'),
                posterData: widget.posterData,
                youtubeVideoId: widget.youtubeVideoId,
                mp4Url: widget.mp4Url,
                autoplay: true,
                startAtSeconds: widget.startAt,
                onProgress: widget.onProgress,
                controller: widget.controller,
                accent: widget.accent,
                accent2: widget.accent2,
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Row(
                children: [
                  Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'Sair da tela cheia',
                      color: Colors.white,
                      icon: const Icon(Icons.fullscreen_exit_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        shadows: [Shadow(blurRadius: 6)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
