import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/premium_pro_limits.dart';

/// Preços reais do checkout Mercado Pago (PIX/cartão), lidos de
/// `app_config/mp_checkout_prices` (leitura pública). O painel Admin pode
/// alterar sem deploy; fallback = tabela padrão do app.
/// Planos comerciais no checkout: Premium mensal/anual (`mp_checkout_prices`). ASSEGO é `plan` no usuário.
class MpCheckoutPricingSnapshot {
  MpCheckoutPricingSnapshot({
    required this.premiumMonthly,
    required this.premiumAnnual,
    this.premiumProMonthly = 25.90,
    this.premiumProAnnual = 299.90,
    this.extraBankConnectionMonthly =
        PremiumProLimits.extraConnectionMonthlyBrl,
    this.extraBankConnectionAnnual = PremiumProLimits.extraConnectionAnnualBrl,
  });

  final double premiumMonthly;
  final double premiumAnnual;

  /// Premium PRO — checkout Mercado Pago (chaves `premium_pro_monthly` / `premium_pro_annual` no Firestore).
  final double premiumProMonthly;
  final double premiumProAnnual;

  /// Add-on: +1 conexão Open Finance (`extra_bank_connection_monthly` / `extra_bank_connection_annual` no Firestore).
  final double extraBankConnectionMonthly;
  final double extraBankConnectionAnnual;

  static MpCheckoutPricingSnapshot defaults() => MpCheckoutPricingSnapshot(
    premiumMonthly: 49.90,
    premiumAnnual: 478.80,
    premiumProMonthly: 25.90,
    premiumProAnnual: 299.90,
    extraBankConnectionMonthly: PremiumProLimits.extraConnectionMonthlyBrl,
    extraBankConnectionAnnual: PremiumProLimits.extraConnectionAnnualBrl,
  );

  static double? _pickDouble(Map<String, dynamic>? m, String key) {
    if (m == null) return null;
    final v = m[key];
    if (v == null) return null;
    if (v is num) {
      final x = v.toDouble();
      return x > 0 ? x : null;
    }
    final s = v.toString().trim().replaceAll(',', '.');
    final x = double.tryParse(s);
    if (x == null || x <= 0) return null;
    return x;
  }

  factory MpCheckoutPricingSnapshot.fromFirestore(Map<String, dynamic>? raw) {
    final d = defaults();
    double? pick(String k1, String k2) =>
        _pickDouble(raw, k1) ?? _pickDouble(raw, k2);
    return MpCheckoutPricingSnapshot(
      premiumMonthly:
          pick('premium_monthly', 'premiumMonthlyBrl') ?? d.premiumMonthly,
      premiumAnnual:
          pick('premium_annual', 'premiumAnnualBrl') ?? d.premiumAnnual,
      premiumProMonthly:
          _pickDouble(raw, 'premium_pro_monthly') ?? d.premiumProMonthly,
      premiumProAnnual:
          _pickDouble(raw, 'premium_pro_annual') ?? d.premiumProAnnual,
      extraBankConnectionMonthly:
          _pickDouble(raw, 'extra_bank_connection_monthly') ??
          d.extraBankConnectionMonthly,
      extraBankConnectionAnnual:
          _pickDouble(raw, 'extra_bank_connection_annual') ??
          d.extraBankConnectionAnnual,
    );
  }

  /// Ex.: 14,99
  static String formatBrlNoPrefix(double v) {
    return v.toStringAsFixed(2).replaceAll('.', ',');
  }

  static String formatBrl(double v) => 'R\$ ${formatBrlNoPrefix(v)}';

  /// Média mensal “de vitrine” no anual: piso em centavos (169,90 → 14,15).
  static double premiumAnnualEquivalentMonthlyFloor(double premiumAnnual) {
    return ((premiumAnnual * 100) ~/ 12) / 100.0;
  }

  String get premiumMonthlyLine => '${formatBrl(premiumMonthly)}/mês';

  String get premiumAnnualLine => '${formatBrl(premiumAnnual)}/ano';

  String get premiumAnnualEquivPerMonthLine =>
      '${formatBrl(premiumAnnualEquivalentMonthlyFloor(premiumAnnual))}/mês';

  String get premiumProMonthlyLine => '${formatBrl(premiumProMonthly)}/mês';

  String get premiumProAnnualLine => '${formatBrl(premiumProAnnual)}/ano';

  String get premiumProAnnualEquivPerMonthLine =>
      '${formatBrl(premiumAnnualEquivalentMonthlyFloor(premiumProAnnual))}/mês';

  /// Vitrine add-on Open Finance: uma linha (mesmos valores do checkout MP).
  String get openFinanceAddOnVitrineLine {
    final m = formatBrl(extraBankConnectionMonthly);
    final a = formatBrl(extraBankConnectionAnnual);
    return 'Conexão bancária extra (além do incluído no PRO): $m/mês ou $a/ano — mesmo valor no app e no checkout (Mercado Pago).';
  }

  /// Economia do anual PRO vs pagar 12× o mensal PRO (null se anual não for mais barato).
  double? get premiumProAnnualSavingsVsTwelveMonthly {
    final full = premiumProMonthly * 12;
    if (premiumProAnnual >= full - 0.009) return null;
    return full - premiumProAnnual;
  }

  /// Percentual aproximado de desconto (0–100) do anual vs 12× mensal PRO.
  int? get premiumProAnnualApproxDiscountPercent {
    final full = premiumProMonthly * 12;
    if (full <= 0 || premiumProAnnual >= full - 0.009) return null;
    return (((full - premiumProAnnual) / full) * 100).round().clamp(1, 99);
  }

  /// Parágrafo longo (ex.: tela licença expirada).
  String get licenseExpiredParagraph {
    final pm = formatBrl(premiumMonthly);
    final pa = formatBrl(premiumAnnual);
    final eq = formatBrl(premiumAnnualEquivalentMonthlyFloor(premiumAnnual));
    return '$pm / mês ou $pa / ano. Plano mensal: $pm por mês. Plano anual: $pa/ano — frisando: comprando anual, sai $eq por mês; é um ótimo negócio. Recomendamos comprar anual. Acesso pelo celular, computador ou notebook. Acesso livre total.';
  }

  String planButtonLabelMonthly() => 'Mensal ${formatBrl(premiumMonthly)}';

  String planButtonLabelAnnual() =>
      'Anual ${formatBrl(premiumAnnual)} (${formatBrl(premiumAnnualEquivalentMonthlyFloor(premiumAnnual))}/mês)';

  /// Campos da landing/divulgação gerados a partir só dos preços Premium.
  Map<String, String> generatedPremiumLandingFields() {
    final pm = formatBrl(premiumMonthly);
    final pa = formatBrl(premiumAnnual);
    final eq = formatBrl(premiumAnnualEquivalentMonthlyFloor(premiumAnnual));
    return {
      'divBasicoMensal': '$pm/mês',
      'divBasicoAnual': '$pa/ano',
      'divPremiumMensal': '$pm/mês',
      'divPremiumAnual': '$pa/ano',
      'divPremiumBeneficios':
          'Módulo financeiro completo, Agenda e lembretes, Cursos bíblicos, Comprovantes e backup, Relatórios e metas',
      'divPlanosSubtitle':
          'Plano Premium: finanças, agenda e cursos num só lugar. Mensal ou anual — no anual sai cerca de $eq/mês em média; '
          'recomendamos o anual. No cartão, o plano anual pode ser parcelado em até 6 vezes quando o Mercado Pago permitir.',
      'landingPremiumDetail':
          'Plano mensal: $pm por mês. Plano anual: $pa/ano — frisando: comprando anual, sai $eq por mês; é um ótimo negócio. Recomendamos comprar anual para máxima economia.',
      'landingPremiumCardPeriod':
          'Mensal ou anual — no anual: $eq/mês, ótimo negócio; recomendamos comprar anual',
    };
  }

  /// Linhas de preço Premium PRO para `landing_content` (sincronização no Admin).
  Map<String, String> generatedPremiumProLandingFields() {
    final pm = formatBrl(premiumProMonthly);
    final pa = formatBrl(premiumProAnnual);
    final exM = formatBrl(extraBankConnectionMonthly);
    final exA = formatBrl(extraBankConnectionAnnual);
    return {
      'divPremiumProMensal': '$pm/mês',
      'divPremiumProAnual': '$pa/ano',
      'divPremiumProExtrasLine': openFinanceAddOnVitrineLine,
      'divPremiumProExtrasMensal': '$exM/mês',
      'divPremiumProExtrasAnual': '$exA/ano',
    };
  }

  List<({String code, String title, String price, String subtitle})>
  premiumPlanRowsForCheckout() {
    final pm = formatBrl(premiumMonthly);
    final pa = formatBrl(premiumAnnual);
    final eq = formatBrl(premiumAnnualEquivalentMonthlyFloor(premiumAnnual));
    return [
      (
        code: 'premium_monthly',
        title: 'Premium',
        price: '$pm/mês',
        subtitle: 'Finanças, metas, escalas, comprovantes e relatórios',
      ),
      (
        code: 'premium_annual',
        title: 'Premium Anual',
        price: '$eq/mês ($pa/ano)',
        subtitle: 'Melhor custo-benefício — no cartão, até 6x no checkout',
      ),
    ];
  }
}

class MpCheckoutPricingService {
  MpCheckoutPricingService._();

  static final DocumentReference<Map<String, dynamic>> _doc = FirebaseFirestore
      .instance
      .collection('app_config')
      .doc('mp_checkout_prices');

  static Stream<MpCheckoutPricingSnapshot> watch() {
    return _doc.snapshots().map(
      (s) => MpCheckoutPricingSnapshot.fromFirestore(s.data()),
    );
  }
}
