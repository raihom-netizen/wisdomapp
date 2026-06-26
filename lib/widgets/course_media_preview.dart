import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Preview de imagem — imagem inteira visível (contain), fundo escuro, alta qualidade.
class CourseImagePreview extends StatelessWidget {
  const CourseImagePreview({
    super.key,
    this.bytes,
    this.networkUrl,
    this.maxHeight = 200,
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
      image = Image.network(
        url,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => Icon(
          Icons.broken_image_outlined,
          size: 40,
          color: Colors.white.withValues(alpha: 0.5),
        ),
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
          Expanded(
            child: Center(child: image),
          ),
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

/// Capa/thumbnail em cards — [cover] para vídeo, [contain] para dicas com foto.
class CourseCoverImage extends StatelessWidget {
  const CourseCoverImage({
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
    if (url.trim().isEmpty) {
      return fallback ?? const SizedBox.expand();
    }
    final bg = fit == BoxFit.contain ? const Color(0xFF0F172A) : null;
    return ColoredBox(
      color: bg ?? Colors.transparent,
      child: Image.network(
        url,
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => fallback ?? const SizedBox.expand(),
      ),
    );
  }
}
