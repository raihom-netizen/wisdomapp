// Fonte ÚNICA dos textos padrão da landing (`/`), da página `/divulgacao`,
// da faixa «Login expresso» e do cartão de promoção pública.
//
// A página pública e o editor do Admin («Landing / Divulgação») leem daqui:
// se `landing_content/main` tiver valor, ele vale; senão, vale o padrão abaixo.
// Assim o editor sempre abre preenchido com o texto que está no site.
//
// Marcadores aceitos em qualquer texto (trocados na hora de exibir pelos
// valores de `app_config/mp_checkout_prices` — mudou o preço, mudou o texto):
//   {premium_mensal}  {premium_anual}  {premium_anual_mes}
//   {extra_mensal}    {extra_anual}    {dias}

import 'app_brand.dart';
import 'app_verse.dart';

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
  LandingFieldDef('divHeroBadge', 'Hero — faixa (badge)',
      'PRINCÍPIOS BÍBLICOS · GESTÃO INTELIGENTE'),
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
  LandingFieldDef(
      'divInstagramLabel', 'Canais — rótulo Instagram', 'Instagram'),
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
  LandingFieldDef(
      'divBtnEntrarPrincipal', 'Botão final — Entrar', 'Entrar — WISDOMAPP'),
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

List<LandingFieldDef> get kLandingAppDownloadFields => kDivulgacaoLandingFields
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

List<LandingFieldDef> get kLandingMentorTarleyFields => kDivulgacaoLandingFields
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
  'heroSlateLine':
      'Organize finanças, metas, compromissos e aprendizado em um só app.',
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
  // Com marcadores: o valor sai sempre de `app_config/mp_checkout_prices`.
  'landingPremiumDetail':
      'Plano mensal: {premium_mensal} por mês. Plano anual: {premium_anual}/ano — frisando: comprando anual, sai {premium_anual_mes} por mês; é um ótimo negócio. Recomendamos comprar anual para máxima economia.',
  'landingPremiumCardPeriod':
      'Mensal ou anual — no anual: {premium_anual_mes}/mês, ótimo negócio; recomendamos comprar anual',
  'landingPremiumFeatures':
      'Financeiro e relatórios, Objetivos Financeiros (52 semanas), Agenda e lembretes, Cursos financeiros bíblicos, Anexar comprovantes, Acesso web e celular, Downloads e suporte',
  'footerText':
      'WISDOMAPP — sabedoria financeira com princípios bíblicos. Acesso pelo celular, computador ou notebook.',
  'supportTitle': 'Downloads e suporte',
  'supportSubtitle':
      'Financeiro, Objetivos Financeiros, agenda, cursos e relatórios; anexar comprovantes; acesso total.',
  'googleAgendaButtonText': 'Ativar integração com Google Agenda',
  'googleAgendaConnectUrl': 'https://calendar.google.com/',
  'googleAgendaHintText':
      'Conecte sua conta Google para abrir eventos da Agenda diretamente no Google Agenda.',
  'divThemePrimaryColor': '#0B1B4B',
  'divThemeAccentColor': '#E8C547',
};

/// Textos fixos que antes estavam direto nas telas (landing `/`, faixa
/// «Login expresso», cartão de promoção e detalhes da `/divulgacao`).
/// Chaves gravadas em `landing_content/main` com o mesmo nome.
const List<LandingFieldDef> kLandingSiteTextFields = [
  // ── Página inicial — topo «Baixe o app» ──
  LandingFieldDef('homeIosSafariHint', 'Aviso no Safari do iPhone',
      'Melhor no iPhone: abra no Safari e toque em Compartilhar → "Adicionar à Tela de Início".'),
  LandingFieldDef(
      'homeDownloadTitle', 'Faixa «Baixe o app» — título', 'BAIXE O APP'),
  LandingFieldDef('homeDownloadVersion',
      'Faixa «Baixe o app» — versão (use {version})', 'Versão {version}'),
  LandingFieldDef('homeIosTestFlightBtn', 'Botão iPhone (TestFlight)',
      'iPhone (TestFlight)'),
  LandingFieldDef('homeIosBaixarBtn', 'Botão Baixar (no iPhone)', 'Baixar'),
  LandingFieldDef(
      'homeIosTestFlightHintWeb',
      'Dica abaixo do botão iPhone (web/Android)',
      'TestFlight na App Store, depois abra este link.'),
  LandingFieldDef('homeIosTestFlightHintIos', 'Dica abaixo do botão (iPhone)',
      'Instale o TestFlight e abra o link da beta.'),
  // ── Página inicial — hero ──
  LandingFieldDef('homeHeroIdealizer', 'Hero — nome abaixo do título',
      AppBrand.idealizerName),
  LandingFieldDef('homeHeroMicroTagline', 'Hero — faixa dourada pequena',
      'SABEDORIA FINANCEIRA'),
  LandingFieldDef(
      'homeHeroCtaTrial',
      'Hero — botão do teste grátis (use {dias})',
      'Começar {dias} dias grátis'),
  LandingFieldDef('homePwaInstalledNote', 'Aviso «app instalado» (PWA)',
      'App instalado: seu login será mantido ao fechar e abrir.'),
  // ── Página inicial — cartão de licença / login ──
  LandingFieldDef(
      'homeLicenseTitle', 'Cartão de licença — título', 'Gerencie sua Licença'),
  LandingFieldDef('homeLicenseBody', 'Cartão de licença — texto',
      'Entre com Google (Android e web) ou com Google/Apple no iPhone. Depois do login você compra ou renova a licença — PIX ou cartão.'),
  LandingFieldDef(
      'homeLicenseTitleIos',
      'Cartão de licença — título (aberto pelo app iPhone)',
      'Renove ou adquira sua licença'),
  LandingFieldDef(
      'homeLicenseBodyIos',
      'Cartão de licença — texto (aberto pelo app iPhone)',
      'Você abriu o site pelo app iPhone/iPad. Entre com Google ou Apple. Depois escolha mensal ou anual — PIX ou cartão.'),
  LandingFieldDef('homeEmailToggle', 'Botão «Entrar com e-mail e senha»',
      'Entrar com e-mail e senha'),
  LandingFieldDef(
      'homeEmailToggleClose', 'Botão fechar o formulário de e-mail', 'Fechar'),
  LandingFieldDef('homeEmailTeamTitle', 'Formulário de e-mail — título',
      'Equipe Wisdom APP'),
  LandingFieldDef('homeEmailTeamSubtitle', 'Formulário de e-mail — subtítulo',
      'Acesse com seu e-mail e senha cadastrados.'),
  LandingFieldDef(
      'homeForgotPassword', 'Link «Esqueceu a senha?»', 'Esqueceu a senha?'),
  LandingFieldDef('homeEmailEnterBtn', 'Botão ENTRAR (e-mail)', 'ENTRAR'),
  LandingFieldDef('homeNoAccount', 'Texto «Não tem conta?»', 'Não tem conta?'),
  LandingFieldDef('homeSignupBtn', 'Link Cadastrar', 'Cadastrar'),
  LandingFieldDef(
      'homeTrialLine',
      'Linha do teste grátis (use {dias}; o link vem logo depois)',
      'Teste grátis por {dias} dias – acesso livre total pelo celular, computador ou notebook. Use no app ou no navegador em '),
  LandingFieldDef('homeTrialLinkText', 'Linha do teste grátis — texto do link',
      'wisdomapp-b9e98.web.app'),
  LandingFieldDef('homeTrialLinkUrl', 'Linha do teste grátis — URL do link',
      'https://wisdomapp-b9e98.web.app/'),
  // ── Página inicial — módulos ──
  LandingFieldDef(
      'homeModulesTitle', 'Módulos — título', 'Módulos do WISDOMAPP'),
  LandingFieldDef('homeModulesSubtitle', 'Módulos — subtítulo',
      'Financeiro, objetivos financeiros, agenda e cursos com princípios bíblicos — tudo integrado.'),
  LandingFieldDef('homeModule1Title', 'Módulo 1 — título', 'Módulo Financeiro'),
  LandingFieldDef('homeModule1Desc', 'Módulo 1 — texto',
      'Receitas, despesas, orçamentos e relatórios.'),
  LandingFieldDef(
      'homeModule2Title', 'Módulo 2 — título', 'Módulo Objetivos Financeiros'),
  LandingFieldDef('homeModule2Desc', 'Módulo 2 — texto',
      'Metas com Projeto 52 semanas — viagem, carro, casa, reserva…'),
  LandingFieldDef('homeModule3Title', 'Módulo 3 — título', 'Módulo Agenda'),
  LandingFieldDef('homeModule3Desc', 'Módulo 3 — texto',
      'Compromissos, lembretes e planejamento no dia a dia.'),
  LandingFieldDef(
      'homeModule4Title', 'Módulo 4 — título', 'Módulo Cursos Financeiros'),
  LandingFieldDef('homeModule4Desc', 'Módulo 4 — texto',
      'Educação financeira com princípios bíblicos.'),
  // ── Página inicial — citação ──
  LandingFieldDef('homeQuoteText', 'Citação — texto',
      '"O homem que consegue organizar sua vida financeira, conseguirá organizar todas as áreas da sua vida."'),
  LandingFieldDef('homeQuoteAuthor', 'Citação — autor', '— Billy Graham'),
  // ── Página inicial — plano ──
  LandingFieldDef('homePlanCtaIos', 'Botão do plano (aberto pelo app iPhone)',
      'Renove ou adquira — ver planos'),
  // ── Página inicial — rodapé ──
  LandingFieldDef('homeFooterLine1', 'Rodapé — linha 1',
      'Sistema sem propagandas indesejáveis, limpo e seguro.'),
  LandingFieldDef('homeFooterLine2', 'Rodapé — linha 2',
      'Acesso pelo celular, computador ou notebook. Acesso livre total.'),
  LandingFieldDef('homeFooterPayment', 'Rodapé — pagamento',
      'Pagamento seguro via Mercado Pago (PIX ou Cartão)'),
  LandingFieldDef('homeFooterPaymentIos', 'Rodapé — pagamento (Safari iPhone)',
      'No Safari no iPhone/iPad, contrate o plano pelo app instalado (TestFlight) ou pelo site no computador.'),
  LandingFieldDef('homeFooterPrivacy', 'Rodapé — link Privacidade',
      'Política de Privacidade'),
  LandingFieldDef('homeFooterTerms', 'Rodapé — link Termos', 'Termos de Uso'),
  LandingFieldDef('homeFooterSupport', 'Rodapé — link Suporte', 'Suporte'),
  LandingFieldDef(
      'homeFooterEmail', 'Rodapé — e-mail de contato', 'raihom@gmail.com'),
  LandingFieldDef('homeFooterVerse', 'Rodapé — versículo', AppVerse.full),
  LandingFieldDef('homeFooterDevBy', 'Rodapé — desenvolvido por',
      'Desenvolvido por Raihom Barbosa'),
  LandingFieldDef(
      'homeFooterCopyright', 'Rodapé — direitos', '© 2026 WISDOMAPP'),
  // ── Faixa fixa «Login expresso» (/ e /divulgacao) ──
  LandingFieldDef(
      'siteExpressTitle', 'Login expresso — título', 'Login expresso'),
  LandingFieldDef('siteExpressSubtitle', 'Login expresso — subtítulo',
      'Clique aqui para entrar com Google ou Apple'),
  LandingFieldDef('siteExpressBtn', 'Login expresso — botão', 'Entrar'),
  // ── Cartão de promoção ativa (/ e /divulgacao) ──
  LandingFieldDef('promoBadge', 'Promoção — selo', 'PROMO ATIVA'),
  LandingFieldDef(
      'promoDurationLine',
      'Promoção — linha de valor (use {preco} e {dias_licenca})',
      '{preco} · +{dias_licenca} dias de licença após pagamento aprovado'),
  LandingFieldDef('promoCtaGuest', 'Promoção — botão (visitante)',
      'Entrar e aproveitar — PIX ou cartão'),
  LandingFieldDef(
      'promoCtaLogged', 'Promoção — botão (logado)', 'Pagar com esta promoção'),
  LandingFieldDef('promoFootnote', 'Promoção — nota abaixo do botão',
      'Novos e clientes: mesma conta. PIX ou cartão com Mercado Pago no app ou na web — a licença fica na sua conta.'),
  LandingFieldDef('promoIosTitle', 'Promoção — título (Safari iPhone)',
      'Promoção limitada'),
  LandingFieldDef('promoIosBody', 'Promoção — texto (Safari iPhone)',
      'Toque para abrir o site oficial e ver os detalhes desta campanha.'),
  LandingFieldDef('promoIosLink', 'Promoção — link exibido (Safari iPhone)',
      'wisdomapp-b9e98.web.app'),
  // ── /divulgacao — detalhes ──
  LandingFieldDef('divBookAuthorLine', 'Livro — linha do autor (use {autor})',
      'Autor: {autor}'),
];

/// Linhas de preço que SEMPRE vêm de `app_config/mp_checkout_prices`
/// (o editor mostra só para conferência; mudar o preço muda a linha).
const Set<String> kLandingPriceDrivenKeys = {
  'divBasicoMensal',
  'divBasicoAnual',
  'divPremiumMensal',
  'divPremiumAnual',
  'divPremiumProMensal',
  'divPremiumProAnual',
  'divPremiumProExtrasLine',
};

/// Rótulos dos campos «legados» (landing `/`) usados no editor.
const Map<String, String> kLegacyLandingLabels = {
  'heroTitle': 'Hero — título (marca)',
  'heroSubtitle': 'Hero — subtítulo (dourado)',
  'heroTealLine': 'Hero — linha em destaque',
  'heroSlateLine': 'Hero — linha final',
  'heroBadges': 'Badges (vírgula)',
  'heroNote': 'Hero — nota abaixo do botão (vazio = não mostra)',
  'plansTitle': 'Plano — título da seção',
  'planCtaText': 'Plano — texto do botão',
  'landingPremiumDetail': 'Plano — parágrafo abaixo do preço',
  'landingPremiumCardPeriod': 'Plano — linha menor sob o valor no cartão',
  'landingPremiumFeatures': 'Plano — benefícios no cartão (vírgula)',
  'footerText': 'Texto do rodapé (antigo)',
  'supportTitle': 'Título do suporte (antigo)',
  'supportSubtitle': 'Subtítulo do suporte (antigo)',
  'googleAgendaButtonText': 'Google Agenda — texto do botão',
  'googleAgendaConnectUrl': 'Google Agenda — URL da integração',
  'googleAgendaHintText': 'Google Agenda — texto de ajuda',
  'divThemePrimaryColor': 'Cor principal da divulgação (hex, ex.: #0B1B4B)',
  'divThemeAccentColor': 'Cor destaque da divulgação (hex, ex.: #E8C547)',
};

/// Campos legados que o editor grava (os espelhos premiumPrice/masterPrice/
/// *Perks são calculados no salvar e não aparecem no formulário).
const List<String> kLegacyLandingEditableKeys = [
  'heroTitle',
  'heroSubtitle',
  'heroTealLine',
  'heroSlateLine',
  'heroBadges',
  'heroNote',
  'plansTitle',
  'planCtaText',
  'landingPremiumDetail',
  'landingPremiumCardPeriod',
  'landingPremiumFeatures',
  'footerText',
  'supportTitle',
  'supportSubtitle',
  'googleAgendaButtonText',
  'googleAgendaConnectUrl',
  'googleAgendaHintText',
  'divThemePrimaryColor',
  'divThemeAccentColor',
];

/// Seção do editor do Admin — mesma ordem em que aparece no site.
class LandingEditorSection {
  const LandingEditorSection(this.id, this.title, this.subtitle, this.keys);

  final String id;
  final String title;
  final String subtitle;
  final List<String> keys;
}

const List<LandingEditorSection> kLandingEditorSections = [
  LandingEditorSection(
    'home_top',
    'Página inicial (/) — topo «Baixe o app»',
    'Faixa azul do topo e aviso do Safari no iPhone.',
    [
      'homeIosSafariHint',
      'homeDownloadTitle',
      'homeDownloadVersion',
      'divPlayStoreUrl',
      'divPlayStoreLabel',
      'homeIosTestFlightBtn',
      'homeIosBaixarBtn',
      'homeIosTestFlightHintWeb',
      'homeIosTestFlightHintIos',
    ],
  ),
  LandingEditorSection(
    'home_hero',
    'Página inicial (/) — hero',
    'Marca, chamadas e botão do teste grátis.',
    [
      'heroTitle',
      'homeHeroIdealizer',
      'homeHeroMicroTagline',
      'heroSubtitle',
      'heroTealLine',
      'heroSlateLine',
      'homeHeroCtaTrial',
      'heroNote',
      'homePwaInstalledNote',
    ],
  ),
  LandingEditorSection(
    'home_login',
    'Página inicial (/) — cartão de licença e login',
    'Cartão branco com Google/Apple e formulário de e-mail.',
    [
      'homeLicenseTitle',
      'homeLicenseBody',
      'homeLicenseTitleIos',
      'homeLicenseBodyIos',
      'homeEmailToggle',
      'homeEmailToggleClose',
      'homeEmailTeamTitle',
      'homeEmailTeamSubtitle',
      'homeForgotPassword',
      'homeEmailEnterBtn',
      'homeNoAccount',
      'homeSignupBtn',
      'homeTrialLine',
      'homeTrialLinkText',
      'homeTrialLinkUrl',
    ],
  ),
  LandingEditorSection(
    'home_modules',
    'Página inicial (/) — módulos',
    'Os 4 cartões de módulos.',
    [
      'homeModulesTitle',
      'homeModulesSubtitle',
      'homeModule1Title',
      'homeModule1Desc',
      'homeModule2Title',
      'homeModule2Desc',
      'homeModule3Title',
      'homeModule3Desc',
      'homeModule4Title',
      'homeModule4Desc',
    ],
  ),
  LandingEditorSection(
    'home_quote',
    'Página inicial (/) — citação',
    '',
    ['homeQuoteText', 'homeQuoteAuthor'],
  ),
  LandingEditorSection(
    'home_plan',
    'Página inicial (/) — plano Premium',
    'A linha de preço é automática pelos preços do checkout. O nome do plano '
        'no cartão é o mesmo da /divulgacao (seção «/divulgacao — planos»).',
    [
      'plansTitle',
      'landingPremiumDetail',
      'landingPremiumCardPeriod',
      'landingPremiumFeatures',
      'planCtaText',
      'homePlanCtaIos',
    ],
  ),
  LandingEditorSection(
    'home_footer',
    'Página inicial (/) — rodapé',
    '',
    [
      'homeFooterLine1',
      'homeFooterLine2',
      'homeFooterPayment',
      'homeFooterPaymentIos',
      'homeFooterPrivacy',
      'homeFooterTerms',
      'homeFooterSupport',
      'homeFooterEmail',
      'homeFooterVerse',
      'homeFooterDevBy',
      'homeFooterCopyright',
    ],
  ),
  LandingEditorSection(
    'express',
    'Faixa fixa «Login expresso»',
    'Barra no rodapé da tela em / e /divulgacao.',
    ['siteExpressTitle', 'siteExpressSubtitle', 'siteExpressBtn'],
  ),
  LandingEditorSection(
    'channels',
    'Canais oficiais',
    'YouTube, Instagram e WhatsApp (topo do site e apps).',
    [
      'divChannelsTitle',
      'divChannelsSubtitle',
      'divYoutubeUrl',
      'divInstagramUrl',
      'divWhatsappUrl',
      'divYoutubeLabel',
      'divInstagramLabel',
      'divWhatsappLabel',
    ],
  ),
  LandingEditorSection(
    'promo',
    'Cartão de promoção ativa',
    'Aparece quando há promoção marcada para o site (aba Promoções). '
        'Título, valor e vagas vêm da própria promoção.',
    [
      'promoBadge',
      'promoDurationLine',
      'promoCtaGuest',
      'promoCtaLogged',
      'promoFootnote',
      'promoIosTitle',
      'promoIosBody',
      'promoIosLink',
    ],
  ),
  LandingEditorSection(
    'div_hero',
    '/divulgacao — topo',
    '',
    [
      'divNavInicio',
      'divHeroTitle',
      'divHeroTagline',
      'divHeroBadge',
      'divHeroHeadline',
      'divHeroBtnPlanos',
      'divHeroChip1',
      'divHeroChip2',
      'divHeroChip3',
    ],
  ),
  LandingEditorSection(
    'div_book',
    '/divulgacao — livro e mentor (Tarley)',
    'Seção «Um Degrau Abaixo» e botões do mentor.',
    [
      'divBookBadge',
      'divBookTitle',
      'divBookAuthor',
      'divBookAuthorLine',
      'divBookSubtitle',
      'divBookLaunchText',
      'divBookImageUrl',
      'divMentorName',
      'divMentorRole',
      'divMentorInstagramUrl',
      'divMentorInstagramLabel',
      'divMentorYoutubeUrl',
      'divMentorYoutubeLabel',
    ],
  ),
  LandingEditorSection(
    'div_steps',
    '/divulgacao — como funciona e comece aqui',
    '',
    [
      'divLabelComoFunciona',
      'divStep1Title',
      'divStep1Body',
      'divStep2Title',
      'divStep2Body',
      'divStep3Title',
      'divStep3Body',
      'divLabelComece',
      'divComeceParagraph',
    ],
  ),
  LandingEditorSection(
    'div_license',
    '/divulgacao — licença e teste grátis',
    'No título do teste use {days} para os dias grátis.',
    [
      'divGerencieTopBadge',
      'divGerencieTitle',
      'divGerencieSubtitle',
      'divGerencieParagraph',
      'divTrialTitle',
      'divTrialBody',
    ],
  ),
  LandingEditorSection(
    'div_plans',
    '/divulgacao — planos',
    'As linhas de valor (mensal/anual) são automáticas pelos preços do checkout.',
    [
      'divLabelPlanos',
      'divPlanosSubtitle',
      'divBasicoTitulo',
      'divBasicoMensal',
      'divBasicoAnual',
      'divBasicoBeneficios',
      'divPremiumRibbon',
      'divPremiumTitulo',
      'divPremiumCardSubtitle',
      'divPremiumMensal',
      'divPremiumAnual',
      'divPremiumBeneficios',
      'divIncluiLabel',
    ],
  ),
  LandingEditorSection(
    'div_footer',
    '/divulgacao — rodapé e botões',
    '',
    [
      'divFooterDomain',
      'divFooterHome',
      'divFooterTerms',
      'divFooterPrivacy',
      'divBtnAreaAdmin',
    ],
  ),
  LandingEditorSection(
    'config',
    'Cores da divulgação e Google Agenda',
    'Cores-base da /divulgacao e botão de integração no módulo Agenda.',
    [
      'divThemePrimaryColor',
      'divThemeAccentColor',
      'googleAgendaButtonText',
      'googleAgendaConnectUrl',
      'googleAgendaHintText',
    ],
  ),
  LandingEditorSection(
    'unused',
    'Campos guardados que hoje não aparecem no site',
    'Ficam salvos para uso futuro (Premium PRO, botões e rodapé antigos).',
    [
      'heroBadges',
      'footerText',
      'supportTitle',
      'supportSubtitle',
      'divHeroBtnEntrar',
      'divGerencieTapLine',
      'divGerencieLoginBtn',
      'divGerencieGoogleBtn',
      'divBtnEntrarPrincipal',
      'divMentorWhatsappUrl',
      'divMentorWhatsappLabel',
      'divPremiumProRibbon',
      'divPremiumProTitulo',
      'divPremiumProCardSubtitle',
      'divPremiumProMensal',
      'divPremiumProAnual',
      'divPremiumProBeneficios',
      'divPremiumProExtrasLine',
    ],
  ),
];

Map<String, LandingFieldDef>? _allLandingFieldsCache;

/// Todos os campos editáveis (legados + /divulgacao + textos do site), por chave.
Map<String, LandingFieldDef> get kLandingAllFieldsByKey {
  return _allLandingFieldsCache ??= {
    for (final k in kLegacyLandingEditableKeys)
      k: LandingFieldDef(
          k, kLegacyLandingLabels[k] ?? k, kLegacyLandingDefaults[k] ?? ''),
    for (final f in kDivulgacaoLandingFields) f.key: f,
    for (final f in kLandingSiteTextFields) f.key: f,
  };
}

/// Texto padrão (o que está no código) de qualquer chave da landing.
String landingDefaultFor(String key) =>
    kLandingAllFieldsByKey[key]?.defaultValue ??
    kLegacyLandingDefaults[key] ??
    '';
