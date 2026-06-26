// Navegador: blob + postMessage. Ignorar avisos: só importado em compilação web.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:html' as html;
import 'dart:math' as math;

/// Abre o Pluggy Connect noutra janela (blob URL) e envia o resultado com [postMessage].
/// Deve ser chamada **diretamente** no `onPressed` (sem `await` antes) para o popup não ser bloqueado.
///
/// Retorna `false` se a janela for bloqueada; [onDone] recebe `null` nesse caso, ou o mapa alinhado
/// a [PluggyService.openConnectWebView].
bool startPluggyConnectInWebPopup(
  String connectToken,
  bool includeSandbox, {
  required void Function(Map<String, dynamic>?) onDone,
}) {
  final opId = 'pluggy_${DateTime.now().microsecondsSinceEpoch}_'
      '${math.Random().nextInt(0x7fffffff).toString()}';

  final tokenJson = jsonEncode(connectToken);
  final sandbox = includeSandbox ? 'true' : 'false';
  final page = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
  <script src="https://cdn.pluggy.ai/pluggy-connect/latest/pluggy-connect.js"></script>
  <style>body { margin:0; font-family: system-ui,sans-serif; background:#f4f6fb; }
  #msg { padding:12px; font-size:14px; color:#334155; }
  </style>
</head>
<body>
  <div id="msg">Abrindo conexão segura…</div>
  <script>
    (function() {
      var opId = ${jsonEncode(opId)};
      var token = $tokenJson;
      var includeSandbox = $sandbox;
      function send(type, payload) {
        var msg = JSON.stringify({
          pluggy: true, opId: opId, type: type, payload: payload || {}
        });
        try {
          if (window.opener) {
            window.opener.postMessage(msg, '*');
            return;
          }
        } catch (e) {}
        try { window.postMessage(msg, '*'); } catch (e) {}
      }
      try {
        if (typeof PluggyConnect === 'undefined') {
          send('error', { message: 'Script Pluggy Connect não carregou. Verifique rede e tente de novo.' });
          return;
        }
        var pc = new PluggyConnect({
          connectToken: token,
          includeSandbox: includeSandbox,
          onSuccess: function(data) { send('success', data); },
          onError: function(err) { send('error', { message: String(err && err.message || err) }); },
          onClose: function() { send('close', {}); }
        });
        pc.init();
      } catch (e) {
        send('error', { message: String(e) });
      }
    })();
  </script>
</body>
</html>
''';

  late void Function(html.Event) listener;
  void cleanUp() {
    html.window.removeEventListener('message', listener);
  }

  listener = (html.Event e) {
    if (e is! html.MessageEvent) return;
    final d = e.data;
    if (d is! String) return;
    try {
      final m = Map<String, dynamic>.from(
        (jsonDecode(d) as Map).map((k, v) => MapEntry(k.toString(), v)),
      );
      if (m['pluggy'] != true) return;
      if (m['opId'] == null || m['opId'].toString() != opId) return;
      final t = m['type']?.toString() ?? '';
      final payload = m['payload'];
      if (t == 'success') {
        cleanUp();
        onDone({'ok': true, 'data': payload});
        return;
      }
      if (t == 'error') {
        final msg = (payload is Map && payload['message'] != null) ? payload['message'].toString() : 'Erro Pluggy Connect';
        cleanUp();
        onDone({'ok': false, 'message': msg});
        return;
      }
      if (t == 'close') {
        cleanUp();
        onDone({'ok': false, 'reason': 'closed'});
        return;
      }
    } catch (_) {}
  };
  html.window.addEventListener('message', listener);

  final blob = html.Blob([page], 'text/html');
  final objectUrl = html.Url.createObjectUrlFromBlob(blob);
  final w = html.window.open(
    objectUrl,
    '_blank',
    'width=500,height=820,scrollbars=yes,menubar=no',
  );
  // O browser pode bloquear popups (null), embora o analisador às vezes aponte o tipo como não-nullable.
  // ignore: unnecessary_null_comparison
  if (w == null) {
    cleanUp();
    html.Url.revokeObjectUrl(objectUrl);
    onDone(null);
    return false;
  }
  // Permite a página do blob carregar antes de revogar a URL.
  Future<void>.delayed(const Duration(seconds: 1), () {
    try {
      html.Url.revokeObjectUrl(objectUrl);
    } catch (_) {}
  });
  return true;
}
