import 'package:flutter/material.dart';

Widget buildCourseProtectedNetworkImage({
  required String url,
  required BoxFit fit,
  required Widget loading,
  required Widget error,
}) {
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onLongPress: () {},
    child: Image.network(
      url,
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      loadingBuilder: (_, child, progress) => progress == null ? child : loading,
      errorBuilder: (_, __, ___) => error,
    ),
  );
}
