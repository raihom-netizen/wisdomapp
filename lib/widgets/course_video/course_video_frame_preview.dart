import 'package:flutter/material.dart';

import '../../services/course_video_poster.dart';

/// Prévia de um vídeo MP4 SEM capa: um quadro do próprio vídeo preenchendo
/// o card 16:9 (padrão YouTube/Instagram), sem som e sem tocar.
///
/// O quadro vem de [courseVideoFrameImage] (cache por URL): Android/iOS via
/// FFmpeg sobre o começo do arquivo; Web via `<video>` fora da tela + canvas.
/// Nada de elemento HTML por cima do Flutter — rolagem e toque no card
/// seguem normais. [fallback] enquanto prepara e se não der.
class CourseVideoFramePreview extends StatefulWidget {
  const CourseVideoFramePreview({
    super.key,
    required this.videoUrl,
    required this.fallback,
    this.placeholder,
  });

  final String videoUrl;
  final Widget fallback;

  /// Enquanto prepara (padrão: [fallback]).
  final Widget? placeholder;

  @override
  State<CourseVideoFramePreview> createState() =>
      _CourseVideoFramePreviewState();
}

class _CourseVideoFramePreviewState extends State<CourseVideoFramePreview> {
  // Futuro guardado no estado: redesenho não gera o quadro de novo.
  late Future<ImageProvider?> _imagem = courseVideoFrameImage(widget.videoUrl);

  @override
  void didUpdateWidget(covariant CourseVideoFramePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) {
      _imagem = courseVideoFrameImage(widget.videoUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ImageProvider?>(
      future: _imagem,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return widget.placeholder ?? widget.fallback;
        }
        final img = snap.data;
        if (img == null) return widget.fallback;
        return Image(
          image: img,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => widget.fallback,
        );
      },
    );
  }
}
