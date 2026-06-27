import 'package:flutter/material.dart';

/// Embed de vídeo (stub — mobile usa WebView).
class CourseVideoEmbed extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF0F0F0F),
      child: Center(
        child: CircularProgressIndicator(color: Colors.white54),
      ),
    );
  }
}
