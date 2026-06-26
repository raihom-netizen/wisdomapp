// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/widgets.dart';

/// No web: embede o checkout do Mercado Pago na mesma tela via iframe.
Widget buildCheckoutEmbed(String url) {
  return HtmlElementView.fromTagName(
    tagName: 'iframe',
    onElementCreated: (Object element) {
      final iframe = element as html.IFrameElement;
      iframe.src = url;
      iframe.style.width = '100%';
      iframe.style.height = '100%';
      iframe.style.border = 'none';
    },
  );
}
