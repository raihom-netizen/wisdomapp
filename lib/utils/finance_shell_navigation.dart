import 'package:flutter/foundation.dart';

/// Pedido do Painel (ou shell) para abrir o Financeiro já filtrado por conta.
class FinanceShellNavigation {
  FinanceShellNavigation._();

  /// `null` = sem pedido; `''` = todas as contas; id = conta específica.
  static final ValueNotifier<String?> pendingAccountId = ValueNotifier<String?>(null);

  static void requestOpenFinanceiro({String? accountId}) {
    if (accountId == null) {
      pendingAccountId.value = '';
      return;
    }
    final t = accountId.trim();
    pendingAccountId.value = t.isEmpty ? '' : t;
  }
}
