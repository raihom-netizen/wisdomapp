/**
 * Bootstrap completo Firestore + Storage para WISDOMAPP.
 * Usado por ctBootstrapWisdomappFirestore (HTTP) e scripts/bootstrap-wisdomapp-firebase.js
 */
const WISDOMAPP_CLIENT_ID = "941346310248415";
const ADMIN_EMAIL = "raihom@gmail.com";
const PREMIUM_MONTHLY = 49.9;
const PREMIUM_ANNUAL = 478.8;

const LEGACY_LANDING = {
  heroTitle: "WISDOMAPP",
  heroSubtitle: "Sabedoria financeira baseada nos princípios bíblicos.",
  heroTealLine: "Módulo Financeiro · Agenda · Cursos financeiros",
  heroSlateLine: "Organize suas finanças, compromissos e aprendizado em um só app.",
  heroNote: "",
  plansTitle: "Plano Premium",
  premiumPrice: "R$ 49,90/mês • R$ 478,80/ano",
  masterPrice: "R$ 49,90/mês • R$ 478,80/ano",
  premiumPerks:
    "Módulo financeiro completo, Agenda e lembretes, Cursos com princípios bíblicos, Anexar comprovantes, Relatórios e metas",
  masterPerks:
    "Módulo financeiro completo, Agenda e lembretes, Cursos com princípios bíblicos, Anexar comprovantes, Relatórios e metas",
  planCtaText: "Assinar agora",
  landingPremiumDetail:
    "Plano mensal: R$ 49,90 por mês. Plano anual: R$ 478,80/ano — equivalente a R$ 39,90/mês; recomendamos o anual para máxima economia.",
  landingPremiumCardPeriod:
    "Mensal ou anual — no anual: R$ 39,90/mês; recomendamos comprar anual",
  landingPremiumFeatures:
    "Financeiro, metas e relatórios, Agenda e lembretes, Cursos financeiros bíblicos, Anexar comprovantes, Acesso web e celular, Downloads e suporte",
  footerText:
    "WISDOMAPP — sabedoria financeira com princípios bíblicos. Acesso pelo celular, computador ou notebook.",
  supportTitle: "Downloads e suporte",
  supportSubtitle:
    "Financeiro, agenda, cursos e relatórios; anexar comprovantes; acesso total.",
};

const DIV_LANDING = {
  divHeroTitle: "WISDOMAPP",
  divHeroTagline: "Sabedoria financeira",
  divHeroBadge: "PRINCÍPIOS BÍBLICOS · GESTÃO INTELIGENTE",
  divHeroHeadline:
    "Finanças, agenda e cursos em um só lugar — com sabedoria financeira baseada nos princípios bíblicos.",
  divHeroBtnEntrar: "Entrar",
  divHeroBtnPlanos: "Ver planos",
  divHeroChip1: "Seguro",
  divHeroChip2: "Sincronizado",
  divHeroChip3: "PIX e cartão no site",
  divNavInicio: "Início",
  divChannelsTitle: "Canais oficiais",
  divChannelsSubtitle: "Raihom Barbosa",
  divYoutubeUrl: "https://youtube.com/",
  divInstagramUrl: "https://www.instagram.com/wisdomappgo/",
  divWhatsappUrl: "https://wa.me/5562996713032",
  divPlayStoreUrl:
    "https://play.google.com/store/apps/details?id=com.wisdomapp.app",
  divPlayStoreLabel: "Google Play",
  divBookBadge: "LANÇAMENTO DO LIVRO",
  divBookTitle: "Um Degrau Abaixo",
  divBookAuthor: "Johnathan Tarley",
  divBookSubtitle: "Método Wisdom de organização financeira.",
  divBookLaunchText:
    "Em breve: reserva e novidades no Instagram, WhatsApp e YouTube oficial do mentor.",
  divBookImageUrl: "",
  divMentorName: "Johnathan Tarley",
  divMentorRole: "Mentor do curso e autor do método Wisdom.",
  divMentorInstagramUrl: "https://www.instagram.com/wisdomappgo/",
  divMentorWhatsappUrl: "https://wa.me/5562996713032",
  divMentorYoutubeUrl: "",
  divMentorInstagramLabel: "Instagram do Mentor",
  divMentorWhatsappLabel: "WhatsApp do Mentor",
  divMentorYoutubeLabel: "YouTube do Mentor",
  divLabelComoFunciona: "Como funciona",
  divStep1Title: "Crie sua conta",
  divStep1Body: "Entre com Google ou e-mail. Os dados ficam na sua conta segura.",
  divStep2Title: "Escolha o plano no site",
  divStep2Body:
    "Promoções ativas mostram preço e duração da licença. Pagamento com Mercado Pago (PIX ou cartão) no site oficial.",
  divStep3Title: "Use no app ou na web",
  divStep3Body:
    "A mesma conta no celular e no computador — finanças, agenda e cursos sincronizados.",
  divLabelComece: "Comece aqui",
  divComeceParagraph:
    "Gestão financeira, agenda e cursos num só lugar — padrão super premium no site.",
  divLabelPlanos: "Planos",
  divPlanosSubtitle:
    "Plano Premium: finanças, agenda e cursos num só lugar. Pague mensal ou anual — no anual, melhor custo-benefício; recomendamos o anual. No cartão, o plano anual pode ser parcelado em até 6 vezes quando o Mercado Pago permitir.",
  divBasicoTitulo: "Destaque",
  divBasicoMensal: "R$ 49,90/mês",
  divBasicoAnual: "R$ 478,80/ano",
  divBasicoBeneficios:
    "Controle financeiro, Agenda e lembretes, Cursos financeiros bíblicos, Relatórios e metas",
  divPremiumTitulo: "Premium",
  divPremiumMensal: "R$ 49,90/mês",
  divPremiumAnual: "R$ 478,80/ano",
  divPremiumBeneficios:
    "Módulo financeiro completo, Agenda e lembretes, Cursos bíblicos, Comprovantes e backup, Relatórios e metas",
  divPremiumCardSubtitle: "Finanças, agenda e cursos com controlo total à mão",
  divPremiumRibbon: "SUPER PREMIUM",
  divPremiumProTitulo: "Premium PRO — Open Finance (quando disponível)",
  divPremiumProMensal: "R$ 25,90/mês",
  divPremiumProAnual: "R$ 299,90/ano",
  divPremiumProBeneficios:
    "Open Finance, Extrato automático, Categorias inteligentes, Tudo do Premium",
  divPremiumProCardSubtitle: "Integração bancária automática (add-on futuro)",
  divPremiumProExtrasLine:
    "Conexão bancária extra — preços definidos no checkout Mercado Pago.",
  divPremiumProRibbon: "PRO",
  divIncluiLabel: "Inclui",
  divGerencieTopBadge: "SUPER PREMIUM · LICENÇA",
  divGerencieTitle: "Gerencie sua licença",
  divGerencieSubtitle: "Login no site · renovação premium com PIX ou cartão",
  divGerencieTapLine: "Clique aqui para renovar sua licença com PIX ou cartão.",
  divGerencieParagraph:
    "Entre com e-mail e senha (Gmail, Outlook, Hotmail…) ou com Google. Depois do login você usa o sistema normalmente e compra ou renova pelo próprio site — PIX ou cartão.",
  divGerencieLoginBtn: "Login — e-mail ou CPF + senha",
  divGerencieGoogleBtn: "Continuar com Google",
  divTrialTitle: "{days} dias grátis — tudo liberado",
  divTrialBody:
    "E-mail ou Google. Período completo em modo premium; depois escolha o plano no painel.",
  divFooterDomain: "wisdomapp-b9e98.web.app",
  divFooterHome: "Página inicial",
  divFooterTerms: "Termos",
  divFooterPrivacy: "Privacidade",
  divBtnEntrarPrincipal: "Entrar — WISDOMAPP",
  divBtnAreaAdmin: "Área administrativa",
};

const STORAGE_PATHS = [
  "comprovantes/_bootstrap/.keep",
  "users/_bootstrap/receipts/.keep",
  "app/ipa/.keep",
  "releases/.keep",
  "admin/.keep",
  "backups/.keep",
  "wisdomapp/course_videos/_bootstrap/.keep",
];

async function writeDoc(db, admin, path, data, { force, mergeAlways = false }) {
  const ref = db.doc(path);
  const snap = await ref.get();
  if (snap.exists && !force && !mergeAlways) {
    return { path, action: "skipped" };
  }
  const payload = {
    ...data,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (!snap.exists) {
    payload.createdAt = admin.firestore.FieldValue.serverTimestamp();
  }
  await ref.set(payload, { merge: !force });
  return { path, action: snap.exists ? (force ? "overwritten" : "merged") : "created" };
}

async function ensureStoragePlaceholder(bucket, filePath) {
  const file = bucket.file(filePath);
  const [exists] = await file.exists();
  if (exists) return { path: filePath, action: "skipped" };
  await file.save("WISDOMAPP placeholder\n", {
    metadata: { contentType: "text/plain", cacheControl: "no-cache" },
  });
  return { path: filePath, action: "created" };
}

async function setupAdminUser(admin, db, email) {
  const auth = admin.auth();
  let user;
  try {
    user = await auth.getUserByEmail(email);
  } catch (e) {
    if (e.code === "auth/user-not-found") {
      return { email, action: "skipped", reason: "usuario ainda nao existe no Auth — faca login uma vez" };
    }
    throw e;
  }

  const uid = user.uid;
  const licenseExpires = new Date("2099-12-31T23:59:59.000Z");
  const profile = {
    uid,
    email,
    name: user.displayName || "Administrador",
    role: "admin",
    plan: "master",
    planStatus: "active",
    licenseExpiresAt: admin.firestore.Timestamp.fromDate(licenseExpires),
    profileComplete: true,
    cpf: "",
    cpfMasked: "",
    app: "WISDOMAPP",
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  const ref = db.doc(`users/${uid}`);
  const snap = await ref.get();
  if (!snap.exists) profile.createdAt = admin.firestore.FieldValue.serverTimestamp();
  await ref.set(profile, { merge: true });
  return { email, uid, action: snap.exists ? "updated" : "created" };
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {typeof import('firebase-admin')} admin
 * @param {{ force?: boolean, adminEmail?: string, version?: string, buildNumber?: number, versionCode?: number }} options
 */
async function runWisdomappFirestoreBootstrap(db, admin, options = {}) {
  const force = !!options.force;
  const adminEmail = (options.adminEmail || ADMIN_EMAIL).trim();
  const version = (options.version || "10.02").trim();
  const buildNumber = Number(options.buildNumber ?? 2);
  const versionCode = Number(options.versionCode ?? 2);
  const results = { firestore: [], storage: [], admin: null };

  const landingContent = {
    ...LEGACY_LANDING,
    ...DIV_LANDING,
    appName: "WISDOMAPP",
  };

  const docs = [
    [
      "app_config/version",
      {
        version,
        buildNumber,
        versionCode,
        forceUpdate: false,
        apkDownloadUrl: "https://play.google.com/store/apps/details?id=com.wisdomapp.app",
        releaseTag: `${version}+${buildNumber}`,
        app: "WISDOMAPP",
      },
      { force: true },
    ],
    [
      "app_config/mp_checkout_prices",
      {
        premium_monthly: PREMIUM_MONTHLY,
        premium_annual: PREMIUM_ANNUAL,
        premiumMonthlyBrl: PREMIUM_MONTHLY,
        premiumAnnualBrl: PREMIUM_ANNUAL,
        currency: "BRL",
        app: "WISDOMAPP",
        note: "Valores usados no checkout Mercado Pago e sincronizados na divulgacao.",
      },
      { force },
    ],
    [
      "app_config/pro_open_finance",
      {
        maxConnectionsPerUser: 3,
        extraConnectionPriceBrl: 9.9,
        enabled: false,
        note: "Open Finance desligado no WISDOMAPP ate configurar Pluggy.",
      },
      { force },
    ],
    [
      "app_config/notification_templates",
      {
        brandName: "WISDOMAPP",
        emailFooter: "© WISDOMAPP — Sabedoria financeira com principios biblicos.",
        emailIntro: "",
        richPushEnabled: true,
        digestEnabled: true,
        digestHourBrasilia: 20,
        digestPushEnabled: true,
        accentAudiencia: "#1E3A5F",
        accentCompromisso: "#2563EB",
        accentEscala: "#C9A227",
        accentFinanceiro: "#0D9488",
        accentFolga: "#7C3AED",
      },
      { force: true },
    ],
    [
      "app_config/premium_pro_monitor",
      {
        pluggyCostPerItemMonthBrl: 12,
        firebaseEstimatePerUserMonthBrl: 0.85,
        mercadoPagoFeePercent: 4.98,
      },
      { force },
    ],
    [
      "app_config/admin_scheduled_exports",
      {
        enabled: false,
        email: adminEmail,
        frequency: "weekly",
      },
      { force },
    ],
    [
      "app_config/pluggy",
      {
        configured: false,
        note: "Preencha clientId e clientSecret no Painel Admin > Pluggy.",
      },
      { force },
    ],
    ["landing_content/main", landingContent, { force: true }],
    [
      "app_config/wisdom_courses_module",
      {
        heroTitle: "Cursos Financeiros",
        heroMessage:
          "Aulas em vídeo com princípios bíblicos — conteúdo publicado pelo Painel Admin.",
        sectionTitle: "Vídeos publicados",
        emptyMessage:
          "Nenhum vídeo publicado ainda. O administrador adiciona links do YouTube no Painel Admin → Cursos.",
        showTipsSection: true,
      },
      { force: true },
    ],
    [
      "mp_project_config/main",
      {
        projectName: "WISDOMAPP",
        clientId: WISDOMAPP_CLIENT_ID,
        splitEnabled: true,
        splitMode: "fifty_fifty",
        ownerSharePercent: 50,
        partnerSharePercent: 50,
        ownerLabel: "Raihom Barbosa",
        partnerLabel: "Johnathan Tarley",
        ownerDisplayName: "Raihom Barbosa",
        partnerDisplayName: "Johnathan Tarley",
      },
      { force: true },
    ],
    [
      "secure_config/mercado_pago",
      {
        clientId: WISDOMAPP_CLIENT_ID,
        splitEnabled: false,
        configured: false,
        note: "Execute functions/set_mp_split_config.js com access token e partner collector ID reais.",
      },
      { force },
    ],
    [
      "settings/mercadopago",
      {
        client_id: WISDOMAPP_CLIENT_ID,
        clientId: WISDOMAPP_CLIENT_ID,
        public_key: "",
        publicKey: "",
        access_token: "",
        accessToken: "",
        client_secret: "",
        clientSecret: "",
        webhookUrl: "https://us-central1-wisdomapp-b9e98.cloudfunctions.net/mpWebhook",
        note: "Credenciais de producao — preencha pelo Painel Admin ou set_mp_split_config.js",
      },
      { force },
    ],
    [
      "settings/email",
      {
        configured: false,
        note: "Defina user (Gmail) e appPassword para envio de lembretes.",
      },
      { force },
    ],
    [
      "config/scale_rates",
      {
        ratePeriods: [],
        note: "Historico AC4 GO — preenchido pelo admin quando necessario.",
      },
      { force },
    ],
    [
      "_bootstrap/status",
      {
        app: "WISDOMAPP",
        projectId: "wisdomapp-b9e98",
        initialized: true,
        schemaVersion: 1,
        collections: [
          "app_config",
          "landing_content",
          "mp_project_config",
          "secure_config",
          "settings",
          "config",
          "users",
          "mp_payments",
          "public_downloads",
          "promotions",
          "course_videos",
          "user_feedback",
          "activity_logs",
          "admin_audit_log",
        ],
      },
      { force: true },
    ],
    [
      "mp_payments/_schema",
      {
        note: "Pagamentos gravados automaticamente pelos webhooks e funcoes MP. Nao editar manualmente.",
        fields: [
          "id",
          "status",
          "uid",
          "payerEmail",
          "amount",
          "plan",
          "period",
          "createdAt",
          "updatedAt",
        ],
      },
      { force },
    ],
    [
      "public_downloads/_info",
      {
        note: "Links publicos de APK/IPA/documentos — gerenciados pelo Painel Admin.",
      },
      { force },
    ],
    [
      "promotions/_info",
      {
        note: "Promocoes de licenca — criadas pelo Painel Admin.",
      },
      { force },
    ],
  ];

  for (const [path, data, opts] of docs) {
    results.firestore.push(await writeDoc(db, admin, path, data, opts));
  }

  results.admin = await setupAdminUser(admin, db, adminEmail);

  let bucket = null;
  try {
    bucket = admin.storage().bucket();
    for (const p of STORAGE_PATHS) {
      results.storage.push(await ensureStoragePlaceholder(bucket, p));
    }
  } catch (e) {
    results.storageError = String(e.message || e);
  }

  return results;
}

module.exports = {
  runWisdomappFirestoreBootstrap,
  ADMIN_EMAIL,
  WISDOMAPP_CLIENT_ID,
};
