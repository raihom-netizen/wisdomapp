import 'package:flutter/material.dart';

import 'course_video_controller.dart';

/// Embed de vídeo (stub — mobile usa WebView).
class CourseVideoEmbed extends StatelessWidget {
  const CourseVideoEmbed({
    super.key,
    this.youtubeVideoId,
    this.mp4Url,
    this.autoplay = true,
    this.posterUrl,
    this.startAtSeconds = 0,
    this.onReady,
    this.onProgress,
    this.controller,
  });

  final String? youtubeVideoId;
  final String? mp4Url;
  final bool autoplay;
  final String? posterUrl;
  final double startAtSeconds;
  final VoidCallback? onReady;
  final void Function(double position, double duration)? onProgress;
  final CourseVideoController? controller;

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF0F0F0F),
      child: Center(
        child: CircularProgressIndicator(color: Colors.white54),
      ),
    );
  }
}
