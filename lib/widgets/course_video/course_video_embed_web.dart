import 'dart:ui_web' as ui_web;

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/material.dart';

import '../../utils/youtube_url_helper.dart';

/// YouTube / MP4 na Web — iframe e `<video>` nativos (sem WebView).
class CourseVideoEmbed extends StatefulWidget {
  const CourseVideoEmbed({
    super.key,
    this.youtubeVideoId,
    this.mp4Url,
    this.autoplay = true,
  });

  final String? youtubeVideoId;
  final String? mp4Url;
  final bool autoplay;

  @override
  State<CourseVideoEmbed> createState() => _CourseVideoEmbedState();
}

class _CourseVideoEmbedState extends State<CourseVideoEmbed> {
  static int _viewCounter = 0;
  late final String _viewType;
  bool _registered = false;

  @override
  void initState() {
    super.initState();
    _viewType = 'course-video-${++_viewCounter}';
    _registerView();
  }

  void _registerView() {
    if (_registered) return;
    final yt = widget.youtubeVideoId?.trim();
    final mp4 = widget.mp4Url?.trim();
    final origin = Uri.base.origin;

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      if (yt != null && yt.isNotEmpty) {
        final iframe = html.IFrameElement()
          ..src = YoutubeUrlHelper.embedUrl(
            yt,
            autoplay: widget.autoplay,
            origin: origin,
          )
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%'
          ..allowFullscreen = true
          ..setAttribute(
            'allow',
            'accelerometer; autoplay; clipboard-write; encrypted-media; '
            'gyroscope; picture-in-picture; web-share; fullscreen',
          );
        return iframe;
      }
      if (mp4 != null && mp4.isNotEmpty) {
        final video = html.VideoElement()
          ..src = mp4
          ..controls = true
          ..autoplay = widget.autoplay
          ..setAttribute('playsinline', 'true')
          ..preload = 'auto'
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.objectFit = 'contain'
          ..style.backgroundColor = '#000';
        return video;
      }
      return html.DivElement()
        ..style.color = '#fff'
        ..text = 'Vídeo indisponível';
    });
    _registered = true;
    if (mounted) setState(() {});
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
            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white54),
          ),
        ),
      );
    }
    return HtmlElementView(viewType: _viewType);
  }
}
