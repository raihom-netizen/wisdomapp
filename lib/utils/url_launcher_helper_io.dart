import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

Uri _normalizeHttpUri(String urlOriginal) {
  String url = urlOriginal.trim();
  if (!url.startsWith('http')) url = 'https://$url';
  return Uri.parse(url);
}

/// `launchUrl` devolve `false` quando não abre — não lança exceção (comum no iOS).
Future<bool> _tryLaunch(Uri uri, LaunchMode mode) async {
  try {
    return await launchUrl(uri, mode: mode);
  } catch (_) {
    return false;
  }
}

/// Abre [uri] no navegador do sistema (Safari / Chrome / navegador padrão).
Future<bool> _launchInBrowser(Uri uri) async {
  if (await _tryLaunch(uri, LaunchMode.externalApplication)) return true;
  if (await _tryLaunch(uri, LaunchMode.platformDefault)) return true;
  if (uri.scheme == 'http' || uri.scheme == 'https') {
    if (await _tryLaunch(uri, LaunchMode.inAppBrowserView)) return true;
  }
  return false;
}

/// iOS/Android: no iOS tenta Chrome se instalado; senão Safari/navegador padrão.
Future<void> openUrlPreferChrome(String urlOriginal) async {
  if (urlOriginal.trim().isEmpty) return;
  final defaultUri = _normalizeHttpUri(urlOriginal);
  final url = defaultUri.toString();

  if (Platform.isIOS) {
    final chromeUrl = url
        .replaceFirst('https://', 'googlechromes://')
        .replaceFirst('http://', 'googlechrome://');
    final chromeUri = Uri.parse(chromeUrl);
    if (await _launchInBrowser(chromeUri)) return;
    if (await _launchInBrowser(defaultUri)) return;
    throw 'Não foi possível abrir o link: $url';
  }

  if (await _launchInBrowser(defaultUri)) return;

  if (Platform.isAndroid) {
    throw 'Não foi possível abrir o link: $url';
  }
  throw 'Não foi possível abrir o link: $url';
}

/// iOS: sempre externo (App Store 3.1.1 — sem pagamento embutido no app nativo).
/// Android: Custom Tab (experiência “dentro do app”); fallback externo.
Future<void> openPromoMaintenanceLink(String urlOriginal) async {
  if (urlOriginal.trim().isEmpty) return;
  final uri = _normalizeHttpUri(urlOriginal);
  final url = uri.toString();

  if (Platform.isIOS) {
    await openUrlPreferChrome(urlOriginal);
    return;
  }

  if (Platform.isAndroid) {
    try {
      if (await canLaunchUrl(uri)) {
        if (await _tryLaunch(uri, LaunchMode.inAppBrowserView)) return;
      }
    } catch (_) {}
    if (await _launchInBrowser(uri)) return;
    throw 'Não foi possível abrir o link: $url';
  }

  await openUrlPreferChrome(urlOriginal);
}
