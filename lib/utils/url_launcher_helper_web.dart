// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'pwa_install_helper.dart';

/// Web (Safari iOS incluso): não usar `await canLaunchUrl` antes de abrir — o Safari cancela
/// o gesto do utilizador e o link não abre (fica “preso” na tela de licença).
Future<void> openUrlPreferChrome(String urlOriginal) async {
  if (urlOriginal.trim().isEmpty) return;
  var url = urlOriginal.trim();
  if (!url.startsWith('http')) url = 'https://$url';

  if (isPwaIos) {
    // iPhone/iPad: mesma aba é fiável (gesto preservado; carrega plano/checkout no site).
    html.window.location.assign(url);
    return;
  }

  html.window.open(url, '_blank', 'noopener,noreferrer');
}

Future<void> openPromoMaintenanceLink(String urlOriginal) async {
  await openUrlPreferChrome(urlOriginal);
}
