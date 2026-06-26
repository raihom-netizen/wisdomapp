import 'url_launcher_helper_stub.dart'
    if (dart.library.html) 'url_launcher_helper_web.dart'
    if (dart.library.io) 'url_launcher_helper_io.dart' as impl;

/// Abre [url] no navegador. No iOS tenta Chrome primeiro (googlechromes://); se não tiver Chrome, abre no Safari.
/// Na web e no Android usa o navegador padrão.
/// Garante que a URL tenha protocolo (https se não tiver).
Future<void> openUrlPreferChrome(String url) => impl.openUrlPreferChrome(url);

/// Promo / manutenção: **iPhone app** = sempre navegador externo (Safari/Chrome), sem checkout embutido no app.
/// **Android** = Chrome Custom Tab (`inAppBrowserView`) quando disponível; senão navegador externo.
/// **Web** = nova aba / externo (fluxo de pagamento no site).
Future<void> openPromoMaintenanceLink(String url) =>
    impl.openPromoMaintenanceLink(url);
