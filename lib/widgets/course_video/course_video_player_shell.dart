import 'package:flutter/material.dart';

import '../../utils/course_media_url_resolver.dart';
import '../../utils/youtube_url_helper.dart';
import '../course_media_preview.dart';
import 'course_video_embed.dart';

/// Player estilo YouTube — capa/thumbnail até o usuário tocar ▶; depois embed nativo.
class CourseVideoPlayerShell extends StatefulWidget {
  const CourseVideoPlayerShell({
    super.key,
    this.posterData,
    this.youtubeVideoId,
    this.mp4Url,
    this.autoplay = false,
    this.accent = const Color(0xFF2563EB),
    this.accent2 = const Color(0xFF7C3AED),
    this.embedKey,
  });

  /// Documento Firestore (title, thumbnailUrl, id…) para resolver a capa.
  final Map<String, dynamic>? posterData;
  final String? youtubeVideoId;
  final String? mp4Url;
  final bool autoplay;
  final Color accent;
  final Color accent2;
  final Key? embedKey;

  @override
  State<CourseVideoPlayerShell> createState() => _CourseVideoPlayerShellState();
}

class _CourseVideoPlayerShellState extends State<CourseVideoPlayerShell> {
  var _playbackStarted = false;
  var _embedReady = false;
  String? _posterUrl;
  var _posterLoading = true;

  bool get _showEmbed => widget.autoplay || _playbackStarted;

  bool get _isYoutube =>
      widget.youtubeVideoId != null && widget.youtubeVideoId!.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _playbackStarted = widget.autoplay;
    _resolvePoster();
  }

  @override
  void didUpdateWidget(covariant CourseVideoPlayerShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.posterData != widget.posterData ||
        oldWidget.youtubeVideoId != widget.youtubeVideoId ||
        oldWidget.mp4Url != widget.mp4Url) {
      _embedReady = false;
      if (!widget.autoplay) _playbackStarted = false;
      _resolvePoster();
    }
    if (widget.autoplay && !_playbackStarted) {
      _playbackStarted = true;
    }
  }

  Future<void> _resolvePoster() async {
    setState(() {
      _posterLoading = true;
      _posterUrl = null;
    });

    final data = widget.posterData;
    if (data != null) {
      try {
        final docId = data['id']?.toString();
        final urls = await CourseMediaUrlResolver.resolveImageUrls(
          data,
          docId: docId,
        );
        if (urls.isNotEmpty) {
          if (mounted) {
            setState(() {
              _posterUrl = urls.first;
              _posterLoading = false;
            });
          }
          return;
        }
      } catch (_) {
        // fallback abaixo
      }
    }

    final yt = widget.youtubeVideoId?.trim();
    if (yt != null && yt.isNotEmpty) {
      if (mounted) {
        setState(() {
          _posterUrl = YoutubeUrlHelper.thumbnailUrl(yt);
          _posterLoading = false;
        });
      }
      return;
    }

    if (mounted) setState(() => _posterLoading = false);
  }

  void _startPlayback() {
    if (_playbackStarted) return;
    setState(() {
      _playbackStarted = true;
      _embedReady = false;
    });
  }

  void _onEmbedReady() {
    if (!mounted || _embedReady) return;
    setState(() => _embedReady = true);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_showEmbed)
          CourseVideoEmbed(
            key: widget.embedKey,
            youtubeVideoId: widget.youtubeVideoId,
            mp4Url: widget.mp4Url,
            autoplay: widget.autoplay || _playbackStarted,
            posterUrl: _posterUrl,
            onReady: _onEmbedReady,
          ),
        if (!_showEmbed)
          Positioned.fill(
            child: _posterOverlay(onPlay: _startPlayback, showPlayButton: true),
          ),
        if (_showEmbed && !_embedReady)
          Positioned.fill(
            child: IgnorePointer(
              child: _posterOverlay(showPlayButton: false),
            ),
          ),
      ],
    );
  }

  Widget _posterOverlay({VoidCallback? onPlay, bool showPlayButton = true}) {
    final data = widget.posterData;
    return Material(
      color: Colors.black,
      child: InkWell(
        onTap: onPlay,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (data != null)
              CourseMediaThumbnail.fromData(
                data,
                fit: BoxFit.cover,
                showPlayButton: false,
                fallback: _gradientFallback(),
              )
            else if (_posterUrl != null)
              _posterImage(_posterUrl!)
            else if (_posterLoading)
              _gradientFallback(showSpinner: true)
            else
              _gradientFallback(),
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.08),
                      Colors.black.withValues(alpha: 0.45),
                    ],
                  ),
                ),
              ),
            ),
            if (showPlayButton)
              Center(
                child: _PlayButton(
                  isYoutube: _isYoutube,
                  accent: widget.accent,
                  accent2: widget.accent2,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _posterImage(String url) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => _gradientFallback(),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _gradientFallback(showSpinner: true);
      },
    );
  }

  Widget _gradientFallback({bool showSpinner = false}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            widget.accent.withValues(alpha: 0.85),
            widget.accent2.withValues(alpha: 0.75),
            const Color(0xFF0F172A),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: showSpinner
          ? Center(
              child: SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
            )
          : null,
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.isYoutube,
    required this.accent,
    required this.accent2,
  });

  final bool isYoutube;
  final Color accent;
  final Color accent2;

  @override
  Widget build(BuildContext context) {
    if (isYoutube) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFF0000).withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Icon(
          Icons.play_arrow_rounded,
          color: Colors.white,
          size: 64,
        ),
      );
    }

    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [accent, accent2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.45),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 3),
      ),
      child: const Icon(
        Icons.play_arrow_rounded,
        color: Colors.white,
        size: 44,
      ),
    );
  }
}
