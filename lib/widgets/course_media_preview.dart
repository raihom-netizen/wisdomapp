import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../utils/course_thumb_resolver.dart';

/// Preview de imagem — imagem inteira visível (contain), fundo escuro, alta qualidade.
class CourseImagePreview extends StatelessWidget {
  const CourseImagePreview({
    super.key,
    this.bytes,
    this.networkUrl,
    this.maxHeight = 240,
    this.subtitle,
  });

  final Uint8List? bytes;
  final String? networkUrl;
  final double maxHeight;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final hasBytes = bytes != null && bytes!.isNotEmpty;
    final url = networkUrl?.trim() ?? '';
    if (!hasBytes && url.isEmpty) return const SizedBox.shrink();

    Widget image;
    if (hasBytes) {
      image = Image.memory(
        bytes!,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
      );
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
    required this.urls,
    this.fit = BoxFit.cover,
    this.fallback,
    this.borderRadius = BorderRadius.zero,
    this.showPlayButton = true,
    this.isYoutube = false,
    this.showBottomGradient = true,
    this.playIconSize = 56,
  });

  /// Construtor a partir de documento Firestore.
  factory CourseMediaThumbnail.fromData(
    Map<String, dynamic> data, {
    BoxFit? fit,
    Widget? fallback,
    BorderRadius borderRadius = BorderRadius.zero,
    bool showPlayButton = true,
    double playIconSize = 56,
  }) {
    final urls = CourseThumbResolver.resolveUrls(data);
    final isVideo = CourseThumbResolver.isVideoContent(data);
    final isYt = CourseThumbResolver.videoIdFromData(data) != null;
    final photo = CourseThumbResolver.isDicaPhoto(data);
    return CourseMediaThumbnail(
      urls: urls,
      fit: fit ?? (photo ? BoxFit.contain : BoxFit.cover),
      fallback: fallback,
      borderRadius: borderRadius,
      showPlayButton: showPlayButton && (isVideo || isYt),
      isYoutube: isYt,
      showBottomGradient: showPlayButton,
      playIconSize: playIconSize,
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
  final BoxFit fit;
  final Widget? fallback;
  final BorderRadius borderRadius;
  final bool showPlayButton;
  final bool isYoutube;
  final bool showBottomGradient;
  final double playIconSize;

  @override
  State<CourseMediaThumbnail> createState() => _CourseMediaThumbnailState();
}

class _CourseMediaThumbnailState extends State<CourseMediaThumbnail> {
  int _urlIndex = 0;
  bool _loaded = false;
  bool _failedAll = false;

  List<String> get _urls => widget.urls.where((u) => u.trim().isNotEmpty).toList();

  void _tryNextUrl() {
    if (_urlIndex + 1 < _urls.length) {
      setState(() {
        _urlIndex++;
        _loaded = false;
      });
    } else {
      setState(() => _failedAll = true);
    }
  }

  @override
  void didUpdateWidget(covariant CourseMediaThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urls.join('|') != widget.urls.join('|')) {
      _urlIndex = 0;
      _loaded = false;
      _failedAll = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_urls.isEmpty || _failedAll) {
      return ClipRRect(
        borderRadius: widget.borderRadius,
        child: widget.fallback ?? _defaultFallback(),
      );
    }

    final url = _urls[_urlIndex.clamp(0, _urls.length - 1)];
    final bg = widget.fit == BoxFit.contain ? const Color(0xFF0F172A) : null;

    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: ColoredBox(
        color: bg ?? Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              url,
              fit: widget.fit,
              width: double.infinity,
              height: double.infinity,
              filterQuality: FilterQuality.high,
              gaplessPlayback: true,
              loadingBuilder: (context, child, progress) {
                if (progress == null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && !_loaded) setState(() => _loaded = true);
                  });
                  return child;
                }
                return _loadingSkeleton();
              },
              errorBuilder: (_, __, ___) {
                if (_urlIndex + 1 < _urls.length) {
                  WidgetsBinding.instance.addPostFrameCallback((_) => _tryNextUrl());
                  return _loadingSkeleton();
                }
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _failedAll = true);
                });
                return widget.fallback ?? _defaultFallback();
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

  Widget _loadingSkeleton() {
    return Container(
      color: const Color(0xFF1E293B),
      alignment: Alignment.center,
      child: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: Colors.white.withValues(alpha: 0.55),
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
