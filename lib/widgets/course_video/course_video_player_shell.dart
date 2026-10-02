import 'package:flutter/material.dart';

import '../../utils/course_media_url_resolver.dart';
import '../course_media_preview.dart';
import 'course_video_controller.dart';
import 'course_video_embed.dart';

/// Um player por vez no app inteiro.
///
/// Quando um player começa a tocar ele «reivindica» a vez; qualquer outro
/// player montado (feed com keep-alive, painel do módulo, tela de baixo da
/// tela cheia…) volta para a capa — o embed (WebView/iframe) é DESTRUÍDO, o
/// que libera memória e para o áudio duplicado.
class CourseActivePlayer {
  CourseActivePlayer._();

  static final ValueNotifier<Object?> active = ValueNotifier<Object?>(null);

  static void claim(Object token) {
    if (!identical(active.value, token)) active.value = token;
  }

  static void release(Object token) {
    if (identical(active.value, token)) active.value = null;
  }
}

/// Player estilo YouTube — capa/thumbnail até o usuário tocar ▶; depois embed nativo.
class CourseVideoPlayerShell extends StatefulWidget {
  const CourseVideoPlayerShell({
    super.key,
    this.posterData,
    this.youtubeVideoId,
    this.mp4Url,
    this.autoplay = false,
    this.accent = const Color(0xFF2563EB),
    this.accent2 = const Color(0xFF7C3AED),
    this.embedKey,
    this.courseId,
    this.startAtSeconds = 0,
    this.onProgress,
    this.contentTitle,
    this.contentType,
    this.controller,
  });

  /// Documento Firestore (title, thumbnailUrl, id…) para resolver a capa.
  final Map<String, dynamic>? posterData;
  final String? youtubeVideoId;
  final String? mp4Url;
  final bool autoplay;
  final Color accent;
  final Color accent2;
  final Key? embedKey;
  final String? courseId;
  final double startAtSeconds;
  final void Function(double position, double duration)? onProgress;
  final String? contentTitle;
  final String? contentType;

  /// Velocidade/pausa a partir da tela e última posição (tela cheia).
  final CourseVideoController? controller;

  @override
  State<CourseVideoPlayerShell> createState() => _CourseVideoPlayerShellState();
}

class _CourseVideoPlayerShellState extends State<CourseVideoPlayerShell> {
  final Object _token = Object();
  var _playbackStarted = false;
  var _embedReady = false;

  /// Outro player assumiu a vez — não religa sozinho (nem com autoplay).
  var _stoppedByOther = false;
  String? _posterUrl;
  String _posterFp = '';

  bool get _showEmbed => _playbackStarted;

  bool get _isYoutube =>
      widget.youtubeVideoId != null && widget.youtubeVideoId!.trim().isNotEmpty;

  /// Início explícito vindo de quem abriu o player (ex.: «Continuar» na tela
  /// do curso, feed e tela de assistir retomando a aula). Fixado na abertura
  /// da aula — o embed NÃO remonta quando muda (ver didUpdateWidget dos embeds).
  double get _effectiveStart => widget.startAtSeconds;

  /// Dados da capa: o documento ou, só com o ID do YouTube, um mínimo.
  Map<String, dynamic>? get _posterSource {
    final data = widget.posterData;
    if (data != null) return data;
    final yt = widget.youtubeVideoId?.trim();
    if (yt != null && yt.isNotEmpty) return {'youtubeVideoId': yt};
    return null;
  }

  /// Identidade estável do conteúdo — o pai costuma recriar o Map do
  /// documento a cada build; comparar a instância PARAVA o vídeo em qualquer
  /// rebuild (busca, progresso, rolagem do feed).
  String _computePosterFp() {
    final src = _posterSource;
    return src == null
        ? ''
        : CourseMediaUrlResolver.imageFingerprint(src,
            docId: src['id']?.toString());
  }

  @override
  void initState() {
    super.initState();
    _playbackStarted = widget.autoplay;
    _posterFp = _computePosterFp();
    CourseActivePlayer.active.addListener(_onActiveChanged);
    if (_playbackStarted) _claimAfterFrame();
    _resolvePoster();
  }

  @override
  void dispose() {
    CourseActivePlayer.active.removeListener(_onActiveChanged);
    CourseActivePlayer.release(_token);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CourseVideoPlayerShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final fp = _computePosterFp();
    final sourceChanged = oldWidget.youtubeVideoId != widget.youtubeVideoId ||
        oldWidget.mp4Url != widget.mp4Url;
    if (sourceChanged || fp != _posterFp) {
      _posterFp = fp;
      if (sourceChanged) {
        _embedReady = false;
        if (!widget.autoplay) _playbackStarted = false;
        _stoppedByOther = false;
      }
      _resolvePoster();
    }
    if (widget.autoplay && !_playbackStarted && !_stoppedByOther) {
      _playbackStarted = true;
      _claimAfterFrame();
    }
  }

  /// Reivindica depois do frame — nunca chama setState de outro player
  /// durante o build.
  void _claimAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _playbackStarted) CourseActivePlayer.claim(_token);
    });
  }

  void _onActiveChanged() {
    final current = CourseActivePlayer.active.value;
    if (current == null || identical(current, _token)) return;
    if (!mounted || !_playbackStarted) return;
    setState(() {
      _playbackStarted = false;
      _embedReady = false;
      _stoppedByOther = true;
    });
  }

  /// URL da capa só para o `poster` do embed (MP4). A capa visível é a
  /// [CourseMediaThumbnail], que escolhe a resolução pelo tamanho do quadro.
  Future<void> _resolvePoster() async {
    final src = _posterSource;
    final fp = _posterFp;
    if (src == null) {
      if (_posterUrl != null && mounted) setState(() => _posterUrl = null);
      return;
    }
    final cached = CourseMediaUrlResolver.cachedImageUrls(
      src,
      docId: src['id']?.toString(),
      light: true,
    );
    if (cached != null && cached.isNotEmpty) {
      _posterUrl = cached.first;
      return;
    }
    try {
      final urls = await CourseMediaUrlResolver.resolveImageUrls(
        src,
        docId: src['id']?.toString(),
        light: true,
      );
      if (!mounted || fp != _posterFp) return;
      final next = urls.isEmpty ? null : urls.first;
      if (next != _posterUrl) setState(() => _posterUrl = next);
    } catch (_) {
      // capa é opcional
    }
  }

  void _startPlayback() {
    if (_playbackStarted) return;
    setState(() {
      _playbackStarted = true;
      _embedReady = false;
      _stoppedByOther = false;
    });
    CourseActivePlayer.claim(_token);
  }

  void _onEmbedReady() {
    if (!mounted || _embedReady) return;
    setState(() => _embedReady = true);
  }

  void _onProgress(double position, double duration) {
    widget.controller?.reportProgress(position, duration);
    // Quem abriu o player (tela do curso, feed, módulo, tela de assistir)
    // grava o progresso da aula via CourseProgressService.recordLessonProgress.
    widget.onProgress?.call(position, duration);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_showEmbed)
          CourseVideoEmbed(
            key: widget.embedKey,
            youtubeVideoId: widget.youtubeVideoId,
            mp4Url: widget.mp4Url,
            autoplay: true,
            posterUrl: _posterUrl,
            startAtSeconds: _effectiveStart,
            onReady: _onEmbedReady,
            onProgress: _onProgress,
            controller: widget.controller,
          ),
        if (!_showEmbed)
          Positioned.fill(
            child: _posterOverlay(
              onPlay: _startPlayback,
              showPlayButton: true,
            ),
          ),
        if (_showEmbed && !_embedReady)
          Positioned.fill(
            child: IgnorePointer(
              child: _posterOverlay(showPlayButton: false),
            ),
          ),
      ],
    );
  }

  Widget _posterOverlay({
    VoidCallback? onPlay,
    bool showPlayButton = true,
  }) {
    final src = _posterSource;
    return Material(
      color: Colors.black,
      child: InkWell(
        onTap: onPlay,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (src != null)
              // Destaque: maior capa disponível conforme a largura × DPR
              // (maxres em telas grandes/retina), sempre inteira.
              CourseMediaThumbnail.fromData(
                src,
                showPlayButton: false,
                light: false,
                fallback: _gradientFallback(),
              )
            else
              _gradientFallback(),
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.05),
                      Colors.black.withValues(alpha: 0.55),
                    ],
                  ),
                ),
              ),
            ),
            if (showPlayButton)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PlayButton(
                      isYoutube: _isYoutube,
                      accent: widget.accent,
                      accent2: widget.accent2,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _gradientFallback() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A1A2E),
            widget.accent.withValues(alpha: 0.55),
            const Color(0xFF0F0F0F),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.ondemand_video_rounded,
          size: 56,
          color: Colors.white.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.isYoutube,
    required this.accent,
    required this.accent2,
  });

  final bool isYoutube;
  final Color accent;
  final Color accent2;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFFFF0000),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: accent.withValues(alpha: 0.15),
            blurRadius: 8,
          ),
        ],
      ),
      child: Icon(
        Icons.play_arrow_rounded,
        color: Colors.white.withValues(alpha: isYoutube ? 1 : 0.98),
        size: 40,
      ),
    );
  }
}
