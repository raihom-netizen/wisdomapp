import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../utils/course_media_url_resolver.dart';
import '../utils/course_thumb_resolver.dart';
import '../utils/youtube_url_helper.dart';
import 'course_video/course_photo_lightbox.dart';
import 'course_video/course_protected_image.dart';
import 'course_video/course_video_frame_preview.dart';

/// Preview de imagem — imagem inteira visível (contain), fundo escuro, alta qualidade.
class CourseImagePreview extends StatelessWidget {
  const CourseImagePreview({
    super.key,
    this.bytes,
    this.networkUrl,
    this.firestoreData,
    this.maxHeight = 240,
    this.subtitle,
  });

  final Uint8List? bytes;
  final String? networkUrl;
  final Map<String, dynamic>? firestoreData;
  final double maxHeight;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final hasBytes = bytes != null && bytes!.isNotEmpty;
    final url = networkUrl?.trim() ?? '';
    final hasData = firestoreData != null;
    if (!hasBytes && url.isEmpty && !hasData) return const SizedBox.shrink();

    Widget image;
    if (hasBytes) {
      image = Image.memory(
        bytes!,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
      );
    } else if (hasData) {
      image = CoursePhotoGallery(data: firestoreData!, height: maxHeight - 40);
    } else {
      image = CourseMediaThumbnail(
        urls: [url],
        fit: BoxFit.contain,
        borderRadius: BorderRadius.circular(12),
        showPlayButton: false,
        showBottomGradient: false,
      );
    }

    return Container(
      width: double.infinity,
      height: maxHeight,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF0F172A),
            const Color(0xFF1E293B).withValues(alpha: 0.95),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (subtitle != null && subtitle!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.65),
                ),
              ),
            ),
          Expanded(child: Center(child: image)),
        ],
      ),
    );
  }
}

/// Galeria moderna — deslize horizontal entre fotos (até 10).
class CoursePhotoGallery extends StatefulWidget {
  const CoursePhotoGallery({
    super.key,
    required this.data,
    this.height = 260,
    this.fit = BoxFit.contain,
    this.borderRadius = BorderRadius.zero,
    this.showIndicators = true,
    this.allowExpand = true,
    this.title,
    this.accent = const Color(0xFF2563EB),
  });

  final Map<String, dynamic> data;
  final double height;
  final BoxFit fit;
  final BorderRadius borderRadius;
  final bool showIndicators;
  final bool allowExpand;
  final String? title;
  final Color accent;

  @override
  State<CoursePhotoGallery> createState() => _CoursePhotoGalleryState();
}

class _CoursePhotoGalleryState extends State<CoursePhotoGallery>
    with AutomaticKeepAliveClientMixin {
  final PageController _pageCtrl = PageController();
  List<String> _urls = const [];
  bool _loading = true;
  int _index = 0;
  String? _loadedDocId;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CoursePhotoGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newId = widget.data['id']?.toString() ?? '';
    if (newId != _loadedDocId) _load();
  }

  Future<void> _load() async {
    final docId = widget.data['id']?.toString() ?? '';
    if (!_loading && docId.isNotEmpty && docId == _loadedDocId && _urls.isNotEmpty) {
      return;
    }
    if (mounted) setState(() => _loading = true);
    final urls = await CourseMediaUrlResolver.resolveImageUrls(
      widget.data,
      docId: docId.isEmpty ? null : docId,
    );
    if (!mounted) return;
    setState(() {
      _urls = urls;
      _loading = false;
      _index = 0;
      _loadedDocId = docId.isEmpty ? null : docId;
    });
  }

  void _openExpanded([int? atIndex]) {
    if (!widget.allowExpand || _urls.isEmpty) return;
    CoursePhotoLightbox.open(
      context,
      urls: _urls,
      initialIndex: atIndex ?? _index,
      title: widget.title ?? (widget.data['title'] ?? '').toString(),
      accent: widget.accent,
    );
  }

  Widget _wrapExpandable(Widget child) {
    if (!widget.allowExpand) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(onTap: () => _openExpanded(), child: child),
        Positioned(
          right: 10,
          bottom: 10,
          child: Material(
            color: Colors.black.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(999),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _openExpanded(),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.zoom_out_map_rounded, color: Colors.white, size: 16),
                    SizedBox(width: 5),
                    Text(
                      'Ampliar',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return SizedBox(
        height: widget.height,
        child: const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }
    if (_urls.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.image_not_supported_outlined,
                size: 40,
                color: Colors.white.withValues(alpha: 0.45),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Recarregar imagem'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_urls.length == 1) {
      return ClipRRect(
        borderRadius: widget.borderRadius,
        child: SizedBox(
          height: widget.height,
          child: _wrapExpandable(_networkImage(_urls.first)),
        ),
      );
    }

    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: SizedBox(
        height: widget.height,
        child: _wrapExpandable(
          Stack(
            fit: StackFit.expand,
            children: [
              PageView.builder(
                controller: _pageCtrl,
                itemCount: _urls.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => _networkImage(_urls[i]),
              ),
              if (widget.showIndicators) ...[
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 10,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_urls.length, (i) {
                      final active = i == _index;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: active ? 18 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: active
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      );
                    }),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${_index + 1}/${_urls.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Widget _networkImage(String url) {
    return ColoredBox(
      color: const Color(0xFF0F172A),
      child: CourseProtectedNetworkImage(
        url: url,
        fit: widget.fit,
        loading: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
        error: Center(
          child: Icon(
            Icons.broken_image_outlined,
            size: 36,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}

/// Card moderno para vídeo MP4 selecionado (admin).
class CourseVideoFilePreview extends StatelessWidget {
  const CourseVideoFilePreview({
    super.key,
    required this.fileName,
    required this.sizeBytes,
    this.onRemove,
    this.accent = const Color(0xFF2563EB),
    this.busy = false,
  });

  final String fileName;
  final int sizeBytes;
  final VoidCallback? onRemove;
  final Color accent;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final mb = sizeBytes / (1024 * 1024);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF0F172A),
            accent.withValues(alpha: 0.35),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.play_circle_fill_rounded,
              color: accent.withValues(alpha: 0.95),
              size: 32,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  sizeBytes > 0
                      ? '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB · MP4'
                      : 'MP4 anexado',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (onRemove != null && !busy)
            IconButton(
              onPressed: onRemove,
              icon: Icon(Icons.close_rounded, color: Colors.white.withValues(alpha: 0.85)),
              tooltip: 'Remover vídeo',
            ),
        ],
      ),
    );
  }
}

/// Capa estilo YouTube — 16:9, Full HD, fallback em cascata, botão play.
class CourseMediaThumbnail extends StatefulWidget {
  const CourseMediaThumbnail({
    super.key,
    this.urls = const [],
    this.firestoreData,
    this.fit = BoxFit.cover,
    this.fallback,
    this.borderRadius = BorderRadius.zero,
    this.showPlayButton = true,
    this.isYoutube = false,
    this.showBottomGradient = true,
    this.playIconSize = 56,
    this.light = true,
  });

  /// Construtor a partir de documento Firestore.
  factory CourseMediaThumbnail.fromData(
    Map<String, dynamic> data, {
    String? docId,
    BoxFit? fit,
    Widget? fallback,
    BorderRadius borderRadius = BorderRadius.zero,
    bool showPlayButton = true,
    double playIconSize = 56,
    bool light = true,
  }) {
    final merged = docId != null
        ? CourseMediaUrlResolver.enrichWithDocId(data, docId)
        : data;
    final isVideo = CourseThumbResolver.isVideoContent(merged);
    final isYt = CourseThumbResolver.videoIdFromData(merged) != null;
    final photo = CourseThumbResolver.isDicaPhoto(merged) ||
        CourseMediaUrlResolver.hasResolvableImage(merged);
    return CourseMediaThumbnail(
      firestoreData: merged,
      fit: fit ?? (photo ? BoxFit.contain : BoxFit.cover),
      fallback: fallback,
      borderRadius: borderRadius,
      showPlayButton: showPlayButton && (isVideo || isYt),
      isYoutube: isYt,
      showBottomGradient: showPlayButton,
      playIconSize: playIconSize,
      light: light,
    );
  }

  /// Compatibilidade com [CourseCoverImage].
  factory CourseMediaThumbnail.network({
    required String url,
    BoxFit fit = BoxFit.cover,
    Widget? fallback,
    BorderRadius borderRadius = BorderRadius.zero,
    bool showPlayButton = false,
  }) {
    final u = url.trim();
    return CourseMediaThumbnail(
      urls: u.isEmpty ? const [] : [u],
      fit: fit,
      fallback: fallback,
      borderRadius: borderRadius,
      showPlayButton: showPlayButton,
      showBottomGradient: showPlayButton,
    );
  }

  final List<String> urls;
  final Map<String, dynamic>? firestoreData;
  final BoxFit fit;
  final Widget? fallback;
  final BorderRadius borderRadius;
  final bool showPlayButton;
  final bool isYoutube;
  final bool showBottomGradient;
  final double playIconSize;

  /// Capa leve do YouTube (hq/mq) — padrão para listas/cards/pôster.
  final bool light;

  @override
  State<CourseMediaThumbnail> createState() => _CourseMediaThumbnailState();
}

class _CourseMediaThumbnailState extends State<CourseMediaThumbnail> {
  int _urlIndex = 0;
  bool _loaded = false;
  bool _failedAll = false;
  bool _resolving = true;
  List<String> _resolvedUrls = const [];
  String _fingerprint = '';
  String? _ytId;

  /// MP4 sem capa nem YouTube: link do 1º vídeo para a prévia (quadro).
  Future<String?>? _videoUrl;
  Set<String> _posterUrls = const {};

  void _prepararPreviaVideo() {
    final data = widget.firestoreData;
    _posterUrls = data == null
        ? const {}
        : CourseMediaUrlResolver.videoPosterUrls(data).toSet();
    if (data == null || _ytId != null) {
      _videoUrl = null;
      return;
    }
    final ref = CourseMediaUrlResolver.firstVideoRef(data);
    if (ref == null) {
      _videoUrl = null;
    } else if (CourseMediaUrlResolver.looksLikeHttpUrl(ref)) {
      _videoUrl = Future.value(ref);
    } else {
      _videoUrl = CourseMediaUrlResolver.resolveFirstVideoUrl(data);
    }
  }

  /// Identidade estável: o pai costuma recriar o Map a cada build
  /// (`{...doc.data, 'id': doc.id}`) — comparar a instância refazia a
  /// resolução (Storage) e a capa piscava a cada letra da busca.
  String _computeFingerprint() {
    final data = widget.firestoreData;
    return data != null
        ? CourseMediaUrlResolver.imageFingerprint(data,
            docId: data['id']?.toString())
        : widget.urls.join('|');
  }

  @override
  void initState() {
    super.initState();
    _fingerprint = _computeFingerprint();
    final data = widget.firestoreData;
    _ytId = data != null ? CourseThumbResolver.videoIdFromData(data) : null;
    _prepararPreviaVideo();
    // Capa já resolvida antes (outro card / volta da rolagem): sem spinner.
    final cached = data != null
        ? CourseMediaUrlResolver.cachedImageUrls(
            data,
            docId: data['id']?.toString(),
            light: true,
          )
        : null;
    if (cached != null && cached.isNotEmpty) {
      _resolvedUrls = cached;
      _resolving = false;
    } else {
      _resolveUrls(initial: true);
    }
  }

  @override
  void didUpdateWidget(covariant CourseMediaThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    final fp = _computeFingerprint();
    if (fp != _fingerprint) {
      _fingerprint = fp;
      final data = widget.firestoreData;
      _ytId = data != null ? CourseThumbResolver.videoIdFromData(data) : null;
      _prepararPreviaVideo();
      _urlIndex = 0;
      _loaded = false;
      _failedAll = false;
      _resolveUrls();
    } else if (oldWidget.light != widget.light) {
      _urlIndex = 0;
      _failedAll = false;
    }
  }

  Future<void> _resolveUrls({bool initial = false}) async {
    if (initial) {
      _resolving = true;
    } else {
      setState(() {
        _resolving = true;
        _failedAll = false;
        _urlIndex = 0;
        _loaded = false;
      });
    }
    final requestFp = _fingerprint;
    try {
      List<String> urls;
      if (widget.firestoreData != null) {
        final docId = widget.firestoreData!['id']?.toString();
        // Sempre o modo leve no resolver (memo compartilhado, sem varrer o
        // Storage quando há YouTube); a resolução do YouTube é escolhida no
        // build conforme o tamanho real do quadro.
        urls = await CourseMediaUrlResolver.resolveImageUrls(
          widget.firestoreData!,
          docId: docId,
          light: true,
        );
      } else {
        urls = await CourseMediaUrlResolver.resolveRawUrls(widget.urls);
      }
      // Resposta atrasada de um conteúdo antigo não sobrescreve o atual.
      if (!mounted || requestFp != _fingerprint) return;
      setState(() {
        _resolvedUrls = urls;
        _resolving = false;
        _failedAll = urls.isEmpty;
      });
    } catch (_) {
      if (!mounted || requestFp != _fingerprint) return;
      setState(() {
        _resolvedUrls = const [];
        _resolving = false;
        _failedAll = true;
      });
    }
  }

  /// Largura em pixels físicos do quadro (cobre 16:9 quando a altura manda).
  int _targetPx(BoxConstraints c, double dpr) {
    var w = c.maxWidth.isFinite ? c.maxWidth : 0.0;
    if (c.maxHeight.isFinite) {
      final byH = c.maxHeight * 16 / 9;
      if (byH > w) w = byH;
    }
    if (w <= 0) w = 320;
    return (w * dpr).round().clamp(64, 3840);
  }

  /// Imagens enviadas primeiro (sempre); capa do YouTube na resolução certa:
  /// lista = `mqdefault` (leve); destaque = escolha pela largura real × DPR.
  List<String> _displayUrls(int targetPx) {
    final yt = _ytId;
    if (yt == null) return _resolvedUrls;
    final own = _resolvedUrls
        .where((u) => !YoutubeUrlHelper.isYoutubeThumbUrl(u))
        .toList();
    return [
      ...own,
      // Alta resolução pelo tamanho REAL do quadro (maxres → sd → hq → mq);
      // o modo leve (mq 320 px) só em quadro pequeno — capa nítida em card.
      ...YoutubeUrlHelper.thumbnailUrlsForWidth(yt, targetPx),
    ];
  }

  void _tryNextUrl(int total) {
    if (_urlIndex + 1 < total) {
      setState(() {
        _urlIndex++;
        _loaded = false;
      });
    } else {
      setState(() => _failedAll = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_resolving) {
      return ClipRRect(
        borderRadius: widget.borderRadius,
        child: _loadingSkeleton(),
      );
    }

    if (_resolvedUrls.isEmpty || _failedAll) {
      final video = _videoUrl;
      if (video != null) {
        return ClipRRect(
          borderRadius: widget.borderRadius,
          child: _previaDoVideo(video),
        );
      }
      return ClipRRect(
        borderRadius: widget.borderRadius,
        child: widget.fallback ?? _defaultFallback(),
      );
    }

    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: ColoredBox(
        color: const Color(0xFF0F172A),
        child: Stack(
          fit: StackFit.expand,
          children: [
            LayoutBuilder(
              builder: (context, c) {
                final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
                final px = _targetPx(c, dpr);
                final urls = _displayUrls(px);
                if (urls.isEmpty) {
                  return widget.fallback ?? _defaultFallback();
                }
                final url = urls[_urlIndex.clamp(0, urls.length - 1)];
                // Capa do YouTube (sd/hq têm tarjas pretas embutidas) e quadro
                // do vídeo: preenchem o 16:9 inteiro. Foto enviada: inteira.
                final preencher = YoutubeUrlHelper.isYoutubeThumbUrl(url) ||
                    _posterUrls.contains(url);
                return CourseFramedImage(
                  url: url,
                  cover: preencher && widget.fit == BoxFit.cover,
                  cacheWidth: px,
                  placeholder: _loadingSkeleton(),
                  onLoaded: () {
                    if (!_loaded) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && !_loaded) setState(() => _loaded = true);
                      });
                    }
                  },
                  onError: () {
                    final hasNext = _urlIndex + 1 < urls.length;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _tryNextUrl(urls.length);
                    });
                    return hasNext
                        ? _loadingSkeleton()
                        : (widget.fallback ?? _defaultFallback());
                  },
                );
              },
            ),
            if (widget.showBottomGradient)
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: _loaded ? 0.35 : 0.15),
                      ],
                    ),
                  ),
                ),
              ),
            if (widget.showPlayButton && _loaded)
              Center(child: _playButton()),
          ],
        ),
      ),
    );
  }

  /// MP4 sem capa: quadro do próprio vídeo (padrão YouTube/Instagram), com
  /// o mesmo degradê e botão play; chapéu/ícone só se não der.
  Widget _previaDoVideo(Future<String?> videoUrl) {
    final reserva = widget.fallback ?? _defaultFallback();
    return FutureBuilder<String?>(
      future: videoUrl,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _loadingSkeleton();
        }
        final url = snap.data;
        if (url == null || url.isEmpty) return reserva;
        return ColoredBox(
          color: const Color(0xFF0F172A),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CourseVideoFramePreview(
                videoUrl: url,
                fallback: reserva,
                placeholder: _loadingSkeleton(),
              ),
              if (widget.showBottomGradient)
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.35),
                        ],
                      ),
                    ),
                  ),
                ),
              if (widget.showPlayButton) Center(child: _playButton()),
            ],
          ),
        );
      },
    );
  }

  Widget _playButton() {
    if (widget.isYoutube) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFF0000).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          Icons.play_arrow_rounded,
          color: Colors.white,
          size: widget.playIconSize,
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 2),
      ),
      child: Icon(
        Icons.play_circle_fill_rounded,
        color: Colors.white.withValues(alpha: 0.95),
        size: widget.playIconSize,
      ),
    );
  }

  /// Placeholder estático em gradiente (sem spinner girando em cada card).
  Widget _loadingSkeleton() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E293B), Color(0xFF334155), Color(0xFF0F172A)],
        ),
      ),
    );
  }

  Widget _defaultFallback() {
    return Container(
      color: const Color(0xFF1E293B),
      alignment: Alignment.center,
      child: Icon(
        Icons.image_not_supported_outlined,
        size: 40,
        color: Colors.white.withValues(alpha: 0.45),
      ),
    );
  }
}

/// Capa SEMPRE inteira (sem recorte): a imagem aparece com [BoxFit.contain]
/// e a sobra do quadro é preenchida pela MESMA imagem ampliada e desfocada,
/// levemente escurecida. O fundo usa a imagem decodificada minúscula (24 px)
/// esticada — o próprio filtro bilinear dá o desfoque, sem custo de blur por
/// frame (leve em listas).
class CourseFramedImage extends StatelessWidget {
  const CourseFramedImage({
    super.key,
    required this.url,
    this.cacheWidth,
    this.placeholder,
    this.onLoaded,
    this.onError,
    this.cover = false,
  });

  final String url;
  final int? cacheWidth;

  /// `true`: preenche o quadro inteiro ([BoxFit.cover], alta qualidade) —
  /// capa do YouTube e quadro de vídeo. `false`: imagem inteira + fundo
  /// desfocado (foto enviada pelo admin).
  final bool cover;
  final Widget? placeholder;
  final VoidCallback? onLoaded;

  /// Devolve o widget a mostrar quando a imagem falha.
  final Widget Function()? onError;

  @override
  Widget build(BuildContext context) {
    final ph = placeholder ?? const ColoredBox(color: Color(0xFF1E293B));
    if (cover) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: cacheWidth,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
        loadingBuilder: (context, child, progress) {
          if (progress == null) {
            onLoaded?.call();
            return child;
          }
          return ph;
        },
        errorBuilder: (_, __, ___) =>
            onError?.call() ?? const SizedBox.shrink(),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        // Fundo desfocado (mesma URL → mesmo download em cache HTTP).
        ExcludeSemantics(
          child: Image.network(
            url,
            fit: BoxFit.cover,
            cacheWidth: 24,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
        const ColoredBox(color: Color(0x73000000)),
        Image.network(
          url,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          width: double.infinity,
          height: double.infinity,
          cacheWidth: cacheWidth,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          loadingBuilder: (context, child, progress) {
            if (progress == null) {
              onLoaded?.call();
              return child;
            }
            return ph;
          },
          errorBuilder: (_, __, ___) =>
              onError?.call() ?? const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// Alias legado — redireciona para [CourseMediaThumbnail].
typedef CourseCoverImage = CourseMediaThumbnailLegacy;

class CourseMediaThumbnailLegacy extends StatelessWidget {
  const CourseMediaThumbnailLegacy({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.fallback,
  });

  final String url;
  final BoxFit fit;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    return CourseMediaThumbnail.network(
      url: url,
      fit: fit,
      fallback: fallback,
    );
  }
}
