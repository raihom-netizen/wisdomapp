import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../utils/course_media_url_resolver.dart';

/// Abre MP4(s) do documento — lista se houver mais de um vídeo.
Future<void> openCourseMp4FromData(
  BuildContext context, {
  required Map<String, dynamic> data,
  required String title,
}) async {
  final videos = await CourseMediaUrlResolver.resolveVideoEntries(data);
  if (videos.isEmpty) return;
  if (!context.mounted) return;
  if (videos.length == 1) {
    await showCourseMp4PlayerDialog(
      context,
      videoUrl: videos.first.url,
      title: title,
    );
    return;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Escolha o vídeo',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < videos.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFF2563EB).withValues(alpha: 0.12),
                  child: Icon(Icons.play_arrow_rounded, color: Colors.blue.shade700),
                ),
                title: Text(
                  videos[i].label ?? 'Vídeo ${i + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await showCourseMp4PlayerDialog(
                    context,
                    videoUrl: videos[i].url,
                    title: '${videos[i].label ?? 'Vídeo ${i + 1}'} · $title',
                  );
                },
              ),
            ),
        ],
      ),
    ),
  );
}

/// Player de vídeo MP4/WebM hospedado no Firebase Storage.
Future<void> showCourseMp4PlayerDialog(
  BuildContext context, {
  required String videoUrl,
  required String title,
}) async {
  final escaped = videoUrl
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
  final html = '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body { width: 100%; height: 100%; background: #000; }
  video { width: 100%; height: 100%; object-fit: contain; }
</style>
</head>
<body>
  <video controls autoplay playsinline preload="metadata" src="$escaped"></video>
</body>
</html>
''';

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..loadHtmlString(html);
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
        backgroundColor: const Color(0xFF0F0F0F),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              AspectRatio(
                aspectRatio: 16 / 9,
                child: WebViewWidget(controller: controller),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}
