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
    this.courseId,
    this.startAtSeconds = 0,
    this.onProgress,
    this.contentTitle,
    this.contentType,
  });

  /// Documento Firestore (title, thumbnailUrl, id…) para resolver a capa.
  final Map<String, dynamic>? posterData;
  final String? youtubeVideoId;
  final String? mp4Url;
  final bool autoplay;
  final Color accent;
  final Color accent2;
  final Key? embedKey;
  final String? courseId;
  final double startAtSeconds;
  final void Function(double position, double duration)? onProgress;
  final String? contentTitle;
  final String? contentType;

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

  /// Sem resume automático — evita remontar o embed e voltar ao início.
  double get _effectiveStart => 0;

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

  void _onProgress(double position, double duration) {
    widget.onProgress?.call(position, duration);
    // Sem save de posição/resume — o usuário controla no player nativo.
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
            startAtSeconds: _effectiveStart,
            onReady: _onEmbedReady,
            onProgress: _onProgress,
          ),
        if (!_showEmbed)
          Positioned.fill(
            child: _posterOverlay(
              onPlay: _startPlayback,
              showPlayButton: true,
            ),
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

  Widget _posterOverlay({
    VoidCallback? onPlay,
    bool showPlayButton = true,
  }) {
    final data = widget.posterData;
    return Material(
      color: Colors.black,
      child: InkWell(
        onTap: onPlay,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_posterUrl != null)
              _posterImage(_posterUrl!)
            else if (data != null)
              CourseMediaThumbnail.fromData(
                data,
                fit: BoxFit.cover,
                showPlayButton: false,
                fallback: _gradientFallback(),
              )
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
                      Colors.black.withValues(alpha: 0.05),
                      Colors.black.withValues(alpha: 0.55),
                    ],
                  ),
                ),
              ),
            ),
            if (showPlayButton)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PlayButton(
                      isYoutube: _isYoutube,
                      accent: widget.accent,
                      accent2: widget.accent2,
                    ),
                  ],
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
      errorBuilder: (_, __, ___) {
        final data = widget.posterData;
        if (data != null) {
          return CourseMediaThumbnail.fromData(
            data,
            fit: BoxFit.cover,
            showPlayButton: false,
            fallback: _gradientFallback(),
          );
        }
        return _gradientFallback();
      },
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
            const Color(0xFF1A1A2E),
            widget.accent.withValues(alpha: 0.55),
            const Color(0xFF0F0F0F),
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
          : Center(
              child: Icon(
                Icons.ondemand_video_rounded,
                size: 56,
                color: Colors.white.withValues(alpha: 0.35),
              ),
            ),
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
    return Container(
      width: 72,
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFFFF0000),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: accent.withValues(alpha: 0.15),
            blurRadius: 8,
          ),
        ],
      ),
      child: Icon(
        Icons.play_arrow_rounded,
        color: Colors.white.withValues(alpha: isYoutube ? 1 : 0.98),
        size: 40,
      ),
    );
  }
}
