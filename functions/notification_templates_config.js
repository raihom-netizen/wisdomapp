/**
 * Templates globais de notificações (Firestore: app_config/notification_templates).
 * Cache em memória para não ler Firestore a cada push/e-mail.
 */

const DEFAULT_NOTIFICATION_TEMPLATES = {
  brandName: "Controle Total App",
  emailFooter: "© Controle Total App — Gestão financeira, escalas e metas.",
  emailIntro: "",
  richPushEnabled: true,
  digestEnabled: true,
  digestHourBrasilia: 20,
  digestPushEnabled: true,
  accentAudiencia: "#5B21B6",
  accentCompromisso: "#2563EB",
  accentEscala: "#EA580C",
  accentFinanceiro: "#0D9488",
  accentFolga: "#7C3AED",
};

let _cache = { data: null, at: 0 };
const CACHE_MS = 60 * 1000;

function invalidateNotificationTemplatesCache() {
  _cache = { data: null, at: 0 };
}

async function loadNotificationTemplates(db) {
  const now = Date.now();
  if (_cache.data && now - _cache.at < CACHE_MS) {
    return _cache.data;
  }
  let merged = { ...DEFAULT_NOTIFICATION_TEMPLATES };
  try {
    const snap = await db.collection("app_config").doc("notification_templates").get();
    if (snap.exists) {
      const d = snap.data() || {};
      merged = { ...merged, ...d };
    }
  } catch (_) {}
  _cache = { data: merged, at: now };
  return merged;
}

function mergeChannelTheme(baseTheme, templates, channelKind) {
  const k = (channelKind || "").toString().toLowerCase();
  let accentKey = "accentEscala";
  if (k === "audiencia") accentKey = "accentAudiencia";
  else if (k === "compromisso") accentKey = "accentCompromisso";
  else if (k === "financeiro") accentKey = "accentFinanceiro";
  else if (k === "folga") accentKey = "accentFolga";
  const custom = (templates[accentKey] || "").toString().trim();
  if (!custom) return baseTheme;
  return { ...baseTheme, accent: custom, accent2: custom, androidColor: custom };
}

function richPushImageUrl(channelKind, appDomain, templates) {
  if (templates && templates.richPushEnabled === false) return null;
  const k = (channelKind || "escala").toString().toLowerCase();
  const allowed = ["audiencia", "compromisso", "escala", "financeiro", "folga"];
  const safe = allowed.includes(k) ? k : "escala";
  const domain = (appDomain || "").replace(/\/$/, "");
  return `${domain}/icons/push-banner-${safe}.png`;
}

/** Deep link web/PWA ao tocar no push (home_shell lê ?tab=). */
function agendaDeepLinkPath(channelKind, sourceType) {
  const k = (channelKind || "").toString().toLowerCase();
  const src = (sourceType || "").toString().toLowerCase();
  if (src === "scale" || k === "escala") return "/?tab=escalas";
  if (k === "financeiro" || src === "transaction") return "/?tab=financeiro";
  if (k === "audiencia") return "/?tab=agenda&sub=audiencia";
  if (k === "compromisso") return "/?tab=agenda&sub=compromisso";
  return "/?tab=agenda";
}

module.exports = {
  DEFAULT_NOTIFICATION_TEMPLATES,
  loadNotificationTemplates,
  invalidateNotificationTemplatesCache,
  mergeChannelTheme,
  richPushImageUrl,
  agendaDeepLinkPath,
};
