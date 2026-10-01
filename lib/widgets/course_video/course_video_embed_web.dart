import 'dart:async';
import 'dart:ui_web' as ui_web;

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/material.dart';

import '../../utils/youtube_url_helper.dart';
import 'course_media_view_policy.dart';

/// YouTube / MP4 na Web — iframe e `<video>` nativos (sem WebView).
class CourseVideoEmbed extends StatefulWidget {
  const CourseVideoEmbed({
    super.key,
    this.youtubeVideoId,
    this.mp4Url,
    this.autoplay = true,
    this.posterUrl,
    this.startAtSeconds = 0,
    this.onReady,
    this.onProgress,
  });

  final String? youtubeVideoId;
  final String? mp4Url;
  final bool autoplay;
  final String? posterUrl;
  final double startAtSeconds;
  final VoidCallback? onReady;
  final void Function(double position, double duration)? onProgress;

  @override
  State<CourseVideoEmbed> createState() => _CourseVideoEmbedState();
}

class _CourseVideoEmbedState extends State<CourseVideoEmbed> {
  static int _viewCounter = 0;
  late final String _viewType;
  bool _registered = false;
  var _notifiedReady = false;
  Timer? _progressTimer;
  html.VideoElement? _videoEl;

  int get _startAt =>
      widget.startAtSeconds > 8 ? widget.startAtSeconds.round() : 0;

  @override
  void initState() {
    super.initState();
    _viewType = 'course-video-${++_viewCounter}';
    _registerView();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CourseVideoEmbed oldWidget) {
    super.didUpdateWidget(oldWidget);
    // NÃO remontar só por startAtSeconds — isso resetava o vídeo ao meio da reprodução.
    if (oldWidget.youtubeVideoId != widget.youtubeVideoId ||
        oldWidget.mp4Url != widget.mp4Url ||
        // A capa só importa ANTES do play: com autoplay, trocar o pôster
        // (que chega depois, assíncrono) recarregava o player do zero.
        (!widget.autoplay && oldWidget.posterUrl != widget.posterUrl) ||
        oldWidget.autoplay != widget.autoplay) {
      _notifiedReady = false;
      _registered = false;
      _progressTimer?.cancel();
      _registerView();
    }
  }

  void _notifyReady() {
    if (_notifiedReady) return;
    _notifiedReady = true;
    widget.onReady?.call();
  }

  void _emitProgress(double t, double d) {
    widget.onProgress?.call(t, d);
  }

  void _registerView() {
    if (_registered) return;
    final yt = widget.youtubeVideoId?.trim();
    final mp4 = widget.mp4Url?.trim();
    final poster = widget.posterUrl?.trim();
    final origin = Uri.base.origin;
    final start = _startAt;

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      if (yt != null && yt.isNotEmpty) {
        if (!widget.autoplay) {
          return _buildYoutubePosterView(yt, poster, start);
        }
        final iframe = html.IFrameElement()
          ..src = YoutubeUrlHelper.embedUrl(
            yt,
            autoplay: widget.autoplay,
            origin: origin,
            startSeconds: start,
          )
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%'
          ..allowFullscreen = true
          ..setAttribute(
            'allow',
            'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share; fullscreen',
          )
          // YouTube exige Referer/origin no embed (sem ele: erro 153).
          ..setAttribute('referrerpolicy', 'strict-origin-when-cross-origin');
        iframe.onLoad.listen((_) => _notifyReady());
        return iframe;
      }
      if (mp4 != null && mp4.isNotEmpty) {
        final video = html.VideoElement()
          ..src = mp4
          ..controls = true
          ..autoplay = widget.autoplay
          ..setAttribute('playsinline', 'true')
          ..setAttribute('controlsList', CourseMediaViewPolicy.videoControlsList)
          ..setAttribute('disablePictureInPicture', 'true')
          // Só metadados até tocar (autoplay = carrega já).
          ..preload = widget.autoplay ? 'auto' : 'metadata'
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.objectFit = 'contain'
          ..style.backgroundColor = '#000';
        if (poster != null && poster.isNotEmpty) {
          video.poster = poster;
        }
        _videoEl = video;
        video.onContextMenu.listen((e) => e.preventDefault());
        video.onDragStart.listen((e) => e.preventDefault());
        video.onLoadedMetadata.listen((_) {
          if (start > 0) {
            try {
              video.currentTime = start.toDouble();
            } catch (_) {}
          } else if (poster == null || poster.isEmpty) {
            try {
              video.currentTime = 0.05;
            } catch (_) {}
          }
        });
        video.onLoadedData.first.then((_) => _notifyReady());
        video.onPause.listen((_) {
          _emitProgress(
            video.currentTime.toDouble(),
            video.duration.isFinite ? video.duration.toDouble() : 0.0,
          );
        });
        video.onEnded.listen((_) {
          _emitProgress(
            video.currentTime.toDouble(),
            video.duration.isFinite ? video.duration.toDouble() : 0.0,
          );
        });
        _progressTimer?.cancel();
        _progressTimer = Timer.periodic(const Duration(seconds: 4), (_) {
          if (_videoEl == null) return;
          final v = _videoEl!;
          final d = v.duration.isFinite ? v.duration.toDouble() : 0.0;
          _emitProgress(v.currentTime.toDouble(), d);
        });
        return video;
      }
      _notifyReady();
      return html.DivElement()
        ..style.color = '#fff'
        ..text = 'Vídeo indisponível';
    });
    _registered = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  html.Element _buildYoutubePosterView(
    String videoId,
    String? poster,
    int start,
  ) {
    final wrap = html.DivElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.position = 'relative'
      ..style.backgroundColor = '#000'
      ..style.overflow = 'hidden';

    final thumb = poster ?? YoutubeUrlHelper.thumbnailUrl(videoId);
    final posterEl = html.DivElement()
      ..style.position = 'absolute'
      ..style.top = '0'
      ..style.left = '0'
      ..style.right = '0'
      ..style.bottom = '0'
      ..style.backgroundImage = 'url($thumb)'
      ..style.backgroundSize = 'cover'
      ..style.backgroundPosition = 'center'
      ..style.cursor = 'pointer';

    final gradient = html.DivElement()
      ..style.position = 'absolute'
      ..style.top = '0'
      ..style.left = '0'
      ..style.right = '0'
      ..style.bottom = '0'
      ..style.background =
          'linear-gradient(180deg, rgba(0,0,0,0.08), rgba(0,0,0,0.42))';

    final playBtn = html.DivElement()
      ..style.position = 'absolute'
      ..style.left = '50%'
      ..style.top = '50%'
      ..style.transform = 'translate(-50%, -50%)'
      ..style.width = '68px'
      ..style.height = '48px'
      ..style.backgroundColor = 'rgba(255,0,0,0.94)'
      ..style.borderRadius = '12px'
      ..style.display = 'flex'
      ..style.alignItems = 'center'
      ..style.justifyContent = 'center'
      ..style.boxShadow = '0 6px 18px rgba(0,0,0,0.45)';

    playBtn.setInnerHtml(
      '<svg width="34" height="34" viewBox="0 0 24 24" style="margin-left:4px"><path fill="#fff" d="M8 5v14l11-7z"/></svg>',
      treeSanitizer: html.NodeTreeSanitizer.trusted,
    );

    posterEl.children.addAll([gradient, playBtn]);

    final iframe = html.IFrameElement()
      ..style.border = 'none'
      ..style.position = 'absolute'
      ..style.top = '0'
      ..style.left = '0'
      ..style.right = '0'
      ..style.bottom = '0'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.display = 'none'
      ..allowFullscreen = true
      ..setAttribute(
        'allow',
        'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share; fullscreen',
      )
      ..setAttribute('referrerpolicy', 'strict-origin-when-cross-origin');

    void startPlay() {
      posterEl.style.display = 'none';
      iframe.style.display = 'block';
      iframe.src = YoutubeUrlHelper.embedUrl(
        videoId,
        autoplay: true,
        origin: Uri.base.origin,
        startSeconds: start,
      );
      iframe.onLoad.first.then((_) => _notifyReady());
    }

    posterEl.onClick.listen((_) => startPlay());
    _notifyReady();

    wrap.children.addAll([posterEl, iframe]);
    return wrap;
  }

  @override
  Widget build(BuildContext context) {
    if (!_registered) {
      return const ColoredBox(
        color: Color(0xFF0F0F0F),
        child: Center(
          child: SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Colors.white54,
            ),
          ),
        ),
      );
    }
    return HtmlElementView(viewType: _viewType);
  }
}
