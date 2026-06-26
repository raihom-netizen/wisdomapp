import 'package:url_launcher/url_launcher.dart';

/// Implementação para Web: abre no navegador padrão (sem tentar Chrome).
Future<void> openUrlPreferChrome(String urlOriginal) async {
  if (urlOriginal.trim().isEmpty) return;
  String url = urlOriginal.trim();
  if (!url.startsWith('http')) url = 'https://$url';
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } else {
    throw 'Não foi possível abrir o link: $url';
  }
}

/// Web: mesma política que link normal (nova aba / externo) — checkout e promo no domínio do site.
Future<void> openPromoMaintenanceLink(String urlOriginal) async {
  await openUrlPreferChrome(urlOriginal);
}
