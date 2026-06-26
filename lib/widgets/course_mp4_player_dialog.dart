import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
