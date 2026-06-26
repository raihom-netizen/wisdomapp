import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:webview_flutter_web/webview_flutter_web.dart';

/// Web: instala o adaptador iframe do pacote `webview_flutter_web`.
void registerWebViewForWebEngine() {
  WebViewPlatform.instance ??= WebWebViewPlatform();
}
