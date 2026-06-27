import 'package:flutter/material.dart';

import 'course_video/course_video_watch_screen.dart';

/// Abre MP4(s) do documento — lista se houver mais de um vídeo.
Future<void> openCourseMp4FromData(
  BuildContext context, {
  required Map<String, dynamic> data,
  required String title,
  List<Map<String, dynamic>> related = const [],
}) {
  return openCourseVideoFromData(
    context,
    data: {...data, 'title': title},
    related: related,
  );
}

/// Player MP4 — abre tela estilo YouTube (compatível Web + mobile).
Future<void> showCourseMp4PlayerDialog(
  BuildContext context, {
  required String videoUrl,
  required String title,
}) {
  return openMp4WatchScreen(context, videoUrl: videoUrl, title: title);
}
