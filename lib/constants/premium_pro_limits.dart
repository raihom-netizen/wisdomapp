/// Limites comerciais Premium PRO (Open Finance / custo de API por item).
class PremiumProLimits {
  PremiumProLimits._();

  /// Ciclo do plano **mensal** PRO: mesmos 30 dias de licença que o backend aplica ao aprovar pagamento.
  static const int monthlyLicenseDays = 30;

  /// Conexões Open Finance **inclusas** no plano padrão; acima disso → [extraConnectionMonthlyBrl]/mês cada.
  static const int defaultIncludedBankConnections = 2;

  /// Contas com limite incluso ampliado (monitoramento manual de custo API).
  static const int vipIncludedBankConnections = 5;

  /// E-mails com [vipIncludedBankConnections] slots inclusos antes de cobrar extra (sempre cobra além disso).
  static const Set<String> kHighIncludedConnectionsEmails = {
    'raihom@gmail.com',
    'isabelle.krdoso@gmail.com',
  };

  /// Conexões inclusas para o e-mail do utilizador (normalmente 2; VIP na lista → 5).
  static int includedBankConnectionsForEmail(String? email) {
    final e = email?.trim().toLowerCase() ?? '';
    if (kHighIncludedConnectionsEmails.contains(e)) return vipIncludedBankConnections;
    return defaultIncludedBankConnections;
  }

  /// Valor opcional gravado em `users.premiumProIncludedBankConnections` pelo painel Admin (por utilizador).
  static int? parseAdminIncludedSlotsOverride(dynamic v) {
    if (v == null) return null;
    if (v is int) return v >= 1 ? v.clamp(1, 99) : null;
    if (v is num) {
      final i = v.toInt();
      return i >= 1 ? i.clamp(1, 99) : null;
    }
    return null;
  }

  /// Limite incluso efetivo: override do Admin > lista VIP > padrão [defaultIncludedBankConnections].
  static int includedBankConnections({
    String? email,
    int? adminPerUserOverride,
  }) {
    final o = parseAdminIncludedSlotsOverride(adminPerUserOverride);
    if (o != null) return o;
    return includedBankConnectionsForEmail(email);
  }

  /// Texto comercial genérico / legado: valor padrão (2).
  static int get maxBankConnections => defaultIncludedBankConnections;

  /// Preço de vitrine por conexão adicional (mensal) — integração de cobrança no app/suporte quando ativa.
  static const double extraConnectionMonthlyBrl = 5.90;

  /// Conexão extra paga anual à frente (add-on) — alinhado à Cloud Function `extra_bank_connection_annual`.
  static const double extraConnectionAnnualBrl = 59.90;

  static String get extraConnectionPriceLabel =>
      'R\$ ${extraConnectionMonthlyBrl.toStringAsFixed(2).replaceAll('.', ',')}';

  static String get extraConnectionAnnualPriceLabel =>
      'R\$ ${extraConnectionAnnualBrl.toStringAsFixed(2).replaceAll('.', ',')}';

  /// Frase comercial: [included] conexões simultâneas inclusas; da [includedPlusOne]ª cobra-se extra (mesmo [extraConnectionPriceLabel] do app).
  static String includedConnectionsPricingLine(int included, int includedPlusOne) =>
      '$included conexões de banco inclusas no plano. A partir da $includedPlusOneª, cada uma custa '
      '$extraConnectionPriceLabel/mês a mais — o mesmo valor já usado no app para cobrir custos de '
      'integração e não operarmos em prejuízo.';

  /// Dias de teste sugeridos para validar automação no **anual** (comercial; exige regra no checkout/Firestore para ter efeito legal).
  static const int suggestedAnnualAutomationTrialDays = 7;
}
