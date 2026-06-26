import 'package:flutter/foundation.dart';

/// Cobrança de **conexões bancárias extras** além do pacote PRO (2 inclusas).
///
/// Integração prevista: **Google Play Billing** (in-app product) ou **RevenueCat**
/// com o mesmo product id na Play Console / App Store Connect.
///
/// O fluxo ativo de conexão extra é **Mercado Pago** (`planCode` `extra_bank_connection_monthly` /
/// `extra_bank_connection_annual`) + subcoleção `users/{uid}/bank_connection_entitlements` no Firestore.
class PremiumProAddonBillingService {
  PremiumProAddonBillingService._();

  /// Reservado para possível produto in-app (Play/App Store) no futuro; não usado hoje.
  static const String extraBankConnectionProductId = 'premium_pro_extra_bank_connection';

  static Future<bool> purchaseExtraBankConnectionSlot() async {
    if (kDebugMode) {
      debugPrint('PremiumProAddonBillingService: use checkout MP para conexão extra (stub).');
    }
    return false;
  }
}
