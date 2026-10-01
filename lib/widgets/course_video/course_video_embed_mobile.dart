import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../utils/youtube_url_helper.dart';
import 'course_media_view_policy.dart';

/// Origem HTTPS do HTML do player no Android/iOS.
///
/// Sem `baseUrl`, o `loadHtmlString` roda em `about:blank` e o iframe do
/// YouTube não recebe Referer/origin — desde 2025 o YouTube recusa esse embed
/// com «Erro 153 · erro de configuração do player» (vídeo não toca no app).
const String _kYoutubeEmbedBaseUrl = 'https://wisdomapp.com.br';

/// YouTube / MP4 no Android/iOS — WebView com HTML5 (fullscreen nativo do player).
class CourseVideoEmbed extends StatefulWidget {
  const CourseVideoEmbed({
    super.key,
    this.youtubeVideoId,
    this.mp4Url,
    this.autoplay = true,
    this.posterUrl,
    this.startAtSeconds = 0,
    this.onReady,
    this.onProgress,
  });

  final String? youtubeVideoId;
  final String? mp4Url;
  final bool autoplay;
  final String? posterUrl;
  final double startAtSeconds;
  final VoidCallback? onReady;
  final void Function(double position, double duration)? onProgress;

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
    // NÃO remontar só por startAtSeconds — isso resetava o vídeo ao meio da reprodução.
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

  void _onProgressMessage(JavaScriptMessage msg) {
    try {
      final data = jsonDecode(msg.message);
      if (data is Map) {
        final pos = (data['t'] as num?)?.toDouble() ?? 0;
        final dur = (data['d'] as num?)?.toDouble() ?? 0;
        widget.onProgress?.call(pos, dur);
      }
    } catch (_) {}
  }

  String _escapeAttr(String raw) => raw
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');

  void _initController() {
    final yt = widget.youtubeVideoId?.trim();
    final mp4 = widget.mp4Url?.trim();
    final poster = widget.posterUrl?.trim();
    final start = widget.startAtSeconds > 8 ? widget.startAtSeconds.round() : 0;
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'CourseProgress',
        onMessageReceived: _onProgressMessage,
      )
      ..addJavaScriptChannel(
        'flutterReady',
        onMessageReceived: (_) => _notifyReady(),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _notifyReady(),
        ),
      );

    if (yt != null && yt.isNotEmpty) {
      final thumb = poster ?? YoutubeUrlHelper.thumbnailUrl(yt);
      if (!widget.autoplay && thumb.isNotEmpty) {
        c.loadHtmlString(
          _youtubePosterHtml(yt, thumb, start),
          baseUrl: _kYoutubeEmbedBaseUrl,
        );
      } else {
        c.loadHtmlString(
          _youtubeApiHtml(yt, start, autoplay: widget.autoplay),
          baseUrl: _kYoutubeEmbedBaseUrl,
        );
      }
    } else if (mp4 != null && mp4.isNotEmpty) {
      c.loadHtmlString(_mp4Html(mp4, poster, start));
    }

    setState(() {
      _controller = c;
      _ready = true;
    });
  }

  String _youtubePosterHtml(String videoId, String thumbUrl, int start) {
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
  <div id="player"></div>
</div>
<script src="https://www.youtube.com/iframe_api"></script>
<script>
var startAt=$start;
var ytPlayer=null;
function postProg(){
  try{
    if(!ytPlayer||!ytPlayer.getCurrentTime) return;
    var t=ytPlayer.getCurrentTime()||0;
    var d=ytPlayer.getDuration()||0;
    CourseProgress.postMessage(JSON.stringify({t:t,d:d}));
  }catch(e){}
}
function onYouTubeIframeAPIReady(){}
function bootPlayer(){
  document.getElementById('poster').style.display='none';
  document.getElementById('player').style.display='block';
  ytPlayer=new YT.Player('player',{
    videoId:'$videoId',
    playerVars:{autoplay:1,rel:0,modestbranding:1,playsinline:1,fs:1,start:startAt,iv_load_policy:3,origin:'$_kYoutubeEmbedBaseUrl',widget_referrer:'$_kYoutubeEmbedBaseUrl'},
    events:{
      onReady:function(e){ try{e.target.playVideo();}catch(x){} setInterval(postProg,4000); },
      onStateChange:function(e){ if(e.data===1||e.data===2||e.data===0) postProg(); }
    }
  });
}
(function(){
  var poster=document.getElementById('poster');
  poster.addEventListener('click', function(){
    if(window.YT && YT.Player){ bootPlayer(); }
    else {
      var t=setInterval(function(){
        if(window.YT && YT.Player){ clearInterval(t); bootPlayer(); }
      },200);
    }
  });
})();
</script>
</body></html>
''';
  }

  String _youtubeApiHtml(String videoId, int start, {required bool autoplay}) {
    return '''
<!DOCTYPE html>
<html><head>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<style>
  *{margin:0;padding:0;box-sizing:border-box}
  html,body{width:100%;height:100%;background:#000;overflow:hidden}
  #player{width:100%;height:100%}
</style>
</head><body>
<div id="player"></div>
<script src="https://www.youtube.com/iframe_api"></script>
<script>
var startAt=$start;
var ytPlayer=null;
function postProg(){
  try{
    if(!ytPlayer||!ytPlayer.getCurrentTime) return;
    CourseProgress.postMessage(JSON.stringify({t:ytPlayer.getCurrentTime()||0,d:ytPlayer.getDuration()||0}));
  }catch(e){}
}
function onYouTubeIframeAPIReady(){
  ytPlayer=new YT.Player('player',{
    videoId:'$videoId',
    playerVars:{autoplay:${autoplay ? 1 : 0},rel:0,modestbranding:1,playsinline:1,fs:1,start:startAt,iv_load_policy:3,origin:'$_kYoutubeEmbedBaseUrl',widget_referrer:'$_kYoutubeEmbedBaseUrl'},
    events:{
      onReady:function(e){ try{ window.flutterReady && flutterReady.postMessage('1'); }catch(x){} if($autoplay){try{e.target.playVideo();}catch(x){}} setInterval(postProg,4000); },
      onStateChange:function(e){ if(e.data===1||e.data===2||e.data===0) postProg(); }
    }
  });
}
</script>
</body></html>
''';
  }

  String _mp4Html(String mp4, String? poster, int start) {
    final escaped = _escapeAttr(mp4);
    final autoplayAttr = widget.autoplay ? 'autoplay' : '';
    final hasPoster = poster != null && poster.isNotEmpty;
    final posterAttr = hasPoster ? 'poster="${_escapeAttr(poster)}"' : '';
    final seekFirstFrame = (!hasPoster && start <= 0) ? 'true' : 'false';
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
  var startAt=$start;
  function ready(){ try { window.flutterReady && window.flutterReady.postMessage('1'); } catch(e){} }
  function post(){
    try{
      CourseProgress.postMessage(JSON.stringify({t:v.currentTime||0,d:v.duration||0}));
    }catch(e){}
  }
  v.addEventListener('loadeddata', ready, {once:true});
  v.addEventListener('loadedmetadata', function(){
    if(startAt>0){ try{ v.currentTime=startAt; }catch(e){} }
    else if($seekFirstFrame){ try{ v.currentTime=0.05; }catch(e){} }
  }, {once:true});
  v.addEventListener('timeupdate', function(){
    if(!v._lastPost || (Date.now()-v._lastPost)>3500){ v._lastPost=Date.now(); post(); }
  });
  v.addEventListener('pause', post);
  v.addEventListener('ended', post);
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
