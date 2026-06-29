// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Remove parâmetros gcal/gcal_error da URL (evita reprocessar ao recarregar).
void cleanGcalQueryFromBrowserUrl() {
  try {
    final u = Uri.parse(html.window.location.href);
    if (!u.queryParameters.containsKey('gcal') &&
        !u.queryParameters.containsKey('gcal_error')) {
      return;
    }
    final q = Map<String, String>.from(u.queryParameters)
      ..remove('gcal')
      ..remove('gcal_error');
    final newUri = u.replace(queryParameters: q.isEmpty ? null : q);
    html.window.history.replaceState(null, '', newUri.toString());
  } catch (_) {}
}
