import 'package:flutter/material.dart';

import 'course_protected_image_stub.dart'
    if (dart.library.html) 'course_protected_image_web.dart' as protected_img;

/// Imagem de curso/dica — bloqueia menu «Salvar imagem» na web e long-press no mobile.
class CourseProtectedNetworkImage extends StatelessWidget {
  const CourseProtectedNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.contain,
    this.loading,
    this.error,
  });

  final String url;
  final BoxFit fit;
  final Widget? loading;
  final Widget? error;

  @override
  Widget build(BuildContext context) {
    return protected_img.buildCourseProtectedNetworkImage(
      url: url,
      fit: fit,
      loading: loading ??
          const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
      error: error ??
          Center(
            child: Icon(
              Icons.broken_image_outlined,
              size: 36,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
    );
  }
}
