import 'package:flutter/widgets.dart';

/// Stub para plataformas não-web.
Widget buildAnexoIframe(String url) => const SizedBox.shrink();

Widget buildAnexoWebViewer(
  String url, {
  String? fileName,
  String? mimeType,
  VoidCallback? onRetry,
}) =>
    const SizedBox.shrink();
