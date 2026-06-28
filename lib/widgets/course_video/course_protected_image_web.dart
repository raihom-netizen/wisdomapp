// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

class _ProtectedImageView extends StatefulWidget {
  const _ProtectedImageView({required this.url, required this.fit});

  final String url;
  final BoxFit fit;

  @override
  State<_ProtectedImageView> createState() => _ProtectedImageViewState();
}

class _ProtectedImageViewState extends State<_ProtectedImageView> {
  late final String _viewType;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    _viewType = 'course-protected-img-${widget.url.hashCode}-${DateTime.now().microsecondsSinceEpoch}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      final img = html.ImageElement()
        ..src = widget.url
        ..draggable = false
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = _cssObjectFit(widget.fit)
        ..style.userSelect = 'none'
        ..style.setProperty('-webkit-user-select', 'none')
        ..style.pointerEvents = 'auto';
      img.onContextMenu.listen((e) => e.preventDefault());
      img.onDragStart.listen((e) => e.preventDefault());
      img.onError.listen((_) {
        if (mounted) setState(() => _failed = true);
      });
      return img;
    });
  }

  String _cssObjectFit(BoxFit fit) {
    switch (fit) {
      case BoxFit.cover:
        return 'cover';
      case BoxFit.fill:
        return 'fill';
      case BoxFit.fitWidth:
      case BoxFit.fitHeight:
        return 'contain';
      case BoxFit.none:
        return 'none';
      case BoxFit.scaleDown:
      case BoxFit.contain:
        return 'contain';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Center(
        child: Icon(
          Icons.broken_image_outlined,
          size: 36,
          color: Colors.white.withValues(alpha: 0.5),
        ),
      );
    }
    return HtmlElementView(viewType: _viewType);
  }
}

Widget buildCourseProtectedNetworkImage({
  required String url,
  required BoxFit fit,
  required Widget loading,
  required Widget error,
}) {
  return _ProtectedImageView(url: url, fit: fit);
}
