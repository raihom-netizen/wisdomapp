import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../utils/youtube_url_helper.dart';
import 'course_media_view_policy.dart';

/// YouTube / MP4 no Android/iOS — WebView com HTML5 (fullscreen nativo do player).
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
  WebViewController? _controller;
  var _ready = false;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  @override
  void didUpdateWidget(covariant CourseVideoEmbed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.youtubeVideoId != widget.youtubeVideoId ||
        oldWidget.mp4Url != widget.mp4Url) {
      _initController();
    }
  }

  void _initController() {
    final yt = widget.youtubeVideoId?.trim();
    final mp4 = widget.mp4Url?.trim();
    final c = WebViewController()..setJavaScriptMode(JavaScriptMode.unrestricted);

    if (yt != null && yt.isNotEmpty) {
      c.loadRequest(
        Uri.parse(YoutubeUrlHelper.embedUrl(yt, autoplay: widget.autoplay)),
      );
    } else if (mp4 != null && mp4.isNotEmpty) {
      final escaped = mp4
          .replaceAll('&', '&amp;')
          .replaceAll('"', '&quot;')
          .replaceAll("'", '&#39;');
      final autoplayAttr = widget.autoplay ? 'autoplay' : '';
      c.loadHtmlString('''
<!DOCTYPE html>
<html><head>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<style>
  *{margin:0;padding:0;-webkit-user-select:none;user-select:none}
  html,body{width:100%;height:100%;background:#000}
  video{width:100%;height:100%;object-fit:contain}
</style>
<script>${CourseMediaViewPolicy.videoContextMenuBlockJs}</script>
</head><body>
<video controls playsinline preload="auto" controlslist="${CourseMediaViewPolicy.videoControlsList}" disablepictureinpicture oncontextmenu="return false;" $autoplayAttr src="$escaped"></video>
</body></html>
''');
    }

    setState(() {
      _controller = c;
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _controller == null) {
      return const ColoredBox(
        color: Color(0xFF0F0F0F),
        child: Center(child: CircularProgressIndicator(color: Colors.white54)),
      );
    }
    return WebViewWidget(controller: _controller!);
  }
}
