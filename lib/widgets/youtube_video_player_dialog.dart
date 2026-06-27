import 'package:flutter/material.dart';

import 'course_video/course_video_watch_screen.dart';

/// Player YouTube — abre tela estilo YouTube (compatível Web + mobile).
Future<void> showYoutubeVideoPlayerDialog(
  BuildContext context, {
  required String videoId,
  required String title,
}) {
  return openYoutubeWatchScreen(context, videoId: videoId, title: title);
}
