import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Carrega o widget **Pluggy Connect** via CDN numa WebView (token só em memória).
class PluggyConnectWebViewScreen extends StatefulWidget {
  final String connectToken;
  final bool includeSandbox;

  const PluggyConnectWebViewScreen({
    super.key,
    required this.connectToken,
    this.includeSandbox = true,
  });

  @override
  State<PluggyConnectWebViewScreen> createState() => _PluggyConnectWebViewScreenState();
}

class _PluggyConnectWebViewScreenState extends State<PluggyConnectWebViewScreen> {
  late final WebViewController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    final tokenJson = jsonEncode(widget.connectToken);
    final sandbox = widget.includeSandbox ? 'true' : 'false';
    final html = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
  <script src="https://cdn.pluggy.ai/pluggy-connect/latest/pluggy-connect.js"></script>
  <style>
    body { margin:0; font-family: system-ui,sans-serif; background:#f4f6fb; }
    #msg { padding:12px; font-size:14px; color:#334155; }
  </style>
</head>
<body>
  <div id="msg">Abrindo conexão segura…</div>
  <script>
    (function() {
      var token = $tokenJson;
      var includeSandbox = $sandbox;
      function send(type, payload) {
        try {
          PluggyBridge.postMessage(JSON.stringify({ type: type, payload: payload || {} }));
        } catch (e) {}
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

    final c = WebViewController();
    if (!kIsWeb) {
      c.setJavaScriptMode(JavaScriptMode.unrestricted);
      c.setBackgroundColor(const Color(0xFFF0F4FA));
    }
    c.addJavaScriptChannel(
      'PluggyBridge',
      onMessageReceived: (JavaScriptMessage message) {
        _handleBridgeMessage(message.message);
      },
    );
    c.loadHtmlString(html, baseUrl: 'https://cdn.pluggy.ai/');
    _controller = c;
  }

  void _handleBridgeMessage(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final type = (map['type'] ?? '').toString();
      final payload = map['payload'];
      if (type == 'success') {
        if (mounted) Navigator.of(context).pop<Map<String, dynamic>>({'ok': true, 'data': payload});
        return;
      }
      if (type == 'error') {
        setState(() {
          _error = (payload is Map && payload['message'] != null)
              ? payload['message'].toString()
              : 'Erro Pluggy Connect';
        });
        return;
      }
      if (type == 'close') {
        if (mounted) Navigator.of(context).pop<Map<String, dynamic>>({'ok': false, 'reason': 'closed'});
      }
    } catch (_) {
      setState(() => _error = 'Resposta inválida do widget.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conectar banco'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop<Map<String, dynamic>>({'ok': false, 'reason': 'cancelled'}),
        ),
      ),
      body: Column(
        children: [
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              backgroundColor: Colors.red.shade50,
              actions: [
                TextButton(onPressed: () => setState(() => _error = null), child: const Text('OK')),
              ],
            ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}
