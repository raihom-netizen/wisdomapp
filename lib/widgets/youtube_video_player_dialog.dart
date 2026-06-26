import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../utils/youtube_url_helper.dart';

/// Player YouTube embutido (padrão iframe / WebView).
Future<void> showYoutubeVideoPlayerDialog(
  BuildContext context, {
  required String videoId,
  required String title,
}) async {
  final embed = YoutubeUrlHelper.embedUrl(videoId);
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..loadRequest(Uri.parse(embed));
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
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
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded),
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
