import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/course_progress_service.dart';
import '../../utils/course_media_url_resolver.dart';
import '../../utils/course_thumb_resolver.dart';
import '../../utils/youtube_url_helper.dart';
import '../course_media_preview.dart';
import 'course_video_player_shell.dart';

/// Card estilo YouTube — cursos e dicas: capa 16:9, player/galeria, descrição e «Gostei».
class CourseYoutubeFeedCard extends StatefulWidget {
  const CourseYoutubeFeedCard({
    super.key,
    required this.data,
    required this.uid,
    required this.isActive,
    required this.onActivate,
    this.accent = const Color(0xFFFF0000),
    this.accent2 = const Color(0xFFCC0000),
  });

  final Map<String, dynamic> data;
  final String uid;
  final bool isActive;
  final VoidCallback onActivate;
  final Color accent;
  final Color accent2;

  @override
  State<CourseYoutubeFeedCard> createState() => _CourseYoutubeFeedCardState();
}

class _CourseYoutubeFeedCardState extends State<CourseYoutubeFeedCard> {
  var _descExpanded = false;
  String? _resolvedMp4;
  var _mp4Loading = false;
  StreamSubscription<String>? _progressSub;
  CourseProgress _progress = const CourseProgress();

  String get _courseId => (widget.data['id'] ?? '').toString();

  bool get _isDica =>
      (widget.data['type'] ?? 'curso').toString().trim().toLowerCase() ==
      'dica';

  String get _title =>
      (widget.data['title'] ?? (_isDica ? 'Dica' : 'Curso')).toString();

  String get _description {
    final body = (widget.data['bodyText'] ?? '').toString().trim();
    if (body.isNotEmpty) return body;
    return (widget.data['description'] ?? '').toString().trim();
  }

  String? get _youtubeId {
    return YoutubeUrlHelper.videoIdFromData(widget.data);
  }

  bool get _hasImage => CourseMediaUrlResolver.hasResolvableImage(widget.data);

  bool get _hasVideo =>
      _youtubeId != null ||
      _resolvedMp4 != null ||
      CourseThumbResolver.isVideoContent(widget.data);

  Color get _ctaColor =>
      _isDica ? const Color(0xFFF59E0B) : const Color(0xFFFF0000);

  @override
  void initState() {
    super.initState();
    unawaited(CourseProgressService.instance.bindUser(widget.uid));
    _progress = CourseProgressService.instance.of(_courseId);
    _progressSub = CourseProgressService.instance.changes.listen((id) {
      if (id == _courseId && mounted) {
        setState(() => _progress = CourseProgressService.instance.of(_courseId));
      }
    });
    _loadMp4();
  }

  @override
  void didUpdateWidget(covariant CourseYoutubeFeedCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data['id'] != widget.data['id']) {
      _descExpanded = false;
      _progress = CourseProgressService.instance.of(_courseId);
      _resolvedMp4 = null;
      _loadMp4();
    }
    if (oldWidget.uid != widget.uid) {
      unawaited(CourseProgressService.instance.bindUser(widget.uid));
    }
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    super.dispose();
  }

  Future<void> _loadMp4() async {
    final direct = (widget.data['mp4Url'] ?? '').toString().trim();
    if (direct.isNotEmpty) {
      setState(() => _resolvedMp4 = direct);
      return;
    }
    if (CourseMediaUrlResolver.collectVideoEntries(widget.data).isEmpty) return;
    setState(() => _mp4Loading = true);
    try {
      final entries =
          await CourseMediaUrlResolver.resolveVideoEntries(widget.data);
      if (!mounted) return;
      setState(() {
        _resolvedMp4 = entries.isNotEmpty ? entries.first.url : null;
        _mp4Loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _mp4Loading = false);
    }
  }

  Future<void> _toggleLike() async {
    await CourseProgressService.instance.toggleLike(
      _courseId,
      title: _title,
      type: _isDica ? 'dica' : 'curso',
    );
    if (mounted) {
      setState(() => _progress = CourseProgressService.instance.of(_courseId));
    }
  }

  Widget _mediaArea() {
    if (widget.isActive && _hasVideo) {
      if (_mp4Loading) {
        return const Center(
          child: CircularProgressIndicator(
            color: Colors.white54,
            strokeWidth: 2.5,
          ),
        );
      }
      return CourseVideoPlayerShell(
        embedKey: ValueKey(
          'feed-$_courseId|${_youtubeId ?? ''}|${_resolvedMp4 ?? ''}',
        ),
        posterData: widget.data,
        youtubeVideoId: _youtubeId,
        mp4Url: _resolvedMp4,
        courseId: _courseId,
        startAtSeconds: 0,
        contentTitle: _title,
        contentType: _isDica ? 'dica' : 'curso',
        autoplay: false,
        accent: widget.accent,
        accent2: widget.accent2,
      );
    }

    if (widget.isActive && _hasImage && !_hasVideo) {
      return LayoutBuilder(
        builder: (context, c) {
          return CoursePhotoGallery(
            data: widget.data,
            height: c.maxHeight.isFinite ? c.maxHeight : 220,
            fit: BoxFit.contain,
            title: _title,
            accent: widget.accent,
          );
        },
      );
    }

    return _CoverTap(
      data: widget.data,
      isDica: _isDica,
      hasVideo: _hasVideo,
      accent: _ctaColor,
      onTap: widget.onActivate,
    );
  }

  @override
  Widget build(BuildContext context) {
    final borderAccent = widget.isActive
        ? _ctaColor.withValues(alpha: 0.5)
        : Colors.white.withValues(alpha: 0.06);

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F0F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderAccent),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ColoredBox(
                  color: const Color(0xFF0F0F0F),
                  child: _mediaArea(),
                ),
              ),
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (_isDica
                            ? const Color(0xFFF59E0B)
                            : const Color(0xFFFF0000))
                        .withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _isDica ? 'DICA' : 'CURSO',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                    height: 1.25,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _LikeButton(
                      liked: _progress.liked,
                      accent: _ctaColor,
                      onTap: _toggleLike,
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: widget.onActivate,
                      icon: Icon(
                        widget.isActive
                            ? (_hasVideo
                                ? Icons.play_circle_fill_rounded
                                : Icons.menu_book_rounded)
                            : (_hasVideo
                                ? Icons.play_arrow_rounded
                                : Icons.visibility_rounded),
                        color: _ctaColor,
                        size: 20,
                      ),
                      label: Text(
                        widget.isActive
                            ? (_hasVideo ? 'Assistindo' : 'Aberta')
                            : (_hasVideo ? 'Assistir' : 'Abrir'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_description.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () => setState(() => _descExpanded = !_descExpanded),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.07),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isDica ? 'Texto da dica' : 'Descrição',
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _description,
                            maxLines: _descExpanded ? null : (_isDica ? 6 : 4),
                            overflow: _descExpanded
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey.shade300,
                              fontSize: 13.5,
                              height: 1.45,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (_description.length > 100) ...[
                            const SizedBox(height: 6),
                            Text(
                              _descExpanded
                                  ? 'Ver menos'
                                  : 'Ver descrição completa',
                              style: const TextStyle(
                                color: Color(0xFF3EA6FF),
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverTap extends StatelessWidget {
  const _CoverTap({
    required this.data,
    required this.isDica,
    required this.hasVideo,
    required this.accent,
    required this.onTap,
  });

  final Map<String, dynamic> data;
  final bool isDica;
  final bool hasVideo;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final yt = YoutubeUrlHelper.videoIdFromData(data);
    final thumb = yt != null ? YoutubeUrlHelper.thumbnailUrl(yt) : null;
    final fit = CourseThumbResolver.isDicaPhoto(data)
        ? BoxFit.contain
        : BoxFit.cover;

    return Material(
      color: Colors.black,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (thumb != null)
              Image.network(
                thumb,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => CourseMediaThumbnail.fromData(
                  data,
                  fit: fit,
                  showPlayButton: false,
                ),
              )
            else
              CourseMediaThumbnail.fromData(
                data,
                fit: fit,
                showPlayButton: false,
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.05),
                    Colors.black.withValues(alpha: 0.55),
                  ],
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: hasVideo ? 72 : 64,
                    height: hasVideo ? 52 : 64,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius:
                          BorderRadius.circular(hasVideo ? 14 : 999),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Icon(
                      hasVideo
                          ? Icons.play_arrow_rounded
                          : (isDica
                              ? Icons.lightbulb_rounded
                              : Icons.visibility_rounded),
                      color: Colors.white,
                      size: hasVideo ? 40 : 30,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LikeButton extends StatelessWidget {
  const _LikeButton({
    required this.liked,
    required this.onTap,
    required this.accent,
  });

  final bool liked;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: liked ? accent.withValues(alpha: 0.16) : const Color(0xFF272727),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                liked
                    ? Icons.thumb_up_alt_rounded
                    : Icons.thumb_up_off_alt_rounded,
                size: 18,
                color: liked ? accent : Colors.white70,
              ),
              const SizedBox(width: 6),
              Text(
                'Gostei',
                style: TextStyle(
                  color: liked ? accent : Colors.white70,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
