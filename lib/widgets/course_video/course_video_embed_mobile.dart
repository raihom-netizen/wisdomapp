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
    this.posterUrl,
    this.onReady,
  });

  final String? youtubeVideoId;
  final String? mp4Url;
  final bool autoplay;
  final String? posterUrl;
  final VoidCallback? onReady;

  @override
  State<CourseVideoEmbed> createState() => _CourseVideoEmbedState();
}

class _CourseVideoEmbedState extends State<CourseVideoEmbed> {
  WebViewController? _controller;
  var _ready = false;
  var _notifiedReady = false;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  @override
  void didUpdateWidget(covariant CourseVideoEmbed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.youtubeVideoId != widget.youtubeVideoId ||
        oldWidget.mp4Url != widget.mp4Url ||
        oldWidget.posterUrl != widget.posterUrl ||
        oldWidget.autoplay != widget.autoplay) {
      _notifiedReady = false;
      _initController();
    }
  }

  void _notifyReady() {
    if (_notifiedReady) return;
    _notifiedReady = true;
    widget.onReady?.call();
  }

  String _escapeAttr(String raw) => raw
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');

  void _initController() {
    final yt = widget.youtubeVideoId?.trim();
    final mp4 = widget.mp4Url?.trim();
    final poster = widget.posterUrl?.trim();
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _notifyReady(),
        ),
      );

    if (yt != null && yt.isNotEmpty) {
      final thumb = poster ?? YoutubeUrlHelper.thumbnailUrl(yt);
      if (!widget.autoplay && thumb.isNotEmpty) {
        c.loadHtmlString(_youtubePosterHtml(yt, thumb));
      } else {
        c.loadRequest(
          Uri.parse(YoutubeUrlHelper.embedUrl(yt, autoplay: widget.autoplay)),
        );
      }
    } else if (mp4 != null && mp4.isNotEmpty) {
      c.loadHtmlString(_mp4Html(mp4, poster));
    }

    setState(() {
      _controller = c;
      _ready = true;
    });
  }

  String _youtubePosterHtml(String videoId, String thumbUrl) {
    final embed = _escapeAttr(
      YoutubeUrlHelper.embedUrl(videoId, autoplay: true),
    );
    final thumb = _escapeAttr(thumbUrl);
    return '''
<!DOCTYPE html>
<html><head>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<style>
  *{margin:0;padding:0;box-sizing:border-box;-webkit-user-select:none;user-select:none}
  html,body{width:100%;height:100%;background:#000;overflow:hidden}
  #wrap{position:relative;width:100%;height:100%}
  #poster,#player{position:absolute;inset:0;width:100%;height:100%;border:0}
  #poster{background:#000 center/cover no-repeat;cursor:pointer}
  #poster::after{content:'';position:absolute;inset:0;background:linear-gradient(180deg,rgba(0,0,0,.08),rgba(0,0,0,.42))}
  #poster .play{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);width:68px;height:48px;background:rgba(255,0,0,.94);border-radius:12px;display:flex;align-items:center;justify-content:center;box-shadow:0 6px 18px rgba(0,0,0,.45)}
  #poster .play svg{width:34px;height:34px;fill:#fff;margin-left:4px}
  #player{display:none;background:#000}
</style>
<script>${CourseMediaViewPolicy.videoContextMenuBlockJs}</script>
</head><body>
<div id="wrap">
  <div id="poster" style="background-image:url('$thumb')">
    <div class="play"><svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg></div>
  </div>
  <iframe id="player" allow="accelerometer; autoplay; encrypted-media; gyroscope; fullscreen" allowfullscreen></iframe>
</div>
<script>
(function(){
  var poster=document.getElementById('poster');
  var player=document.getElementById('player');
  function start(){
    poster.style.display='none';
    player.style.display='block';
    player.src='$embed';
  }
  poster.addEventListener('click', start);
})();
</script>
</body></html>
''';
  }

  String _mp4Html(String mp4, String? poster) {
    final escaped = _escapeAttr(mp4);
    final autoplayAttr = widget.autoplay ? 'autoplay' : '';
    final hasPoster = poster != null && poster.isNotEmpty;
    final posterAttr = hasPoster ? 'poster="${_escapeAttr(poster)}"' : '';
    final seekFirstFrame = hasPoster ? 'false' : 'true';
    return '''
<!DOCTYPE html>
<html><head>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<style>
  *{margin:0;padding:0;-webkit-user-select:none;user-select:none}
  html,body{width:100%;height:100%;background:#000}
  video{width:100%;height:100%;object-fit:contain;background:#000}
</style>
<script>${CourseMediaViewPolicy.videoContextMenuBlockJs}</script>
</head><body>
<video id="v" controls playsinline preload="auto" controlslist="${CourseMediaViewPolicy.videoControlsList}" disablepictureinpicture oncontextmenu="return false;" $autoplayAttr $posterAttr src="$escaped"></video>
<script>
(function(){
  var v=document.getElementById('v');
  function ready(){ try { window.flutterReady && window.flutterReady.postMessage('1'); } catch(e){} }
  v.addEventListener('loadeddata', ready, {once:true});
  if($seekFirstFrame){
    v.addEventListener('loadeddata', function(){
      try { v.currentTime = 0.05; } catch(e){}
    }, {once:true});
  }
  if(v.readyState >= 2) ready();
})();
</script>
</body></html>
''';
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
