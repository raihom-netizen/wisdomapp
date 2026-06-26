/// IDs dos produtos no App Store Connect (assinaturas automáticas).
/// Criar em App Store Connect com **exatamente** estes identificadores.
class IosIapProducts {
  IosIapProducts._();

  static const String premiumMonthly = 'br.com.controletotalapp1.premium.monthly';
  static const String premiumAnnual = 'br.com.controletotalapp1.premium.annual';

  static const Set<String> allIds = {premiumMonthly, premiumAnnual};

  /// Alinha ao código de plano interno (Mercado Pago / Firestore).
  static String? planCodeForProductId(String productId) {
    switch (productId) {
      case premiumMonthly:
        return 'premium_monthly';
      case premiumAnnual:
        return 'premium_annual';
      default:
        return null;
    }
  }
}
