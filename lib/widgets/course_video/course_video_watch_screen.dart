import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../screens/course_detail_screen.dart' show CourseFullscreenPlayer;
import '../../services/course_progress_service.dart';
import '../../utils/course_lessons.dart';
import '../../utils/course_media_url_resolver.dart';
import '../../utils/course_share.dart';
import '../../utils/youtube_url_helper.dart';
import '../course/course_yt_palette.dart';
import '../course_media_preview.dart';
import 'course_comments_section.dart';
import 'course_video_controller.dart';
import 'course_video_player_shell.dart';

/// Abre vídeo de curso com UI estilo YouTube (player + lista relacionada).
Future<void> openCourseVideoFromData(
  BuildContext context, {
  required Map<String, dynamic> data,
  List<Map<String, dynamic>> related = const [],
}) async {
  final videos = await CourseMediaUrlResolver.resolveVideoEntries(data);
  if (videos.length > 1) {
    if (!context.mounted) return;
    final title = (data['title'] ?? 'Vídeo').toString();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _VideoPickerSheet(
        title: title,
        videos: videos,
        onPick: (url, label) {
          Navigator.pop(ctx);
          if (!context.mounted) return;
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CourseVideoWatchScreen(
                data: data,
                mp4Url: url,
                mp4Label: label,
                related: related,
              ),
            ),
          );
        },
      ),
    );
    return;
  }

  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CourseVideoWatchScreen(
        data: data,
        mp4Url: videos.isNotEmpty ? videos.first.url : _mp4FromData(data),
        related: related,
      ),
    ),
  );
}

String? _mp4FromData(Map<String, dynamic> data) {
  final u = (data['mp4Url'] ?? '').toString().trim();
  return u.isEmpty ? null : u;
}

String? _youtubeIdFromData(Map<String, dynamic> data) {
  return YoutubeUrlHelper.videoIdFromData(data);
}

/// Tela de reprodução estilo YouTube — player 16:9, metadados e vídeos relacionados.
class CourseVideoWatchScreen extends StatefulWidget {
  const CourseVideoWatchScreen({
    super.key,
    required this.data,
    this.mp4Url,
    this.mp4Label,
    this.related = const [],
  });

  final Map<String, dynamic> data;
  final String? mp4Url;
  final String? mp4Label;
  final List<Map<String, dynamic>> related;

  @override
  State<CourseVideoWatchScreen> createState() => _CourseVideoWatchScreenState();
}

class _CourseVideoWatchScreenState extends State<CourseVideoWatchScreen> {
  var _descExpanded = false;

  /// Velocidade/pausa e última posição do player desta tela.
  final _videoCtrl = CourseVideoController();
  final _progressSvc = CourseProgressService.instance;

  /// Parâmetros do player fixados ao (re)abrir — nunca mudam no meio da
  /// reprodução (trocar remontaria o vídeo).
  var _autoplay = true;
  double _startAt = 0;
  int _playNonce = 0;

  String get _courseId => (widget.data['id'] ?? '').toString();

  String? get _uid {
    final bound = _progressSvc.boundUid;
    if (bound != null && bound.isNotEmpty) return bound;
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  /// Aula tocada aqui (mesma chave da tela do curso — progresso único).
  String? get _lessonKey =>
      CourseLessons.lessonKeyFor(widget.data, mp4Url: _mp4Url);

  @override
  void initState() {
    super.initState();
    final uid = _uid;
    if (uid != null && uid.isNotEmpty && _courseId.isNotEmpty) {
      unawaited(_progressSvc.bindUser(uid));
      // Retoma de onde parou (mesma regra da tela do curso).
      final key = _lessonKey;
      if (key != null) {
        final lp = _progressSvc.of(_courseId).lesson(key);
        if (lp.canResume) _startAt = lp.positionSeconds;
      }
    }
  }

  @override
  void dispose() {
    if (_courseId.isNotEmpty) unawaited(_progressSvc.flush(_courseId));
    _videoCtrl.dispose();
    super.dispose();
  }

  void _onProgress(double position, double duration) {
    final key = _lessonKey;
    if (_courseId.isEmpty || key == null) return;
    unawaited(_progressSvc.recordLessonProgress(
      _courseId,
      key,
      positionSeconds: position,
      durationSeconds: duration,
      title: _title,
      type: (widget.data['type'] ?? 'curso').toString(),
    ));
  }

  String get _title => (widget.data['title'] ?? 'Vídeo').toString();

  String get _description {
    final body = (widget.data['bodyText'] ?? '').toString().trim();
    if (body.isNotEmpty) return body;
    return (widget.data['description'] ?? '').toString().trim();
  }

  String? get _youtubeId => _youtubeIdFromData(widget.data);

  String? get _mp4Url {
    final direct = widget.mp4Url?.trim();
    if (direct != null && direct.isNotEmpty) return direct;
    return _mp4FromData(widget.data);
  }

  String get _typeLabel {
    final t = (widget.data['type'] ?? 'curso').toString();
    return t == 'dica' ? 'Dica Wisdom' : 'Wisdom Cursos';
  }

  Color get _accent {
    final t = (widget.data['type'] ?? 'curso').toString();
    return t == 'dica' ? const Color(0xFFF59E0B) : const Color(0xFF2563EB);
  }

  void _openRelated(Map<String, dynamic> item) {
    final filtered = widget.related
        .where((r) => r['id']?.toString() != item['id']?.toString())
        .toList();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => CourseVideoWatchScreen(
          data: item,
          related: [widget.data, ...filtered],
        ),
      ),
    );
  }

  /// Tela cheia de verdade: paisagem + modo imersivo (mesmo player da tela do
  /// curso), começando no ponto atual; ao voltar, o player de baixo retoma
  /// de onde a tela cheia parou.
  Future<void> _openFullscreen() async {
    final from = _videoCtrl.position > 0 ? _videoCtrl.position : _startAt;
    // Fecha o player de baixo para não tocar dois ao mesmo tempo.
    setState(() {
      _autoplay = false;
      _startAt = from;
      _playNonce++;
    });
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => CourseFullscreenPlayer(
          title: _title,
          posterData: widget.data,
          youtubeVideoId: _youtubeId,
          mp4Url: _mp4Url,
          startAt: from,
          onProgress: _onProgress,
          controller: _videoCtrl,
          accent: _accent,
          accent2: _accent.withValues(alpha: 0.72),
        ),
      ),
    );
    if (_courseId.isNotEmpty) unawaited(_progressSvc.flush(_courseId));
    if (!mounted) return;
    setState(() {
      _startAt = _videoCtrl.position > 0 ? _videoCtrl.position : from;
      _autoplay = true;
      _playNonce++;
    });
  }

  void _shareCurrent() => CourseShare.share(context, widget.data);

  @override
  Widget build(BuildContext context) {
    final related = widget.related
        .where((r) => r['id']?.toString() != widget.data['id']?.toString())
        .take(12)
        .toList();

    return Scaffold(
      backgroundColor: CourseYt.background(context),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            elevation: 0,
            backgroundColor: CourseYt.background(context),
            foregroundColor: CourseYt.text(context),
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              _title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            actions: [
              IconButton(
                tooltip: 'Compartilhar',
                icon: const Icon(Icons.share_rounded),
                onPressed: _shareCurrent,
              ),
              IconButton(
                tooltip: 'Tela cheia',
                icon: const Icon(Icons.fullscreen_rounded),
                onPressed: _openFullscreen,
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = MediaQuery.sizeOf(context).width;
                final maxW = kIsWeb ? (w > 960 ? 720.0 : w) : w;
                return Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxW),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CourseVideoPlayerShell(
                            key: ValueKey('watch-shell-$_playNonce'),
                            embedKey: ValueKey(
                                '${_youtubeId ?? ''}|${_mp4Url ?? ''}|$_playNonce'),
                            posterData: widget.data,
                            youtubeVideoId: _youtubeId,
                            mp4Url: _mp4Url,
                            autoplay: _autoplay,
                            startAtSeconds: _startAt,
                            courseId: _courseId.isEmpty ? null : _courseId,
                            onProgress: _onProgress,
                            controller: _videoCtrl,
                            accent: _accent,
                            accent2: _accent.withValues(alpha: 0.72),
                          ),
                          Positioned(
                            right: 8,
                            bottom: 8,
                            child: Material(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(999),
                              child: InkWell(
                                onTap: _openFullscreen,
                                borderRadius: BorderRadius.circular(999),
                                child: const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Icon(Icons.fullscreen_rounded,
                                      color: Colors.white, size: 22),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    _title,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      height: 1.25,
                      color: CourseYt.text(context),
                    ),
                  ),
                  if (widget.mp4Label != null &&
                      widget.mp4Label!.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.mp4Label!,
                      style: TextStyle(
                        color: CourseYt.textSecondary(context),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  // Speed controls
                  _SpeedControlBar(accent: _accent, controller: _videoCtrl),
                  const SizedBox(height: 12),
                  // Channel info
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [_accent, _accent.withValues(alpha: 0.75)],
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.school_rounded,
                            color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _typeLabel,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: CourseYt.text(context),
                              ),
                            ),
                            Text(
                              _youtubeId != null
                                  ? 'YouTube · até 4K'
                                  : 'HD · MP4',
                              style: TextStyle(
                                color: CourseYt.textMuted(context),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF0000),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Wisdom',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Quality badge
                  if (_youtubeId != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        children: [
                          Icon(Icons.hd_rounded, size: 16, color: _accent),
                          const SizedBox(width: 4),
                          Text(
                            'Qualidade até 4K no player',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: CourseYt.textMuted(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Description
                  if (_description.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () =>
                          setState(() => _descExpanded = !_descExpanded),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: CourseYt.isDark(context)
                              ? CourseYt.card(context)
                              : CourseYt.surfaceAlt(context),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _description,
                              maxLines: _descExpanded ? null : 3,
                              overflow:
                                  _descExpanded ? null : TextOverflow.ellipsis,
                              style: TextStyle(
                                color: CourseYt.isDark(context)
                                    ? Colors.grey.shade300
                                    : CourseYt.text(context),
                                height: 1.45,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _descExpanded ? 'Mostrar menos' : 'Mostrar mais',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                color: CourseYt.text(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_courseId.isNotEmpty &&
              (_uid ?? '').isNotEmpty &&
              _lessonKey != null)
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: CourseCommentsSection(
                    courseId: _courseId,
                    lessonKey: _lessonKey!,
                    uid: _uid!,
                  ),
                ),
              ),
            ),
          if (related.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                child: Text(
                  'Próximos vídeos',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: CourseYt.text(context),
                  ),
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final item = related[i];
                  return _RelatedVideoTile(
                    data: item,
                    onTap: () => _openRelated(item),
                  );
                },
                childCount: related.length,
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

class _RelatedVideoTile extends StatelessWidget {
  const _RelatedVideoTile({
    required this.data,
    required this.onTap,
  });

  final Map<String, dynamic> data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] ?? 'Vídeo').toString();
    final type = (data['type'] ?? 'curso').toString();
    final accent =
        type == 'dica' ? const Color(0xFFF59E0B) : const Color(0xFF2563EB);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 168,
                  height: 94,
                  child: CourseMediaThumbnail.fromData(
                    data,
                    fit: BoxFit.cover,
                    fallback: Container(
                      color: CourseYt.surfaceAlt(context),
                      child: Icon(Icons.play_circle_fill_rounded,
                          color: accent, size: 36),
                    ),
                    showPlayButton: true,
                    playIconSize: 32,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        height: 1.25,
                        color: CourseYt.text(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      type == 'dica' ? 'Dica Wisdom' : 'Wisdom Cursos',
                      style: TextStyle(
                        color: CourseYt.textMuted(context),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Mais opções',
                icon: Icon(Icons.more_vert_rounded,
                    color: CourseYt.textMuted(context), size: 20),
                onSelected: (v) {
                  if (v == 'play') onTap();
                  if (v == 'share') CourseShare.share(context, data);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'play',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.play_arrow_rounded),
                      title: Text('Assistir agora'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'share',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.share_rounded),
                      title: Text('Compartilhar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barra de velocidade estilo YouTube — aplica de verdade no player
/// (YouTube: `setPlaybackRate`; MP4: `playbackRate`) via [controller].
class _SpeedControlBar extends StatefulWidget {
  const _SpeedControlBar({required this.accent, required this.controller});
  final Color accent;
  final CourseVideoController controller;

  @override
  State<_SpeedControlBar> createState() => _SpeedControlBarState();
}

class _SpeedControlBarState extends State<_SpeedControlBar> {
  double get _speed => widget.controller.playbackRate;

  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onCtrl);
  }

  @override
  void didUpdateWidget(covariant _SpeedControlBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onCtrl);
      widget.controller.addListener(_onCtrl);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onCtrl);
    super.dispose();
  }

  void _onCtrl() {
    if (mounted) setState(() {});
  }

  void _pick(double s) {
    widget.controller.setPlaybackRate(s);
    if (!widget.controller.hasTarget && s != 1.0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Velocidade ${_speedLabel(s)} — vale quando o vídeo tocar.'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  String _speedLabel(double s) {
    if (s == 1.0) return 'Normal';
    return '${s}x';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: CourseYt.isDark(context)
            ? CourseYt.card(context)
            : CourseYt.surfaceAlt(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.speed_rounded, size: 16, color: widget.accent),
          const SizedBox(width: 6),
          Text(
            'Velocidade:',
            style: TextStyle(
              color: CourseYt.textSecondary(context),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final s in _speeds)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: GestureDetector(
                        onTap: () => _pick(s),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _speed == s
                                ? widget.accent.withValues(alpha: 0.2)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            border: _speed == s
                                ? Border.all(color: widget.accent, width: 1)
                                : null,
                          ),
                          child: Text(
                            _speedLabel(s),
                            style: TextStyle(
                              color: _speed == s
                                  ? widget.accent
                                  : CourseYt.textMuted(context),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
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

class _VideoPickerSheet extends StatelessWidget {
  const _VideoPickerSheet({
    required this.title,
    required this.videos,
    required this.onPick,
  });

  final String title;
  final List<CourseVideoEntry> videos;
  final void Function(String url, String label) onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      decoration: BoxDecoration(
        color: CourseYt.card(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Escolha o vídeo · $title',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: CourseYt.text(context),
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < videos.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                tileColor: CourseYt.surfaceAlt(context),
                leading: CircleAvatar(
                  backgroundColor:
                      const Color(0xFFFF0000).withValues(alpha: 0.15),
                  child: const Icon(Icons.play_arrow_rounded,
                      color: Color(0xFFFF0000)),
                ),
                title: Text(
                  videos[i].label ?? 'Vídeo ${i + 1}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: CourseYt.text(context),
                  ),
                ),
                onTap: () => onPick(
                  videos[i].url,
                  videos[i].label ?? 'Vídeo ${i + 1}',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Atalho para YouTube por ID (admin / preview).
Future<void> openYoutubeWatchScreen(
  BuildContext context, {
  required String videoId,
  required String title,
  Map<String, dynamic>? extraData,
}) {
  final data = {
    'title': title,
    'youtubeVideoId': videoId,
    'type': 'curso',
    if (extraData != null) ...extraData,
  };
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CourseVideoWatchScreen(data: data),
    ),
  );
}

/// Atalho MP4 (admin / preview).
Future<void> openMp4WatchScreen(
  BuildContext context, {
  required String videoUrl,
  required String title,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CourseVideoWatchScreen(
        data: {'title': title, 'type': 'curso'},
        mp4Url: videoUrl,
      ),
    ),
  );
}
