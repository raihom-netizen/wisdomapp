import 'package:flutter/foundation.dart';

import '../services/finance_opening_balance_service.dart';

/// Sinal global leve: qualquer gravação/alteração em lançamentos financeiros
/// incrementa [revision] para painéis, gráficos e sheets que usam Future/cache.
abstract final class FinanceTransactionsHub {
  FinanceTransactionsHub._();

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Chamado após criar, editar, excluir ou confirmar lançamentos.
  static void notifyMutated({
    String? uid,
    DateTime? effectiveDate,
    bool invalidateOpeningBalance = true,
  }) {
    revision.value++;
    if (!invalidateOpeningBalance || uid == null || uid.isEmpty) return;
    if (effectiveDate != null) {
      FinanceOpeningBalanceService.invalidateIfBefore(uid, effectiveDate);
    } else {
      FinanceOpeningBalanceService.invalidateForUser(uid);
    }
  }
}
