import 'package:flutter/foundation.dart' show ValueNotifier;

import '../constants/landing_defaults.dart';
import '../services/mp_checkout_pricing_service.dart';
import 'user_profile.dart';

export '../constants/landing_defaults.dart';

// Conteúdo editável da landing (`/`) e da página pública `/divulgacao`, lido de
// `landing_content/main`. Valores em branco no Firestore usam os padrões de
// `lib/constants/landing_defaults.dart` (texto atual do site) — a mesma fonte
// que o editor do Admin usa, então página e editor nunca divergem.
//
// Preços: as linhas de valor (mensal/anual) vêm sempre de
// `app_config/mp_checkout_prices` via [applyPremiumTextsFromCheckoutPricing], e
// os marcadores {premium_mensal}, {premium_anual}, {premium_anual_mes},
// {extra_mensal}, {extra_anual} e {dias} são trocados pelos valores atuais.

/// Último conteúdo público carregado pela landing / divulgação (com preços).
/// Widgets avulsos (ex.: cartão de promoção) leem daqui sem abrir outra escuta.
final ValueNotifier<LandingPublicContent> landingContentLive =
    ValueNotifier<LandingPublicContent>(LandingPublicContent.initial());

/// Troca os marcadores de preço/dias pelo valor atual.
String landingFillPlaceholders(String text, MpCheckoutPricingSnapshot? p) {
  if (!text.contains('{')) return text;
  final snap = p ?? MpCheckoutPricingSnapshot.defaults();
  final f = MpCheckoutPricingSnapshot.formatBrl;
  return text
      .replaceAll('{premium_mensal}', f(snap.premiumMonthly))
      .replaceAll('{premium_anual_mes}',
          f(MpCheckoutPricingSnapshot.premiumAnnualEquivalentMonthlyFloor(
              snap.premiumAnnual)))
      .replaceAll('{premium_anual}', f(snap.premiumAnnual))
      .replaceAll('{extra_mensal}', f(snap.extraBankConnectionMonthly))
      .replaceAll('{extra_anual}', f(snap.extraBankConnectionAnnual))
      .replaceAll('{dias}', '${UserProfile.newUserTrialDays}');
}


Map<String, String>? _divDefaultsCache;

Map<String, String> _divDefaultsByKey() {
  return _divDefaultsCache ??= {
    for (final f in kDivulgacaoLandingFields) f.key: f.defaultValue,
  };
}

String _pickStr(Map<String, dynamic>? raw, String key, String def) {
  if (raw == null) return def;
  final v = raw[key];
  if (v == null) return def;
  if (v is String) {
    final t = v.trim();
    return t.isEmpty ? def : t;
  }
  if (v is Iterable) {
    final joined =
        v.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).join(', ');
    return joined.isEmpty ? def : joined;
  }
  final t = v.toString().trim();
  return t.isEmpty ? def : t;
}

/// Se o Firestore ainda tiver textos do Controle Total, usa o default WISDOMAPP.
String _pickLegacyHero(Map<String, dynamic>? raw, String key) {
  final def = _legacyDef(key);
  final v = _pickStr(raw, key, def);
  final lower = v.toLowerCase();
  if (lower.contains('controle total')) return def;
  if (key == 'heroSubtitle' && lower.contains('escalas e metas')) return def;
  return v;
}

String _pickDivHero(Map<String, dynamic>? raw, String key) {
  final def = _divDef(key);
  final v = _pickStr(raw, key, def);
  if (v.toLowerCase().contains('controle total')) return def;
  return v;
}

String _legacyDef(String key) => kLegacyLandingDefaults[key] ?? '';

String _divDef(String key) => _divDefaultsByKey()[key] ?? '';

/// Linha “R$ X / mês ou R$ Y / ano” a partir dos campos mensal/anual.
String landingFormatMensalOuAnual(String mensal, String anual) {
  String norm(String x) {
    final t = x.trim();
    if (t.isEmpty) return t;
    return t.replaceAll('/mês', ' / mês').replaceAll('/ano', ' / ano');
  }

  final m = norm(mensal);
  final a = norm(anual);
  if (m.isEmpty && a.isEmpty) return '';
  if (m.isEmpty) return a;
  if (a.isEmpty) return m;
  return '$m ou $a';
}

/// Snapshot mesclado (Firestore + defaults) para UI pública.
class LandingPublicContent {
  const LandingPublicContent({
    required this.heroTitle,
    required this.heroSubtitle,
    required this.heroTealLine,
    required this.heroSlateLine,
    required this.plansTitle,
    required this.planCtaText,
    required this.landingPremiumDetail,
    required this.landingPremiumCardPeriod,
    required this.landingPremiumFeaturesCsv,
    required this.divHeroTitle,
    required this.divHeroTagline,
    required this.divHeroBadge,
    required this.divHeroHeadline,
    required this.divHeroBtnEntrar,
    required this.divHeroBtnPlanos,
    required this.divHeroChip1,
    required this.divHeroChip2,
    required this.divHeroChip3,
    required this.divNavInicio,
    required this.divChannelsTitle,
    required this.divChannelsSubtitle,
    required this.divYoutubeUrl,
    required this.divInstagramUrl,
    required this.divWhatsappUrl,
    required this.divYoutubeLabel,
    required this.divInstagramLabel,
    required this.divWhatsappLabel,
    required this.divPlayStoreUrl,
    required this.divPlayStoreLabel,
    required this.divLabelComoFunciona,
    required this.divStep1Title,
    required this.divStep1Body,
    required this.divStep2Title,
    required this.divStep2Body,
    required this.divStep3Title,
    required this.divStep3Body,
    required this.divLabelComece,
    required this.divComeceParagraph,
    required this.divLabelPlanos,
    required this.divPlanosSubtitle,
    required this.divBasicoTitulo,
    required this.divBasicoMensal,
    required this.divBasicoAnual,
    required this.divBasicoBeneficiosCsv,
    required this.divPremiumTitulo,
    required this.divPremiumMensal,
    required this.divPremiumAnual,
    required this.divPremiumBeneficiosCsv,
    required this.divPremiumCardSubtitle,
    required this.divPremiumRibbon,
    required this.divPremiumProTitulo,
    required this.divPremiumProMensal,
    required this.divPremiumProAnual,
    required this.divPremiumProBeneficiosCsv,
    required this.divPremiumProCardSubtitle,
    required this.divPremiumProExtrasLine,
    required this.divPremiumProRibbon,
    required this.divIncluiLabel,
    required this.divGerencieTopBadge,
    required this.divGerencieTitle,
    required this.divGerencieSubtitle,
    required this.divGerencieTapLine,
    required this.divGerencieParagraph,
    required this.divGerencieLoginBtn,
    required this.divGerencieGoogleBtn,
    required this.divTrialTitle,
    required this.divTrialBody,
    required this.divFooterDomain,
    required this.divFooterHome,
    required this.divFooterTerms,
    required this.divFooterPrivacy,
    required this.divBtnEntrarPrincipal,
    required this.divBtnAreaAdmin,
    this.raw,
    this.pricing,
  });

  /// Documento `landing_content/main` como veio do Firestore (para [t]).
  final Map<String, dynamic>? raw;

  /// Preços do checkout já aplicados (null = ainda não carregou → padrão).
  final MpCheckoutPricingSnapshot? pricing;

  /// Texto de qualquer chave (Firestore ou padrão do código), com marcadores
  /// de preço/dias já trocados. Use para os textos que não têm campo próprio.
  String t(String key) =>
      landingFillPlaceholders(_pickStr(raw, key, landingDefaultFor(key)), pricing);

  /// Como [t], mas devolve vazio se o admin apagou o texto (campos opcionais).
  String tOptional(String key) {
    final v = raw?[key];
    if (v is String && v.trim().isEmpty && raw!.containsKey(key)) return '';
    return t(key);
  }

  final String heroTitle;
  final String heroSubtitle;
  final String heroTealLine;
  final String heroSlateLine;

  /// Título da seção de preços Premium na página inicial (/).
  final String plansTitle;
  final String planCtaText;
  final String landingPremiumDetail;
  final String landingPremiumCardPeriod;
  final String landingPremiumFeaturesCsv;

  final String divHeroTitle;
  final String divHeroTagline;
  final String divHeroBadge;
  final String divHeroHeadline;
  final String divHeroBtnEntrar;
  final String divHeroBtnPlanos;
  final String divHeroChip1;
  final String divHeroChip2;
  final String divHeroChip3;
  final String divNavInicio;
  final String divChannelsTitle;
  final String divChannelsSubtitle;
  final String divYoutubeUrl;
  final String divInstagramUrl;
  final String divWhatsappUrl;
  final String divYoutubeLabel;
  final String divInstagramLabel;
  final String divWhatsappLabel;
  final String divPlayStoreUrl;
  final String divPlayStoreLabel;
  final String divLabelComoFunciona;
  final String divStep1Title;
  final String divStep1Body;
  final String divStep2Title;
  final String divStep2Body;
  final String divStep3Title;
  final String divStep3Body;
  final String divLabelComece;
  final String divComeceParagraph;
  final String divLabelPlanos;
  final String divPlanosSubtitle;
  final String divBasicoTitulo;
  final String divBasicoMensal;
  final String divBasicoAnual;
  final String divBasicoBeneficiosCsv;
  final String divPremiumTitulo;
  final String divPremiumMensal;
  final String divPremiumAnual;
  final String divPremiumBeneficiosCsv;
  final String divPremiumCardSubtitle;
  final String divPremiumRibbon;
  final String divPremiumProTitulo;
  final String divPremiumProMensal;
  final String divPremiumProAnual;
  final String divPremiumProBeneficiosCsv;
  final String divPremiumProCardSubtitle;

  /// Bancos extra: preço “de vitrine” alinhado a `app_config/mp_checkout_prices` (add-on).
  final String divPremiumProExtrasLine;
  final String divPremiumProRibbon;
  final String divIncluiLabel;
  final String divGerencieTopBadge;
  final String divGerencieTitle;
  final String divGerencieSubtitle;
  final String divGerencieTapLine;
  final String divGerencieParagraph;
  final String divGerencieLoginBtn;
  final String divGerencieGoogleBtn;
  final String divTrialTitle;
  final String divTrialBody;
  final String divFooterDomain;
  final String divFooterHome;
  final String divFooterTerms;
  final String divFooterPrivacy;
  final String divBtnEntrarPrincipal;
  final String divBtnAreaAdmin;

  /// Conteúdo padrão já com os preços padrão aplicados (antes do Firestore chegar).
  factory LandingPublicContent.initial() => LandingPublicContent.fromMap(null)
      .applyPremiumTextsFromCheckoutPricing(MpCheckoutPricingSnapshot.defaults());

  factory LandingPublicContent.fromMap(Map<String, dynamic>? raw) {
    return LandingPublicContent(
      heroTitle: _pickLegacyHero(raw, 'heroTitle'),
      heroSubtitle: _pickLegacyHero(raw, 'heroSubtitle'),
      heroTealLine: _pickLegacyHero(raw, 'heroTealLine'),
      heroSlateLine: _pickLegacyHero(raw, 'heroSlateLine'),
      plansTitle: _pickStr(raw, 'plansTitle', _legacyDef('plansTitle')),
      planCtaText: _pickStr(raw, 'planCtaText', _legacyDef('planCtaText')),
      landingPremiumDetail: _pickStr(
          raw, 'landingPremiumDetail', _legacyDef('landingPremiumDetail')),
      landingPremiumCardPeriod: _pickStr(raw, 'landingPremiumCardPeriod',
          _legacyDef('landingPremiumCardPeriod')),
      landingPremiumFeaturesCsv: _pickStr(
          raw, 'landingPremiumFeatures', _legacyDef('landingPremiumFeatures')),
      divHeroTitle: _pickDivHero(raw, 'divHeroTitle'),
      divHeroTagline:
          _pickDivHero(raw, 'divHeroTagline'),
      divHeroBadge: _pickStr(raw, 'divHeroBadge', _divDef('divHeroBadge')),
      divHeroHeadline:
          _pickStr(raw, 'divHeroHeadline', _divDef('divHeroHeadline')),
      divHeroBtnEntrar:
          _pickStr(raw, 'divHeroBtnEntrar', _divDef('divHeroBtnEntrar')),
      divHeroBtnPlanos:
          _pickStr(raw, 'divHeroBtnPlanos', _divDef('divHeroBtnPlanos')),
      divHeroChip1: _pickStr(raw, 'divHeroChip1', _divDef('divHeroChip1')),
      divHeroChip2: _pickStr(raw, 'divHeroChip2', _divDef('divHeroChip2')),
      divHeroChip3: _pickStr(raw, 'divHeroChip3', _divDef('divHeroChip3')),
      divNavInicio: _pickStr(raw, 'divNavInicio', _divDef('divNavInicio')),
      divChannelsTitle:
          _pickStr(raw, 'divChannelsTitle', _divDef('divChannelsTitle')),
      divChannelsSubtitle:
          _pickStr(raw, 'divChannelsSubtitle', _divDef('divChannelsSubtitle')),
      divYoutubeUrl: _pickStr(raw, 'divYoutubeUrl', _divDef('divYoutubeUrl')),
      divInstagramUrl:
          _pickStr(raw, 'divInstagramUrl', _divDef('divInstagramUrl')),
      divWhatsappUrl:
          _pickStr(raw, 'divWhatsappUrl', _divDef('divWhatsappUrl')),
      divYoutubeLabel:
          _pickStr(raw, 'divYoutubeLabel', _divDef('divYoutubeLabel')),
      divInstagramLabel:
          _pickStr(raw, 'divInstagramLabel', _divDef('divInstagramLabel')),
      divWhatsappLabel:
          _pickStr(raw, 'divWhatsappLabel', _divDef('divWhatsappLabel')),
      divPlayStoreUrl:
          _pickStr(raw, 'divPlayStoreUrl', _divDef('divPlayStoreUrl')),
      divPlayStoreLabel:
          _pickStr(raw, 'divPlayStoreLabel', _divDef('divPlayStoreLabel')),
      divLabelComoFunciona: _pickStr(
          raw, 'divLabelComoFunciona', _divDef('divLabelComoFunciona')),
      divStep1Title: _pickStr(raw, 'divStep1Title', _divDef('divStep1Title')),
      divStep1Body: _pickStr(raw, 'divStep1Body', _divDef('divStep1Body')),
      divStep2Title: _pickStr(raw, 'divStep2Title', _divDef('divStep2Title')),
      divStep2Body: _pickStr(raw, 'divStep2Body', _divDef('divStep2Body')),
      divStep3Title: _pickStr(raw, 'divStep3Title', _divDef('divStep3Title')),
      divStep3Body: _pickStr(raw, 'divStep3Body', _divDef('divStep3Body')),
      divLabelComece:
          _pickStr(raw, 'divLabelComece', _divDef('divLabelComece')),
      divComeceParagraph:
          _pickStr(raw, 'divComeceParagraph', _divDef('divComeceParagraph')),
      divLabelPlanos:
          _pickStr(raw, 'divLabelPlanos', _divDef('divLabelPlanos')),
      divPlanosSubtitle:
          _pickStr(raw, 'divPlanosSubtitle', _divDef('divPlanosSubtitle')),
      divBasicoTitulo:
          _pickStr(raw, 'divBasicoTitulo', _divDef('divBasicoTitulo')),
      divBasicoMensal:
          _pickStr(raw, 'divBasicoMensal', _divDef('divBasicoMensal')),
      divBasicoAnual:
          _pickStr(raw, 'divBasicoAnual', _divDef('divBasicoAnual')),
      divBasicoBeneficiosCsv:
          _pickStr(raw, 'divBasicoBeneficios', _divDef('divBasicoBeneficios')),
      divPremiumTitulo:
          _pickStr(raw, 'divPremiumTitulo', _divDef('divPremiumTitulo')),
      divPremiumMensal:
          _pickStr(raw, 'divPremiumMensal', _divDef('divPremiumMensal')),
      divPremiumAnual:
          _pickStr(raw, 'divPremiumAnual', _divDef('divPremiumAnual')),
      divPremiumBeneficiosCsv: _pickStr(
          raw, 'divPremiumBeneficios', _divDef('divPremiumBeneficios')),
      divPremiumCardSubtitle: _pickStr(
          raw, 'divPremiumCardSubtitle', _divDef('divPremiumCardSubtitle')),
      divPremiumRibbon:
          _pickStr(raw, 'divPremiumRibbon', _divDef('divPremiumRibbon')),
      divPremiumProTitulo:
          _pickStr(raw, 'divPremiumProTitulo', _divDef('divPremiumProTitulo')),
      divPremiumProMensal:
          _pickStr(raw, 'divPremiumProMensal', _divDef('divPremiumProMensal')),
      divPremiumProAnual:
          _pickStr(raw, 'divPremiumProAnual', _divDef('divPremiumProAnual')),
      divPremiumProBeneficiosCsv: _pickStr(
          raw, 'divPremiumProBeneficios', _divDef('divPremiumProBeneficios')),
      divPremiumProCardSubtitle: _pickStr(raw, 'divPremiumProCardSubtitle',
          _divDef('divPremiumProCardSubtitle')),
      divPremiumProExtrasLine: _pickStr(
          raw, 'divPremiumProExtrasLine', _divDef('divPremiumProExtrasLine')),
      divPremiumProRibbon:
          _pickStr(raw, 'divPremiumProRibbon', _divDef('divPremiumProRibbon')),
      divIncluiLabel:
          _pickStr(raw, 'divIncluiLabel', _divDef('divIncluiLabel')),
      divGerencieTopBadge:
          _pickStr(raw, 'divGerencieTopBadge', _divDef('divGerencieTopBadge')),
      divGerencieTitle:
          _pickStr(raw, 'divGerencieTitle', _divDef('divGerencieTitle')),
      divGerencieSubtitle:
          _pickStr(raw, 'divGerencieSubtitle', _divDef('divGerencieSubtitle')),
      divGerencieTapLine:
          _pickStr(raw, 'divGerencieTapLine', _divDef('divGerencieTapLine')),
      divGerencieParagraph: _pickStr(
          raw, 'divGerencieParagraph', _divDef('divGerencieParagraph')),
      divGerencieLoginBtn:
          _pickStr(raw, 'divGerencieLoginBtn', _divDef('divGerencieLoginBtn')),
      divGerencieGoogleBtn: _pickStr(
          raw, 'divGerencieGoogleBtn', _divDef('divGerencieGoogleBtn')),
      divTrialTitle: _pickStr(raw, 'divTrialTitle', _divDef('divTrialTitle')),
      divTrialBody: _pickStr(raw, 'divTrialBody', _divDef('divTrialBody')),
      divFooterDomain:
          _pickStr(raw, 'divFooterDomain', _divDef('divFooterDomain')),
      divFooterHome: _pickStr(raw, 'divFooterHome', _divDef('divFooterHome')),
      divFooterTerms:
          _pickStr(raw, 'divFooterTerms', _divDef('divFooterTerms')),
      divFooterPrivacy:
          _pickStr(raw, 'divFooterPrivacy', _divDef('divFooterPrivacy')),
      divBtnEntrarPrincipal: _pickStr(
          raw, 'divBtnEntrarPrincipal', _divDef('divBtnEntrarPrincipal')),
      divBtnAreaAdmin:
          _pickStr(raw, 'divBtnAreaAdmin', _divDef('divBtnAreaAdmin')),
      raw: raw,
    );
  }

  List<String> _splitBenefits(String csv) {
    return csv
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  List<String> get divBasicoBeneficiosList =>
      _splitBenefits(divBasicoBeneficiosCsv);
  List<String> get divPremiumBeneficiosList =>
      _splitBenefits(divPremiumBeneficiosCsv);
  List<String> get divPremiumProBeneficiosList =>
      _splitBenefits(divPremiumProBeneficiosCsv);
  List<String> get landingPremiumFeaturesList =>
      _splitBenefits(landingPremiumFeaturesCsv);

  /// Preço combinado na home (/) a partir de Premium mensal + anual.
  String get homePremiumCombinedPriceLine =>
      landingFormatMensalOuAnual(divPremiumMensal, divPremiumAnual);

  /// Preço combinado Premium PRO (mensal + anual) para landing e paywall.
  String get homePremiumProCombinedPriceLine =>
      landingFormatMensalOuAnual(divPremiumProMensal, divPremiumProAnual);

  /// Substitui linhas Premium/preço pela geração a partir dos valores reais do checkout
  /// (mesma regra do Admin «Sincronizar textos Premium» + add-on Open Finance no PRO).
  LandingPublicContent applyPremiumTextsFromCheckoutPricing(
      MpCheckoutPricingSnapshot snap) {
    final g = snap.generatedPremiumLandingFields();
    final gp = snap.generatedPremiumProLandingFields();
    String p(String s) => landingFillPlaceholders(s, snap);
    // Parágrafo com marcadores → usa o texto do admin com o preço atual.
    // Texto antigo com «R$» fixo → usa o gerado (preço nunca fica velho).
    // Sem preço → texto do admin como está.
    String para(String stored, String? generated) {
      if (stored.contains('{')) return p(stored);
      if (generated != null && stored.contains(r'R$')) return generated;
      return stored;
    }

    return LandingPublicContent(
      heroTitle: p(heroTitle),
      heroSubtitle: p(heroSubtitle),
      heroTealLine: p(heroTealLine),
      heroSlateLine: p(heroSlateLine),
      plansTitle: p(plansTitle),
      planCtaText: p(planCtaText),
      landingPremiumDetail:
          para(landingPremiumDetail, g['landingPremiumDetail']),
      landingPremiumCardPeriod:
          para(landingPremiumCardPeriod, g['landingPremiumCardPeriod']),
      landingPremiumFeaturesCsv: p(landingPremiumFeaturesCsv),
      divHeroTitle: p(divHeroTitle),
      divHeroTagline: p(divHeroTagline),
      divHeroBadge: p(divHeroBadge),
      divHeroHeadline: p(divHeroHeadline),
      divHeroBtnEntrar: p(divHeroBtnEntrar),
      divHeroBtnPlanos: p(divHeroBtnPlanos),
      divHeroChip1: p(divHeroChip1),
      divHeroChip2: p(divHeroChip2),
      divHeroChip3: p(divHeroChip3),
      divNavInicio: p(divNavInicio),
      divChannelsTitle: p(divChannelsTitle),
      divChannelsSubtitle: p(divChannelsSubtitle),
      divYoutubeUrl: p(divYoutubeUrl),
      divInstagramUrl: p(divInstagramUrl),
      divWhatsappUrl: p(divWhatsappUrl),
      divYoutubeLabel: p(divYoutubeLabel),
      divInstagramLabel: p(divInstagramLabel),
      divWhatsappLabel: p(divWhatsappLabel),
      divPlayStoreUrl: p(divPlayStoreUrl),
      divPlayStoreLabel: p(divPlayStoreLabel),
      divLabelComoFunciona: p(divLabelComoFunciona),
      divStep1Title: p(divStep1Title),
      divStep1Body: p(divStep1Body),
      divStep2Title: p(divStep2Title),
      divStep2Body: p(divStep2Body),
      divStep3Title: p(divStep3Title),
      divStep3Body: p(divStep3Body),
      divLabelComece: p(divLabelComece),
      divComeceParagraph: p(divComeceParagraph),
      divLabelPlanos: p(divLabelPlanos),
      divPlanosSubtitle: para(divPlanosSubtitle, g['divPlanosSubtitle']),
      divBasicoTitulo: p(divBasicoTitulo),
      divBasicoMensal: g['divBasicoMensal'] ?? divBasicoMensal,
      divBasicoAnual: g['divBasicoAnual'] ?? divBasicoAnual,
      divBasicoBeneficiosCsv: p(divBasicoBeneficiosCsv),
      divPremiumTitulo: p(divPremiumTitulo),
      divPremiumMensal: g['divPremiumMensal'] ?? divPremiumMensal,
      divPremiumAnual: g['divPremiumAnual'] ?? divPremiumAnual,
      divPremiumBeneficiosCsv: p(divPremiumBeneficiosCsv),
      divPremiumCardSubtitle: p(divPremiumCardSubtitle),
      divPremiumRibbon: p(divPremiumRibbon),
      divPremiumProTitulo: p(divPremiumProTitulo),
      divPremiumProMensal: gp['divPremiumProMensal'] ?? divPremiumProMensal,
      divPremiumProAnual: gp['divPremiumProAnual'] ?? divPremiumProAnual,
      divPremiumProBeneficiosCsv: p(divPremiumProBeneficiosCsv),
      divPremiumProCardSubtitle: p(divPremiumProCardSubtitle),
      divPremiumProExtrasLine:
          gp['divPremiumProExtrasLine'] ?? divPremiumProExtrasLine,
      divPremiumProRibbon: p(divPremiumProRibbon),
      divIncluiLabel: p(divIncluiLabel),
      divGerencieTopBadge: p(divGerencieTopBadge),
      divGerencieTitle: p(divGerencieTitle),
      divGerencieSubtitle: p(divGerencieSubtitle),
      divGerencieTapLine: p(divGerencieTapLine),
      divGerencieParagraph: p(divGerencieParagraph),
      divGerencieLoginBtn: p(divGerencieLoginBtn),
      divGerencieGoogleBtn: p(divGerencieGoogleBtn),
      divTrialTitle: p(divTrialTitle),
      divTrialBody: p(divTrialBody),
      divFooterDomain: p(divFooterDomain),
      divFooterHome: p(divFooterHome),
      divFooterTerms: p(divFooterTerms),
      divFooterPrivacy: p(divFooterPrivacy),
      divBtnEntrarPrincipal: p(divBtnEntrarPrincipal),
      divBtnAreaAdmin: p(divBtnAreaAdmin),
      raw: raw,
      pricing: snap,
    );
  }

  String divTrialTitleWithDays(int days) =>
      divTrialTitle.replaceAll('{days}', '$days');

  /// Texto para controllers do Admin (Firestore ou default do site).
  static String pickLegacyEditor(Map<String, dynamic>? data, String key) =>
      _pickStr(data, key, _legacyDef(key));

  static String pickDivEditor(Map<String, dynamic>? data, String key) =>
      _pickStr(data, key, _divDef(key));
}
