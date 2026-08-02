import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/finance_month_cache.dart';
import '../services/finance_opening_balance_service.dart';

/// Sinal global leve: qualquer gravação/alteração em lançamentos financeiros
/// incrementa [revision] para painéis, gráficos e sheets que usam Future/cache.
abstract final class FinanceTransactionsHub {
  FinanceTransactionsHub._();

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Timer? _debounce;
  static int _burstCount = 0;
  static String? _pendingUid;
  static DateTime? _pendingEffectiveDate;
  static bool _pendingInvalidateOpening = true;

  /// Chamado após criar, editar, excluir ou confirmar lançamentos.
  /// Debounce evita cascata de rebuild no painel + financeiro após cada save.
  static void notifyMutated({
    String? uid,
    DateTime? effectiveDate,
    bool invalidateOpeningBalance = true,
  }) {
    _burstCount++;
    if (uid != null && uid.isNotEmpty) _pendingUid = uid;
    if (effectiveDate != null) _pendingEffectiveDate = effectiveDate;
    if (!invalidateOpeningBalance) _pendingInvalidateOpening = false;

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 520), () {
      final count = _burstCount;
      _burstCount = 0;
      revision.value += count;

      final u = _pendingUid;
      final date = _pendingEffectiveDate;
      final inv = _pendingInvalidateOpening;
      _pendingUid = null;
      _pendingEffectiveDate = null;
      _pendingInvalidateOpening = true;

      if (u != null && u.isNotEmpty) {
        if (date != null) {
          FinanceMonthCache.invalidateMonth(u, date);
        } else {
          FinanceMonthCache.clearUid(u);
        }
        if (inv) {
          if (date != null) {
            FinanceOpeningBalanceService.invalidateIfBefore(u, date);
          } else {
            FinanceOpeningBalanceService.invalidateForUser(u);
          }
        }
      }
    });
  }
}
