import '../services/mp_checkout_pricing_service.dart';

// Conteúdo editável da landing (`/`) e da página pública `/divulgacao`, lido de
// `landing_content/main`. Valores em branco no Firestore usam os defaults abaixo
// (texto atual do site) para o painel já abrir preenchido.
//
// Os textos de preço Premium exibidos no site são alinhados a
// `app_config/mp_checkout_prices` via [applyPremiumTextsFromCheckoutPricing]
// para não ficarem presos a texto antigo gravado só em `landing_content/main`.

/// URL padrão da Google Play (pacote Android oficial).
const String kDefaultPlayStoreUrl =
    'https://play.google.com/store/apps/details?id=com.wisdomapp.app';

/// Instagram oficial WISDOMAPP (@wisdomappgo).
const String kDefaultWisdomAppInstagramUrl =
    'https://www.instagram.com/wisdomappgo/';

/// Definição de campo para o editor Admin (página /divulgacao).
class LandingFieldDef {
  const LandingFieldDef(this.key, this.label, this.defaultValue);

  final String key;
  final String label;
  final String defaultValue;
}

/// Campos da rota `/divulgacao` (ordem do formulário).
const List<LandingFieldDef> kDivulgacaoLandingFields = [
  LandingFieldDef('divHeroTitle', 'Hero — título principal', 'WISDOMAPP'),
  LandingFieldDef(
      'divHeroTagline',
      'Hero — linha dourada (ex.: Sabedoria financeira)',
      'Sabedoria financeira'),
  LandingFieldDef(
      'divHeroBadge', 'Hero — faixa (badge)', 'PRINCÍPIOS BÍBLICOS · GESTÃO INTELIGENTE'),
  LandingFieldDef(
    'divHeroHeadline',
    'Hero — parágrafo (branco)',
    'Finanças, objetivos financeiros, agenda e cursos em um só lugar — com sabedoria financeira baseada nos princípios bíblicos.',
  ),
  LandingFieldDef('divHeroBtnEntrar', 'Hero — botão Entrar', 'Entrar'),
  LandingFieldDef('divHeroBtnPlanos', 'Hero — botão Ver planos', 'Ver planos'),
  LandingFieldDef('divHeroChip1', 'Hero — chip 1', 'Seguro'),
  LandingFieldDef('divHeroChip2', 'Hero — chip 2', 'Sincronizado'),
  LandingFieldDef('divHeroChip3', 'Hero — chip 3', 'PIX e cartão no site'),
  LandingFieldDef('divNavInicio', 'Topo web — botão Início', 'Início'),
  LandingFieldDef(
      'divChannelsTitle', 'Canais oficiais — título', 'Canais oficiais'),
  LandingFieldDef(
      'divChannelsSubtitle', 'Canais oficiais — subtítulo', 'Raihom Barbosa'),
  LandingFieldDef(
    'divYoutubeUrl',
    'Canais oficiais — URL YouTube',
    'https://youtube.com/',
  ),
  LandingFieldDef(
    'divInstagramUrl',
    'Canais oficiais — URL Instagram',
    kDefaultWisdomAppInstagramUrl,
  ),
  LandingFieldDef(
    'divWhatsappUrl',
    'Canais oficiais — URL WhatsApp',
    'https://wa.me/5562996713032',
  ),
  LandingFieldDef('divYoutubeLabel', 'Canais — rótulo YouTube', 'YouTube'),
  LandingFieldDef('divInstagramLabel', 'Canais — rótulo Instagram', 'Instagram'),
  LandingFieldDef('divWhatsappLabel', 'Canais — rótulo WhatsApp', 'WhatsApp'),
  LandingFieldDef(
    'divPlayStoreUrl',
    'Baixar app — URL Google Play',
    kDefaultPlayStoreUrl,
  ),
  LandingFieldDef(
    'divPlayStoreLabel',
    'Baixar app — rótulo botão Google Play',
    'Google Play',
  ),
  LandingFieldDef(
    'divBookBadge',
    'Livro (lançamento) — faixa',
    'LANÇAMENTO DO LIVRO',
  ),
  LandingFieldDef(
    'divBookTitle',
    'Livro (lançamento) — título',
    'Um Degrau Abaixo',
  ),
  LandingFieldDef(
    'divBookAuthor',
    'Livro (lançamento) — autor',
    'Johnathan Tarley',
  ),
  LandingFieldDef(
    'divBookSubtitle',
    'Livro (lançamento) — subtítulo',
    'Método Wisdom de organização financeira.',
  ),
  LandingFieldDef(
    'divBookLaunchText',
    'Livro (lançamento) — texto da chamada',
    'Em breve: reserva e novidades no Instagram, WhatsApp e YouTube oficial do mentor.',
  ),
  LandingFieldDef(
    'divBookImageUrl',
    'Livro (lançamento) — URL da capa (opcional)',
    '',
  ),
  LandingFieldDef(
    'divMentorName',
    'Mentor — nome',
    'Johnathan Tarley',
  ),
  LandingFieldDef(
    'divMentorRole',
    'Mentor — cargo/chamada',
    'Mentor do curso e autor do método Wisdom.',
  ),
  LandingFieldDef(
    'divMentorInstagramUrl',
    'Mentor (Tarley) — URL Instagram',
    kDefaultWisdomAppInstagramUrl,
  ),
  LandingFieldDef(
    'divMentorWhatsappUrl',
    'Mentor — URL WhatsApp',
    'https://wa.me/5562996713032',
  ),
  LandingFieldDef(
    'divMentorYoutubeUrl',
    'Mentor — URL YouTube',
    '',
  ),
  LandingFieldDef(
    'divMentorInstagramLabel',
    'Mentor — rótulo botão Instagram',
    'Instagram do Mentor',
  ),
  LandingFieldDef(
    'divMentorWhatsappLabel',
    'Mentor — rótulo botão WhatsApp',
    'WhatsApp do Mentor',
  ),
  LandingFieldDef(
    'divMentorYoutubeLabel',
    'Mentor — rótulo botão YouTube',
    'YouTube do Mentor',
  ),
  LandingFieldDef('divLabelComoFunciona', 'Seção — rótulo “Como funciona”',
      'Como funciona'),
  LandingFieldDef('divStep1Title', 'Passo 1 — título', 'Crie sua conta'),
  LandingFieldDef(
    'divStep1Body',
    'Passo 1 — texto',
    'Entre com Google ou e-mail. Os dados ficam na sua conta segura.',
  ),
  LandingFieldDef(
      'divStep2Title', 'Passo 2 — título', 'Escolha o plano no site'),
  LandingFieldDef(
    'divStep2Body',
    'Passo 2 — texto',
    'Promoções ativas mostram preço e duração da licença. Pagamento com Mercado Pago (PIX ou cartão) no site oficial.',
  ),
  LandingFieldDef('divStep3Title', 'Passo 3 — título', 'Use no app ou na web'),
  LandingFieldDef(
    'divStep3Body',
    'Passo 3 — texto',
    'A mesma conta no celular e no computador — finanças, objetivos, agenda e metas sincronizadas.',
  ),
  LandingFieldDef(
      'divLabelComece', 'Seção — rótulo “Comece aqui”', 'Comece aqui'),
  LandingFieldDef(
    'divComeceParagraph',
    'Comece aqui — parágrafo',
    'Gestão financeira, Objetivos Financeiros (Projeto 52 semanas), agenda e cursos num só lugar — padrão super premium no site.',
  ),
  LandingFieldDef('divLabelPlanos', 'Seção — rótulo “Planos”', 'Planos'),
  LandingFieldDef(
    'divPlanosSubtitle',
    'Planos — subtítulo',
    r'Plano Premium: finanças, objetivos financeiros, agenda e cursos num só lugar. Pague mensal ou anual — no anual, melhor custo-benefício; recomendamos o anual. No cartão, o plano anual pode ser parcelado em até 6 vezes quando o Mercado Pago permitir.',
  ),
  LandingFieldDef(
      'divBasicoTitulo', 'Bloco secundário — título (opcional)', 'Destaque'),
  LandingFieldDef(
      'divBasicoMensal', 'Bloco secundário — linha mensal', r'R$ 49,90/mês'),
  LandingFieldDef(
      'divBasicoAnual', 'Bloco secundário — linha anual', r'R$ 478,80/ano'),
  LandingFieldDef(
    'divBasicoBeneficios',
    'Bloco secundário — benefícios (vírgula)',
    'Controle financeiro, Objetivos Financeiros (52 semanas), Agenda e lembretes, Cursos financeiros bíblicos, Relatórios',
  ),
  LandingFieldDef('divPremiumTitulo', 'Plano Premium — nome', 'Premium'),
  LandingFieldDef(
      'divPremiumMensal', 'Plano Premium — linha mensal', r'R$ 49,90/mês'),
  LandingFieldDef(
      'divPremiumAnual', 'Plano Premium — linha anual', r'R$ 478,80/ano'),
  LandingFieldDef(
    'divPremiumBeneficios',
    'Plano Premium — benefícios (vírgula)',
    'Módulo financeiro completo, Objetivos Financeiros (52 semanas), Agenda e lembretes, Cursos bíblicos, Comprovantes e backup, Relatórios',
  ),
  LandingFieldDef(
    'divPremiumCardSubtitle',
    'Cartão Premium — subtítulo (cinza)',
    'Finanças, objetivos financeiros, agenda e cursos com controlo total à mão',
  ),
  LandingFieldDef(
      'divPremiumRibbon', 'Cartão Premium — faixa superior', 'SUPER PREMIUM'),
  LandingFieldDef(
    'divPremiumProTitulo',
    'Plano Premium PRO — nome',
    'Premium PRO — o teu dinheiro entra sozinho no app.',
  ),
  LandingFieldDef('divPremiumProMensal', 'Plano Premium PRO — linha mensal',
      r'R$ 25,90/mês'),
  LandingFieldDef('divPremiumProAnual', 'Plano Premium PRO — linha anual',
      r'R$ 299,90/ano'),
  LandingFieldDef(
    'divPremiumProBeneficios',
    'Plano Premium PRO — benefícios (vírgula)',
    'Diferença do Premium: conexão Open Finance com bancos e cartões, Extrato e movimentos a entrar no app, Categorias certas nos lançamentos, Tudo o mais igual ao Premium (metas, escalas, comprovantes, app e web, lançar à mão quando quiseres)',
  ),
  LandingFieldDef(
    'divPremiumProCardSubtitle',
    'Cartão PRO — subtítulo (cinza)',
    'Conecta bancos (Open Finance), extrato e movimentos nas categorias certas. O resto do Premium continua: lançar à mão, metas, escalas, app e web. A diferença é a integração automática com bancos e cartões',
  ),
  LandingFieldDef(
    'divPremiumProExtrasLine',
    "Plano PRO — conexão extra (preços = checkout MP; Sincronizar no Admin preenche)",
    r'Conexão bancária extra a partir de R$ 5,90/mês ou R$ 59,90/ano (checkout) — vinculada ao teto de ligações do app.',
  ),
  LandingFieldDef('divPremiumProRibbon', 'Cartão PRO — faixa superior', 'PRO'),
  LandingFieldDef(
      'divIncluiLabel', 'Planos — rótulo da lista “Inclui”', 'Inclui'),
  LandingFieldDef('divGerencieTopBadge', 'Cartão licença — faixa superior',
      'SUPER PREMIUM · LICENÇA'),
  LandingFieldDef(
      'divGerencieTitle', 'Cartão licença — título', 'Gerencie sua licença'),
  LandingFieldDef(
    'divGerencieSubtitle',
    'Cartão licença — subtítulo',
    'Login no site · renovação premium com PIX ou cartão',
  ),
  LandingFieldDef(
    'divGerencieTapLine',
    'Cartão licença — linha clicável (PIX/cartão)',
    'Clique aqui para renovar sua licença com PIX ou cartão.',
  ),
  LandingFieldDef(
    'divGerencieParagraph',
    'Cartão licença — parágrafo',
    'Entre com Google (Android e web) ou com Google/Apple no iPhone. Depois do login você usa o sistema normalmente e compra ou renova pelo próprio site — PIX ou cartão.',
  ),
  LandingFieldDef('divGerencieLoginBtn', 'Cartão licença — botão login',
      'Continuar com Google'),
  LandingFieldDef('divGerencieGoogleBtn', 'Cartão licença — botão Google',
      'Continuar com Google'),
  LandingFieldDef(
    'divTrialTitle',
    'Trial — título (use {days} para os dias grátis)',
    '{days} dias grátis — tudo liberado',
  ),
  LandingFieldDef(
    'divTrialBody',
    'Trial — texto',
    'E-mail ou Google. Período completo em modo premium; depois escolha o plano no painel.',
  ),
  LandingFieldDef(
      'divFooterDomain', 'Rodapé web — domínio', 'wisdomapp-b9e98.web.app'),
  LandingFieldDef(
      'divFooterHome', 'Rodapé web — link inicial', 'Página inicial'),
  LandingFieldDef('divFooterTerms', 'Rodapé web — Termos', 'Termos'),
  LandingFieldDef(
      'divFooterPrivacy', 'Rodapé web — Privacidade', 'Privacidade'),
  LandingFieldDef('divBtnEntrarPrincipal', 'Botão final — Entrar',
      'Entrar — WISDOMAPP'),
  LandingFieldDef('divBtnAreaAdmin', 'Botão final — Área administrativa',
      'Área administrativa'),
];

/// Chaves de [kDivulgacaoLandingFields] só de planos (nome, mensal, anual, benefícios).
const Set<String> kDivulgacaoPlanPricingKeys = {
  'divBasicoTitulo',
  'divBasicoMensal',
  'divBasicoAnual',
  'divBasicoBeneficios',
  'divPremiumTitulo',
  'divPremiumMensal',
  'divPremiumAnual',
  'divPremiumBeneficios',
  'divPremiumProTitulo',
  'divPremiumProMensal',
  'divPremiumProAnual',
  'divPremiumProBeneficios',
  'divPremiumProExtrasLine',
};

/// Botão «Baixar o app» na landing (Google Play).
const Set<String> kLandingAppDownloadFieldKeys = {
  'divPlayStoreUrl',
  'divPlayStoreLabel',
};

List<LandingFieldDef> get kLandingAppDownloadFields =>
    kDivulgacaoLandingFields
        .where((f) => kLandingAppDownloadFieldKeys.contains(f.key))
        .toList();

/// Livro + mentor Johnathan Tarley (`/divulgacao` e módulo Tarley).
const Set<String> kLandingMentorTarleyFieldKeys = {
  'divBookBadge',
  'divBookTitle',
  'divBookAuthor',
  'divBookSubtitle',
  'divBookLaunchText',
  'divBookImageUrl',
  'divMentorName',
  'divMentorRole',
  'divMentorInstagramUrl',
  'divMentorWhatsappUrl',
  'divMentorYoutubeUrl',
  'divMentorInstagramLabel',
  'divMentorWhatsappLabel',
  'divMentorYoutubeLabel',
};

List<LandingFieldDef> get kLandingMentorTarleyFields =>
    kDivulgacaoLandingFields
        .where((f) => kLandingMentorTarleyFieldKeys.contains(f.key))
        .toList();

/// Campos da faixa «Canais oficiais» (site / landing).
const Set<String> kLandingOfficialChannelsFieldKeys = {
  'divChannelsTitle',
  'divChannelsSubtitle',
  'divYoutubeUrl',
  'divInstagramUrl',
  'divWhatsappUrl',
  'divYoutubeLabel',
  'divInstagramLabel',
  'divWhatsappLabel',
};

List<LandingFieldDef> get kLandingOfficialChannelsFields =>
    kDivulgacaoLandingFields
        .where((f) => kLandingOfficialChannelsFieldKeys.contains(f.key))
        .toList();

/// Campos /divulgacao exceto planos (evita duplicar no formulário).
List<LandingFieldDef> get kDivulgacaoLandingFieldsSemPlanos =>
    kDivulgacaoLandingFields
        .where((f) =>
            !kDivulgacaoPlanPricingKeys.contains(f.key) &&
            !kLandingOfficialChannelsFieldKeys.contains(f.key) &&
            !kLandingAppDownloadFieldKeys.contains(f.key) &&
            !kLandingMentorTarleyFieldKeys.contains(f.key))
        .toList();

/// Ordem fixa dos campos de plano para o bloco “Preços” no Admin.
List<LandingFieldDef> get kDivulgacaoPlanPricingFields =>
    kDivulgacaoLandingFields
        .where((f) => kDivulgacaoPlanPricingKeys.contains(f.key))
        .toList();

/// Defaults da seção “Página inicial /” e textos legados já usados no Admin.
const Map<String, String> kLegacyLandingDefaults = {
  'heroTitle': 'WISDOMAPP',
  'heroSubtitle': 'Sabedoria financeira baseada nos princípios bíblicos.',
  'heroTealLine': 'Módulo Financeiro · Objetivos Financeiros · Agenda · Cursos',
  'heroSlateLine': 'Organize finanças, metas, compromissos e aprendizado em um só app.',
  'heroBadges':
      'Receitas e despesas, Objetivos Financeiros 52 semanas, Orçamentos, Compromissos, Cursos bíblicos, Dicas do dia',
  'heroNote': '',
  'plansTitle': 'Plano Premium',
  'premiumPrice': r'R$ 49,90/mês • R$ 478,80/ano',
  'masterPrice': r'R$ 49,90/mês • R$ 478,80/ano',
  'premiumPerks':
      'Módulo financeiro completo, Objetivos Financeiros (52 semanas), Agenda e lembretes, Cursos com princípios bíblicos, Anexar comprovantes, Relatórios e dicas bíblicas',
  'masterPerks':
      'Módulo financeiro completo, Objetivos Financeiros (52 semanas), Agenda e lembretes, Cursos com princípios bíblicos, Anexar comprovantes, Relatórios e dicas bíblicas',
  'planCtaText': 'Assinar agora',
  'landingPremiumDetail':
      r'Plano mensal: R$ 49,90 por mês. Plano anual: R$ 478,80/ano — equivalente a R$ 39,90/mês; recomendamos o anual para máxima economia.',
  'landingPremiumCardPeriod':
      r'Mensal ou anual — no anual: R$ 39,90/mês; recomendamos comprar anual',
  'landingPremiumFeatures':
      'Financeiro e relatórios, Objetivos Financeiros (52 semanas), Agenda e lembretes, Cursos financeiros bíblicos, Anexar comprovantes, Acesso web e celular, Downloads e suporte',
  'footerText':
      'WISDOMAPP — sabedoria financeira com princípios bíblicos. Acesso pelo celular, computador ou notebook.',
  'supportTitle': 'Downloads e suporte',
  'supportSubtitle':
      'Financeiro, Objetivos Financeiros, agenda, cursos e relatórios; anexar comprovantes; acesso total.',
};

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
  });

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
    return LandingPublicContent(
      heroTitle: heroTitle,
      heroSubtitle: heroSubtitle,
      heroTealLine: heroTealLine,
      heroSlateLine: heroSlateLine,
      plansTitle: plansTitle,
      planCtaText: planCtaText,
      landingPremiumDetail: g['landingPremiumDetail'] ?? landingPremiumDetail,
      landingPremiumCardPeriod:
          g['landingPremiumCardPeriod'] ?? landingPremiumCardPeriod,
      landingPremiumFeaturesCsv: landingPremiumFeaturesCsv,
      divHeroTitle: divHeroTitle,
      divHeroTagline: divHeroTagline,
      divHeroBadge: divHeroBadge,
      divHeroHeadline: divHeroHeadline,
      divHeroBtnEntrar: divHeroBtnEntrar,
      divHeroBtnPlanos: divHeroBtnPlanos,
      divHeroChip1: divHeroChip1,
      divHeroChip2: divHeroChip2,
      divHeroChip3: divHeroChip3,
      divNavInicio: divNavInicio,
      divChannelsTitle: divChannelsTitle,
      divChannelsSubtitle: divChannelsSubtitle,
      divYoutubeUrl: divYoutubeUrl,
      divInstagramUrl: divInstagramUrl,
      divWhatsappUrl: divWhatsappUrl,
      divYoutubeLabel: divYoutubeLabel,
      divInstagramLabel: divInstagramLabel,
      divWhatsappLabel: divWhatsappLabel,
      divPlayStoreUrl: divPlayStoreUrl,
      divPlayStoreLabel: divPlayStoreLabel,
      divLabelComoFunciona: divLabelComoFunciona,
      divStep1Title: divStep1Title,
      divStep1Body: divStep1Body,
      divStep2Title: divStep2Title,
      divStep2Body: divStep2Body,
      divStep3Title: divStep3Title,
      divStep3Body: divStep3Body,
      divLabelComece: divLabelComece,
      divComeceParagraph: divComeceParagraph,
      divLabelPlanos: divLabelPlanos,
      divPlanosSubtitle: g['divPlanosSubtitle'] ?? divPlanosSubtitle,
      divBasicoTitulo: divBasicoTitulo,
      divBasicoMensal: g['divBasicoMensal'] ?? divBasicoMensal,
      divBasicoAnual: g['divBasicoAnual'] ?? divBasicoAnual,
      divBasicoBeneficiosCsv: divBasicoBeneficiosCsv,
      divPremiumTitulo: divPremiumTitulo,
      divPremiumMensal: g['divPremiumMensal'] ?? divPremiumMensal,
      divPremiumAnual: g['divPremiumAnual'] ?? divPremiumAnual,
      divPremiumBeneficiosCsv:
          g['divPremiumBeneficios'] ?? divPremiumBeneficiosCsv,
      divPremiumCardSubtitle: divPremiumCardSubtitle,
      divPremiumRibbon: divPremiumRibbon,
      divPremiumProTitulo: divPremiumProTitulo,
      divPremiumProMensal: gp['divPremiumProMensal'] ?? divPremiumProMensal,
      divPremiumProAnual: gp['divPremiumProAnual'] ?? divPremiumProAnual,
      divPremiumProBeneficiosCsv: divPremiumProBeneficiosCsv,
      divPremiumProCardSubtitle: divPremiumProCardSubtitle,
      divPremiumProExtrasLine:
          gp['divPremiumProExtrasLine'] ?? divPremiumProExtrasLine,
      divPremiumProRibbon: divPremiumProRibbon,
      divIncluiLabel: divIncluiLabel,
      divGerencieTopBadge: divGerencieTopBadge,
      divGerencieTitle: divGerencieTitle,
      divGerencieSubtitle: divGerencieSubtitle,
      divGerencieTapLine: divGerencieTapLine,
      divGerencieParagraph: divGerencieParagraph,
      divGerencieLoginBtn: divGerencieLoginBtn,
      divGerencieGoogleBtn: divGerencieGoogleBtn,
      divTrialTitle: divTrialTitle,
      divTrialBody: divTrialBody,
      divFooterDomain: divFooterDomain,
      divFooterHome: divFooterHome,
      divFooterTerms: divFooterTerms,
      divFooterPrivacy: divFooterPrivacy,
      divBtnEntrarPrincipal: divBtnEntrarPrincipal,
      divBtnAreaAdmin: divBtnAreaAdmin,
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
