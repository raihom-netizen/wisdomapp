import 'package:flutter/widgets.dart';

/// Stub para plataformas não-web.
Widget buildAnexoIframe(String url) => const SizedBox.shrink();

Widget buildAnexoWebViewer(
  String url, {
  String? fileName,
  VoidCallback? onRetry,
}) =>
    const SizedBox.shrink();
