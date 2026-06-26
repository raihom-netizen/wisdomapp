import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../screens/pluggy_connect_webview_screen.dart';
import '../utils/pluggy_web_open.dart';
import 'functions_service.dart';

/// Integração **Pluggy** no app.
///
/// **Nunca** armazene `Client ID` / `Client Secret` no Flutter. A autenticação na API Pluggy
/// (`POST https://api.pluggy.ai/auth` + `POST /connect_token`) fica na **Cloud Function**
/// `ctCreatePluggyConnectToken`, que lê credenciais de `app_config/pluggy` (painel Admin).
///
/// Este serviço apenas obtém o **connect token** já gerado no servidor e abre o widget na WebView.
class PluggyService {
  PluggyService._();
  static final PluggyService instance = PluggyService._();

  final FunctionsService _functions = FunctionsService();

  /// Obtém o connect token (accessToken) via Callable — equivalente seguro a chamar o backend.
  Future<String?> getConnectToken({String? redirectUri}) async {
    final map = await _functions.createPluggyConnectToken(redirectUri: redirectUri);
    if (map['ok'] == true) {
      final t = (map['accessToken'] ?? map['connectToken'] ?? '').toString().trim();
      if (t.isNotEmpty) return t;
    }
    return null;
  }

  /// Abre o **Pluggy Connect** em WebView (CDN oficial). Retorna `null` se não houver token.
  Future<Map<String, dynamic>?> openConnectWebView(
    BuildContext context, {
    String? redirectUri,
    bool? includeSandbox,
  }) async {
    final map = await _functions.createPluggyConnectToken(redirectUri: redirectUri);
    final ok = map['ok'] == true;
    final token = (map['accessToken'] ?? map['connectToken'] ?? '').toString().trim();
    if (!ok || token.isEmpty) {
      if (context.mounted) {
        final msg = (map['message'] ?? 'Pluggy não configurado ou sem permissão.')
            .toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
      return null;
    }
    final sandbox = includeSandbox ?? (map['includeSandbox'] == true);
    if (!context.mounted) return null;

    if (kIsWeb) {
      final c = Completer<Map<String, dynamic>?>();
      var webWindowOpened = false;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (dctx) {
          return PopScope(
            onPopInvokedWithResult: (bool didPop, Object? r) {
              if (didPop && !webWindowOpened && !c.isCompleted) c.complete(null);
            },
            child: AlertDialog(
              title: const Text('Conexão bancária (navegador)'),
              content: const Text(
                'Abriremos uma janela segura do Pluggy. Conclua a ligação ao banco nessa janela. '
                'Se a janela for bloqueada, permita popups para este site na barra de endereço e tente de novo.',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    if (!c.isCompleted) c.complete(null);
                    Navigator.of(dctx).pop();
                  },
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    final opened = startPluggyConnectInWebPopup(
                      token,
                      sandbox,
                      onDone: (m) {
                        if (!c.isCompleted) c.complete(m);
                      },
                    );
                    if (opened) {
                      webWindowOpened = true;
                      Navigator.of(dctx).pop();
                    } else if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'A janela foi bloqueada. Permita popups para este site e tente de novo.',
                          ),
                        ),
                      );
                    }
                  },
                  child: const Text('Abrir janela'),
                ),
              ],
            ),
          );
        },
      );
      return c.future;
    }

    return Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PluggyConnectWebViewScreen(
          connectToken: token,
          includeSandbox: sandbox,
        ),
      ),
    );
  }
}
