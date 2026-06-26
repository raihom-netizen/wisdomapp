// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/widgets.dart';

/// Web: Google Finance / pesquisas dentro do app via iframe (mesmo padrão do checkout).
Widget buildFinanceNewsEmbed(String url, {Key? key}) {
  return HtmlElementView.fromTagName(
    key: key ?? ValueKey<String>(url),
    tagName: 'iframe',
    onElementCreated: (Object element) {
      final iframe = element as html.IFrameElement;
      iframe.src = url;
      iframe.style.width = '100%';
      iframe.style.height = '100%';
      iframe.style.border = 'none';
      iframe.setAttribute('loading', 'lazy');
      iframe.setAttribute('referrerpolicy', 'no-referrer-when-downgrade');
    },
  );
}
