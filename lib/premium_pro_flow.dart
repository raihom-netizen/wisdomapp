/// **Premium PRO — fluxo, segurança e automação (Open Finance).**
///
/// ### Webhook Pluggy (app fechado)
/// No painel Pluggy, configure a **URL HTTPS** da sua Cloud Function (ou API) que:
/// 1) Valida a assinatura do webhook; 2) Normaliza transações; 3) Grava no Firestore
/// (`users/{uid}/transactions` ou fila). Sem isso, o app só sincroniza quando aberto.
///
/// ### Add-on de conexões
/// Limite base: 2 conexões. Compras extras: [PremiumProAddonBillingService] + produto na loja
/// + atualização segura do limite no servidor (não confiar só no cliente).
///
/// ### Arquivos relacionados
/// - [BankConnectionManager], [SensitiveBalancePreferences], [TransactionNameCleaner],
///   categorias em [kDefaultOpenFinanceCategories] e regras em [CategoryMatcher].
library;

export 'constants/default_open_finance_categories.dart';
export 'constants/premium_pro_limits.dart';
export 'services/bank_connection_manager.dart';
export 'services/premium_pro_addon_billing_service.dart';
export 'services/sensitive_balance_preferences.dart';
export 'utils/category_matcher.dart';
export 'utils/transaction_name_cleaner.dart';
