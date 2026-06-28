// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

bool _pathLooksLikeImage(String s) {
  final d = s.toLowerCase();
  return d.endsWith('.png') ||
      d.endsWith('.jpg') ||
      d.endsWith('.jpeg') ||
      d.endsWith('.webp') ||
      d.endsWith('.gif');
}

bool _pathLooksLikePdf(String s) {
  return s.toLowerCase().endsWith('.pdf');
}

bool isReceiptImageUrl(String url, {String? fileName, String? mimeType}) {
  final m = (mimeType ?? '').trim().toLowerCase();
  if (m.startsWith('image/')) return true;
  final f = (fileName ?? '').trim();
  if (_pathLooksLikeImage(f)) return true;
  try {
    final u = Uri.parse(url);
    final path = Uri.decodeComponent(u.path).toLowerCase();
    if (_pathLooksLikeImage(path)) return true;
    if (u.pathSegments.isNotEmpty) {
      final last = Uri.decodeComponent(u.pathSegments.last).toLowerCase();
      if (_pathLooksLikeImage(last)) return true;
    }
    for (final key in ['name', 'filename', 'file']) {
      final v = u.queryParameters[key] ?? '';
      if (_pathLooksLikeImage(Uri.decodeComponent(v).toLowerCase())) return true;
    }
  } catch (_) {}
  return false;
}

bool isReceiptPdfUrl(String url, {String? fileName, String? mimeType}) {
  final m = (mimeType ?? '').trim().toLowerCase();
  if (m == 'application/pdf') return true;
  final f = (fileName ?? '').trim().toLowerCase();
  if (_pathLooksLikePdf(f)) return true;
  try {
    final decoded = Uri.decodeFull(url).toLowerCase();
    if (decoded.contains('.pdf')) return true;
    final u = Uri.parse(url);
    for (final key in ['name', 'filename', 'file']) {
      final v = (u.queryParameters[key] ?? '').toLowerCase();
      if (v.contains('.pdf')) return true;
    }
  } catch (_) {}
  return false;
}

class _RegisteredIframe extends StatefulWidget {
  final String src;

  const _RegisteredIframe({super.key, required this.src});

  @override
  State<_RegisteredIframe> createState() => _RegisteredIframeState();
}

class _RegisteredIframeState extends State<_RegisteredIframe> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'anexo-iframe-${widget.src.hashCode}-${DateTime.now().microsecondsSinceEpoch}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final iframe = html.IFrameElement()
        ..src = widget.src
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.border = 'none'
        ..setAttribute('title', 'Comprovante');
      return iframe;
    });
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}

class _RegisteredHtmlImage extends StatefulWidget {
  final String url;

  const _RegisteredHtmlImage({super.key, required this.url});

  @override
  State<_RegisteredHtmlImage> createState() => _RegisteredHtmlImageState();
}

class _RegisteredHtmlImageState extends State<_RegisteredHtmlImage> {
  late final String _viewType;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _viewType = 'anexo-img-${widget.url.hashCode}-${DateTime.now().microsecondsSinceEpoch}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final img = html.ImageElement()
        ..src = widget.url
        ..style.maxWidth = '100%'
        ..style.maxHeight = '100%'
        ..style.objectFit = 'contain'
        ..style.display = 'block'
        ..style.margin = 'auto';
      img.onError.listen((_) {
        if (mounted) setState(() => _failed = true);
      });
      return img;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return _WebPreviewError(
        message: 'Não foi possível carregar a imagem do comprovante.',
        url: widget.url,
      );
    }
    return HtmlElementView(viewType: _viewType);
  }
}

/// Pré-visualização na web quando bytes locais não estão disponíveis (CORS no http.get).
/// Firebase Storage: URL direta com token — nunca Google Docs Viewer.
Widget buildAnexoWebViewer(
  String url, {
  String? fileName,
  String? mimeType,
  VoidCallback? onRetry,
}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final mq = MediaQuery.sizeOf(context);
      final h = constraints.hasBoundedHeight && constraints.maxHeight.isFinite && constraints.maxHeight > 48
          ? constraints.maxHeight
          : mq.height * 0.78;
      final w = constraints.hasBoundedWidth && constraints.maxWidth.isFinite && constraints.maxWidth > 48
          ? constraints.maxWidth
          : mq.width;
      final isImage = isReceiptImageUrl(url, fileName: fileName, mimeType: mimeType);
      return SizedBox(
        width: w,
        height: h,
        child: Column(
          children: [
            if (onRetry != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Text(
                  isImage
                      ? 'Visualização do comprovante — use «Abrir em nova aba» se não carregar.'
                      : 'Visualização do PDF — use «Abrir em nova aba» se não carregar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 12),
                ),
              ),
            Expanded(
              child: isImage
                  ? _WebImagePreview(
                      url: url,
                      width: w,
                      height: h,
                      onRetry: onRetry,
                    )
                  : _DirectEmbedPreview(url: url, width: w, height: h),
            ),
          ],
        ),
      );
    },
  );
}

class _WebImagePreview extends StatelessWidget {
  final String url;
  final double width;
  final double height;
  final VoidCallback? onRetry;

  const _WebImagePreview({
    required this.url,
    required this.width,
    required this.height,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: 0.35,
      maxScale: 5,
      child: Center(
        child: Image.network(
          url,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          loadingBuilder: (ctx, child, progress) {
            if (progress == null) return child;
            return SizedBox(
              height: height * 0.35,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2),
              ),
            );
          },
          errorBuilder: (_, __, ___) => _RegisteredHtmlImage(key: ValueKey<String>(url), url: url),
        ),
      ),
    );
  }
}

/// PDF ou outros tipos: iframe com URL direta (Firebase Storage, etc.).
class _DirectEmbedPreview extends StatelessWidget {
  final String url;
  final double width;
  final double height;

  const _DirectEmbedPreview({
    required this.url,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    if (url.trim().isEmpty) {
      return const _WebPreviewError(message: 'Link do comprovante indisponível.');
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ColoredBox(
        color: const Color(0xFF2C2C2E),
        child: _RegisteredIframe(key: ValueKey<String>(url), src: url),
      ),
    );
  }
}

class _WebPreviewError extends StatelessWidget {
  final String message;
  final String? url;

  const _WebPreviewError({required this.message, this.url});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

Widget buildAnexoIframe(String url) => buildAnexoWebViewer(url, fileName: null);
