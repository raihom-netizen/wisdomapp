import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/theme_context.dart';

/// Faixa de erro padrão do Financeiro: diz o que houve e tem «Tentar de novo».
///
/// Usada onde uma leitura do servidor falhou ou passou do prazo — no lugar do
/// spinner eterno ou de uma lista vazia que parecia «sumiram meus dados».
class FinanceLoadErrorBox extends StatelessWidget {
  const FinanceLoadErrorBox({
    super.key,
    required this.onRetry,
    this.error,
    this.message,
    this.compact = false,
  });

  final VoidCallback onRetry;
  final Object? error;
  final String? message;

  /// `true` = faixa fina acima de dados já carregados.
  final bool compact;

  static String mensagemPara(Object? error) {
    if (error is TimeoutException) {
      return 'O servidor demorou para responder.';
    }
    final s = (error ?? '').toString().toLowerCase();
    if (s.contains('permission-denied') || s.contains('permission_denied')) {
      return 'Sem permissão para ler estes dados. Saia e entre de novo.';
    }
    if (s.contains('unavailable') || s.contains('offline') || s.contains('network')) {
      return 'Sem conexão com o servidor.';
    }
    return 'Não foi possível carregar.';
  }

  @override
  Widget build(BuildContext context) {
    final msg = message ?? mensagemPara(error);
    final dark = context.isDarkMode;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 12 : 18),
      margin: EdgeInsets.only(bottom: compact ? 12 : 0),
      decoration: BoxDecoration(
        color: dark ? context.appSurface : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline_rounded,
                  size: compact ? 22 : 30, color: Colors.orange.shade700),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  compact ? '$msg Mostrando os dados já carregados.' : msg,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: context.appTextPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 20),
            label: const Text('Tentar de novo'),
          ),
        ],
      ),
    );
  }
}
