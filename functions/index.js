const functions = require("firebase-functions");
const { onCall, onRequest } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentCreated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const { defineString } = require("firebase-functions/params");
const admin = require("firebase-admin");

const appVersionSecret = defineString("APP_VERSION_SECRET", { default: "" });
/** App Store Connect → App → App Information → App-Specific Shared Secret (verifyReceipt). */
const APPLE_IAP_UNSET = "__UNSET__";
const appleIapSharedSecretParam = defineString("APPLE_IAP_SHARED_SECRET", { default: APPLE_IAP_UNSET });
const crypto = require("crypto");
const vision = require("@google-cloud/vision");
const speech = require("@google-cloud/speech");

if (!admin.apps.length) admin.initializeApp();

const financePdfSuperExtrato = require("./financePdfSuperExtrato");
const scaleAutoConfirmScheduled = require("./scaleAutoConfirmScheduled");
const goiasScaleRatesRecalc = require("./goiasScaleRatesRecalc");
const agendaMsg = require("./agenda_message_templates");
const notifTpl = require("./notification_templates_config");
const agendaDigest = require("./agenda_daily_digest");
const agendaDelivery = require("./agenda_delivery_prefs");
const agendaPeriodSnapshot = require("./agendaPeriodSnapshot");

const MAX_BYTES = 5 * 1024 * 1024; // 5 MB
const ALLOWED_MIME = new Set([
  "application/pdf",
  "image/png",
  "image/jpeg",
]);

/** Domínio de produção: https://controletotalapp.com.br/ */
const APP_DOMAIN = "https://controletotalapp.com.br";

/** Ícone premium (miniatura) — hosting público do PWA. */
const APP_ICON_URL = `${APP_DOMAIN}/icons/Icon-192.png`;

/** Web + iOS (APNs) + Android: link ao tocar + ícone do app em miniatura. */
function multicastWebPushApnsLink(link) {
  const iconBlock = {
    webpush: {
      notification: { icon: APP_ICON_URL, badge: APP_ICON_URL },
    },
    android: { notification: { imageUrl: APP_ICON_URL } },
    apns: {
      fcmOptions: { image: APP_ICON_URL },
      payload: { aps: { "mutable-content": 1 } },
    },
  };
  if (!link || typeof link !== "string") return iconBlock;
  return {
    webpush: {
      fcmOptions: { link },
      notification: { icon: APP_ICON_URL, badge: APP_ICON_URL },
    },
    apns: {
      fcmOptions: { link, image: APP_ICON_URL },
      payload: { aps: { "mutable-content": 1 } },
    },
    android: { notification: { imageUrl: APP_ICON_URL } },
  };
}

/** Canal Android alinhado ao app (flutter_local_notifications). */
function androidChannelForAgendaKind(channelKind) {
  const k = (channelKind || "").toString().toLowerCase();
  if (k === "audiencia") return "controletotal_audiencia";
  if (k === "compromisso") return "controletotal_compromisso";
  if (k === "folga") return "controletotal_folga";
  if (k === "financeiro") return "controletotal_financeiro";
  return "controletotal_escala";
}

/** Push de lembrete de agenda: prioridade alta + canal correto (Android Doze / OEM). */
function agendaReminderMulticastOptions(link, channelKind, alert, templatesOpt) {
  const templates = templatesOpt || {};
  const channelId = androidChannelForAgendaKind(channelKind);
  const theme = notifTpl.mergeChannelTheme(agendaMsg.channelTheme(channelKind), templates, channelKind);
  const richImage =
    notifTpl.richPushImageUrl(channelKind, APP_DOMAIN, templates) || APP_ICON_URL;
  const base = multicastWebPushApnsLink(link);
  const apsAlert =
    alert && alert.title
      ? {
          title: alert.title,
          ...(alert.subtitle ? { subtitle: alert.subtitle } : {}),
          body: alert.body || "",
        }
      : undefined;
  return {
    webpush: {
      ...(base.webpush || {}),
      notification: {
        ...(base.webpush?.notification || {}),
        icon: APP_ICON_URL,
        badge: APP_ICON_URL,
        image: richImage,
      },
    },
    android: {
      priority: "high",
      ttl: 86400000,
      collapseKey: `agenda_${theme.threadId}`,
      notification: {
        channelId,
        priority: "high",
        defaultSound: true,
        defaultVibrateTimings: true,
        visibility: "public",
        color: theme.androidColor,
        imageUrl: richImage,
        ...(base.android?.notification || {}),
        // Ícone pequeno = launcher do app (AndroidManifest); imagem grande = banner do tipo.
      },
    },
    apns: {
      headers: {
        "apns-priority": "10",
        "apns-push-type": "alert",
      },
      payload: {
        aps: {
          ...(base.apns?.payload?.aps || {}),
          sound: "default",
          "mutable-content": 1,
          "thread-id": theme.threadId,
          ...(apsAlert ? { alert: apsAlert } : {}),
        },
      },
      fcmOptions: { ...(base.apns?.fcmOptions || {}), image: richImage },
    },
  };
}

/** Push genérico (notificações do painel / broadcast): prioridade alta + canal Android. */
function defaultPushMulticastOptions(link, channelKind, templatesOpt) {
  const templates = templatesOpt || {};
  const channelId = androidChannelForAgendaKind(channelKind || "escala");
  const theme = notifTpl.mergeChannelTheme(agendaMsg.channelTheme(channelKind), templates, channelKind);
  const richImage =
    notifTpl.richPushImageUrl(channelKind, APP_DOMAIN, templates) || APP_ICON_URL;
  const base = multicastWebPushApnsLink(link);
  return {
    webpush: {
      ...(base.webpush || {}),
      notification: {
        ...(base.webpush?.notification || {}),
        icon: APP_ICON_URL,
        badge: APP_ICON_URL,
        image: richImage,
      },
    },
    android: {
      priority: "high",
      ttl: 86400000,
      collapseKey: theme.threadId,
      notification: {
        channelId,
        priority: "high",
        defaultSound: true,
        defaultVibrateTimings: true,
        visibility: "public",
        color: theme.androidColor,
        imageUrl: richImage,
        ...(base.android?.notification || {}),
      },
    },
    apns: {
      headers: {
        "apns-priority": "10",
        "apns-push-type": "alert",
      },
      payload: {
        aps: {
          ...(base.apns?.payload?.aps || {}),
          sound: "default",
          "mutable-content": 1,
          "thread-id": theme.threadId,
        },
      },
      fcmOptions: { ...(base.apns?.fcmOptions || {}), image: richImage },
    },
  };
}

/** Horário padrão: Brasília/São Paulo (GMT-3). Usar em licenças, avisos e comparações de data. */
const TZ_BRASILIA = "America/Sao_Paulo";

/** Retorna { year, month, day, hour, minute, second } em Brasília para a data d. */
function getDatePartsBrasilia(d) {
  d = d || new Date();
  const fmt = new Intl.DateTimeFormat("en-CA", {
    timeZone: TZ_BRASILIA,
    year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: false,
  });
  const parts = fmt.formatToParts(d);
  const get = (t) => parts.find((p) => p.type === t)?.value || "0";
  return {
    year: parseInt(get("year"), 10),
    month: parseInt(get("month"), 10) - 1,
    day: parseInt(get("day"), 10),
    hour: parseInt(get("hour"), 10),
    minute: parseInt(get("minute"), 10),
    second: parseInt(get("second"), 10),
  };
}

/** Início do dia (00:00:00) em Brasília como Date UTC. */
function startOfDayBrasilia(d) {
  const p = getDatePartsBrasilia(d);
  return new Date(Date.UTC(p.year, p.month, p.day, 3, 0, 0, 0));
}

/** Fim do dia (23:59:59.999) em Brasília como Date UTC. */
function endOfDayBrasilia(d) {
  const p = getDatePartsBrasilia(d);
  return new Date(Date.UTC(p.year, p.month, p.day, 26, 59, 59, 999));
}

/** Cria Date para (y,m,d,h,m,s) em Brasília. hour,minute,second default 0. */
function dateInBrasilia(year, month, day, hour = 0, minute = 0, second = 0) {
  return new Date(Date.UTC(year, month - 1, day, hour + 3, minute, second));
}

/** Data de hoje em Brasília como "YYYY-MM-DD". */
function todayBrasiliaISO() {
  const p = getDatePartsBrasilia(new Date());
  return `${p.year}-${String(p.month + 1).padStart(2, "0")}-${String(p.day).padStart(2, "0")}`;
}

/** Início de amanhã (00:00) em Brasília — migração em massa da fila agendaAlerts. */
function startOfTomorrowBrasilia(d) {
  const todayStart = startOfDayBrasilia(d || new Date());
  return new Date(todayStart.getTime() + 24 * 60 * 60 * 1000);
}

/** Corte para replanejamento em massa: eventos a partir de hoje (inclui mesmo dia). */
function agendaForwardCutoffBrasilia(now) {
  return startOfDayBrasilia(now || new Date());
}

const nodemailer = require("nodemailer");

/** Lê credenciais de e-mail: Firestore settings/email (user, appPassword). Gmail com App Password. */
async function getEmailConfig() {
  try {
    const snap = await admin.firestore().collection("settings").doc("email").get();
    if (snap.exists && snap.data()) {
      const d = snap.data();
      const user = (d.user || d.email || "").toString().trim();
      let pass = (d.appPassword || d.pass || d.password || "").toString().trim();
      // Senha de app Gmail: 16 caracteres; remover espaços (formato ex.: "abcd efgh ijkl mnop")
      pass = pass.replace(/\s/g, "");
      if (user && pass) return { user, pass };
    }
  } catch (e) {
    console.warn("getEmailConfig:", e?.message);
  }
  return null;
}

/** Envia e-mail HTML via Gmail SMTP. Retorna { ok: boolean, error?: string }. */
async function sendEmailHtml(to, subject, html) {
  const cfg = await getEmailConfig();
  if (!cfg) {
    console.warn("[sendEmail] settings/email não configurado. Defina user e appPassword.");
    return { ok: false, error: "E-mail não configurado." };
  }
  const transporter = nodemailer.createTransport({
    host: "smtp.gmail.com",
    port: 587,
    secure: false,
    auth: { user: cfg.user, pass: cfg.pass },
    pool: true,
    maxConnections: 2,
    maxMessages: 50,
    connectionTimeout: 90_000,
    greetingTimeout: 45_000,
    socketTimeout: 90_000,
    tls: { rejectUnauthorized: true },
  });
  const mail = {
    from: `"Controle Total" <${cfg.user}>`,
    to,
    subject,
    html,
    text: html.replace(/<[^>]*>/g, "").replace(/\s+/g, " ").trim(),
  };
  let lastErr = "";
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      if (attempt > 0) {
        await new Promise((r) => setTimeout(r, 900 * attempt));
      }
      await transporter.sendMail(mail);
      return { ok: true };
    } catch (e) {
      lastErr = (e?.message || String(e)).toString();
      console.warn(`[sendEmail] tentativa ${attempt + 1}/3 falhou:`, lastErr.slice(0, 200));
    }
  }
  try {
    transporter.close();
  } catch (_) {}
  const raw = lastErr || "Falha ao enviar e-mail.";
  console.error("[sendEmail] erro após 3 tentativas:", raw);
  let msg = raw;
  if (/535-5\.7\.8|534-5\.7\.9|BadCredentials|Username and Password not accepted|Application-specific password|InvalidSecondFactor|senha de app/i.test(raw)) {
    msg = "Gmail rejeitou o login. Corrija assim: (1) Conta Google → Segurança → Verificação em 2 etapas ATIVA. (2) Senhas de app → Gerar nova senha (16 caracteres). (3) Cole a senha aqui SEM espaços e clique em Salvar. Se já fez isso, gere outra senha de app (a anterior pode ter sido revogada).";
  }
  return { ok: false, error: msg };
}

/** Template base HTML profissional — Controle Total. */
function buildEmailBase(title, bodyHtml) {
  return `<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1.0">
<style>body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;background:#f4f7fa;margin:0;padding:0;color:#1e293b;line-height:1.6}
.container{max-width:560px;margin:0 auto;padding:24px;background:#fff;border-radius:16px;box-shadow:0 4px 16px rgba(0,0,0,.08)}
.header{text-align:center;padding-bottom:20px;border-bottom:2px solid #2D5BFF}
.logo{font-size:22px;font-weight:800;color:#2D5BFF}
.footer{text-align:center;padding-top:20px;font-size:12px;color:#64748b}
.btn{display:inline-block;padding:12px 24px;background:#2D5BFF;color:#fff!important;text-decoration:none;border-radius:10px;font-weight:700;margin-top:16px}
table{border-collapse:collapse;width:100%;margin:16px 0}
th,td{padding:10px 12px;text-align:left;border-bottom:1px solid #e2e8f0}
th{background:#f8fafc;font-weight:700;color:#475569}
.row-item{padding:12px;background:#f8fafc;border-radius:10px;margin:8px 0;border-left:4px solid #2D5BFF}
.alert{background:#fef3c7;border-left:4px solid #f59e0b;padding:12px;border-radius:8px;margin:16px 0}
</style></head>
<body><div class="container">
<div class="header"><span class="logo">CONTROLE TOTAL</span></div>
<h2 style="margin:20px 0;color:#1e293b">${title}</h2>
${bodyHtml}
<div class="footer">© Controle Total — Gestão financeira, escalas e metas.</div>
</div></body></html>`;
}

/** Cache de config MP (60s) para reduzir leituras no Firestore em checks e webhooks. */
let _mpConfigCache = null;
const MP_CONFIG_CACHE_MS = 60 * 1000;

const MP_WISDOMAPP_CLIENT_ID = "941346310248415";
const MP_WISDOMAPP_WEBHOOK_URL =
  "https://us-central1-wisdomapp-b9e98.cloudfunctions.net/mpWebhook";

function pickMpField(...values) {
  for (const v of values) {
    const s = (v ?? "").toString().trim();
    if (s) return s;
  }
  return "";
}

/** Lê config MP admin (secure_config + settings + split + preços). */
async function loadMpAdminConfigFromDb() {
  const db = admin.firestore();
  const [secureSnap, ownerSnap, partnerSnap, projectSnap, pricesSnap] = await Promise.all([
    db.collection("secure_config").doc("mercado_pago").get(),
    db.collection("settings").doc("mercadopago").get(),
    db.collection("settings").doc("mercadopago_partner").get(),
    db.collection("mp_project_config").doc("main").get(),
    db.collection("app_config").doc("mp_checkout_prices").get(),
  ]);
  const secure = secureSnap.exists ? secureSnap.data() || {} : {};
  const ownerDoc = ownerSnap.exists ? ownerSnap.data() || {} : {};
  const partnerDoc = partnerSnap.exists ? partnerSnap.data() || {} : {};
  const project = projectSnap.exists ? projectSnap.data() || {} : {};
  const prices = pricesSnap.exists ? pricesSnap.data() || {} : {};
  const split = normalizeMpSplitConfig({ ...project, ...secure });

  const ownerAccessToken = pickMpField(
    secure.accessToken,
    secure.access_token,
    ownerDoc.accessToken,
    ownerDoc.access_token,
  );
  const ownerPublicKey = pickMpField(
    secure.publicKey,
    secure.public_key,
    ownerDoc.publicKey,
    ownerDoc.public_key,
  );
  const ownerClientId = pickMpField(
    project.clientId,
    secure.clientId,
    secure.client_id,
    ownerDoc.clientId,
    ownerDoc.client_id,
    MP_WISDOMAPP_CLIENT_ID,
  );
  const ownerClientSecret = pickMpField(
    secure.clientSecret,
    secure.client_secret,
    ownerDoc.clientSecret,
    ownerDoc.client_secret,
  );
  const ownerWebhookUrl = pickMpField(
    secure.webhookUrl,
    secure.webhook_url,
    ownerDoc.webhookUrl,
    ownerDoc.webhook_url,
    MP_WISDOMAPP_WEBHOOK_URL,
  );
  const ownerWebhookSecret = pickMpField(
    secure.webhookSecret,
    secure.webhook_secret,
    ownerDoc.webhookSecret,
    ownerDoc.webhook_secret,
  );
  const ownerCollectorId = pickMpField(
    ownerDoc.collectorId,
    ownerDoc.collector_id,
    secure.collectorId,
    secure.collector_id,
  );

  const partnerAccessToken = pickMpField(
    secure.partnerAccessToken,
    secure.partner_access_token,
    partnerDoc.accessToken,
    partnerDoc.access_token,
  );
  const partnerPublicKey = pickMpField(
    secure.partnerPublicKey,
    secure.partner_public_key,
    partnerDoc.publicKey,
    partnerDoc.public_key,
  );
  const partnerClientId = pickMpField(
    secure.partnerClientId,
    secure.partner_client_id,
    partnerDoc.clientId,
    partnerDoc.client_id,
  );
  const partnerCollectorId = pickMpField(
    split.partnerCollectorId,
    secure.partnerCollectorId,
    partnerDoc.collectorId,
    partnerDoc.collector_id,
  );

  const premiumMonthly = roundMoney(
    toNumberSafe(prices.premium_monthly ?? split.referenceGross, 49.9),
  );
  const premiumAnnual = roundMoney(toNumberSafe(prices.premium_annual, 478.8));

  return {
    owner: {
      publicKey: ownerPublicKey,
      accessToken: ownerAccessToken,
      clientId: ownerClientId,
      clientSecret: ownerClientSecret,
      webhookUrl: ownerWebhookUrl,
      webhookSecret: ownerWebhookSecret,
      collectorId: ownerCollectorId,
      configured: !!ownerAccessToken,
    },
    partner: {
      publicKey: partnerPublicKey,
      accessToken: partnerAccessToken,
      clientId: partnerClientId,
      collectorId: partnerCollectorId,
      configured: !!partnerAccessToken && !!partnerCollectorId,
    },
    split: {
      enabled: split.enabled,
      mode: split.mode,
      ownerSharePercent: split.ownerSharePercent,
      partnerSharePercent: split.partnerSharePercent,
      ownerShareFixed: split.ownerShareFixed,
      partnerShareFixed: split.partnerShareFixed,
      referenceGross: split.referenceGross,
    },
    prices: {
      premium_monthly: premiumMonthly,
      premium_annual: premiumAnnual,
    },
    webhookDefaultUrl: MP_WISDOMAPP_WEBHOOK_URL,
  };
}

function toNumberSafe(v, fallback = 0) {
  const n = typeof v === "number" ? v : Number(String(v || "").replace(",", "."));
  return Number.isFinite(n) ? n : fallback;
}

function roundMoney(v) {
  return Math.round((toNumberSafe(v, 0) + Number.EPSILON) * 100) / 100;
}

function clampPercent(v, fallback) {
  const n = toNumberSafe(v, fallback);
  if (!Number.isFinite(n)) return fallback;
  if (n < 0) return 0;
  if (n > 100) return 100;
  return n;
}

function normalizeMpSplitConfig(raw) {
  const splitEnabled = raw.splitEnabled === true || raw.enable_split === true || raw.split_enabled === true;
  const ownerSharePercent = clampPercent(
    raw.ownerSharePercent ?? raw.owner_share_percent ?? raw.primary_share_percent ?? 50,
    50,
  );
  const partnerSharePercentRaw = raw.partnerSharePercent ?? raw.partner_share_percent;
  const partnerSharePercent =
    partnerSharePercentRaw == null
      ? clampPercent(100 - ownerSharePercent, 50)
      : clampPercent(partnerSharePercentRaw, 50);
  const ownerShareFixedRaw = raw.ownerShareFixed ?? raw.owner_share_fixed;
  const partnerShareFixedRaw = raw.partnerShareFixed ?? raw.partner_share_fixed;
  const referenceGrossRaw = raw.referenceGross ?? raw.reference_gross ?? raw.licenseGross ?? 49.9;
  const referenceGross = roundMoney(toNumberSafe(referenceGrossRaw, 49.9));
  const modeRaw = (raw.splitMode || raw.split_mode || "percent").toString().trim().toLowerCase();
  const mode = modeRaw === "fixed" || modeRaw === "fifty_fifty" ? modeRaw : "percent";
  return {
    enabled: splitEnabled,
    mode: mode === "fifty_fifty" ? "percent" : mode,
    ownerSharePercent,
    partnerSharePercent,
    ownerShareFixed: ownerShareFixedRaw == null ? null : roundMoney(toNumberSafe(ownerShareFixedRaw, 0)),
    partnerShareFixed: partnerShareFixedRaw == null ? null : roundMoney(toNumberSafe(partnerShareFixedRaw, 0)),
    referenceGross,
    partnerCollectorId: (raw.partnerCollectorId || raw.partner_collector_id || raw.collector_id || "").toString().trim(),
    ownerLabel: (raw.ownerLabel || raw.owner_label || "Raihom Barbosa").toString().trim() || "Raihom Barbosa",
    partnerLabel: (raw.partnerLabel || raw.partner_label || "Johnathan Tarley").toString().trim() || "Johnathan Tarley",
    ownerDisplayName: (raw.ownerDisplayName || raw.owner_display_name || raw.ownerLabel || "Raihom Barbosa").toString().trim(),
    partnerDisplayName: (raw.partnerDisplayName || raw.partner_display_name || raw.partnerLabel || "Johnathan Tarley").toString().trim(),
  };
}

function resolveOwnerShareAmount(gross, split) {
  const g = roundMoney(gross);
  if (g <= 0) return 0;
  const mode = (split.mode || "percent").toString();
  if (mode === "fixed") {
    const ownerFixed = split.ownerShareFixed;
    const ref = roundMoney(split.referenceGross || 0);
    if (ownerFixed != null && Number.isFinite(ownerFixed) && ownerFixed >= 0) {
      if (ref > 0 && Math.abs(ref - g) > 0.009) {
        return roundMoney(Math.min(g, (ownerFixed / ref) * g));
      }
      return roundMoney(Math.min(g, ownerFixed));
    }
  }
  return roundMoney((g * split.ownerSharePercent) / 100);
}

function buildMpSplitForRequest(amount, mpCfg) {
  const gross = roundMoney(amount);
  const split = mpCfg?.split || {};
  const canApply = split.enabled === true && gross > 0 && !!split.partnerCollectorId;
  if (!canApply) {
    return {
      enabled: false,
      metadata: {
        splitEnabled: false,
      },
    };
  }
  const ownerShareAmount = resolveOwnerShareAmount(gross, split);
  const partnerShareAmount = roundMoney(gross - ownerShareAmount);
  return {
    enabled: true,
    collectorId: split.partnerCollectorId,
    marketplaceFee: ownerShareAmount,
    applicationFee: ownerShareAmount,
    ownerShareAmount,
    partnerShareAmount,
    ownerSharePercent: split.ownerSharePercent,
    partnerSharePercent: split.partnerSharePercent,
    metadata: {
      splitEnabled: true,
      splitMode: split.mode || "percent",
      splitOwnerSharePercent: split.ownerSharePercent,
      splitPartnerSharePercent: split.partnerSharePercent,
      splitOwnerShareAmount: ownerShareAmount,
      splitPartnerShareAmount: partnerShareAmount,
      splitCollectorId: split.partnerCollectorId,
      splitOwnerLabel: split.ownerLabel || "owner",
      splitPartnerLabel: split.partnerLabel || "partner",
    },
  };
}

function buildPaymentSplitSnapshot(payment, mpCfg) {
  const meta = getPaymentMetadata(payment);
  const gross = roundMoney(payment?.transaction_amount || 0);
  const mpFee = roundMoney((Array.isArray(payment?.fee_details) ? payment.fee_details : [])
    .reduce((sum, fee) => sum + toNumberSafe(fee?.amount, 0), 0));
  const net = roundMoney(
    payment?.net_received_amount != null
      ? payment.net_received_amount
      : Math.max(gross - mpFee, 0),
  );
  const splitEnabledMeta = meta.splitEnabled === true || String(meta.splitEnabled || "").toLowerCase() === "true";
  const ownerPctMeta = toNumberSafe(meta.splitOwnerSharePercent, NaN);
  const partnerPctMeta = toNumberSafe(meta.splitPartnerSharePercent, NaN);
  const ownerAmountMeta = roundMoney(
    meta.splitOwnerShareAmount ?? payment?.application_fee ?? payment?.marketplace_fee ?? NaN,
  );
  const partnerAmountMeta = roundMoney(meta.splitPartnerShareAmount ?? NaN);
  const ownerSharePercent = Number.isFinite(ownerPctMeta)
    ? clampPercent(ownerPctMeta, 50)
    : (mpCfg?.split?.ownerSharePercent ?? 50);
  const partnerSharePercent = Number.isFinite(partnerPctMeta)
    ? clampPercent(partnerPctMeta, 50)
    : (mpCfg?.split?.partnerSharePercent ?? 50);
  const ownerShareGross = Number.isFinite(ownerAmountMeta)
    ? roundMoney(ownerAmountMeta)
    : roundMoney((gross * ownerSharePercent) / 100);
  const partnerShareGross = Number.isFinite(partnerAmountMeta)
    ? roundMoney(partnerAmountMeta)
    : roundMoney(gross - ownerShareGross);
  const ownerShareNet = roundMoney((net * ownerSharePercent) / 100);
  const partnerShareNet = roundMoney(net - ownerShareNet);
  const splitEnabled = splitEnabledMeta || ownerShareGross > 0 || !!(payment?.application_fee || payment?.marketplace_fee);
  return {
    splitEnabled,
    splitMode: (meta.splitMode || mpCfg?.split?.mode || "fifty_fifty").toString(),
    splitOwnerLabel: (meta.splitOwnerLabel || mpCfg?.split?.ownerLabel || "owner").toString(),
    splitPartnerLabel: (meta.splitPartnerLabel || mpCfg?.split?.partnerLabel || "partner").toString(),
    splitCollectorId: (meta.splitCollectorId || mpCfg?.split?.partnerCollectorId || "").toString().trim() || null,
    splitOwnerSharePercent: ownerSharePercent,
    splitPartnerSharePercent: partnerSharePercent,
    splitOwnerShareGross: ownerShareGross,
    splitPartnerShareGross: partnerShareGross,
    splitOwnerShareNet: ownerShareNet,
    splitPartnerShareNet: partnerShareNet,
    transactionAmountGross: gross,
    transactionFeeAmount: mpFee,
    transactionAmountNet: net,
  };
}

/** Lê credenciais do Mercado Pago: secure_config/mercado_pago -> settings/mercadopago -> env/config. */
async function getMpConfig() {
  if (_mpConfigCache && Date.now() < _mpConfigCache.expires) {
    return _mpConfigCache.data;
  }
  let cfg = {};
  try {
    cfg = functions.config().mercadopago || {};
  } catch (_) {}
  let secure = {};
  let project = {};
  try {
    const secureSnap = await admin.firestore().collection("secure_config").doc("mercado_pago").get();
    if (secureSnap.exists) secure = secureSnap.data() || {};
  } catch (_) {}
  try {
    const projectSnap = await admin.firestore().collection("mp_project_config").doc("main").get();
    if (projectSnap.exists) project = projectSnap.data() || {};
  } catch (_) {}
  const split = normalizeMpSplitConfig({ ...project, ...secure });
  try {
    const snap = await admin.firestore().collection("settings").doc("mercadopago").get();
    if (snap.exists && snap.data()) {
      const d = snap.data();
      const accessToken = (
        secure.access_token || secure.accessToken || d.access_token || d.accessToken || ""
      ).toString().trim();
      if (accessToken) {
        const webhookSecret = (
          secure.webhook_secret ||
          secure.webhookSecret ||
          d.webhook_secret ||
          d.webhookSecret ||
          cfg.webhook_secret ||
          process.env.MERCADOPAGO_WEBHOOK_SECRET ||
          ""
        ).toString().trim();
        const data = {
          accessToken,
          publicKey: (
            secure.public_key || secure.publicKey || d.public_key || d.publicKey || ""
          ).toString().trim(),
          webhookSecret,
          webhookUrl: (
            secure.webhook_url || secure.webhookUrl || d.webhook_url || d.webhookUrl || ""
          ).toString().trim(),
          clientId: (
            project.clientId ||
            secure.client_id ||
            secure.clientId ||
            d.client_id ||
            d.clientId ||
            cfg.client_id ||
            process.env.MERCADOPAGO_CLIENT_ID ||
            MP_WISDOMAPP_CLIENT_ID
          ).toString().trim(),
          split,
        };
        _mpConfigCache = { data, expires: Date.now() + MP_CONFIG_CACHE_MS };
        return data;
      }
    }
  } catch (e) {
    // fallback to config
  }
  const data = {
    accessToken: (
      secure.access_token ||
      secure.accessToken ||
      cfg.access_token ||
      process.env.MERCADOPAGO_ACCESS_TOKEN
    ),
    publicKey: (
      secure.public_key ||
      secure.publicKey ||
      cfg.public_key ||
      process.env.MERCADOPAGO_PUBLIC_KEY
    ),
    webhookSecret: (
      secure.webhook_secret ||
      secure.webhookSecret ||
      cfg.webhook_secret ||
      process.env.MERCADOPAGO_WEBHOOK_SECRET ||
      ""
    ),
    webhookUrl: (
      secure.webhook_url ||
      secure.webhookUrl ||
      cfg.webhook_url ||
      process.env.MERCADOPAGO_WEBHOOK_URL
    ),
    clientId: (
      project.clientId ||
      secure.client_id ||
      secure.clientId ||
      cfg.client_id ||
      process.env.MERCADOPAGO_CLIENT_ID ||
      MP_WISDOMAPP_CLIENT_ID
    ).toString().trim(),
    split,
  };
  _mpConfigCache = { data, expires: Date.now() + MP_CONFIG_CACHE_MS };
  return data;
}

/** Credenciais Pluggy em `app_config/pluggy` (admin). Cache curto no Functions. */
let _pluggyConfigCache = null;
const PLUGGY_CONFIG_CACHE_MS = 15 * 1000;

async function getPluggyConfigFromFirestore() {
  if (_pluggyConfigCache && Date.now() < _pluggyConfigCache.expires) {
    return _pluggyConfigCache.data;
  }
  const snap = await admin.firestore().doc("app_config/pluggy").get();
  const d = snap.exists ? snap.data() || {} : {};
  const data = {
    clientId: (d.clientId || "").toString().trim(),
    clientSecret: (d.clientSecret || "").toString().trim(),
    defaultWebhookUrl: (d.defaultWebhookUrl || d.webhookUrl || "").toString().trim(),
    oauthRedirectUri: (d.oauthRedirectUri || "").toString().trim(),
    includeSandbox: d.includeSandbox === true,
  };
  _pluggyConfigCache = { data, expires: Date.now() + PLUGGY_CONFIG_CACHE_MS };
  return data;
}

/** POST /auth → apiKey (válida ~2h; usar só no servidor). */
async function pluggyCreateApiKey(clientId, clientSecret) {
  const res = await fetch("https://api.pluggy.ai/auth", {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({ clientId, clientSecret }),
  });
  const text = await res.text();
  let j = {};
  try {
    j = JSON.parse(text);
  } catch (_) {}
  if (!res.ok) {
    const msg = (j && j.message) || text.slice(0, 240) || `HTTP ${res.status}`;
    throw new Error(msg);
  }
  const apiKey = (j.apiKey || "").toString().trim();
  if (!apiKey) throw new Error("Resposta Pluggy sem apiKey");
  return apiKey;
}

/** POST /connect_token com header X-API-KEY. */
async function pluggyCreateConnectToken(apiKey, { clientUserId, webhookUrl, oauthRedirectUri }) {
  const options = {};
  if (clientUserId) options.clientUserId = clientUserId;
  if (webhookUrl) options.webhookUrl = webhookUrl;
  if (oauthRedirectUri) options.oauthRedirectUri = oauthRedirectUri;
  options.avoidDuplicates = true;
  const body = { options };
  const res = await fetch("https://api.pluggy.ai/connect_token", {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-API-KEY": apiKey },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  let j = {};
  try {
    j = JSON.parse(text);
  } catch (_) {}
  if (!res.ok) {
    const msg = (j && j.message) || text.slice(0, 240) || `HTTP ${res.status}`;
    throw new Error(msg);
  }
  const accessToken = (j.accessToken || "").toString().trim();
  if (!accessToken) throw new Error("Resposta Pluggy sem accessToken");
  return accessToken;
}

/** Resolve Firebase UID a partir de `users/{uid}/bank_connections` com mesmo `itemId` Pluggy. */
async function resolveUidByPluggyItemId(itemId) {
  const id = (itemId || "").toString().trim();
  if (!id) return null;
  const snap = await admin.firestore().collectionGroup("bank_connections").where("itemId", "==", id).limit(1).get();
  if (snap.empty) return null;
  const path = snap.docs[0].ref.path;
  const parts = path.split("/");
  if (parts[0] !== "users" || parts.length < 4) return null;
  return parts[1];
}

/** Heurística simples (Uber → Transporte, etc.) — alinhada ao app Flutter. */
function pluggyCategorizeDescription(raw) {
  const s = (raw || "").toString().trim();
  if (!s) return "Outros";
  const u = s.toUpperCase();
  if (/UBER|99(TAXI|APP)|CABIFY|METR[OÔ]|ÔNIBUS|ONIBUS|PASSAGEM/i.test(u)) return "Transporte";
  if (/IFOOD|RAPPI|ZEDELIVERY|MERCADO|CARREFOUR|PADARIA|RESTAURANT/i.test(u)) return "Alimentação";
  if (/NETFLIX|SPOTIFY|DISNEY|HBO|PRIME|CINEMA|INGRESSO/i.test(u)) return "Lazer";
  if (/FARMACIA|FARMÁCIA|DROGASIL|HOSPITAL|UNIMED|AMIL|DENTIST/i.test(u)) return "Saúde";
  if (/POSTO|SHELL|IPIRANGA|COMBUST/i.test(u)) return "Combustível";
  return "Outros";
}

function mapPluggyTransactionToFirestore(tx) {
  const ext = String(tx.id || tx.transactionId || "").trim();
  const desc = String(tx.description || tx.name || tx.title || "").trim() || "Open Finance";
  const rawAmt = tx.amount ?? tx.value ?? tx.transactionAmount ?? 0;
  const amt = typeof rawAmt === "number" ? Math.abs(rawAmt) : Math.abs(parseFloat(String(rawAmt).replace(",", "."))) || 0;
  const tRaw = String(tx.type || tx.operationType || "DEBIT").toLowerCase();
  const type = tRaw.includes("credit") || tRaw.includes("income") || tRaw.includes("deposit") ? "income" : "expense";
  let dateTs = admin.firestore.FieldValue.serverTimestamp();
  const dRaw = tx.date || tx.createdAt || tx.postedAt;
  if (dRaw) {
    const d = new Date(dRaw);
    if (!Number.isNaN(d.getTime())) dateTs = admin.firestore.Timestamp.fromDate(d);
  }
  const category = pluggyCategorizeDescription(desc);
  return {
    type,
    amount: amt,
    category,
    description: desc,
    status: "paid",
    date: dateTs,
    effectiveDate: dateTs,
    recurrence: "none",
    installmentCount: 1,
    installmentIndex: 1,
    source: "open_finance",
    openFinanceExternalId: ext,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

/** Espelho de flutter_app/lib/constants/default_categories.dart — categorias que já existem no app sem ir para custom. */
const DEFAULT_EXPENSE_CATEGORIES_LOWER = new Set([
  "energia",
  "água",
  "agua",
  "gás",
  "gas",
  "combustível",
  "combustivel",
  "alimentação",
  "alimentacao",
  "farmácia",
  "farmacia",
  "internet",
  "escola",
  "academia",
  "dízimos",
  "dizimos",
  "ofertas",
  "doações",
  "doacoes",
  "contribuições",
  "contribuicoes",
  "juros",
  "supermercado",
  "cartão",
  "cartao",
  "empréstimo",
  "emprestimo",
  "consórcio",
  "consorcio",
  "transporte",
  "lazer",
  "seguros",
  "telefone",
  "tv / streaming",
  "cursos",
  "vestuário",
  "vestuario",
  "manutenção",
  "manutencao",
  "pet",
  "plano de saúde",
  "plano de saude",
  "iptu / condomínio",
  "iptu / condominio",
]);

const DEFAULT_INCOME_CATEGORIES_LOWER = new Set([
  "salários",
  "salarios",
  "horas extras",
  "bônus",
  "bonus",
  "investimentos",
  "freelance",
  "aluguel recebido",
  "venda",
  "rendimentos",
  "comissão",
  "comissao",
]);

function normalizeCategoryKey(s) {
  return (s || "").toString().trim().toLowerCase();
}

/**
 * Se a categoria do lançamento Open Finance não está nas listas padrão do app,
 * adiciona em users/{uid}/settings/custom_categories (mesmo fluxo que «Incluir nova» no Flutter).
 */
async function ensureUserCustomCategoryIfNeeded(uid, transactionType, categoryName) {
  const cat = (categoryName || "").toString().trim();
  if (!cat) return;
  const isIncome = String(transactionType || "").toLowerCase() === "income";
  const defaults = isIncome ? DEFAULT_INCOME_CATEGORIES_LOWER : DEFAULT_EXPENSE_CATEGORIES_LOWER;
  const keyLower = normalizeCategoryKey(cat);
  if (defaults.has(keyLower)) return;

  const ref = admin.firestore().doc(`users/${uid}/settings/custom_categories`);
  await admin.firestore().runTransaction(async (t) => {
    const snap = await t.get(ref);
    const data = snap.exists ? snap.data() || {} : {};
    const field = isIncome ? "income" : "expense";
    const raw = data[field];
    const list = Array.isArray(raw)
      ? [...raw.map((x) => String(x).trim()).filter((s) => s.length > 0)]
      : [];
    if (list.some((c) => normalizeCategoryKey(c) === keyLower)) return;
    list.push(cat);
    list.sort((a, b) => a.localeCompare(b, "pt-BR"));
    t.set(
      ref,
      {
        ...data,
        [field]: list,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  });
}

const mpHeaders = (accessToken) => ({
  Authorization: `Bearer ${accessToken}`,
  "Content-Type": "application/json",
});

/** Marca pagamentos criados pelo backend do app (checkout / PIX) — usado para filtrar webhooks e sync. */
const CT_MP_METADATA_INTEGRATION = { ct_integration: "controletotal" };

/** Fallback quando `app_config/mp_checkout_prices` não existe ou campo ausente. */
const MP_PRICE_BY_PLAN_DEFAULT = {
  premium_monthly: 14.99,
  premium_annual: 169.9,
  premium_pro_monthly: 25.9,
  premium_pro_annual: 299.9,
  extra_bank_connection_monthly: 5.9,
  extra_bank_connection_annual: 59.9,
};

let _mpPriceMergedCache = { data: null, expires: 0 };
const MP_PRICE_CACHE_MS = 60_000;

/** Mescla defaults com documento público `app_config/mp_checkout_prices` (editável no Admin). */
async function loadMpPriceByPlanMerged() {
  if (_mpPriceMergedCache.data && Date.now() < _mpPriceMergedCache.expires) {
    return _mpPriceMergedCache.data;
  }
  let merged = { ...MP_PRICE_BY_PLAN_DEFAULT };
  try {
    const snap = await admin.firestore().doc("app_config/mp_checkout_prices").get();
    if (snap.exists) {
      const d = snap.data() || {};
      for (const k of Object.keys(merged)) {
        const p = parsePriceBrlField(d[k]);
        if (p != null) merged[k] = p;
      }
    }
  } catch (e) {
    console.warn("loadMpPriceByPlanMerged:", e?.message || e);
  }
  _mpPriceMergedCache = { data: merged, expires: Date.now() + MP_PRICE_CACHE_MS };
  return merged;
}

let _pofConfigCache = { data: null, expires: 0 };
const POF_CONFIG_CACHE_MS = 60_000;

/** Teto global de conexões Open Finance (inclusas + pagas) — `app_config/pro_open_finance`. */
async function loadProOpenFinanceConfigMerged() {
  if (_pofConfigCache.data && Date.now() < _pofConfigCache.expires) {
    return _pofConfigCache.data;
  }
  const d = { maxTotalBankConnections: 5 };
  try {
    const snap = await admin.firestore().doc("app_config/pro_open_finance").get();
    if (snap.exists) {
      const x = snap.data() || {};
      const m = parseInt((x.maxTotalBankConnections ?? x.max_total_bank_connections ?? "5").toString(), 10);
      if (Number.isFinite(m) && m >= 1 && m <= 99) d.maxTotalBankConnections = m;
    }
  } catch (e) {
    console.warn("loadProOpenFinanceConfigMerged:", e?.message || e);
  }
  _pofConfigCache = { data: d, expires: Date.now() + POF_CONFIG_CACHE_MS };
  return d;
}

const CT_VIP_HIGH_INCLUDED_CONN_EMAILS = new Set(
  ["raihom@gmail.com", "isabelle.krdoso@gmail.com"].map((e) => e.toLowerCase()),
);

function parseAdminIncludedSlotsOverride(v) {
  if (v == null) return null;
  if (typeof v === "number" && Number.isFinite(v)) {
    const n = Math.trunc(v);
    return n >= 1 && n <= 99 ? n : null;
  }
  const n = parseInt(String(v), 10);
  return Number.isFinite(n) && n >= 1 && n <= 99 ? n : null;
}

function includedBankConnectionsForUserJs(userData) {
  if (!userData || typeof userData !== "object") return 2;
  const o = parseAdminIncludedSlotsOverride(userData.premiumProIncludedBankConnections);
  if (o != null) return o;
  const e = (userData.email || "").toString().trim().toLowerCase();
  if (CT_VIP_HIGH_INCLUDED_CONN_EMAILS.has(e)) return 5;
  return 2;
}

async function countValidExtraEntitlementsForUser(uid) {
  const now = admin.firestore.Timestamp.now();
  const snap = await admin
    .firestore()
    .collection("users")
    .doc(uid)
    .collection("bank_connection_entitlements")
    .where("expiresAt", ">", now)
    .get();
  return snap.size;
}

/** Callables: dispara se não couber mais nenhum add-on */
async function assertCanPurchaseExtraBankConnectionForUid(uid) {
  const userRef = admin.firestore().doc(`users/${uid}`);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    throw new functions.https.HttpsError("not-found", "Usuário não encontrado.");
  }
  const userData = userSnap.data() || {};
  if (!userHasPremiumProAccess(userData)) {
    throw new functions.https.HttpsError("failed-precondition", "Conexão extra: disponível apenas com Premium PRO ativo.");
  }
  const maxT = (await loadProOpenFinanceConfigMerged()).maxTotalBankConnections;
  const inc = includedBankConnectionsForUserJs(userData);
  const nExtra = await countValidExtraEntitlementsForUser(uid);
  if (inc + nExtra >= maxT) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Limite máximo de conexões bancárias atingido. Remova uma ligação existente para adicionar outro banco.",
    );
  }
}

/** Planos: mensal = +30 dias de licença, anual = +365. (Premium e Premium PRO.) */
const getPlanConfig = (plan, priceMap) => {
  const map = priceMap || MP_PRICE_BY_PLAN_DEFAULT;
  const normalized = normalizeMercadoPagoPlanKey(plan || "premium_monthly");
  const plans = {
    premium_monthly: { title: "Controle Total Premium (Mensal)", plan: "premium" },
    premium_annual: { title: "Controle Total Premium (Anual)", plan: "premium" },
    premium_pro_monthly: { title: "Controle Total Premium PRO (Mensal)", plan: "premium_pro" },
    premium_pro_annual: { title: "Controle Total Premium PRO (Anual)", plan: "premium_pro" },
    extra_bank_connection_monthly: { title: "Controle Total — 1 conexão bancária extra (mensal)", plan: "addon_extra_bank" },
    extra_bank_connection_annual: { title: "Controle Total — 1 conexão bancária extra (anual)", plan: "addon_extra_bank" },
  };
  const base = plans[normalized] || plans.premium_monthly;
  const price = getAmountForMercadoPago(normalized, map);
  return { ...base, price };
};

/** Mensal = +30 dias, anual = +365 (sem promoção). */
function computeStandardLicenseDays(planCode) {
  const p = (planCode || "").toString().toLowerCase();
  const isMensal = p.includes("monthly") || p.includes("mensal");
  const isAnnual = !isMensal && (p.includes("annual") || p.includes("yearly"));
  return isAnnual ? 365 : 30;
}

/** Normaliza priceBrl vindo do Firestore (número, string com vírgula, etc.). */
function parsePriceBrlField(v) {
  if (v == null || v === "") return null;
  if (typeof v === "number" && Number.isFinite(v) && v > 0) return v;
  const s = String(v).trim().replace(/\s/g, "").replace(",", ".");
  const n = Number(s);
  return Number.isFinite(n) && n > 0 ? n : null;
}

/** Lê preço promocional do doc (vários nomes possíveis no Firestore / migrações). */
function coalescePromoPriceBrl(d) {
  if (!d || typeof d !== "object") return null;
  const keys = [
    "priceBrl",
    "price_brl",
    "promoPriceBrl",
    "promotionalPriceBrl",
    "valorPromoBrl",
    "precoBrl",
    "precoPromo",
  ];
  for (const k of keys) {
    if (d[k] == null || d[k] === "") continue;
    const p = parsePriceBrlField(d[k]);
    if (p != null) return p;
  }
  return null;
}

/** Vigência e estoque da promoção (sem checar valor pago). */
function evaluatePromotionEligibility(promoSnap, nowMs) {
  if (!promoSnap.exists) return { ok: false, reason: "not_found" };
  const d = promoSnap.data();
  if (d.active === false) return { ok: false, reason: "inactive" };
  const total = Number(d.quantityTotal ?? 0);
  const sold = Number(d.quantitySold ?? 0);
  if (!(total > 0) || sold >= total) return { ok: false, reason: "sold_out" };
  const vf = d.validFrom?.toMillis?.() ?? null;
  const vu = d.validUntil?.toMillis?.() ?? null;
  if (vf != null && nowMs < vf) return { ok: false, reason: "not_started" };
  if (vu != null && nowMs > vu) return { ok: false, reason: "expired" };
  const durationDays = Number(d.durationDays);
  if (!Number.isFinite(durationDays) || durationDays < 1 || durationDays > 4000) {
    return { ok: false, reason: "bad_duration" };
  }
  const planCode = (d.planCode || "premium_monthly").toString().trim().toLowerCase();
  return { ok: true, durationDays, planCode, data: d };
}

/** Inclui validação do valor pago quando a promoção define priceBrl. */
function evaluatePromotionForPayment(promoSnap, transactionAmount, nowMs, priceMap) {
  const base = evaluatePromotionEligibility(promoSnap, nowMs);
  if (!base.ok) return base;
  const d = promoSnap.data();
  const planCodePromo = (d.planCode || "premium_monthly").toString().trim().toLowerCase();
  const rawPromo = coalescePromoPriceBrl(d);
  const priceBrl =
    rawPromo != null ? alignPromoPriceToCurrentTable(planCodePromo, rawPromo, priceMap) : null;
  if (priceBrl != null) {
    const amt = Number(transactionAmount);
    if (!Number.isFinite(amt) || Math.abs(amt - priceBrl) > 0.05) {
      return { ok: false, reason: "amount_mismatch" };
    }
  }
  return base;
}

/** Plano, título e preço para checkout/PIX com promoção ativa. */
function resolveCheckoutPlanFromPromo(promoSnap, fallbackPlanCode, priceMap) {
  const ev = evaluatePromotionEligibility(promoSnap, Date.now());
  if (!ev.ok) {
    throw new functions.https.HttpsError("failed-precondition", "Promoção indisponível, esgotada ou fora da vigência.");
  }
  const d = ev.data;
  const planCode = ev.planCode;
  const parsedPromo = coalescePromoPriceBrl(d);
  const unitPrice =
    parsedPromo != null
      ? alignPromoPriceToCurrentTable(planCode, parsedPromo, priceMap)
      : getAmountForMercadoPago(planCode, priceMap);
  const cfg = getPlanConfig(planCode, priceMap);
  const title = (d.title || cfg.title).toString();
  return { planCode, unitPrice, title, plan: cfg.plan };
}

/** True se planCode for anual (ex.: premium_annual — cartão com até 6x na preferência dedicada). */
function isAnnualPlanCode(planCode) {
  const p = (planCode || "").toString().toLowerCase();
  if (p.includes("monthly") || p.includes("mensal")) return false;
  return p.includes("annual") || p.includes("yearly") || p.includes("anual");
}

/**
 * Máximo de parcelas na preferência Checkout Pro (cartão).
 * Premium anual sem promo: até 6. Com promoção: até 4. Outros anuais: até 4. Mensal: até 6.
 * PIX usa [ctCreateMpPixPayment] — sempre valor integral, sem parcelas.
 */
function maxInstallmentsForMpPreference(planCode, promoId) {
  const p = (planCode || "").toString().toLowerCase();
  if (isExtraBankPlanCode(p)) return 1;
  if ((promoId || "").toString().trim()) return 4;
  if (p === "premium_annual") return 6;
  if (isAnnualPlanCode(planCode)) return 4;
  return 6;
}

/** Normaliza plan vindo do app (evita chave errada e valor fallback incorreto). */
function normalizeMercadoPagoPlanKey(raw) {
  const k = (raw || "premium_monthly").toString().trim().toLowerCase().replace(/\s+/g, "_");
  const aliases = {
    premium: "premium_monthly",
    premium_mensal: "premium_monthly",
    premium_anual: "premium_annual",
    premium_ano: "premium_annual",
    basic: "premium_monthly",
    basico: "premium_monthly",
    basico_mensal: "premium_monthly",
    master: "premium_monthly",
    master_monthly: "premium_monthly",
    master_annual: "premium_annual",
    basic_monthly: "premium_monthly",
    basic_annual: "premium_annual",
    premium_pro: "premium_pro_monthly",
    premium_pro_mensal: "premium_pro_monthly",
    premium_pro_anual: "premium_pro_annual",
    premium_pro_ano: "premium_pro_annual",
  };
  return aliases[k] || k;
}

/** Retorna o valor em R$ a ser enviado ao MP (PIX/cartão). Usa mapa mesclado (Firestore + default). */
function getAmountForMercadoPago(planCode, priceMap) {
  const map = priceMap || MP_PRICE_BY_PLAN_DEFAULT;
  const key = normalizeMercadoPagoPlanKey(planCode);
  const amount = map[key];
  if (amount != null) return amount;
  return map.premium_monthly;
}

/**
 * Promoções no Firestore com preço “de tabela” antigo (ex. 24,90 / 39,90 mensal) passam a cobrar o valor atual.
 * Descontos reais abaixo do oficial não são alterados.
 */
function alignPromoPriceToCurrentTable(planCode, priceBrl, priceMap) {
  const map = priceMap || MP_PRICE_BY_PLAN_DEFAULT;
  const pc = (planCode || "").toString().toLowerCase();
  const n = Number(priceBrl);
  if (!Number.isFinite(n) || n <= 0) return priceBrl;
  const near = (a, b) => Math.abs(a - b) < 0.02;

  if (pc.includes("premium") && (pc.includes("monthly") || pc.includes("mensal"))) {
    const official = map.premium_monthly;
    if (near(n, official)) return n;
    const staleMonthly = [19.9, 24.9, 29.9, 34.9, 39.9, 49.9, 59.9];
    if (staleMonthly.some((x) => near(n, x))) return official;
    return n;
  }
  if (
    pc.includes("premium") &&
    (pc.includes("annual") || pc.includes("anual") || pc.includes("yearly"))
  ) {
    const official = map.premium_annual;
    if (near(n, official)) return n;
    const staleAnnual = [199.9, 239.9, 229.9, 219.9, 189.9, 179.9];
    if (staleAnnual.some((x) => near(n, x))) return official;
    return n;
  }
  return n;
}

/**
 * Infere planCode pelo valor quando metadata não traz planCode.
 * R$ 19,90 mensal: paywall principal é Premium; Básico mensal mesmo valor deve vir com planCode no metadata.
 * Mantém legado 24,90 / 239,90 para pagamentos antigos ainda em fila.
 */
function inferPlanCodeFromAmount(amount, priceMap) {
  const map = priceMap || MP_PRICE_BY_PLAN_DEFAULT;
  const v = Number(amount);
  if (!Number.isFinite(v)) return null;
  const near = (a, b) => Math.abs(a - b) < 0.02;
  const keys = Object.keys(map).sort((a, b) => {
    const ap = a.includes("premium") ? 0 : 1;
    const bp = b.includes("premium") ? 0 : 1;
    if (ap !== bp) return ap - bp;
    return a.localeCompare(b);
  });
  for (const key of keys) {
    const val = map[key];
    if (typeof val === "number" && near(v, val)) return key;
  }
  if (near(v, 19.9)) return "premium_monthly";
  if (near(v, 199.9)) return "premium_annual";
  return null;
}

function isExtraBankPlanCode(planCode) {
  const p = (planCode || "").toString().toLowerCase();
  return p === "extra_bank_connection_monthly" || p === "extra_bank_connection_annual";
}

/** Mercado Pago: só venda do plano Premium (mensal/anual). PRO e extras Open Finance não são mais contratados aqui. */
function assertMercadoPagoCheckoutPlanAllowed(planCode) {
  const p = (planCode || "").toString().toLowerCase().trim();
  if (p === "premium_pro_monthly" || p === "premium_pro_annual") {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "O plano Premium PRO não está mais disponível para contratação. Use o plano Premium (mensal ou anual)."
    );
  }
  if (isExtraBankPlanCode(p)) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Conexões bancárias extras não estão mais à venda. Contrate apenas o plano Premium."
    );
  }
}

function userHasPremiumProAccess(userData) {
  if (!userData || typeof userData !== "object") return false;
  if ((userData.plan || "").toString() === "premium_pro") return true;
  if (userData.premiumPro === true) return true;
  if (userData.isPremiumPro === true) return true;
  return false;
}

/**
 * Alinhado ao [UserProfile.hasActiveLicense] / licença + 3d carência.
 * Só chamar com `plan: premium` (Premium clássico) quando `planStatus: active` e `plan` não é free.
 */
function userDocLicenseOkForOpenFinance(caller) {
  if (!caller || typeof caller !== "object") return false;
  const p = (caller.plan || "free").toString().toLowerCase().trim();
  if (p === "free") return false;
  if ((caller.planStatus || "active") !== "active") return false;
  const le = caller.licenseExpiresAt;
  if (!le) return true;
  const exp = le.toDate ? le.toDate() : new Date(typeof le === "string" ? le : le);
  if (Number.isNaN(exp.getTime())) return true;
  const y = exp.getFullYear();
  const m = exp.getMonth();
  const d = exp.getDate();
  const now = new Date();
  const today0 = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const exp0 = new Date(y, m, d);
  if (today0.getTime() <= exp0.getTime()) return true;
  const graceEnd0 = new Date(exp0);
  graceEnd0.setDate(graceEnd0.getDate() + 3);
  return today0.getTime() <= graceEnd0.getTime();
}

function extraBankEntitlementDurationDays(planCode) {
  const p = (planCode || "").toString().toLowerCase();
  return p.includes("annual") ? 365 : 30;
}

/**
 * Pagamento aprovado de add-on: +1 "slot" de conexão Open Finance, com validade 30d ou 365d.
 * Não estende a licença do plano principal.
 */
async function processExtraBankConnectionEntitlement(payment, uid, planCode, priceMap) {
  const id = String(payment.id);
  const expected = getAmountForMercadoPago(planCode, priceMap);
  const amt = Number(payment.transaction_amount);
  if (!Number.isFinite(amt) || Math.abs(amt - expected) > 0.06) {
    console.error(
      `processExtraBankConnectionEntitlement: valor inesperado payment ${id} esperado ${expected} recebido ${amt}`,
    );
    return;
  }

  const userRef = admin.firestore().doc(`users/${uid}`);
  const markRef = userRef.collection("entitlement_payments").doc(id);
  const entRef = userRef.collection("bank_connection_entitlements").doc(id);
  const days = extraBankEntitlementDurationDays(planCode);
  const pofCfg = await loadProOpenFinanceConfigMerged();
  const maxT = pofCfg.maxTotalBankConnections;

  const userSnap = await userRef.get();
  const userData = userSnap.exists ? userSnap.data() : {};
  if (!userHasPremiumProAccess(userData)) {
    console.warn(
      `processExtraBankConnectionEntitlement: usuário ${uid} sem Premium PRO — add-on não liberado (payment ${id})`,
    );
    await admin.firestore().collection("mp_payments").doc(id).set(
      { entitlementDeniedReason: "not_premium_pro", licenseRelevant: false, updatedAt: admin.firestore.FieldValue.serverTimestamp() },
      { merge: true },
    );
    return;
  }

  const payTime = payment.date_approved ? new Date(payment.date_approved) : new Date();
  const dEnd = new Date(payTime.getTime());
  dEnd.setUTCDate(dEnd.getUTCDate() + days);
  const expiresAt = admin.firestore.Timestamp.fromDate(endOfDayBrasilia(dEnd));

  const inc0 = includedBankConnectionsForUserJs(userData);
  const nExtra0 = await countValidExtraEntitlementsForUser(uid);
  if (inc0 + nExtra0 >= maxT) {
    console.warn(
      `processExtraBankConnectionEntitlement: limite ${maxT} já atingido (uid ${uid}, payment ${id}) — add-on não gravado.`,
    );
    await admin.firestore().collection("mp_payments").doc(id).set(
      {
        entitlementDeniedReason: "max_total_bank_connections",
        maxTotalBankConnections: maxT,
        licenseRelevant: false,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return;
  }

  let state = "ok"; // "ok" | "already"
  await admin.firestore().runTransaction(async (t) => {
    const m = await t.get(markRef);
    if (m.exists) {
      state = "already";
      return;
    }
    t.set(markRef, {
      type: "extra_bank_connection",
      planCode,
      amount: amt,
      paymentId: id,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    t.set(entRef, {
      planCode,
      paymentId: id,
      durationDays: days,
      amount: amt,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      activatedAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt,
    });
  });

  if (state === "already") {
    console.log(`processExtraBankConnectionEntitlement: ${id} já processado (idempotência).`);
    return;
  }

  await admin.firestore().collection("mp_payments").doc(id).set(
    {
      licenseRelevant: false,
      entitlementType: "extra_bank_connection",
      extraBankEntitlementDays: days,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  console.log(`processExtraBankConnectionEntitlement: +1 conexão extra validada para ${uid} (payment ${id}, ${days}d; teto ${maxT})`);
}

const normalizeFilename = (name) =>
  name
    .trim()
    .replace(/\s+/g, "_")
    .replace(/[^a-zA-Z0-9_\-.]/g, "");

const buildDownloadUrl = (bucketName, filePath, token) => {
  const encoded = encodeURIComponent(filePath);
  return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encoded}?alt=media&token=${token}`;
};

const uploadToStorage = async ({ filePath, buffer, contentType }) => {
  const bucket = admin.storage().bucket();
  const token = crypto.randomUUID();
  const file = bucket.file(filePath);
  await file.save(buffer, {
    resumable: false,
    metadata: {
      contentType,
      metadata: {
        firebaseStorageDownloadTokens: token,
      },
    },
  });

  return {
    storagePath: filePath,
    downloadUrl: buildDownloadUrl(bucket.name, filePath, token),
  };
};

exports.ping = onRequest((req, res) => {
  res.status(200).json({ ok: true, app: "wisdomapp", ts: Date.now() });
});

const wisdomBootstrap = require("./wisdomapp_firestore_bootstrap");

/**
 * Bootstrap Firestore + Storage WISDOMAPP (colecoes app_config, landing, MP, admin).
 * GET ?token=SECRET&force=1 — token = app.version_secret (mesmo de ctSyncAppVersion).
 */
exports.ctBootstrapWisdomappFirestore = onRequest(async (req, res) => {
  try {
    let secret = (appVersionSecret.value() || process.env.APP_VERSION_SECRET || "").toString().trim();
    if (!secret) {
      try {
        const cfg = functions.config();
        secret = (cfg?.app?.version_secret || "").toString().trim();
      } catch (_) {}
    }
    const token = (req.query.token || (req.body && req.body.token) || "").toString().trim();
    if (!secret) {
      return res.status(500).json({ ok: false, error: "secret nao configurado" });
    }
    if (token !== secret) {
      return res.status(401).json({ ok: false, error: "token invalido" });
    }
    const force = req.query.force === "1" || req.query.force === "true";
    const version = (req.query.version || "10.02").toString().trim();
    const buildNumber = parseInt(req.query.buildNumber || "2", 10);
    const versionCode = parseInt(req.query.versionCode || "2", 10);
    const results = await wisdomBootstrap.runWisdomappFirestoreBootstrap(admin.firestore(), admin, {
      force,
      version,
      buildNumber: Number.isNaN(buildNumber) ? 2 : buildNumber,
      versionCode: Number.isNaN(versionCode) ? 2 : versionCode,
    });
    return res.status(200).json({ ok: true, force, results });
  } catch (e) {
    console.error("ctBootstrapWisdomappFirestore:", e);
    return res.status(500).json({ ok: false, error: String(e && e.message) || "erro" });
  }
});

/**
 * Sincroniza app_config/version no Firestore (Painel Admin > "Subir versao
 * e forcar atualizacao", script .\force_version_online.ps1, ou chamada manual
 * autenticada). O deploy.ps1 NAO chama esta funcao — evita forcar todos a
 * atualizar antes de testar em producao (web, Android, iOS).
 * GET ?version=37.01&token=SECRET — token deve ser app.version_secret.
 */
exports.ctSyncAppVersion = onRequest(async (req, res) => {
  try {
    let secret = (appVersionSecret.value() || process.env.APP_VERSION_SECRET || "").toString().trim();
    if (!secret) {
      try {
        const cfg = functions.config();
        secret = (cfg?.app?.version_secret || "").toString().trim();
      } catch (_) {}
    }

    const version = (req.query.version || (req.body && req.body.version) || "").toString().trim();
    const token = (req.query.token || (req.body && req.body.token) || "").toString().trim();
    const iosDownloadUrl = (req.query.iosDownloadUrl || (req.body && req.body.iosDownloadUrl) || "").toString().trim();
    const testFlightUrl = (req.query.testFlightUrl || (req.body && req.body.testFlightUrl) || "").toString().trim();
    const buildNumberRaw = (req.query.buildNumber ?? req.body?.buildNumber ?? "").toString().trim();
    const versionCodeRaw = (req.query.versionCode ?? req.body?.versionCode ?? "").toString().trim();

    if (!version || version.length > 20) {
      return res.status(400).json({ ok: false, error: "version invalida" });
    }
    if (!secret) {
      return res.status(500).json({ ok: false, error: "secret nao configurado - use firebase functions:config:set app.version_secret=xxx" });
    }
    if (token !== secret) {
      return res.status(401).json({ ok: false, error: "token invalido" });
    }

    const apkDownloadUrl = "https://play.google.com/store/apps/details?id=com.wisdomapp.app";
    const bn = parseInt(buildNumberRaw, 10);
    const vc = parseInt(versionCodeRaw, 10);
    const payload = {
      version,
      forceUpdate: true,
      apkDownloadUrl,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (!Number.isNaN(bn) && bn >= 0) {
      payload.buildNumber = bn;
      payload.releaseTag = `${version}+${bn}`;
    }
    if (!Number.isNaN(vc) && vc > 0) {
      payload.versionCode = vc;
    }
    if (iosDownloadUrl && iosDownloadUrl.startsWith("http")) {
      payload.iosDownloadUrl = iosDownloadUrl;
    }
    if (testFlightUrl && testFlightUrl.startsWith("http")) {
      payload.testFlightUrl = testFlightUrl;
    }
    await admin.firestore().collection("app_config").doc("version").set(payload, { merge: true });
    return res.status(200).json({ ok: true, version, iosDownloadUrl: payload.iosDownloadUrl || null, testFlightUrl: payload.testFlightUrl || null });
  } catch (e) {
    console.error("ctSyncAppVersion:", e);
    return res.status(500).json({ ok: false, error: String(e && e.message) || "erro" });
  }
});

exports.getPublicConfig = onCall(async (req) => {
  const googleWebClientId = (functions.config().app?.google_web_client_id || process.env.GOOGLE_WEB_CLIENT_ID || "").toString().trim();
  return {
    googleWebClientId,
  };
});

/**
 * RSS Google Notícias (negócios / pesquisa): o browser bloqueia CORS em `news.google.com`.
 * Busca server-side e devolve XML para o app (Web + mobile).
 *
 * Nota: IPs de datacenter costumam receber HTTP não-OK ou HTML em vez de RSS no Google.
 * Por isso: vários User-Agents e fallback para RSS público (G1 Economia).
 */
/** TTL cache RSS (ms): repetições no app ficam instantâneas sem novo fetch HTTP. */
const NEWS_RSS_CACHE_TTL_MS = 180000;

/** RSS mínimo válido quando todas as fontes HTTP falham (datacenter bloqueado, WAF, etc.) — evita cartão de erro no app sem novo build. */
const EMERGENCY_FINANCE_RSS_BR = `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel>
<title>Finanças — fontes sugeridas</title>
<link>https://g1.globo.com/economia/</link>
<description>As fontes externas não responderam a tempo. Toque num item para abrir no navegador.</description>
<item><title>G1 — Economia</title><link>https://g1.globo.com/economia/</link><description>Últimas notícias de economia no Brasil.</description></item>
<item><title>InfoMoney</title><link>https://www.infomoney.com.br/</link><description>Mercado, ações e investimentos.</description></item>
<item><title>Money Times</title><link>https://www.moneytimes.com.br/</link><description>Notícias financeiras.</description></item>
<item><title>Valor Econômico</title><link>https://valor.globo.com/</link><description>Notícias de negócios.</description></item>
</channel></rss>`;

function stripBomXml(s) {
  if (typeof s !== "string") return "";
  let t = s.trim();
  if (t.charCodeAt(0) === 0xfeff) t = t.slice(1).trim();
  return t;
}

function looksLikeRss(xml) {
  const x = stripBomXml(xml);
  return x.includes("<rss") || x.includes("<feed");
}

/**
 * Núcleo RSS partilhado: [q] já normalizado (trim, máx. 220).
 * Usado pelo callable e por ctFetchGoogleNewsRssRest (POST JSON simples para Android/iOS sem protocolo callable).
 */
async function ctFetchGoogleNewsRssCore(q) {
    const googleUrl =
      q.length === 0
        ? "https://news.google.com/rss/headlines/section/topic/BUSINESS?hl=pt-BR&gl=BR&ceid=BR:pt-419"
        : `https://news.google.com/rss/search?q=${encodeURIComponent(q)}&hl=pt-BR&gl=BR&ceid=BR:pt-419`;

    const rssCacheKey = crypto.createHash("sha256").update(String(googleUrl)).digest("hex").substring(0, 40);
    const rssCacheRef = admin.firestore().collection("news_rss_server_cache").doc(rssCacheKey);

    /** Devolve XML guardado mesmo fora do TTL (último recurso para não falhar no app). */
    async function returnStaleCacheIfAny(reason) {
      try {
        const cs = await rssCacheRef.get();
        if (!cs.exists) return null;
        const d = cs.data() || {};
        const xmlHint = d.xml;
        if (typeof xmlHint === "string" && xmlHint.length > 200 && looksLikeRss(xmlHint)) {
          console.warn("ctFetchGoogleNewsRss stale cache:", reason);
          return { ok: true, xml: stripBomXml(xmlHint), cached: true, stale: true };
        }
      } catch (e) {
        console.error("ctFetchGoogleNewsRss stale read:", e && e.message);
      }
      return null;
    }

    try {
      const cs = await rssCacheRef.get();
      if (cs.exists) {
        const d = cs.data() || {};
        const xmlHint = d.xml;
        const fetchedAt = d.fetchedAt;
        if (typeof xmlHint === "string" && xmlHint.length > 200 && fetchedAt && typeof fetchedAt.toMillis === "function") {
          const age = Date.now() - fetchedAt.toMillis();
          if (age >= 0 && age < NEWS_RSS_CACHE_TTL_MS && looksLikeRss(xmlHint)) {
            return { ok: true, xml: stripBomXml(xmlHint), cached: true };
          }
        }
      }
    } catch (e) {
      console.error("ctFetchGoogleNewsRss cache read:", e && e.message);
    }

    /** Fontes estáveis no GCP (Google News RSS costuma falhar ou ser lento para IPs de datacenter). */
    const fallbackUrls = [
      "https://g1.globo.com/dynamo/economia/rss2.xml",
      "https://www.infomoney.com.br/feed/",
      "https://www.moneytimes.com.br/feed/",
      "https://admin.cnnbrasil.com.br/rss",
      "https://br.investing.com/rss/news_301.rss",
    ];
    const userAgents = [
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
      "Mozilla/5.0 (compatible; ControleTotalApp/1.0; +https://controletotalapp.com.br)",
    ];

    /** Uma tentativa curta (timeout) — evita ficar preso no Google quando o IP do GCP é bloqueado ou lento. */
    async function fetchRssBodyFast(feedUrl) {
      try {
        const res = await fetch(feedUrl, {
          signal: AbortSignal.timeout(22000),
          headers: {
            "User-Agent": userAgents[0],
            Accept: "application/rss+xml, application/xml, text/xml, */*",
          },
        });
        if (!res.ok) return null;
        const xml = stripBomXml(await res.text());
        if (looksLikeRss(xml)) {
          return xml;
        }
      } catch (e) {
        console.error("ctFetchGoogleNewsRss fetchFast:", feedUrl, e && e.message);
      }
      return null;
    }

    /**
     * Dispara Google + fallbacks em paralelo; devolve o primeiro RSS válido (G1 costuma responder antes que o Google).
     * @returns {Promise<string|null>}
     */
    async function fetchFirstParallel(urls) {
      const tasks = urls.map((url) =>
        fetchRssBodyFast(url).then((xml) => {
          if (xml) return xml;
          return Promise.reject(new Error("empty"));
        }),
      );
      try {
        return await Promise.any(tasks);
      } catch {
        return null;
      }
    }

    /**
     * @param {string} feedUrl
     * @returns {Promise<string|null>}
     */
    async function fetchRssBody(feedUrl) {
      for (const ua of userAgents) {
        try {
          const res = await fetch(feedUrl, {
            signal: AbortSignal.timeout(26000),
            headers: {
              "User-Agent": ua,
              Accept: "application/rss+xml, application/xml, text/xml, */*",
            },
          });
          if (!res.ok) {
            continue;
          }
          const xml = stripBomXml(await res.text());
          if (looksLikeRss(xml)) {
            return xml;
          }
        } catch (e) {
          console.error("ctFetchGoogleNewsRss fetch try:", feedUrl, e && e.message);
        }
      }
      return null;
    }

    // Fallbacks primeiro no arranque paralelo: respondem mais rápido que news.google.com a partir do GCP.
    const allUrls = [...fallbackUrls, googleUrl];
    let xml = await fetchFirstParallel(allUrls);
    if (!xml) {
      xml = await fetchRssBody(googleUrl);
    }
    if (!xml) {
      for (const u of fallbackUrls) {
        xml = await fetchRssBody(u);
        if (xml) break;
      }
    }
    if (!xml) {
      const stale = await returnStaleCacheIfAny("fetch_failed");
      if (stale) return stale;
      console.warn("ctFetchGoogleNewsRss: todas as fontes falharam — RSS de contingência (sem novo build no cliente).");
      return { ok: true, xml: EMERGENCY_FINANCE_RSS_BR.trim(), cached: false, emergency: true };
    }

    const max = 900000;
    const bodyRaw = xml.length > max ? xml.slice(0, max) : xml;
    const body = stripBomXml(bodyRaw);
    if (!looksLikeRss(body)) {
      const stale = await returnStaleCacheIfAny("invalid_xml");
      if (stale) return stale;
      console.warn("ctFetchGoogleNewsRss: XML inválido após fetch — contingência.");
      return { ok: true, xml: EMERGENCY_FINANCE_RSS_BR.trim(), cached: false, emergency: true };
    }
    try {
      await rssCacheRef.set(
        {
          xml: body,
          fetchedAt: admin.firestore.FieldValue.serverTimestamp(),
          q,
          urlSample: String(googleUrl).slice(0, 400),
        },
        { merge: true },
      );
    } catch (e) {
      console.error("ctFetchGoogleNewsRss cache write:", e && e.message);
    }
    return { ok: true, xml: body, cached: false };
}

exports.ctFetchGoogleNewsRss = onCall(
  {
    region: "us-central1",
    maxInstances: 15,
    /** Resposta mais rápida no 1.º pedido (apps nativos); custo extra — pode voltar a 0 no console se quiser. */
    minInstances: 1,
    memory: "512MiB",
    timeoutSeconds: 120,
    enforceAppCheck: false,
    cors: true,
    invoker: "public",
  },
  async (req) => {
    try {
      // RSS agrega apenas URLs públicas — não exigir req.auth: vários clientes nativos não ligam o token à callable,
      // e o utilizador já está na app autenticado; sem isto a cadeia falha antes dos fallbacks HTTP (sem novo APK).
      const rawQ = (req.data && req.data.q != null) ? String(req.data.q) : "";
      const q = rawQ.trim().slice(0, 220);
      const out = await ctFetchGoogleNewsRssCore(q);
      const xml = (out && typeof out.xml === "string") ? out.xml : "";
      // Objeto plano — evita falhas de serialização em alguns clientes Callable Gen2.
      return {
        ok: !!(out && out.ok === true && xml.length > 0),
        xml,
        cached: !!(out && out.cached),
        stale: !!(out && out.stale),
        emergency: !!(out && out.emergency),
      };
    } catch (e) {
      console.error("ctFetchGoogleNewsRss callable fatal:", e && e.stack ? e.stack : e);
      const xml = EMERGENCY_FINANCE_RSS_BR.trim();
      return {
        ok: true,
        xml,
        cached: false,
        emergency: true,
        stale: false,
      };
    }
  },
);

/**
 * Mesmo RSS que ctFetchGoogleNewsRss, mas HTTP POST simples (JSON `{ "q": "..." }`; Bearer opcional).
 * Apps Android/iOS: fallback quando o protocolo callable Gen2 falha; token inválido não bloqueia (conteúdo público).
 */
exports.ctFetchGoogleNewsRssRest = onRequest(
  {
    region: "us-central1",
    maxInstances: 20,
    memory: "512MiB",
    timeoutSeconds: 120,
    cors: true,
    invoker: "public",
  },
  async (req, res) => {
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Authorization, Content-Type");
    try {
      if (req.method === "OPTIONS") {
        return res.status(204).send("");
      }
      if (req.method !== "POST") {
        return res.status(405).json({ ok: false, error: "method" });
      }
      const authHeader = req.get("authorization") || req.get("Authorization") || "";
      const m = authHeader.match(/^Bearer\s+(.+)$/i);
      if (m) {
        try {
          await admin.auth().verifyIdToken(m[1]);
        } catch (e) {
          console.warn("ctFetchGoogleNewsRssRest: Bearer inválido/expirado — RSS público mesmo assim:", e && e.code);
        }
      }
      let payload = req.body;
      if (Buffer.isBuffer(payload)) {
        try {
          payload = JSON.parse(payload.toString("utf8") || "{}");
        } catch {
          payload = {};
        }
      }
      if (typeof payload === "string") {
        try {
          payload = JSON.parse(payload || "{}");
        } catch {
          payload = {};
        }
      }
      if (!payload || typeof payload !== "object") {
        payload = {};
      }
      const rawQ = payload.q != null ? String(payload.q) : "";
      const q = rawQ.trim().slice(0, 220);
      const out = await ctFetchGoogleNewsRssCore(q);
      const xml = (out && typeof out.xml === "string") ? out.xml : "";
      return res.status(200).json({
        ok: !!(out && out.ok === true && xml.length > 0),
        xml,
        cached: !!(out && out.cached),
        stale: !!(out && out.stale),
        emergency: !!(out && out.emergency),
      });
    } catch (e) {
      console.error("ctFetchGoogleNewsRssRest fatal:", e && e.stack ? e.stack : e);
      const xml = EMERGENCY_FINANCE_RSS_BR.trim();
      return res.status(200).json({
        ok: true,
        xml,
        cached: false,
        emergency: true,
        stale: false,
      });
    }
  },
);

/**
 * OCR na web: Google Cloud Vision (mesma família de modelos de alta qualidade; não ML Kit no browser).
 * A imagem vai ao Google com auth do utilizador. Ativar API "Cloud Vision" no projeto GCP se ainda não estiver.
 * Cliente: fallback silencioso para Textify se { ok: false } ou texto vazio.
 */
exports.ctOcrImageForSmartInput = onCall(
  { region: "us-central1", maxInstances: 20, memory: "512MiB" },
  async (req) => {
    if (!req.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Inicie sessão para a leitura de imagem no Google.");
    }
    const base64 = (req.data && req.data.base64) ? String(req.data.base64) : "";
    const mimeType = (req.data && req.data.mimeType) ? String(req.data.mimeType).trim() : "image/jpeg";
    if (base64.length < 32) {
      return { ok: false, text: "", error: "imagem vazia" };
    }
    if (!base64 || typeof base64 !== "string") {
      return { ok: false, text: "", error: "dados inválidos" };
    }
    let buffer;
    try {
      buffer = Buffer.from(base64, "base64");
    } catch (e) {
      return { ok: false, text: "", error: "base64 inválido" };
    }
    if (buffer.length < 32 || buffer.length > MAX_BYTES) {
      return { ok: false, text: "", error: "tamanho" };
    }
    const visMime = new Set([
      "image/jpeg",
      "image/jpg",
      "image/png",
      "image/webp",
      "image/gif",
    ]);
    if (mimeType && !visMime.has(mimeType.toLowerCase())) {
      return { ok: false, text: "", error: "formato" };
    }
    const image = { content: buffer };
    const visCtx = { languageHints: ["pt", "pt-BR", "en"] };
    try {
      const client = new vision.ImageAnnotatorClient();
      const [docResult] = await client.documentTextDetection({ image, imageContext: visCtx });
      let text = (docResult.fullTextAnnotation && docResult.fullTextAnnotation.text) || "";
      if (!text || !String(text).trim()) {
        const [txtResult] = await client.textDetection({ image, imageContext: visCtx });
        if (txtResult.textAnnotations && txtResult.textAnnotations.length) {
          text = txtResult.textAnnotations[0].description || "";
        }
      }
      return { ok: true, text: (text || "").trim() };
    } catch (e) {
      console.error("ctOcrImageForSmartInput:", (e && e.message) || e);
      return { ok: false, text: "", error: (e && e.message) || String(e) };
    }
  }
);

const MAX_STT_BYTES = 4 * 1024 * 1024; // 4 MB

/**
 * Transcrição (Google Cloud Speech-to-Text), pt-BR, para o ditado "profissional" no app.
 * Cliente: áudio curto (ex.: .flac 16 kHz mono) em base64. Ativar API "Speech-to-Text" no mesmo projeto GCP.
 */
exports.ctSpeechToTextForSmartInput = onCall(
  { region: "us-central1", maxInstances: 15, memory: "512MiB" },
  async (req) => {
    if (!req.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Inicie sessão para usar a voz Google.");
    }
    const base64 = (req.data && req.data.base64) ? String(req.data.base64) : "";
    if (!base64 || base64.length < 32) {
      return { ok: false, text: "", error: "áudio vazio" };
    }
    let buffer;
    try {
      buffer = Buffer.from(base64, "base64");
    } catch (e) {
      return { ok: false, text: "", error: "base64 inválido" };
    }
    if (buffer.length < 80 || buffer.length > MAX_STT_BYTES) {
      return { ok: false, text: "", error: "tamanho" };
    }
    const encIn = (req.data && req.data.encoding) ? String(req.data.encoding).toUpperCase() : "FLAC";
    const rate = Number((req.data && req.data.sampleRateHertz) || 16000);
    const rateClamped = Math.min(48000, Math.max(8000, Math.floor(Number.isNaN(rate) ? 16000 : rate)));
    const audio = { content: buffer };
    const sttConfig = {
      languageCode: "pt-BR",
      enableAutomaticPunctuation: true,
    };
    if (encIn === "LINEAR16") {
      sttConfig.encoding = "LINEAR16";
      sttConfig.sampleRateHertz = rateClamped;
    } else if (encIn === "OGG_OPUS" || encIn === "OGG" || encIn === "OPUS") {
      sttConfig.encoding = "OGG_OPUS";
    } else {
      sttConfig.encoding = "FLAC";
      sttConfig.sampleRateHertz = rateClamped;
    }
    try {
      const client = new speech.SpeechClient();
      const [result] = await client.recognize({ audio, config: sttConfig });
      const parts = [];
      for (const r of (result && result.results) || []) {
        for (const alt of (r && r.alternatives) || []) {
          if (alt && alt.transcript) {
            parts.push(alt.transcript);
          }
        }
      }
      return { ok: true, text: (parts.length ? parts.join(" ") : "").trim() };
    } catch (e) {
      console.error("ctSpeechToTextForSmartInput:", (e && e.message) || e);
      return { ok: false, text: "", error: (e && e.message) || String(e) };
    }
  }
);

exports.ctUploadReceiptToStorage = onCall(async (req) => {
  if (!req.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
  }

  const uid = req.auth.uid;
  const txPath = (req.data.txPath || "").toString();
  const originalFilename = (req.data.filename || "").toString();
  const mimeType = (req.data.mimeType || "").toString();
  const base64 = (req.data.base64 || "").toString();

  if (!txPath.startsWith(`users/${uid}/transactions/`)) {
    throw new functions.https.HttpsError("permission-denied", "Transação inválida.");
  }
  if (!originalFilename || !mimeType || !base64) {
    throw new functions.https.HttpsError("invalid-argument", "Dados incompletos.");
  }
  if (!ALLOWED_MIME.has(mimeType) || mimeType.startsWith("video/")) {
    throw new functions.https.HttpsError("invalid-argument", "Tipo de arquivo não permitido.");
  }

  const buffer = Buffer.from(base64, "base64");
  if (buffer.length > MAX_BYTES) {
    throw new functions.https.HttpsError("invalid-argument", "Arquivo acima do limite.");
  }
  const txId = txPath.split("/").pop();
  const ext = originalFilename.includes(".")
    ? originalFilename.substring(originalFilename.lastIndexOf(".") + 1)
    : "";
  const baseName = originalFilename.includes(".")
    ? originalFilename.substring(0, originalFilename.lastIndexOf("."))
    : originalFilename;
  const safeBase = normalizeFilename(baseName);
  const safeExt = normalizeFilename(ext);
  const finalName = `${safeBase}${safeExt ? "." + safeExt : ""}`;
  const storagePath = `users/${uid}/receipts/${txId}/${Date.now()}_${finalName}`;

  let upload;
  try {
    upload = await uploadToStorage({
      filePath: storagePath,
      buffer,
      contentType: mimeType,
    });
  } catch (e) {
    console.error("ctUploadReceiptToStorage upload error:", e);
    throw new functions.https.HttpsError(
      "internal",
      "Falha ao enviar o arquivo. Tente anexar depois na lista de lançamentos."
    );
  }

  const receipt = {
    storagePath: upload.storagePath,
    downloadUrl: upload.downloadUrl,
    name: finalName,
    originalName: originalFilename,
    mimeType,
    size: Number(buffer.length),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  try {
    await admin.firestore().doc(txPath).set({ receipt }, { merge: true });
  } catch (e) {
    console.error("ctUploadReceiptToStorage firestore set error:", e);
    throw new functions.https.HttpsError(
      "internal",
      "Comprovante enviado, mas falha ao registrar. Você pode anexar de novo na lista."
    );
  }
  return { ok: true, receipt };
});

/**
 * Protótipo: PDF no servidor com o mesmo visual «Extrato Super Premium» do app (amostra).
 */
exports.ctFinancePdfPrototype = onCall(
  { region: "us-central1", memory: "512MiB", timeoutSeconds: 120 },
  async (req) => {
    if (!req.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
    }
    const PDFDocument = require("pdfkit");
    const uid = req.auth.uid;
    let nomeUsuario = "";
    try {
      const u = await admin.firestore().doc(`users/${uid}`).get();
      nomeUsuario = ((u.data() || {}).name || (u.data() || {}).displayName || "").toString().trim();
    } catch (_) {}
    const rowsProto = [];
    try {
      const snap = await admin
        .firestore()
        .collection("users")
        .doc(uid)
        .collection("transactions")
        .orderBy("date", "desc")
        .limit(8)
        .get();
      if (!snap.empty) {
        snap.forEach((d) => {
          const x = d.data() || {};
          const dt = _asJsDate(x.date);
          const amount = Number(x.amount || 0);
          const type = (x.type || "expense").toString();
          const abs = Math.abs(Number.isFinite(amount) ? amount : 0);
          rowsProto.push({
            effective: dt || new Date(0),
            data: _fmtDateBr(dt || new Date()),
            tipo: type,
            valor: abs,
            cat: ((x.category || "") + "").toString().trim(),
            desc: ((x.description || "") + "").toString().trim(),
          });
        });
      }
    } catch (e) {
      rowsProto.length = 0;
    }
    rowsProto.sort((a, b) => a.effective - b.effective);
    let totalReceitas = 0;
    let totalDespesas = 0;
    for (const r of rowsProto) {
      if (r.tipo === "income") totalReceitas += r.valor;
      else totalDespesas += r.valor;
    }
    const { linhas } = financePdfSuperExtrato.buildExtratoLinhas(0, rowsProto);
    const pdfBuffer = await financePdfSuperExtrato.buildFinanceSuperExtratoPdfBuffer(PDFDocument, {
      nomeUsuario: nomeUsuario || uid,
      conta: "Todas as contas",
      periodo: "Amostra (últimos lançamentos)",
      saldoAbertura: 0,
      totalReceitas,
      totalDespesas,
      linhas,
    });
    const filename = `financeiro_servidor_${Date.now()}.pdf`;
    return {
      ok: true,
      pdfBase64: pdfBuffer.toString("base64"),
      filename,
      notice: "Protótipo no servidor — visual alinhado ao Extrato Super Premium do app.",
    };
  },
);

function _asJsDate(v) {
  if (!v) return null;
  if (v instanceof Date) return v;
  if (typeof v.toDate === "function") return v.toDate();
  if (typeof v === "string" || typeof v === "number") {
    const d = new Date(v);
    if (!Number.isNaN(d.getTime())) return d;
  }
  return null;
}

function _fmtDateBr(d) {
  if (!(d instanceof Date)) return "";
  const dd = String(d.getDate()).padStart(2, "0");
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const yyyy = d.getFullYear();
  return `${dd}/${mm}/${yyyy}`;
}

function _fmtMoneyBr(v) {
  const n = Number(v || 0);
  return new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(Number.isFinite(n) ? n : 0);
}

async function _iterateQueryPaged(q, onDoc, pageSize = 2000, maxDocs = 200000) {
  let cursor = null;
  let processed = 0;
  while (processed < maxDocs) {
    let qq = q.limit(pageSize);
    if (cursor) qq = qq.startAfter(cursor);
    const snap = await qq.get();
    if (snap.empty) break;
    for (const d of snap.docs) {
      await onDoc(d);
      processed += 1;
      if (processed >= maxDocs) break;
    }
    if (snap.docs.length < pageSize || processed >= maxDocs) break;
    cursor = snap.docs[snap.docs.length - 1];
  }
  return processed;
}

/**
 * Relatório financeiro pesado no servidor (Cloud Functions + Storage).
 * Escala para grandes períodos/volumes sem travar Web/Android.
 */
exports.ctGenerateFinancePdfServer = onCall(
  { region: "us-central1", memory: "2GiB", timeoutSeconds: 540 },
  async (req) => {
    if (!req.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
    }
    const uid = req.auth.uid;
    const fromISO = (req.data?.fromISO || "").toString();
    const toISO = (req.data?.toISO || "").toString();
    const financeAccountId = (req.data?.financeAccountId || "").toString().trim();
    const from = _asJsDate(fromISO);
    const to = _asJsDate(toISO);
    if (!from || !to) {
      throw new functions.https.HttpsError("invalid-argument", "Período inválido.");
    }
    const start = new Date(from.getFullYear(), from.getMonth(), from.getDate(), 0, 0, 0, 0);
    const end = new Date(to.getFullYear(), to.getMonth(), to.getDate(), 23, 59, 59, 999);
    if (end < start) {
      throw new functions.https.HttpsError("invalid-argument", "Período inválido.");
    }

    const txCol = admin.firestore().collection("users").doc(uid).collection("transactions");
    let qByDate = txCol
      .where("date", ">=", admin.firestore.Timestamp.fromDate(start))
      .where("date", "<=", admin.firestore.Timestamp.fromDate(end))
      .orderBy("date", "asc");
    let qByPaidAt = txCol
      .where("status", "==", "paid")
      .where("paidAt", ">=", admin.firestore.Timestamp.fromDate(start))
      .where("paidAt", "<=", admin.firestore.Timestamp.fromDate(end))
      .orderBy("paidAt", "asc");
    let qOpening = txCol
      .where("date", "<", admin.firestore.Timestamp.fromDate(start))
      .orderBy("date", "asc");

    if (financeAccountId) {
      qByDate = qByDate.where("financeAccountId", "==", financeAccountId);
      qByPaidAt = qByPaidAt.where("financeAccountId", "==", financeAccountId);
      qOpening = qOpening.where("financeAccountId", "==", financeAccountId);
    }

    let saldoAbertura = 0;
    await _iterateQueryPaged(qOpening, async (doc) => {
      const x = doc.data() || {};
      if ((x.status || "paid").toString() !== "paid") return;
      const amount = Number(x.amount || 0);
      if (!Number.isFinite(amount)) return;
      const type = (x.type || "expense").toString();
      if (type === "income") saldoAbertura += amount;
      else saldoAbertura -= Math.abs(amount);
    });

    const byId = new Map();
    const pushIfPaidInPeriod = (doc) => {
      const x = doc.data() || {};
      if ((x.status || "paid").toString() !== "paid") return;
      const dt = _asJsDate(x.date);
      if (!dt) return;
      const paidAt = _asJsDate(x.paidAt);
      const effective = paidAt || dt;
      if (effective < start || effective > end) return;
      byId.set(doc.id, x);
    };
    await _iterateQueryPaged(qByDate, async (doc) => pushIfPaidInPeriod(doc));
    await _iterateQueryPaged(qByPaidAt, async (doc) => pushIfPaidInPeriod(doc));

    if (byId.size === 0) {
      throw new functions.https.HttpsError("not-found", "Nenhum lançamento pago no período.");
    }

    const rows = [];
    let totalReceitas = 0;
    let totalDespesas = 0;
    for (const [, x] of byId.entries()) {
      const dt = _asJsDate(x.date);
      const paidAt = _asJsDate(x.paidAt);
      const effective = paidAt || dt || start;
      const amount = Number(x.amount || 0);
      const absAmount = Math.abs(Number.isFinite(amount) ? amount : 0);
      const type = (x.type || "expense").toString();
      if (type === "income") totalReceitas += absAmount;
      else totalDespesas += absAmount;
      rows.push({
        effective,
        data: _fmtDateBr(dt || effective),
        tipo: type,
        valor: absAmount,
        conta: ((x.financeAccountId || "") + "").toString().trim(),
        cat: ((x.category || "") + "").toString().trim(),
        desc: ((x.description || "") + "").toString().trim(),
      });
    }
    rows.sort((a, b) => a.effective - b.effective);

    const periodo = `${_fmtDateBr(start)} a ${_fmtDateBr(end)}`;
    const saldoAcum = saldoAbertura + (totalReceitas - totalDespesas);

    let nomeUsuario = "";
    try {
      const u = await admin.firestore().doc(`users/${uid}`).get();
      nomeUsuario = ((u.data() || {}).name || (u.data() || {}).displayName || "").toString().trim();
    } catch (_) {}

    let contaLabel = "Todas as contas";
    if (financeAccountId) {
      contaLabel = financeAccountId;
      try {
        const acc = await admin.firestore().doc(`users/${uid}/finance_accounts/${financeAccountId}`).get();
        const d = acc.data() || {};
        const nick = (d.nickname || "").toString().trim();
        if (nick) contaLabel = nick;
      } catch (_) {}
    }

    const { linhas } = financePdfSuperExtrato.buildExtratoLinhas(saldoAbertura, rows);
    const PDFDocument = require("pdfkit");
    const buffer = await financePdfSuperExtrato.buildFinanceSuperExtratoPdfBuffer(PDFDocument, {
      nomeUsuario: nomeUsuario || uid,
      conta: contaLabel,
      periodo,
      saldoAbertura,
      totalReceitas,
      totalDespesas,
      linhas,
    });

    const safeAccount = financeAccountId ? `_${financeAccountId.replace(/[^a-zA-Z0-9_-]/g, "_")}` : "";
    const filename = `financeiro_${Date.now()}${safeAccount}.pdf`;
    const storagePath = `users/${uid}/reports/finance/${filename}`;
    const upload = await uploadToStorage({
      filePath: storagePath,
      buffer,
      contentType: "application/pdf",
    });
    return {
      ok: true,
      filename,
      storagePath: upload.storagePath,
      downloadUrl: upload.downloadUrl,
      totalRows: rows.length,
      totals: {
        saldoAbertura,
        totalReceitas,
        totalDespesas,
        saldoAcumulado: saldoAcum,
      },
      notice: "Relatório gerado no servidor para evitar travamento no dispositivo.",
    };
  },
);

exports.ctUploadBudgetPdfToStorage = onCall(async (req) => {
  if (!req.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
  }

  const uid = req.auth.uid;
  const budgetPath = (req.data.budgetPath || "").toString();
  const originalFilename = (req.data.filename || "").toString();
  const base64 = (req.data.base64 || "").toString();

  if (!budgetPath.startsWith(`users/${uid}/quotes/`)) {
    throw new functions.https.HttpsError("permission-denied", "Orçamento inválido.");
  }
  if (!originalFilename || !base64) {
    throw new functions.https.HttpsError("invalid-argument", "Dados incompletos.");
  }

  const buffer = Buffer.from(base64, "base64");
  if (buffer.length > MAX_BYTES) {
    throw new functions.https.HttpsError("invalid-argument", "Arquivo acima do limite.");
  }
  const baseName = originalFilename.includes(".")
    ? originalFilename.substring(0, originalFilename.lastIndexOf("."))
    : originalFilename;
  const safeBase = normalizeFilename(baseName);
  const finalName = `${safeBase}.pdf`;
  const budgetId = budgetPath.split("/").pop();
  const storagePath = `users/${uid}/budgets/${budgetId}/${Date.now()}_${finalName}`;
  const upload = await uploadToStorage({
    filePath: storagePath,
    buffer,
    contentType: "application/pdf",
  });
  const pdf = {
    storagePath: upload.storagePath,
    downloadUrl: upload.downloadUrl,
    name: finalName,
    originalName: originalFilename,
    mimeType: "application/pdf",
    size: Number(buffer.length),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  await admin.firestore().doc(budgetPath).set({ pdf }, { merge: true });
  return { ok: true, pdf };
});

exports.ctResolveCpfEmail = onCall(async (req) => {
  const cpf = (req.data?.cpf || "").toString().replace(/[^0-9]/g, "");
  if (cpf.length !== 11) {
    throw new functions.https.HttpsError("invalid-argument", "CPF inválido");
  }

  const snap = await admin.firestore().collection("cpf_index").doc(cpf).get();
  const data = snap.data() || {};
  const email = (data.email || "").toString();

  if (!email) {
    throw new functions.https.HttpsError("not-found", "CPF não cadastrado");
  }

  return { email, uid: data.uid || null };
});

/** Totais do período + saldo de abertura (paginação no servidor — módulo Financeiro). */
exports.ctFinancePeriodTotals = onCall(
  { region: "us-central1", memory: "512MiB", timeoutSeconds: 120 },
  async (req) => {
    if (!req.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
    }
    const uid = req.auth.uid;
    const fromISO = (req.data?.fromISO || "").toString();
    const toISO = (req.data?.toISO || "").toString();
    const statusFilter = (req.data?.statusFilter || "paid").toString();
    const typeFilter = (req.data?.typeFilter || "all").toString();
    const from = _asJsDate(fromISO);
    const to = _asJsDate(toISO);
    if (!from || !to) {
      throw new functions.https.HttpsError("invalid-argument", "Período inválido.");
    }
    const start = new Date(from.getFullYear(), from.getMonth(), from.getDate(), 0, 0, 0, 0);
    const end = new Date(to.getFullYear(), to.getMonth(), to.getDate(), 23, 59, 59, 999);
    const txCol = admin.firestore().collection("users").doc(uid).collection("transactions");
    const { monthKeyBr, openingContribution: openingContribFn, restoreAccountFieldId } = require("./financeMonthBuckets");

    let openingTotal = 0;
    const openingByAccount = {};
    const monthStart = new Date(start.getFullYear(), start.getMonth(), 1, 0, 0, 0, 0);

    try {
      const partialKey = monthKeyBr(admin.firestore.Timestamp.fromDate(start));
      const buckets = await admin
        .firestore()
        .collection(`users/${uid}/finance_month_buckets`)
        .where(admin.firestore.FieldPath.documentId(), "<", partialKey)
        .get();
      buckets.forEach((d) => {
        openingTotal += Number(d.data()?.netPaid || 0);
      });
      const accBuckets = await admin
        .firestore()
        .collection(`users/${uid}/finance_account_month_buckets`)
        .where(admin.firestore.FieldPath.documentId(), "<", partialKey)
        .get();
      accBuckets.forEach((d) => {
        const map = d.data()?.netByAccount;
        if (!map || typeof map !== "object") return;
        for (const [fieldKey, val] of Object.entries(map)) {
          const acc = restoreAccountFieldId(fieldKey);
          if (!acc) continue;
          openingByAccount[acc] = (openingByAccount[acc] || 0) + Number(val || 0);
        }
      });
    } catch (e) {
      console.warn("ctFinancePeriodTotals buckets", e?.message || e);
    }

    async function absorbOpeningDoc(doc) {
      const x = doc.data() || {};
      if ((x.status || "paid").toString() !== "paid") return;
      const c = openingContribFn(x);
      if (c === 0) return;
      openingTotal += c;
      const acc = ((x.financeAccountId || "") + "").toString().trim();
      if (acc) openingByAccount[acc] = (openingByAccount[acc] || 0) + c;
    }

    try {
      await _iterateQueryPaged(
        txCol
          .where("effectiveDate", ">=", admin.firestore.Timestamp.fromDate(monthStart))
          .where("effectiveDate", "<", admin.firestore.Timestamp.fromDate(start)),
        absorbOpeningDoc,
        400,
        3000,
      );
    } catch (e) {
      console.warn("ctFinancePeriodTotals effectiveDate partial", e?.message || e);
    }

    try {
      await _iterateQueryPaged(
        txCol
          .where("date", ">=", admin.firestore.Timestamp.fromDate(monthStart))
          .where("date", "<", admin.firestore.Timestamp.fromDate(start))
          .orderBy("date", "asc"),
        async (doc) => {
          const x = doc.data() || {};
          if (x.effectiveDate) return;
          await absorbOpeningDoc(doc);
        },
        400,
        2500,
      );
    } catch (e) {
      console.warn("ctFinancePeriodTotals date partial fallback", e?.message || e);
    }

    let qPeriod = txCol
      .where("date", ">=", admin.firestore.Timestamp.fromDate(start))
      .where("date", "<=", admin.firestore.Timestamp.fromDate(end))
      .orderBy("date", "asc");
    if (typeFilter === "income") {
      qPeriod = qPeriod.where("type", "==", "income");
    } else if (typeFilter === "expense") {
      qPeriod = qPeriod.where("type", "==", "expense");
    }
    if (statusFilter === "pending") {
      qPeriod = qPeriod.where("status", "==", "pending");
    } else if (statusFilter === "paid") {
      qPeriod = qPeriod.where("status", "==", "paid");
    }

    let income = 0;
    let expense = 0;
    const periodByAccount = {};
    await _iterateQueryPaged(qPeriod, async (doc) => {
      const x = doc.data() || {};
      if (statusFilter !== "all" && statusFilter !== "pending" && statusFilter !== "paid") {
        if ((x.status || "paid").toString() !== statusFilter) return;
      } else if (statusFilter === "all" && (x.status || "paid").toString() !== "paid") {
        return;
      }
      const amount = Math.abs(Number(x.amount || 0));
      if (!Number.isFinite(amount)) return;
      const type = (x.type || "expense").toString();
      if (typeFilter === "income" && type !== "income") return;
      if (typeFilter === "expense" && type !== "expense") return;
      if (type === "income") income += amount;
      else expense += amount;
      const acc = ((x.financeAccountId || "") + "").toString().trim();
      if (!acc) return;
      const delta = type === "income" ? amount : -amount;
      periodByAccount[acc] = (periodByAccount[acc] || 0) + delta;
    });

    let pendingExpenseCount = 0;
    try {
      await _iterateQueryPaged(
        txCol
          .where("date", ">=", admin.firestore.Timestamp.fromDate(start))
          .where("date", "<=", admin.firestore.Timestamp.fromDate(end))
          .where("status", "==", "pending")
          .where("type", "==", "expense")
          .orderBy("date", "asc"),
        async () => {
          pendingExpenseCount += 1;
        },
        400,
        8000,
      );
    } catch (e) {
      console.warn("ctFinancePeriodTotals pendingExpenseCount", e?.message || e);
    }

    return {
      ok: true,
      openingTotal,
      openingByAccount,
      income,
      expense,
      periodByAccount,
      pendingExpenseCount,
      balance: openingTotal + income - expense,
    };
  },
);

exports.ctAgendaRemindersForRange = agendaPeriodSnapshot.ctAgendaRemindersForRange;

/** Login rápido: confirma sub-login (compartilhamento) em 1 leitura no servidor. */
exports.ctProbeDelegateAccess = onCall(async (req) => {
  if (!req.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Faça login.");
  }
  const email = (req.auth.token?.email || "").toString().trim().toLowerCase();
  if (!email) {
    return { isDelegate: false };
  }
  const snap = await admin.firestore().collection("delegate_email_index").doc(email).get();
  if (!snap.exists || snap.data()?.active !== true) {
    return { isDelegate: false };
  }
  const principalUid = (snap.data()?.principalUid || "").toString().trim();
  if (!principalUid || principalUid === req.auth.uid) {
    return { isDelegate: false };
  }
  return {
    isDelegate: true,
    principalUid,
    principalEmail: (snap.data()?.principalEmail || "").toString(),
  };
});

/** Envia um e-mail de teste para o usuário logado (Admin pode usar para testar a configuração de E-mail). */
exports.ctSendTestEmail = onCall(async (req) => {
  if (!req.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Faça login para enviar o teste.");
  }
  const uid = req.auth.uid;
  const userSnap = await admin.firestore().doc(`users/${uid}`).get();
  const userData = userSnap.data() || {};
  const email = (userData.email || req.auth.token?.email || "").toString().trim();
  if (!email || !/^[^@]+@[^@]+\.[^@]+$/.test(email)) {
    throw new functions.https.HttpsError("failed-precondition", "Seu usuário não tem e-mail cadastrado. Adicione um e-mail no perfil.");
  }
  const name = (userData.name || "Usuário").toString().trim();
  const body = `<p>Olá, <strong>${escapeHtml(name)}</strong>!</p><p>Este é um <strong>e-mail de teste</strong> do Controle Total App.</p><p>Se você recebeu esta mensagem, a configuração de e-mail (Admin &gt; E-mail) está funcionando. Os lembretes de plantão e avisos de licença serão enviados automaticamente para os usuários.</p><p style="margin-top:24px;color:#64748b;font-size:13px">Tenha um ótimo dia! 🚀</p>`;
  const html = buildEmailBase("✅ Teste de e-mail — Controle Total", body);
  const res = await sendEmailHtml(email, "Controle Total — E-mail de teste (configuração OK)", html);
  if (!res.ok) {
    return { ok: false, error: res.error || "Falha ao enviar." };
  }
  return { ok: true };
});

exports.ctAutoConfirmScalesByEndTimeScheduled =
  scaleAutoConfirmScheduled.ctAutoConfirmScalesByEndTimeScheduled;

/**
 * Envia lembretes por e-mail (e push) para todos os usuários, a partir de hoje,
 * incluindo lançamentos retroativos de hoje (horário de lembrete já passou mas ainda não foi enviado).
 * Só administradores podem executar. Use para "reativar" envio para quem já tem dados cadastrados.
 */
exports.ctEnviarLembretesRetroativos = onCall(async (req) => {
  if (!req.auth) throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
  await requireAdminPanel(req.auth.uid);
  const result = await runEnviarLembretesRetroativos();
  return result;
});

/** Recalcula plantões GO (>= 2º período, ex. 01/07/2026) para todos os usuários no padrão global. */
exports.ctRecalcGoiasScaleRatesAllUsers = onCall(async (req) => {
  if (!req.auth) throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
  await requireAdminPanel(req.auth.uid);
  const force = req.data?.force === true;
  const db = admin.firestore();
  return goiasScaleRatesRecalc.runGoiasScaleRatesRecalcAllUsers(db, { force });
});


exports.ctCreateMpCheckout = onCall(async (req) => {
  if (!req.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
  }

  const { accessToken, publicKey, webhookUrl, split } = await getMpConfig();
  if (!accessToken) {
    throw new functions.https.HttpsError("failed-precondition", "Mercado Pago não configurado.");
  }

  const uid = req.auth.uid;
  const userSnap = await admin.firestore().doc(`users/${uid}`).get();
  const userData = userSnap.data() || {};
  const priceMap = await loadMpPriceByPlanMerged();

  const promoId = (req.data.promoId || req.data.promotion_id || "").toString().trim();
  let planCode = normalizeMercadoPagoPlanKey(req.data.plan || "premium_monthly");
  if (promoId && isExtraBankPlanCode(planCode)) {
    throw new functions.https.HttpsError("invalid-argument", "Promoção não se aplica à conexão bancária extra.");
  }
  let title;
  let plan;
  let unitPrice;
  if (promoId) {
    const promoSnap = await admin.firestore().collection("promotions").doc(promoId).get();
    const resolved = resolveCheckoutPlanFromPromo(promoSnap, planCode, priceMap);
    planCode = resolved.planCode;
    title = resolved.title;
    plan = resolved.plan;
    unitPrice = resolved.unitPrice;
  } else {
    const cfg = getPlanConfig(planCode, priceMap);
    title = cfg.title;
    plan = cfg.plan;
    unitPrice = getAmountForMercadoPago(planCode, priceMap);
  }

  planCode = normalizeMercadoPagoPlanKey(planCode);
  assertMercadoPagoCheckoutPlanAllowed(planCode);

  const payerEmail = (userData.email || req.auth.token?.email || "").toString().trim();
  if (!payerEmail) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Email do usuário não encontrado. Faça login novamente ou vincule um email à sua conta para pagar com cartão."
    );
  }

  const maxInst = maxInstallmentsForMpPreference(planCode, promoId);

  const premiumAnnualSix = planCode === "premium_annual";
  const paymentMethods = premiumAnnualSix
    ? {
        installments: 6,
        default_installments: 6,
        excluded_payment_types: [{ id: "ticket" }],
      }
    : {
        installments: maxInst,
        default_installments: 1,
        excluded_payment_types: [{ id: "ticket" }],
      };

  const preference = {
    items: [
      {
        title,
        quantity: 1,
        currency_id: "BRL",
        unit_price: unitPrice,
      },
    ],
    payment_methods: paymentMethods,
    payer: {
      email: payerEmail,
      name: (userData.name || "").toString().trim() || undefined,
    },
    metadata: {
      ...CT_MP_METADATA_INTEGRATION,
      uid,
      userId: uid,
      firebase_uid: uid,
      email: payerEmail,
      plan,
      planCode,
      ...(promoId ? { promoId, promotion_id: promoId } : {}),
    },
    external_reference: uid,
    back_urls: {
      success: `${APP_DOMAIN}/payment?status=success`,
      pending: `${APP_DOMAIN}/payment?status=pending`,
      failure: `${APP_DOMAIN}/payment?status=failure`,
    },
    auto_return: "approved",
    notification_url: webhookUrl || MP_WISDOMAPP_WEBHOOK_URL,
  };

  const splitReq = buildMpSplitForRequest(unitPrice, { split });
  if (splitReq.enabled) {
    preference.collector_id = splitReq.collectorId;
    preference.marketplace_fee = splitReq.marketplaceFee;
    preference.metadata = {
      ...preference.metadata,
      ...splitReq.metadata,
    };
  }

  const res = await fetch("https://api.mercadopago.com/checkout/preferences", {
    method: "POST",
    headers: mpHeaders(accessToken),
    body: JSON.stringify(preference),
  });

  if (!res.ok) {
    const errorText = await res.text();
    let msg = "Erro ao criar checkout.";
    try {
      const errJson = JSON.parse(errorText);
      const causes = errJson.cause || errJson.message || errJson.error;
      if (causes) {
        const detail = Array.isArray(causes) ? causes[0]?.description || causes[0] : causes;
        msg = typeof detail === "string" ? detail : (detail?.description || msg);
      }
    } catch (_) {
      if (errorText && errorText.length < 200) msg = errorText;
    }
    throw new functions.https.HttpsError("internal", msg);
  }

  const dataRes = await res.json();
  return {
    id: dataRes.id,
    init_point: dataRes.init_point,
    sandbox_init_point: dataRes.sandbox_init_point,
    public_key: publicKey || null,
    max_installments: maxInst,
    split_enabled: splitReq.enabled,
    split_owner_amount: splitReq.ownerShareAmount ?? null,
    split_partner_amount: splitReq.partnerShareAmount ?? null,
  };
});

/** Cria pagamento PIX (valor integral, à vista — sem parcelamento no Mercado Pago). */
exports.ctCreateMpPixPayment = onCall(async (req) => {
  if (!req.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
  }

  const { accessToken, webhookUrl, split } = await getMpConfig();
  if (!accessToken) {
    throw new functions.https.HttpsError("failed-precondition", "Mercado Pago não configurado.");
  }

  const uid = req.auth.uid;
  const userSnap = await admin.firestore().doc(`users/${uid}`).get();
  const userData = userSnap.data() || {};
  const priceMap = await loadMpPriceByPlanMerged();

  const promoId = (req.data.promoId || req.data.promotion_id || "").toString().trim();
  let planCode = normalizeMercadoPagoPlanKey(req.data.plan || "premium_monthly");
  if (promoId && isExtraBankPlanCode(planCode)) {
    throw new functions.https.HttpsError("invalid-argument", "Promoção não se aplica à conexão bancária extra.");
  }
  let title;
  let plan;
  let transactionAmount;
  if (promoId) {
    const promoSnap = await admin.firestore().collection("promotions").doc(promoId).get();
    const resolved = resolveCheckoutPlanFromPromo(promoSnap, planCode, priceMap);
    planCode = resolved.planCode;
    title = resolved.title;
    plan = resolved.plan;
    transactionAmount = resolved.unitPrice;
    console.log(
      `[ctCreateMpPixPayment] promoId=${promoId} planCode=${planCode} transaction_amount=${transactionAmount}`,
    );
  } else {
    const cfg = getPlanConfig(planCode, priceMap);
    title = cfg.title;
    plan = cfg.plan;
    transactionAmount = getAmountForMercadoPago(planCode, priceMap);
    console.log(`[ctCreateMpPixPayment] sem promo planCode=${planCode} transaction_amount=${transactionAmount}`);
  }

  planCode = normalizeMercadoPagoPlanKey(planCode);
  assertMercadoPagoCheckoutPlanAllowed(planCode);

  const idempotencyKey = `pix-${uid}-${planCode}-${promoId || "std"}-${Date.now()}`;

  const paymentBody = {
    transaction_amount: Number(transactionAmount),
    payment_method_id: "pix",
    payer: {
      email: (userData.email || req.auth.token.email || "").toString(),
      first_name: (userData.name || "").toString().split(" ")[0] || "Cliente",
      last_name: (userData.name || "").toString().split(" ").slice(1).join(" ") || "",
    },
    metadata: {
      ...CT_MP_METADATA_INTEGRATION,
      uid,
      userId: uid,
      firebase_uid: uid,
      email: (userData.email || req.auth.token.email || "").toString(),
      plan,
      planCode,
      ...(promoId ? { promoId, promotion_id: promoId } : {}),
    },
    external_reference: uid,
    notification_url: webhookUrl || MP_WISDOMAPP_WEBHOOK_URL,
    description: title,
  };

  const splitReq = buildMpSplitForRequest(transactionAmount, { split });
  if (splitReq.enabled) {
    paymentBody.collector_id = splitReq.collectorId;
    paymentBody.application_fee = splitReq.applicationFee;
    paymentBody.metadata = {
      ...paymentBody.metadata,
      ...splitReq.metadata,
    };
  }

  const payRes = await fetch("https://api.mercadopago.com/v1/payments", {
    method: "POST",
    headers: {
      ...mpHeaders(accessToken),
      "X-Idempotency-Key": idempotencyKey,
    },
    body: JSON.stringify(paymentBody),
  });

  if (!payRes.ok) {
    const errText = await payRes.text();
    console.error("ctCreateMpPixPayment error:", payRes.status, errText);
    throw new functions.https.HttpsError("internal", "Erro ao gerar PIX. Tente novamente.");
  }

  const payment = await payRes.json();
  const poi = payment.point_of_interaction || {};
  const txData = poi.transaction_data || {};
  const qrCode = txData.qr_code || txData.br_code || "";
  const qrCodeBase64 = txData.qr_code_base64 || "";

  await admin.firestore().doc(`users/${uid}/pending_payment/current`).set({
    paymentId: String(payment.id),
    planCode,
    ...(promoId ? { promoId } : {}),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  return {
    payment_id: payment.id,
    status: payment.status,
    qr_code: qrCode,
    qr_code_base64: qrCodeBase64,
    ticket_url: txData.ticket_url || qrCode,
    transaction_amount: Number(transactionAmount),
    plan_code: planCode,
    split_enabled: splitReq.enabled,
    split_owner_amount: splitReq.ownerShareAmount ?? null,
    split_partner_amount: splitReq.partnerShareAmount ?? null,
    ...(promoId ? { promo_id: promoId } : {}),
  };
});

/** Rate limit: max 60 requests per paymentId per minute (replay protection). */
const mpWebhookRateLimit = new Map(); // paymentId -> [timestamps]
const RATE_LIMIT_MAX = 60;
const RATE_LIMIT_WINDOW_MS = 60 * 1000;

function checkMpWebhookRateLimit(paymentId) {
  const key = String(paymentId);
  const now = Date.now();
  let arr = mpWebhookRateLimit.get(key) || [];
  arr = arr.filter((t) => now - t < RATE_LIMIT_WINDOW_MS);
  if (arr.length >= RATE_LIMIT_MAX) return false;
  arr.push(now);
  mpWebhookRateLimit.set(key, arr);
  return true;
}

exports.mpWebhook = onRequest(async (req, res) => {
  const { accessToken, webhookSecret } = await getMpConfig();
  if (!accessToken) {
    return res.status(500).json({ ok: false, error: "Mercado Pago não configurado." });
  }

  const type = (req.body?.type || req.query?.type || "").toString();
  const dataId = req.body?.data?.id || req.query?.["data.id"] || req.query?.id;

  // Segurança: rejeitar notificações que não venham do Mercado Pago (evita alguém burlar chamando a URL com ID falso).
  if (webhookSecret && webhookSecret.length > 0) {
    const signature = (req.header("x-signature") || "").toString();
    const requestId = (req.header("x-request-id") || "").toString();
    if (signature && requestId && dataId) {
      const expected = crypto
        .createHmac("sha256", webhookSecret)
        .update(`${requestId}.${dataId}`)
        .digest("hex");
      if (!signature.includes(expected)) {
        console.warn("mpWebhook: assinatura inválida — rejeitando. Possível tentativa de burlar o sistema.");
        return res.status(401).json({ ok: false, error: "invalid_signature" });
      }
    }
  }

  if (type !== "payment" || !dataId) {
    return res.status(200).json({ ok: true, ignored: true });
  }

  if (!checkMpWebhookRateLimit(dataId)) {
    return res.status(429).json({ ok: false, error: "rate_limit_exceeded" });
  }

  // Responder 200 IMEDIATAMENTE para o MP contar como "notificação entregue" (evita 0% por timeout).
  // Processamento em segundo plano; se falhar, o cron mpSyncPaymentsScheduled repete em até 15 min.
  res.status(200).json({ ok: true });

  (async () => {
    try {
      const paymentRes = await fetch(`https://api.mercadopago.com/v1/payments/${dataId}`, {
        headers: mpHeaders(accessToken),
      });
      if (!paymentRes.ok) {
        console.error(`mpWebhook: GET payment ${dataId} falhou: ${await paymentRes.text()}`);
        return;
      }
      const payment = await paymentRes.json();
      console.log(`mpWebhook: processando payment ${payment.id}, status=${payment.status}, external_reference=${payment.external_reference || "(vazio)"}`);
      await processMpPayment(payment);
    } catch (e) {
      console.error("mpWebhook background:", e?.message || e);
    }
  })();
});

/** Normaliza metadata (MP às vezes retorna string JSON). */
function getPaymentMetadata(payment) {
  let meta = payment.metadata || payment.additional_info;
  if (typeof meta === "string") {
    try {
      meta = JSON.parse(meta);
    } catch (_) {
      meta = null;
    }
  }
  return meta || {};
}

/**
 * Pagamento “de licença” do Controle Total: checkout/PIX do app, legado com metadata coerente,
 * ou PIX pendente salvo em pending_payment (subcoleção do usuário). Não inclui depósitos/PIX avulsos na conta MP.
 */
async function isMercadoPagoPaymentFromControleTotalApp(payment) {
  if (!payment) return false;
  const meta = getPaymentMetadata(payment);
  const low = (v) => (v || "").toString().trim().toLowerCase();
  if (low(meta.ct_integration) === "controletotal" || low(meta.integration) === "controletotal") {
    return true;
  }
  const paymentId = String(payment.id || "").trim();
  if (paymentId && /^\d+$/.test(paymentId)) {
    const pendingSnap = await admin
      .firestore()
      .collectionGroup("pending_payment")
      .where("paymentId", "==", paymentId)
      .limit(1)
      .get();
    if (!pendingSnap.empty) return true;
  }
  const metaUid = (meta.uid || meta.userId || meta.user_id || meta.firebase_uid || "").toString().trim();
  const extRef = (payment.external_reference || "").toString().trim();
  const hasPlanMeta = !!(low(meta.planCode) || low(meta.plan));
  if (metaUid && hasPlanMeta && extRef && extRef === metaUid) {
    return true;
  }
  return false;
}

/** Helper: resolve uid do pagamento (metadata, external_reference ou pending_payment).
 *  Não usa e-mail do pagador no fluxo automático (evita depósito na conta MP virar “venda” de licença). */
async function resolveUidFromPayment(payment, opts = {}) {
  const meta = getPaymentMetadata(payment);
  const extRef = (payment.external_reference || "").toString().trim();
  let uid = (meta.uid || meta.userId || meta.user_id || meta.firebase_uid || extRef || "").toString().trim() || null;
  if (uid) {
    console.log(`mpWebhook: uid encontrado em metadata/external_reference: ${uid} (payment ${payment.id})`);
    return uid;
  }
  if (opts.allowEmailFallback) {
    const email = (payment.payer?.email || meta.email || "").toString().trim().toLowerCase();
    if (email) {
      const usersSnap = await admin.firestore().collection("users").where("email", "==", email).limit(1).get();
      if (!usersSnap.empty) {
        uid = usersSnap.docs[0].id;
        console.log(`mpWebhook: uid por e-mail (fallback admin) "${email}": ${uid} (payment ${payment.id})`);
        return uid;
      }
    }
  }
  const paymentId = String(payment.id || "").trim();
  if (paymentId && /^\d+$/.test(paymentId)) {
    const pendingSnap = await admin.firestore().collectionGroup("pending_payment").where("paymentId", "==", paymentId).limit(1).get();
    if (!pendingSnap.empty) {
      const docPath = pendingSnap.docs[0].ref.path;
      const parts = docPath.split("/");
      if (parts.indexOf("users") >= 0) {
        const uidIdx = parts.indexOf("users") + 1;
        if (uidIdx < parts.length) {
          uid = parts[uidIdx];
          console.log(`mpWebhook: uid encontrado por pending_payment (paymentId ${paymentId}): ${uid}`);
          return uid;
        }
      }
    }
  }
  console.error(`mpWebhook: ERRO - Usuário não localizado no banco. paymentId=${paymentId}, external_reference=${extRef}, email=${email}, metadata=${JSON.stringify(meta)}`);
  return null;
}

/** Campo indexado no Firestore para o painel admin filtrar por período (evita ler todos os pagamentos). */
function mpDateApprovedTimestamp(payment) {
  if (!payment || !payment.date_approved) {
    return admin.firestore.FieldValue.serverTimestamp();
  }
  const d = new Date(payment.date_approved);
  if (Number.isNaN(d.getTime())) {
    return admin.firestore.FieldValue.serverTimestamp();
  }
  return admin.firestore.Timestamp.fromDate(d);
}

/** Helper: processa um pagamento e grava em mp_payments + atualiza licença do usuário.
 *  @param overrideUid - quando informado (ex.: sync por email), força este uid para ativação.
 *  @param options.bypassIntegrationFilter - só uso admin: aplica mesmo sem marcadores do checkout (evitar depósitos use false).
 *  Fast path: se status !== "approved", só grava registro mínimo em mp_payments e retorna (sem resolveUid nem transaction). */
async function processMpPayment(payment, overrideUid = null, options = {}) {
  const status = payment.status || "pending";
  const mpCfg = await getMpConfig();
  const splitSnapshot = buildPaymentSplitSnapshot(payment, mpCfg);
  if (status !== "approved") {
    await admin.firestore().collection("mp_payments").doc(String(payment.id)).set(
      {
        status,
        raw: payment,
        transaction_amount: payment.transaction_amount ?? null,
        currency_id: payment.currency_id || null,
        ...splitSnapshot,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    return;
  }

  if (!options.bypassIntegrationFilter) {
    const fromCt = await isMercadoPagoPaymentFromControleTotalApp(payment);
    if (!fromCt) {
      console.log(
        `processMpPayment: ignorando pagamento ${payment.id} — não é checkout/PIX Controle Total (ex.: depósito ou cobrança avulsa na mesma conta Mercado Pago).`,
      );
      await admin
        .firestore()
        .collection("mp_payments")
        .doc(String(payment.id))
        .set(
          {
            status,
            licenseRelevant: false,
            skippedNonIntegration: true,
            skipReason: "not_controletotal_checkout",
            transaction_amount: payment.transaction_amount ?? null,
            currency_id: payment.currency_id || null,
            ...splitSnapshot,
            dateApprovedAt: mpDateApprovedTimestamp(payment),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            uid: admin.firestore.FieldValue.delete(),
            plan: admin.firestore.FieldValue.delete(),
            planCode: admin.firestore.FieldValue.delete(),
            licenseDays: admin.firestore.FieldValue.delete(),
            promoId: admin.firestore.FieldValue.delete(),
            isOutgoing: admin.firestore.FieldValue.delete(),
          },
          { merge: true },
        );
      return;
    }
  }

  const meta = getPaymentMetadata(payment);
  const priceMap = await loadMpPriceByPlanMerged();
  let uid = overrideUid || meta.uid || meta.userId || meta.user_id || meta.firebase_uid || (payment.external_reference || "").toString().trim() || null;
  if (!uid) uid = await resolveUidFromPayment(payment, { allowEmailFallback: !!options.bypassIntegrationFilter });
  if (!uid) {
    console.error(`mpWebhook: ERRO CRÍTICO - Pagamento aprovado (${payment.id}) mas usuário não encontrado no Firestore. external_reference=${payment.external_reference}, payer.email=${payment.payer?.email}`);
  }
  let planCode = (meta.planCode || meta.plan_code || "").toString().trim() || null;
  if (!planCode && payment.transaction_amount != null) {
    planCode = inferPlanCodeFromAmount(payment.transaction_amount, priceMap) || "premium_monthly";
  }
  planCode = planCode || "premium_monthly";
  const planConfig = getPlanConfig(planCode, priceMap);
  const plan = meta.plan || planConfig.plan;

  // Detectar se o pagador é admin (saída da conta: você pagou para outra pessoa) — não contar como recebimento.
  let isOutgoing = false;
  if (uid) {
    const userSnap = await admin.firestore().doc(`users/${uid}`).get();
    const userData = userSnap.exists ? userSnap.data() : {};
    const role = (userData.role || "").toString();
    const userPlan = (userData.plan || userData.licensePlan || "").toString().toLowerCase();
    const isAdmin = role === "admin" || role === "master";
    if (isAdmin) {
      isOutgoing = true;
      console.log(`Pagamento ${payment.id} marcado como SAÍDA (isOutgoing): uid ${uid} é admin. Não conta em recebimentos.`);
    }
  }

  await admin.firestore().collection("mp_payments").doc(String(payment.id)).set(
    {
      uid: uid || null,
      plan,
      planCode,
      status,
      raw: payment,
      transaction_amount: payment.transaction_amount ?? null,
      currency_id: payment.currency_id || null,
      ...splitSnapshot,
      dateApprovedAt: mpDateApprovedTimestamp(payment),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...(isOutgoing ? { isOutgoing: true } : {}),
    },
    { merge: true }
  );

  // Quando é saída (admin pagando), NÃO ativar licença no seu usuário.
  if (isOutgoing) {
    return;
  }

  if (uid) {
    const paymentPlanNormalized = normalizeMercadoPagoPlanKey(planCode);
    if (isExtraBankPlanCode(paymentPlanNormalized)) {
      await processExtraBankConnectionEntitlement(payment, uid, paymentPlanNormalized, priceMap);
      return;
    }

    const promoIdRaw = (meta.promoId || meta.promotion_id || "").toString().trim();
    let finalPlanCode = planCode;
    let licenseDays = computeStandardLicenseDays(planCode);
    let appliedPromoId = null;

    const userRef = admin.firestore().doc(`users/${uid}`);
    const licensePaymentRef = admin.firestore().doc(`users/${uid}/license_payments/${payment.id}`);

    const alreadyProcessed = await admin.firestore().runTransaction(async (transaction) => {
      const lpSnap = await transaction.get(licensePaymentRef);
      if (lpSnap.exists) return true;

      finalPlanCode = planCode;
      licenseDays = computeStandardLicenseDays(planCode);
      appliedPromoId = null;

      if (promoIdRaw) {
        const promoRef = admin.firestore().collection("promotions").doc(promoIdRaw);
        const promoSnap = await transaction.get(promoRef);
        const ev = evaluatePromotionForPayment(promoSnap, payment.transaction_amount, Date.now(), priceMap);
        if (ev.ok) {
          finalPlanCode = ev.planCode;
          licenseDays = ev.durationDays;
          appliedPromoId = promoIdRaw;
          transaction.update(promoRef, {
            quantitySold: admin.firestore.FieldValue.increment(1),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        } else {
          console.warn(`processMpPayment: promoção "${promoIdRaw}" não aplicada (${ev.reason}); usando extensão padrão do plano.`);
        }
      }

      const planCfg = getPlanConfig(finalPlanCode, priceMap);
      const planForUser = planCfg.plan;

      const userSnap = await transaction.get(userRef);
      const userData = userSnap.exists ? userSnap.data() : {};
      const existing = userData.licenseExpiresAt;
      const now = new Date();
      let baseDayStart;
      if (existing) {
        const dt = existing.toDate ? existing.toDate() : (existing instanceof Date ? existing : new Date((existing.seconds || 0) * 1000));
        const jaVenceu = dt.getTime() < now.getTime();
        baseDayStart = jaVenceu ? startOfDayBrasilia(now) : startOfDayBrasilia(dt);
      } else {
        baseDayStart = startOfDayBrasilia(now);
      }
      baseDayStart.setUTCDate(baseDayStart.getUTCDate() + licenseDays);
      const novaDataExpiracao = admin.firestore.Timestamp.fromDate(endOfDayBrasilia(baseDayStart));
      const graceDayStart = new Date(baseDayStart.getTime());
      graceDayStart.setUTCDate(graceDayStart.getUTCDate() + 3);
      const licenseValidUntilIncludingGrace = admin.firestore.Timestamp.fromDate(endOfDayBrasilia(graceDayStart));

      transaction.set(userRef, {
        plan: planForUser,
        planStatus: "active",
        licenseExpiresAt: novaDataExpiracao,
        licenseValidUntilIncludingGrace,
        lastPaymentId: String(payment.id),
        lastPaymentDate: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      transaction.set(licensePaymentRef, {
        plan: planForUser,
        planCode: finalPlanCode,
        status,
        amount: payment.transaction_amount,
        currency: payment.currency_id,
        paidAt: payment.date_approved || null,
        rawId: payment.id,
        licenseDays,
        ...(appliedPromoId ? { promoId: appliedPromoId } : {}),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      console.log(
        `Sucesso: Licença do usuário ${uid} estendida até ${endOfDayBrasilia(baseDayStart).toISOString()} (BRT, +${licenseDays} dias, plano ${finalPlanCode}${appliedPromoId ? `, promo ${appliedPromoId}` : ""})`
      );
      return false;
    });

    if (alreadyProcessed) {
      console.log(`Pagamento ${payment.id} já processado para ${uid}; ignorado (idempotência).`);
    } else {
      const cfg = getPlanConfig(finalPlanCode, priceMap);
      await admin
        .firestore()
        .collection("mp_payments")
        .doc(String(payment.id))
        .set(
          {
            planCode: finalPlanCode,
            plan: cfg.plan,
            licenseDays,
            ...(appliedPromoId ? { promoId: appliedPromoId } : {}),
          },
          { merge: true }
        );

      if (finalPlanCode === "premium_pro_annual" && cfg.plan === "premium_pro") {
        try {
          await admin.firestore().collection("users").doc(uid).collection("notifications").add({
            title: "Parabéns! Você agora é Premium PRO",
            body: "Suas finanças estão no piloto automático. Aproveite Open Finance e automação no Controle Total App! 🚀",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            data: { type: "premium_pro_annual_welcome" },
          });
        } catch (e) {
          console.warn("mpWebhook: falha ao criar notificação Premium PRO anual:", e && e.message);
        }
      }
    }
  }
}

/** Admin: busca um pagamento pelo ID no Mercado Pago e atualiza mp_payments com payer/uid (para identificar quem pagou quando o webhook não trouxe dados). */
exports.ctFetchMpPaymentById = onCall(async (req) => {
  if (!req.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
  }
  await requireAdminPanel(req.auth.uid);
  const paymentId = String(req.data?.paymentId ?? req.data?.id ?? "").trim();
  if (!paymentId || !/^\d+$/.test(paymentId)) {
    throw new functions.https.HttpsError("invalid-argument", "Informe paymentId (número do pagamento no MP).");
  }
  const { accessToken } = await getMpConfig();
  if (!accessToken) {
    throw new functions.https.HttpsError("failed-precondition", "Mercado Pago não configurado.");
  }
  const res = await fetch(`https://api.mercadopago.com/v1/payments/${paymentId}`, {
    method: "GET",
    headers: mpHeaders(accessToken),
  });
  if (!res.ok) {
    const errText = await res.text();
    throw new functions.https.HttpsError("not-found", `Pagamento não encontrado no MP: ${errText.slice(0, 200)}`);
  }
  const payment = await res.json();
  const fromCt = await isMercadoPagoPaymentFromControleTotalApp(payment);
  if (!fromCt) {
    await processMpPayment(payment);
    const email = (payment.payer?.email || "").toString().trim();
    const name = (payment.payer?.first_name || payment.payer?.name || "").toString().trim();
    return {
      ok: true,
      paymentId,
      skippedNonIntegration: (payment.status || "") === "approved",
      uid: null,
      email: email || null,
      name: name || null,
      transaction_amount: payment.transaction_amount,
      message:
        (payment.status || "") === "approved"
          ? "Pagamento não é do checkout Controle Total (ex.: depósito na conta MP). Registrado como ignorado para licença."
          : "Pagamento consultado; não é integração Controle Total — sem vínculo de licença.",
    };
  }
  const priceMap = await loadMpPriceByPlanMerged();
  let uid = await resolveUidFromPayment(payment);
  const metaPc = (payment.metadata?.planCode || "").toString().trim();
  const inferredPc = inferPlanCodeFromAmount(payment.transaction_amount, priceMap) || "premium_monthly";
  const resolvedPlanCode = metaPc || inferredPc;
  const fetchMerge = {
    uid: uid || null,
    plan: payment.metadata?.plan || getPlanConfig(resolvedPlanCode, priceMap).plan,
    planCode: resolvedPlanCode,
    status: payment.status,
    raw: payment,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (payment.status === "approved") {
    fetchMerge.dateApprovedAt = mpDateApprovedTimestamp(payment);
  }
  await admin.firestore().collection("mp_payments").doc(paymentId).set(fetchMerge, { merge: true });
  if (uid && payment.status === "approved") {
    await processMpPayment(payment, uid);
  }
  const email = (payment.payer?.email || "").toString().trim();
  const name = (payment.payer?.first_name || payment.payer?.name || "").toString().trim();
  return {
    ok: true,
    paymentId,
    uid: uid || null,
    email: email || null,
    name: name || null,
    transaction_amount: payment.transaction_amount,
  };
});

/** Sincronização automática: a cada 15 min busca pagamentos recentes no MP e atualiza licenças (inclusive pendentes que viraram aprovados). */
exports.mpSyncPaymentsScheduled = onSchedule(
  { schedule: "every 15 minutes", region: "us-central1" },
  async () => {
    try {
      await runMpSyncPayments();
    } catch (e) {
      console.error("mpSyncPaymentsScheduled:", e?.message || e);
    }
  }
);

/** Sincroniza todos os pagamentos dos últimos 7 dias. Usa formato NOW do MP e paginação. */
async function runMpSyncPayments() {
  const { accessToken } = await getMpConfig();
  if (!accessToken) return { ok: false, error: "Mercado Pago não configurado." };
  let processed = 0;
  const processedIds = new Set();
  let offset = 0;
  const limit = 50;
  const ranges = [
    { range: "date_created", begin: "NOW-30DAYS", end: "NOW" },
    { range: "date_last_updated", begin: "NOW-7DAYS", end: "NOW" },
    { range: "date_approved", begin: "NOW-7DAYS", end: "NOW" },
  ];
  for (const { range, begin, end } of ranges) {
    offset = 0;
    for (;;) {
      const params = new URLSearchParams({
        sort: range,
        criteria: "desc",
        range,
        begin_date: begin,
        end_date: end,
        limit: String(limit),
        offset: String(offset),
      });
      const url = `https://api.mercadopago.com/v1/payments/search?${params}`;
      const res = await fetch(url, { headers: mpHeaders(accessToken) });
      if (!res.ok) {
        const errText = await res.text();
        console.warn("runMpSyncPayments API error:", res.status, errText);
        break;
      }
      const data = await res.json();
      const results = Array.isArray(data) ? data : (data.results || []);
      if (results.length === 0) break;
      for (const payment of results) {
        if (!payment.id) continue;
        if (processedIds.has(String(payment.id))) continue;
        processedIds.add(String(payment.id));
        await processMpPayment(payment);
        processed++;
      }
      if (results.length < limit) break;
      offset += limit;
      if (offset >= 1000) break;
    }
  }
  return { ok: true, processed };
}

exports.ctSyncAllMpPayments = onCall(async (req) => {
  if (!req.auth) throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
  await requireAdminPanel(req.auth.uid);
  const result = await runMpSyncPayments();
  if (!result.ok) throw new functions.https.HttpsError("failed-precondition", result.error || "Erro ao sincronizar.");
  return { ok: true, processed: result.processed, message: `${result.processed} pagamento(s) processado(s).` };
});

/** Verifica status do pagamento PIX pendente do usuário. Chamado ao abrir o app após gerar PIX. */
exports.ctCheckMyPayment = onCall(async (req) => {
  if (!req.auth) throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
  const uid = req.auth.uid;
  const pendingSnap = await admin.firestore().doc(`users/${uid}/pending_payment/current`).get();
  const pending = pendingSnap.exists ? pendingSnap.data() : null;
  const paymentId = (pending?.paymentId || req.data?.paymentId || "").toString().trim();
  if (!paymentId || !/^\d+$/.test(paymentId)) {
    return { checked: true, hasPending: false };
  }
  const { accessToken } = await getMpConfig();
  if (!accessToken) return { checked: false, error: "Mercado Pago não configurado." };
  const paymentRes = await fetch(`https://api.mercadopago.com/v1/payments/${paymentId}`, {
    headers: mpHeaders(accessToken),
  });
  if (!paymentRes.ok) {
    return { checked: true, hasPending: true, status: "unknown", error: "Pagamento não encontrado no Mercado Pago." };
  }
  const payment = await paymentRes.json();
  await processMpPayment(payment);
  const status = payment.status;
  if (status === "approved") {
    await admin.firestore().doc(`users/${uid}/pending_payment/current`).delete();
    return { checked: true, hasPending: false, status: "approved", activated: true };
  }
  return { checked: true, hasPending: true, status: status || "pending" };
});

/**
 * Pluggy / Open Finance: connect token (só servidor). Lê Client ID/Secret em `app_config/pluggy`.
 * Retorno alinhado ao widget: { accessToken } (nome usado pelo react-pluggy-connect / app).
 */
exports.ctCreatePluggyConnectToken = onCall(async (req) => {
  if (!req.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
  }
  const uid = req.auth.uid;
  const redirectFromClient = (req.data?.redirectUri || req.data?.oauthRedirectUri || "").toString().trim();

  const callerSnap = await admin.firestore().doc(`users/${uid}`).get();
  const caller = callerSnap.exists ? callerSnap.data() || {} : {};
  const role = (caller.role || "").toString().toLowerCase();
  const isAdminUser = role === "admin" || role === "master";
  const plan = (caller.plan || "").toString().toLowerCase().trim();
  const partnershipId = (caller.partnershipId || "").toString().trim();
  const planIsPro = plan === "premium_pro" || plan.startsWith("premium_pro_");
  const isPartnershipOrAssegoRetailTier =
    !planIsPro && (partnershipId.length > 0 || plan === "premium_assego");
  const flagsPro = caller.premiumPro === true || caller.isPremiumPro === true;
  /** `plan: premium` (pago clássico) com assinatura ativa e data/carencia alinhada ao app — não assego. */
  const legacyPremiumOpenFinance =
    plan === "premium" && userDocLicenseOkForOpenFinance(caller);
  const allowPluggy = isPartnershipOrAssegoRetailTier
    ? planIsPro
    : planIsPro || flagsPro || legacyPremiumOpenFinance;
  if (!allowPluggy && !isAdminUser) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Open Finance (Pluggy) está disponível no plano Premium PRO.",
    );
  }

  try {
    const cfg = await getPluggyConfigFromFirestore();
    if (!cfg.clientId || !cfg.clientSecret) {
      return {
        ok: false,
        configured: false,
        accessToken: null,
        connectUrl: null,
        widgetUrl: null,
        includeSandbox: false,
        message:
          "Pluggy não configurado. No painel Admin > Integração Pluggy, salve Client ID e Client Secret (dashboard.pluggy.ai).",
      };
    }

    const apiKey = await pluggyCreateApiKey(cfg.clientId, cfg.clientSecret);
    const oauthRedirect = redirectFromClient || cfg.oauthRedirectUri || "";
    const accessToken = await pluggyCreateConnectToken(apiKey, {
      clientUserId: uid,
      webhookUrl: cfg.defaultWebhookUrl || undefined,
      oauthRedirectUri: oauthRedirect || undefined,
    });

    return {
      ok: true,
      configured: true,
      accessToken,
      connectUrl: null,
      widgetUrl: null,
      includeSandbox: !!cfg.includeSandbox,
      message: null,
    };
  } catch (e) {
    console.error("ctCreatePluggyConnectToken:", e?.message || e);
    throw new functions.https.HttpsError(
      "internal",
      (e && e.message) || "Falha ao criar connect token na Pluggy. Verifique credenciais e logs.",
    );
  }
});

/**
 * Webhook Pluggy (HTTPS). Configure esta URL no dashboard Pluggy (não use o endpoint do Mercado Pago).
 * Evento `transactions/created`: busca transações em [createdTransactionsLink] e grava em `users/{uid}/transactions`.
 */
exports.pluggyWebhook = onRequest({ cors: true, region: "us-central1" }, async (req, res) => {
  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return;
  }
  if (req.method !== "POST") {
    res.status(405).send("Method Not Allowed");
    return;
  }
  let body = req.body;
  if (typeof body === "string") {
    try {
      body = JSON.parse(body);
    } catch (_) {
      body = {};
    }
  }
  try {
    const event = (body && body.event) || "";
    if (event !== "transactions/created") {
      res.status(200).json({ received: true, ignored: event || "empty" });
      return;
    }
    const itemId = (body.itemId || body.id || "").toString().trim();
    const link = (body.createdTransactionsLink || "").toString().trim();
    if (!itemId || !link) {
      console.warn("pluggyWebhook: transactions/created sem itemId ou createdTransactionsLink");
      res.status(200).json({ received: true, warn: "missing_item_or_link" });
      return;
    }
    const uid = await resolveUidByPluggyItemId(itemId);
    if (!uid) {
      console.warn("pluggyWebhook: nenhum bank_connections com itemId", itemId);
      res.status(200).json({ received: true, warn: "no_user_for_item" });
      return;
    }
    const cfg = await getPluggyConfigFromFirestore();
    if (!cfg.clientId || !cfg.clientSecret) {
      res.status(200).json({ received: true, warn: "pluggy_credentials_missing" });
      return;
    }
    const apiKey = await pluggyCreateApiKey(cfg.clientId, cfg.clientSecret);
    const pageRes = await fetch(link, {
      headers: { "X-API-KEY": apiKey, Accept: "application/json" },
    });
    if (!pageRes.ok) {
      const t = await pageRes.text();
      console.error("pluggyWebhook: GET transactions falhou", pageRes.status, t.slice(0, 400));
      res.status(200).json({ received: true, warn: "pluggy_fetch_failed" });
      return;
    }
    const json = await pageRes.json();
    const results = json.results || json.data || [];
    const batch = admin.firestore().batch();
    let n = 0;
    /** @type {{ type: string, category: string }[]} */
    const categoryEnsureQueue = [];
    for (const tx of results) {
      const ext = String(tx.id || tx.transactionId || "").trim();
      if (!ext) continue;
      const docId = `pluggy_${crypto.createHash("sha256").update(ext).digest("hex").slice(0, 40)}`;
      const ref = admin.firestore().doc(`users/${uid}/transactions/${docId}`);
      const mapped = mapPluggyTransactionToFirestore(tx);
      batch.set(ref, mapped, { merge: true });
      categoryEnsureQueue.push({ type: mapped.type, category: mapped.category });
      n++;
      if (n >= 400) break;
    }
    if (n > 0) {
      await batch.commit();
      const seenCat = new Set();
      for (const row of categoryEnsureQueue) {
        const key = `${row.type}|${row.category}`;
        if (seenCat.has(key)) continue;
        seenCat.add(key);
        await ensureUserCustomCategoryIfNeeded(uid, row.type, row.category);
      }
    }
    res.status(200).json({ received: true, upserted: n });
  } catch (e) {
    console.error("pluggyWebhook:", e?.message || e);
    res.status(500).json({ error: "internal" });
  }
});

/**
 * PATCH /items/{id} na Pluggy — sync agendado 2x/dia (horário de Brasília) para custo previsível.
 * Atualiza lastServerScheduledSync* em bank_connections e openFinanceLastScheduledSyncAt no user.
 * Ver documentação Pluggy: limite de frequência por item no plano; erros (MFA, credenciais) gravados no doc.
 */
async function pluggyPatchItemUpdate(apiKey, itemId) {
  const id = (itemId || "").toString().trim();
  if (!id || id.startsWith("pending_")) return { ok: false, skip: true, error: "sem_item" };
  const res = await fetch(`https://api.pluggy.ai/items/${encodeURIComponent(id)}`, {
    method: "PATCH",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      "X-API-KEY": apiKey,
    },
    body: JSON.stringify({}),
  });
  const text = await res.text();
  let j = {};
  try {
    j = JSON.parse(text);
  } catch (_) {}
  if (!res.ok) {
    const msg = (j && j.message) || text.slice(0, 300) || `HTTP ${res.status}`;
    return { ok: false, error: msg };
  }
  return { ok: true, data: j };
}

exports.pluggyScheduledItemsSync = onSchedule(
  {
    schedule: "0 12,23 * * *",
    timeZone: "America/Sao_Paulo",
    region: "us-central1",
    memory: "512MiB",
    timeoutSeconds: 540,
  },
  async () => {
    const pluggyDoc = await admin.firestore().doc("app_config/pluggy").get();
    const pcfg = pluggyDoc.exists ? pluggyDoc.data() || {} : {};
    if (pcfg.scheduledItemSyncEnabled === false) {
      console.log("pluggyScheduledItemsSync: desligado em app_config/pluggy");
      return;
    }
    const cfg = await getPluggyConfigFromFirestore();
    if (!cfg.clientId || !cfg.clientSecret) {
      console.warn("pluggyScheduledItemsSync: Pluggy sem clientId/Secret");
      return;
    }
    const snap = await admin.firestore().collectionGroup("bank_connections").get();
    const byItem = new Map();
    for (const doc of snap.docs) {
      const d = doc.data() || {};
      const itemId = (d.itemId || "").toString().trim();
      const st = (d.status || "").toString().toLowerCase();
      if (!itemId || itemId.startsWith("pending_")) continue;
      if (st !== "connected" && st !== "ready") continue;
      if ((d.provider || "pluggy").toString().toLowerCase() !== "pluggy") continue;
      if (!byItem.has(itemId)) byItem.set(itemId, []);
      byItem.get(itemId).push(doc.ref);
    }
    if (byItem.size === 0) {
      console.log("pluggyScheduledItemsSync: nenhuma conexão elegível");
      return;
    }
    let apiKey;
    try {
      apiKey = await pluggyCreateApiKey(cfg.clientId, cfg.clientSecret);
    } catch (e) {
      console.error("pluggyScheduledItemsSync: auth Pluggy", e?.message || e);
      return;
    }
    const uidsTouched = new Set();
    let okCount = 0;
    let failCount = 0;
    for (const [itemId, refs] of byItem.entries()) {
      const r = await pluggyPatchItemUpdate(apiKey, itemId);
      if (r.skip) continue;
      if (r.ok) okCount += 1;
      else failCount += 1;
      const ts = admin.firestore.FieldValue.serverTimestamp();
      for (const ref of refs) {
        const parts = ref.path.split("/");
        if (parts[0] === "users" && parts.length >= 2) uidsTouched.add(parts[1]);
        if (r.ok) {
          await ref.set(
            {
              lastServerScheduledSyncAt: ts,
              lastServerScheduledSyncOk: true,
              lastServerScheduledSyncError: admin.firestore.FieldValue.delete(),
              lastSync: ts,
            },
            { merge: true }
          );
        } else {
          await ref.set(
            {
              lastServerScheduledSyncAt: ts,
              lastServerScheduledSyncOk: false,
              lastServerScheduledSyncError: (r.error || "erro").toString().slice(0, 220),
            },
            { merge: true }
          );
        }
      }
    }
    const nowTs = admin.firestore.FieldValue.serverTimestamp();
    for (const uid of uidsTouched) {
      try {
        await admin.firestore().doc(`users/${uid}`).set(
          {
            openFinanceLastScheduledSyncAt: nowTs,
            openFinanceScheduledSyncSlotsBrasilia: "12:00 e 23:00",
            updatedAt: nowTs,
          },
          { merge: true }
        );
      } catch (e) {
        console.warn("pluggyScheduledItemsSync: user patch", uid, e?.message || e);
      }
    }
    console.log(
      `pluggyScheduledItemsSync: itens únicos=${byItem.size} ok~${okCount} falha~${failCount} users=${uidsTouched.size}`,
    );
  }
);

/** Sincroniza manualmente um pagamento do Mercado Pago. Útil quando o webhook não disparou.
 *  Chame com o ID numérico do pagamento (ex.: 147204656312). Apenas admin. */
exports.ctSyncMpPayment = onCall(async (req) => {
  if (!req.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
  }
  await requireAdminPanel(req.auth.uid);

  const paymentId = (req.data?.paymentId || req.data?.payment_id || "").toString().trim();
  if (!paymentId || !/^\d+$/.test(paymentId)) {
    throw new functions.https.HttpsError("invalid-argument", "Informe o ID numérico do pagamento (ex.: 147204656312). Encontre no app Mercado Pago ou no painel do vendedor.");
  }

  const { accessToken } = await getMpConfig();
  if (!accessToken) {
    throw new functions.https.HttpsError("failed-precondition", "Mercado Pago não configurado.");
  }

  const paymentRes = await fetch(`https://api.mercadopago.com/v1/payments/${paymentId}`, {
    headers: mpHeaders(accessToken),
  });

  if (!paymentRes.ok) {
    const errText = await paymentRes.text();
    let msg = "Pagamento não encontrado. Verifique o ID no Mercado Pago.";
    try {
      const err = JSON.parse(errText);
      if (err.message) msg = err.message;
    } catch (_) {}
    throw new functions.https.HttpsError("not-found", msg);
  }

  const payment = await paymentRes.json();
  const force = req.data?.force === true || req.data?.forcar === true;
  const fromCt = await isMercadoPagoPaymentFromControleTotalApp(payment);
  if (!fromCt && !force) {
    await processMpPayment(payment);
    const status = payment.status;
    return {
      ok: true,
      paymentId: payment.id,
      status,
      uid: null,
      plan: null,
      skippedNonIntegration: status === "approved",
      message:
        status === "approved"
          ? "Pagamento aprovado, mas não é do checkout Controle Total (ex.: depósito). Nada alterado. Se for exceção legítima, chame com force: true."
          : `Pagamento registrado (status: ${status}).`,
    };
  }
  await processMpPayment(payment, null, { bypassIntegrationFilter: force });
  const uid = await resolveUidFromPayment(payment, { allowEmailFallback: force });
  const status = payment.status;
  const meta = getPaymentMetadata(payment);
  const plan = meta.plan || "premium";
  return {
    ok: true,
    paymentId: payment.id,
    status,
    uid: uid || null,
    plan,
    message: status === "approved" && uid
      ? `Pagamento sincronizado. Licença ativada para o usuário.`
      : `Pagamento registrado no painel (status: ${status}).`,
  };
});

/** Retorna configuração MP completa (inclui secure_config) para o painel admin. */
exports.ctGetMpAdminConfig = onCall(async (req) => {
  if (!req.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
  }
  await requireAdminPanel(req.auth.uid);
  const cfg = await loadMpAdminConfigFromDb();
  return { ok: true, ...cfg };
});

/** Salva configuração dual Mercado Pago (Raihom + Johnathan), split e preços. Apenas admin. */
exports.ctSaveMpAdminConfig = onCall(async (req) => {
  if (!req.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
  }
  await requireAdminPanel(req.auth.uid);

  const d = req.data || {};
  const owner = d.owner || {};
  const partner = d.partner || {};
  const splitIn = d.split || {};
  const prices = d.prices || {};
  const db = admin.firestore();
  const now = admin.firestore.FieldValue.serverTimestamp();
  const existing = await loadMpAdminConfigFromDb();

  const ownerAccess = pickMpField(
    owner.accessToken,
    owner.access_token,
    existing.owner.accessToken,
  );
  if (!ownerAccess) {
    throw new functions.https.HttpsError("invalid-argument", "Access Token de Raihom Barbosa é obrigatório.");
  }

  const ownerPublicKey = pickMpField(owner.publicKey, owner.public_key, existing.owner.publicKey);
  const ownerClientId = pickMpField(
    owner.clientId,
    owner.client_id,
    existing.owner.clientId,
    MP_WISDOMAPP_CLIENT_ID,
  );
  const ownerClientSecret = pickMpField(
    owner.clientSecret,
    owner.client_secret,
    existing.owner.clientSecret,
  );
  const ownerWebhookUrl = pickMpField(
    owner.webhookUrl,
    owner.webhook_url,
    existing.owner.webhookUrl,
    MP_WISDOMAPP_WEBHOOK_URL,
  );
  const ownerWebhookSecret = pickMpField(
    owner.webhookSecret,
    owner.webhook_secret,
    existing.owner.webhookSecret,
  );
  const ownerCollectorId = pickMpField(
    owner.collectorId,
    owner.collector_id,
    existing.owner.collectorId,
  );

  const partnerAccess = pickMpField(
    partner.accessToken,
    partner.access_token,
    existing.partner.accessToken,
  );
  const partnerPublicKey = pickMpField(
    partner.publicKey,
    partner.public_key,
    existing.partner.publicKey,
  );
  const partnerClientId = pickMpField(
    partner.clientId,
    partner.client_id,
    existing.partner.clientId,
  );

  const splitEnabled = splitIn.enabled === true || splitIn.splitEnabled === true;
  const splitMode = (splitIn.mode || splitIn.splitMode || "percent").toString().trim().toLowerCase() === "fixed"
    ? "fixed"
    : "percent";
  const ownerSharePercent = clampPercent(splitIn.ownerSharePercent ?? 50, 50);
  const partnerSharePercent = clampPercent(
    splitIn.partnerSharePercent ?? 100 - ownerSharePercent,
    50,
  );
  const referenceGross = roundMoney(toNumberSafe(splitIn.referenceGross ?? prices.premium_monthly ?? 49.9, 49.9));
  const ownerShareFixed = splitIn.ownerShareFixed != null
    ? roundMoney(toNumberSafe(splitIn.ownerShareFixed, 0))
    : null;
  const partnerShareFixed = splitIn.partnerShareFixed != null
    ? roundMoney(toNumberSafe(splitIn.partnerShareFixed, 0))
    : null;
  const partnerCollectorId = pickMpField(
    partner.collectorId,
    partner.collector_id,
    splitIn.partnerCollectorId,
    existing.partner.collectorId,
  );

  await db.collection("settings").doc("mercadopago").set(
    {
      public_key: ownerPublicKey,
      publicKey: ownerPublicKey,
      access_token: ownerAccess,
      accessToken: ownerAccess,
      client_id: ownerClientId,
      clientId: ownerClientId,
      client_secret: ownerClientSecret,
      clientSecret: ownerClientSecret,
      webhook_url: ownerWebhookUrl,
      webhookUrl: ownerWebhookUrl,
      webhook_secret: ownerWebhookSecret,
      webhookSecret: ownerWebhookSecret,
      collector_id: ownerCollectorId,
      collectorId: ownerCollectorId,
      ownerDisplayName: "Raihom Barbosa",
      updatedAt: now,
      updatedByUid: req.auth.uid,
    },
    { merge: true },
  );

  await db.collection("settings").doc("mercadopago_partner").set(
    {
      public_key: partnerPublicKey,
      publicKey: partnerPublicKey,
      access_token: partnerAccess,
      accessToken: partnerAccess,
      client_id: partnerClientId,
      clientId: partnerClientId,
      collector_id: partnerCollectorId,
      collectorId: partnerCollectorId,
      partnerDisplayName: "Johnathan Tarley",
      updatedAt: now,
      updatedByUid: req.auth.uid,
    },
    { merge: true },
  );

  const projectPayload = {
    projectName: "WISDOMAPP",
    clientId: ownerClientId,
    splitEnabled,
    splitMode,
    ownerSharePercent,
    partnerSharePercent,
    ownerShareFixed,
    partnerShareFixed,
    referenceGross,
    ownerLabel: "Raihom Barbosa",
    partnerLabel: "Johnathan Tarley",
    ownerDisplayName: "Raihom Barbosa",
    partnerDisplayName: "Johnathan Tarley",
    updatedAt: now,
    updatedByUid: req.auth.uid,
  };
  await db.collection("mp_project_config").doc("main").set(projectPayload, { merge: true });

  const securePayload = {
    accessToken: ownerAccess,
    publicKey: ownerPublicKey,
    clientId: ownerClientId,
    clientSecret: ownerClientSecret,
    webhookSecret: ownerWebhookSecret,
    webhookUrl: ownerWebhookUrl,
    partnerAccessToken: partnerAccess,
    partnerPublicKey: partnerPublicKey,
    partnerClientId: partnerClientId,
    partnerCollectorId,
    splitEnabled,
    splitMode,
    ownerSharePercent,
    partnerSharePercent,
    ownerShareFixed,
    partnerShareFixed,
    referenceGross,
    configured: true,
    updatedAt: now,
  };
  await db.collection("secure_config").doc("mercado_pago").set(securePayload, { merge: true });

  if (prices.premium_monthly != null || prices.premium_annual != null) {
    const premM = roundMoney(toNumberSafe(prices.premium_monthly, 49.9));
    const premA = roundMoney(toNumberSafe(prices.premium_annual, 478.8));
    await db.collection("app_config").doc("mp_checkout_prices").set(
      {
        premium_monthly: premM,
        premium_annual: premA,
        premium_pro_monthly: roundMoney(toNumberSafe(prices.premium_pro_monthly, premM)),
        premium_pro_annual: roundMoney(toNumberSafe(prices.premium_pro_annual, premA)),
        extra_bank_connection_monthly: roundMoney(
          toNumberSafe(prices.extra_bank_connection_monthly, 9.9),
        ),
        extra_bank_connection_annual: roundMoney(
          toNumberSafe(prices.extra_bank_connection_annual, 99.9),
        ),
        updatedAt: now,
        updatedByUid: req.auth.uid,
      },
      { merge: true },
    );

    if (d.syncLandingTexts === true) {
      const fmt = (v) => `R$ ${v.toFixed(2).replace(".", ",")}`;
      await db.collection("landing_content").doc("main").set(
        {
          divPremiumPriceMonthly: fmt(premM),
          divPremiumPriceAnnual: fmt(premA),
          divPremiumProPriceMonthly: fmt(roundMoney(toNumberSafe(prices.premium_pro_monthly, premM))),
          divPremiumProPriceAnnual: fmt(roundMoney(toNumberSafe(prices.premium_pro_annual, premA))),
          updatedAt: now,
        },
        { merge: true },
      );
    }
  }

  _mpConfigCache = null;

  return {
    ok: true,
    message: "Configuração Mercado Pago salva. Apps e checkout usarão os novos valores em até ~1 minuto.",
    splitEnabled,
    splitMode,
  };
});

/** Chave Mestra: reserva de segurança. Consulta o Mercado Pago diretamente e força atualização no banco.
 *  BLINDAGEM 1: Admin (custom claim OU Firestore role). BLINDAGEM 2: Consulta direta na API MP.
 *  BLINDAGEM 3: processMpPayment ativa licença + auditoria (liberado_manualmente, etc.). */
exports.sincronizarManual = onCall(async (req) => {
  if (!req.auth) {
    return { success: false, message: "Acesso restrito. Login obrigatório." };
  }
  const isAdminByClaim = req.auth.token?.admin === true;
  if (!isAdminByClaim) {
    try {
      await requireAdminPanel(req.auth.uid);
    } catch (_) {
      return { success: false, message: "Acesso restrito ao Administrador." };
    }
  }

  const paymentId = (req.data?.paymentId || req.data?.payment_id || "").toString().trim();
  if (!paymentId || !/^\d+$/.test(paymentId)) {
    return { success: false, message: "ID do pagamento é obrigatório." };
  }

  try {
    const { accessToken } = await getMpConfig();
    if (!accessToken) {
      return { success: false, message: "Mercado Pago não configurado." };
    }

    const paymentRes = await fetch(`https://api.mercadopago.com/v1/payments/${paymentId}`, {
      headers: mpHeaders(accessToken),
    });

    if (!paymentRes.ok) {
      const errText = await paymentRes.text();
      let msg = "Erro ao consultar Mercado Pago. Verifique o ID.";
      try {
        const err = JSON.parse(errText);
        if (err.message) msg = err.message;
      } catch (_) {}
      return { success: false, message: msg };
    }

    const payment = await paymentRes.json();

    if (payment.status !== "approved") {
      return {
        success: false,
        message: `O status deste pagamento no Mercado Pago é: ${payment.status}`,
      };
    }

    const uid = await resolveUidFromPayment(payment, { allowEmailFallback: true });
    if (!uid) {
      return {
        success: false,
        message: "Pagamento aprovado, mas ID do usuário não encontrado na referência.",
      };
    }

    await processMpPayment(payment, null, { bypassIntegrationFilter: true });

    const userRef = admin.firestore().doc(`users/${uid}`);
    await userRef.set({
      lastPaymentSyncMethod: "Sincronização Manual ADM",
      lastPaymentSyncAt: admin.firestore.FieldValue.serverTimestamp(),
      liberado_manualmente: true,
      mp_payment_id: paymentId,
    }, { merge: true });
    await admin.firestore().doc(`users/${uid}/license_payments/${payment.id}`).set({
      syncMethod: "Sincronização Manual ADM",
      liberado_manualmente: true,
    }, { merge: true });

    return { success: true, message: `Usuário liberado com sucesso!` };
  } catch (error) {
    console.error("sincronizarManual:", error);
    return { success: false, message: "Erro ao consultar Mercado Pago. Verifique o ID." };
  }
});

/** Sincroniza pagamento PIX do usuário pelo e-mail. Usa o pending_payment salvo ao gerar o PIX. Admin. */
exports.ctSyncMpPaymentByEmail = onCall(async (req) => {
  if (!req.auth) throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
  await requireAdminPanel(req.auth.uid);

  const email = (req.data?.email || req.data?.userEmail || "").toString().trim().toLowerCase();
  if (!email) throw new functions.https.HttpsError("invalid-argument", "Informe o e-mail do usuário (ex.: usuario@email.com).");

  const usersSnap = await admin.firestore().collection("users").where("email", "==", email).limit(1).get();
  if (usersSnap.empty) throw new functions.https.HttpsError("not-found", "Usuário não encontrado com este e-mail.");

  const uid = usersSnap.docs[0].id;
  const pendingSnap = await admin.firestore().doc(`users/${uid}/pending_payment/current`).get();
  const pending = pendingSnap.exists ? pendingSnap.data() : null;
  const paymentId = (pending?.paymentId || "").toString().trim();

  if (!paymentId || !/^\d+$/.test(paymentId)) {
    await runMpSyncPayments();
    // Busca em mp_payments: pagamentos aprovados que possam ser deste usuário (uid null ou payer.email)
    const userData = usersSnap.docs[0].data();
    const userEmail = (userData.email || "").toString().trim().toLowerCase();
    const mpPaymentsSnap = await admin.firestore().collection("mp_payments").where("status", "==", "approved").limit(150).get();
    let activated = false;
    for (const doc of mpPaymentsSnap.docs) {
      const d = doc.data();
      if ((d.status || "") !== "approved") continue;
      const raw = d.raw || {};
      const fromCt = await isMercadoPagoPaymentFromControleTotalApp(raw);
      if (!fromCt) continue;
      const storedUid = (d.uid || "").toString();
      if (storedUid === uid) {
        activated = true;
        break;
      }
      const meta = getPaymentMetadata(raw);
      const metaUid = (meta.uid || raw.external_reference || "").toString();
      if (metaUid === uid) {
        await processMpPayment(raw, uid);
        activated = true;
        break;
      }
    }
    return {
      ok: true,
      noPending: true,
      activated,
      message: activated
        ? "Licença ativada. O pagamento foi encontrado e vinculado ao usuário."
        : "Sincronização executada. Nenhum pagamento aprovado encontrado para este e-mail. Verifique o Mercado Pago ou sincronize pelo ID numérico.",
    };
  }

  const { accessToken } = await getMpConfig();
  if (!accessToken) throw new functions.https.HttpsError("failed-precondition", "Mercado Pago não configurado.");

  const paymentRes = await fetch(`https://api.mercadopago.com/v1/payments/${paymentId}`, {
    headers: mpHeaders(accessToken),
  });

  if (!paymentRes.ok) {
    const errText = await paymentRes.text();
    throw new functions.https.HttpsError("not-found", `Pagamento ${paymentId} não encontrado no Mercado Pago. ${errText.substring(0, 100)}`);
  }

  const payment = await paymentRes.json();
  await processMpPayment(payment);

  const status = payment.status;
  if (status === "approved") {
    await admin.firestore().doc(`users/${uid}/pending_payment/current`).delete();
  }

  const meta = getPaymentMetadata(payment);
  const plan = meta.plan || "premium";
  return {
    ok: true,
    paymentId: payment.id,
    status,
    uid,
    plan,
    message: status === "approved"
      ? `Licença ativada para ${email}.`
      : `Pagamento encontrado (status: ${status}). A licença será ativada quando o pagamento for aprovado.`,
  };
});

/** Scheduled: every day at 9:00 AM — envia e-mail para usuários com licença vencendo em 3 ou 7 dias. */
exports.mpLicenseReminderScheduled = onSchedule(
  { schedule: "0 9 * * *", timeZone: "America/Sao_Paulo", region: "us-central1" },
  async () => {
    try {
      await runLicenseReminderEmails();
    } catch (e) {
      console.error("mpLicenseReminderScheduled:", e?.message || e);
    }
  }
);

async function runLicenseReminderEmails() {
  const db = admin.firestore();
  const now = new Date();
  const todayStart = startOfDayBrasilia(now);
  const in3DaysStart = new Date(todayStart.getTime());
  in3DaysStart.setUTCDate(in3DaysStart.getUTCDate() + 3);
  const startOfDay3 = startOfDayBrasilia(in3DaysStart);
  const in3Days = endOfDayBrasilia(in3DaysStart);
  const in7DaysStart = new Date(todayStart.getTime());
  in7DaysStart.setUTCDate(in7DaysStart.getUTCDate() + 7);
  const startOfDay7 = startOfDayBrasilia(in7DaysStart);
  const in7Days = endOfDayBrasilia(in7DaysStart);

  const snap3 = await db
    .collection("users")
    .where("licenseExpiresAt", ">=", admin.firestore.Timestamp.fromDate(startOfDay3))
    .where("licenseExpiresAt", "<=", admin.firestore.Timestamp.fromDate(in3Days))
    .get();
  const snap7 = await db
    .collection("users")
    .where("licenseExpiresAt", ">=", admin.firestore.Timestamp.fromDate(startOfDay7))
    .where("licenseExpiresAt", "<", admin.firestore.Timestamp.fromDate(startOfDay3))
    .get();

  let sent = 0;
  for (const doc of [...snap3.docs, ...snap7.docs]) {
    const d = doc.data();
    const email = (d.email || "").toString().trim();
    if (!email || !/^[^@]+@[^@]+\.[^@]+$/.test(email)) continue;
    const role = (d.role || "").toString();
    const plan = (d.plan || "").toString().toLowerCase();
    if (role === "admin" || role === "master") continue;

    const exp = d.licenseExpiresAt?.toDate?.() || null;
    const name = (d.name || "").toString().trim() || "Usuário";
    const dd = exp ? String(exp.getDate()).padStart(2, "0") : "";
    const mm = exp ? String(exp.getMonth() + 1).padStart(2, "0") : "";
    const yyyy = exp ? exp.getFullYear() : "";
    const dias = snap3.docs.some((x) => x.id === doc.id) ? 3 : 7;

    const body = `<p>Olá, <strong>${escapeHtml(name)}</strong>!</p>
<p>Sua licença do <strong>Controle Total</strong> vence em <strong>${dias} dias</strong>.</p>
<div class="alert"><strong>📅 Data de vencimento:</strong> ${dd}/${mm}/${yyyy}</div>
<p>Renove seu plano pelo app para manter todas as funcionalidades:</p>
<ul><li>Controle financeiro</li><li>Escalas e plantões</li><li>Calculadora de horas extras</li><li>Agenda e compromissos</li></ul>
<p><a href="${APP_DOMAIN}/escolha-plano" class="btn">Renovar licença</a></p>`;
    const html = buildEmailBase("⚠️ Renovação da licença", body);
    const res = await sendEmailHtml(email, `Controle Total — Licença vence em ${dias} dias`, html);
    if (res.ok) sent++;
  }
  if (sent > 0) console.log(`[mpLicenseReminderScheduled] Enviados ${sent} e-mail(s) de renovação.`);
}

function escapeHtml(s) {
  return String(s || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/** Link seguro para atributo href (escapa & e aspas). */
function escapeAttrUrl(url) {
  return String(url || "")
    .replace(/&/g, "&amp;")
    .replace(/"/g, "&quot;");
}

/**
 * E-mail em massa: link do site oficial (promoção / planos). Admin.
 * Requer settings/email configurado. Máx. 2000 destinatários por chamada.
 */
exports.ctSendMaintenancePromoEmails = onCall(
  {
    // Muitos destinatários × (SMTP + delay) estourava 540s → cliente via [internal].
    timeoutSeconds: 3600,
    memory: "1GiB",
    maxInstances: 3,
    region: "us-central1",
  },
  async (req) => {
    try {
      if (!req.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
      }
      await requireAdminPanel(req.auth.uid);

      const linkUrl = (req.data?.linkUrl || "").toString().trim();
      const messageText = (req.data?.messageText || "").toString().trim();
      const subject = (req.data?.subject || "Controle Total — promoção e planos no site oficial")
        .toString()
        .trim();
      const rawUids = req.data?.targetUids;
      const targetUids = Array.isArray(rawUids)
        ? rawUids.map((u) => String(u || "").trim()).filter(Boolean)
        : null;

      if (!/^https:\/\//i.test(linkUrl)) {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "Informe linkUrl com https:// (site oficial).",
        );
      }

      const cfgEarly = await getEmailConfig();
      if (!cfgEarly) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "E-mail não configurado. Em Admin > E-mail, salve usuário Gmail e senha de app.",
        );
      }

      const db = admin.firestore();
      const recipients = [];
      const seenEmails = new Set();

      const pushUser = (uid, email) => {
        const em = (email || "").toString().trim().toLowerCase();
        if (!em || !/^[^@]+@[^@]+\.[^@]+$/.test(em)) return;
        if (seenEmails.has(em)) return;
        seenEmails.add(em);
        recipients.push({ uid, email: em });
      };

      if (targetUids && targetUids.length > 0) {
        for (const uid of targetUids) {
          const u = await db.doc(`users/${uid}`).get();
          if (!u.exists) continue;
          const d = u.data() || {};
          pushUser(uid, d.email);
        }
      } else {
        let lastDoc = null;
        // eslint-disable-next-line no-constant-condition
        while (true) {
          let q = db.collection("users").orderBy(admin.firestore.FieldPath.documentId()).limit(400);
          if (lastDoc) q = q.startAfter(lastDoc);
          const snap = await q.get();
          if (snap.empty) break;
          for (const doc of snap.docs) {
            const d = doc.data() || {};
            const role = (d.role || "").toString();
            const plan = (d.plan || "").toString().toLowerCase();
            if (role === "admin" || role === "master") {
              continue;
            }
            pushUser(doc.id, d.email);
            if (recipients.length >= 2000) break;
          }
          if (recipients.length >= 2000) break;
          lastDoc = snap.docs[snap.docs.length - 1];
        }
      }

      const href = escapeAttrUrl(linkUrl);
      const bodyIntro = messageText
        ? `<div class="alert">${escapeHtml(messageText)}</div>`
        : `<p>Temos uma <strong>oferta</strong> no site oficial do <strong>Controle Total</strong>. Entre com sua conta Google ou e-mail, confira o <strong>banner de promoção</strong> e conclua no valor promocional (PIX ou cartão).</p>`;

      const body = `${bodyIntro}
<p style="margin-top:16px"><a href="${href}" class="btn">Abrir site oficial — ver promoção e planos</a></p>
<p style="font-size:13px;color:#64748b;margin-top:20px">Se o botão não abrir, copie e cole no navegador:<br/><span style="word-break:break-all">${escapeHtml(linkUrl)}</span></p>`;

      const html = buildEmailBase("Controle Total — Site oficial", body);

      let sent = 0;
      let failed = 0;
      const errors = [];
      const batchSize = 4;
      const pauseMs = 90;
      for (let i = 0; i < recipients.length; i += batchSize) {
        const chunk = recipients.slice(i, i + batchSize);
        const results = await Promise.all(
          chunk.map((r) => sendEmailHtml(r.email, subject, html)),
        );
        for (const res of results) {
          if (res.ok) sent++;
          else {
            failed++;
            if (errors.length < 8) errors.push(res.error || "erro");
          }
        }
        if (i + batchSize < recipients.length) {
          await new Promise((resolve) => setTimeout(resolve, pauseMs));
        }
      }

      return {
        ok: true,
        sent,
        failed,
        total: recipients.length,
        errors: errors.length ? errors : undefined,
      };
    } catch (e) {
      if (e instanceof functions.https.HttpsError) throw e;
      const msg = (e?.message || String(e)).toString().slice(0, 480);
      console.error("[ctSendMaintenancePromoEmails]", e);
      // failed-precondition costuma exibir a mensagem no app; "internal" aparece só como "internal".
      throw new functions.https.HttpsError(
        "failed-precondition",
        msg || "Erro ao enviar e-mails de promoção. Veja logs: ctSendMaintenancePromoEmails.",
      );
    }
  },
);

/**
 * Um e-mail de teste (mesmo HTML da campanha). Admin — valida SMTP antes do envio em massa.
 */
exports.ctSendMaintenancePromoTestEmail = onCall(async (req) => {
  try {
    if (!req.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
    }
    await requireAdminPanel(req.auth.uid);

    const linkUrl = (req.data?.linkUrl || "").toString().trim();
    const messageText = (req.data?.messageText || "").toString().trim();
    const subject = (req.data?.subject || "Controle Total — promoção e planos no site oficial")
      .toString()
      .trim();
    const testEmail = (req.data?.testEmail || "").toString().trim().toLowerCase();

    if (!/^https:\/\//i.test(linkUrl)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Informe linkUrl com https:// (site oficial).",
      );
    }
    if (!testEmail || !/^[^@]+@[^@]+\.[^@]+$/.test(testEmail)) {
      throw new functions.https.HttpsError("invalid-argument", "Informe testEmail válido.");
    }

    const cfgEarly = await getEmailConfig();
    if (!cfgEarly) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "E-mail não configurado. Em Admin > E-mail, salve usuário Gmail e senha de app.",
      );
    }

    const href = escapeAttrUrl(linkUrl);
    const bodyIntro = messageText
      ? `<div class="alert">${escapeHtml(messageText)}</div>`
      : `<p>Temos uma <strong>oferta</strong> no site oficial do <strong>Controle Total</strong>. Entre com sua conta Google ou e-mail, confira o <strong>banner de promoção</strong> e conclua no valor promocional (PIX ou cartão).</p>`;

    const body = `${bodyIntro}
<p style="margin-top:16px"><a href="${href}" class="btn">Abrir site oficial — ver promoção e planos</a></p>
<p style="font-size:13px;color:#64748b;margin-top:20px">Se o botão não abrir, copie e cole no navegador:<br/><span style="word-break:break-all">${escapeHtml(linkUrl)}</span></p>
<p style="font-size:12px;color:#94a3b8;margin-top:16px">Esta mensagem é um <strong>teste</strong> enviado pelo painel administrativo.</p>`;

    const html = buildEmailBase("Controle Total — Site oficial", body);
    const res = await sendEmailHtml(testEmail, subject, html);
    if (!res.ok) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        (res.error || "Falha ao enviar e-mail de teste.").toString().slice(0, 400),
      );
    }
    return { ok: true, to: testEmail };
  } catch (e) {
    if (e instanceof functions.https.HttpsError) throw e;
    const msg = (e?.message || String(e)).toString().slice(0, 480);
    console.error("[ctSendMaintenancePromoTestEmail]", e);
    throw new functions.https.HttpsError(
      "failed-precondition",
      msg || "Erro ao enviar e-mail de teste.",
    );
  }
});

/**
 * Estrutura da notificação (FCM HTTP v1 / Admin SDK).
 * O servidor deve enviar um payload equivalente a este JSON para o Firebase entender:
 *
 * {
 *   "message": {
 *     "token": "TOKEN_DO_USUARIO_SALVO_NO_BANCO",
 *     "notification": {
 *       "title": "🚨 Alerta de Escala!",
 *       "body": "Sua escala de Audiência começa em 30 minutos."
 *     },
 *     "webpush": {
 *       "fcm_options": {
 *         "link": "https://seu-site.com/agenda"
 *       }
 *     }
 *   }
 * }
 *
 * No Admin SDK usamos: admin.messaging().send({ token, notification, data: { url }, webpush: { fcmOptions: { link } } }).
 */

/**
 * verificarAgendaEDisparar (Scheduled Function): roda a cada 1 minuto.
 * Processa a fila users/{uid}/agendaAlerts (pending com notifyAt <= agora) e dispara push/e-mail.
 * Funciona com app fechado — não depende do cliente aberto.
 */
exports.verificarAgendaEDisparar = onSchedule(
  { schedule: "every 1 minutes", region: "us-central1", timeoutSeconds: 540 },
  async () => {
    try {
      await runProcessAgendaAlertQueue();
    } catch (e) {
      console.error("verificarAgendaEDisparar:", e?.message || e);
    }
  }
);

/** Resumo diário (amanhã) — e-mail + push opcional às 20h Brasília. */
async function sendDigestPushForUser(db, uid, userData, payload) {
  if (userData.pushEnabled === false) return false;
  const tokens = await getUserFcmTokens(db, uid, userData);
  if (!tokens.length) return false;
  const templates = await notifTpl.loadNotificationTemplates(db);
  try {
    const resp = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: { title: payload.title, body: payload.body },
      data: {
        url: payload.link,
        type: "agenda_digest",
        title: payload.title,
        body: payload.body,
      },
      ...agendaReminderMulticastOptions(
        payload.link,
        "compromisso",
        { title: payload.title, body: payload.body },
        templates,
      ),
    });
    resp.responses.forEach((r, i) => {
      if (
        !r.success &&
        (r.error?.code === "messaging/invalid-registration-token" ||
          r.error?.code === "messaging/registration-token-not-registered")
      ) {
        const badToken = tokens[i];
        if (badToken) deleteInvalidFcmToken(db, uid, badToken).catch(() => {});
      }
    });
    return resp.successCount > 0;
  } catch (err) {
    console.warn(`[sendDigestPushForUser] uid=${uid}:`, err?.message || err);
    return false;
  }
}

exports.enviarResumoAgendaDiario = onSchedule(
  { schedule: "0 20 * * *", timeZone: TZ_BRASILIA, region: "us-central1", timeoutSeconds: 540 },
  async () => {
    try {
      const db = admin.firestore();
      await agendaDigest.runDailyAgendaDigest(db, APP_DOMAIN, sendEmailHtml, (uid, userData, payload) =>
        sendDigestPushForUser(db, uid, userData, payload),
      );
    } catch (e) {
      console.error("enviarResumoAgendaDiario:", e?.message || e);
    }
  },
);

/**
 * Ao criar/editar audiência ou compromisso (users/{uid}/reminders), dispara na hora
 * push/e-mail para antecedências já vencidas (ex.: cadastro 15 min antes do evento).
 */
exports.onAgendaReminderWritten = onDocumentWritten(
  { document: "users/{uid}/reminders/{reminderId}", region: "us-central1" },
  async (event) => {
    try {
      await controlAgendaAlertsOnReminderWritten(event);
    } catch (e) {
      console.warn("onAgendaReminderWritten:", e?.message || e);
    }
  },
);

/**
 * Ao criar/editar plantão na coleção scales, dispara push/e-mail para antecedências
 * já vencidas no dia (ex.: plantão hoje 14h — só avisa 60 min antes, não «1 dia»).
 */
exports.onScaleWritten = onDocumentWritten(
  { document: "users/{uid}/scales/{scaleId}", region: "us-central1" },
  async (event) => {
    try {
      await controlAgendaAlertsOnScaleWritten(event);
    } catch (e) {
      console.warn("onScaleWritten:", e?.message || e);
    }
  },
);

/**
 * Ao criar/editar conta a pagar/receber pendente (users/{uid}/transactions),
 * planeja/cancela lembretes financeiros na fila agendaAlerts e dispara o que já venceu.
 */
exports.onTransactionWritten = onDocumentWritten(
  { document: "users/{uid}/transactions/{txId}", region: "us-central1" },
  async (event) => {
    try {
      await controlAgendaAlertsOnTransactionWritten(event);
    } catch (e) {
      console.warn("onTransactionWritten:", e?.message || e);
    }
  },
);

/**
 * Ao alterar settings/notifications, replaneja alertas futuros de forma incremental
 * (novas antecedências só adicionam slots; remoções cancelam pendentes).
 */
exports.onAgendaNotificationSettingsWritten = onDocumentWritten(
  { document: "users/{uid}/settings/notifications", region: "us-central1" },
  async (event) => {
    const before = event.data?.before;
    const after = event.data?.after;
    if (!after?.exists) return;
    const uid = event.params.uid;
    const db = admin.firestore();
    const now = new Date();
    const beforeData = before?.exists ? before.data() : null;
    const afterData = after.data();
    try {
      const config = await loadAgendaNotificationConfig(db, uid);
      if (!config.scaleReminderEnabled) {
        const pending = await db
          .collection("users")
          .doc(uid)
          .collection(AGENDA_ALERTS_COLL)
          .where("status", "==", AGENDA_ALERT_STATUS.PENDING)
          .limit(500)
          .get();
        const batch = db.batch();
        pending.docs.forEach((doc) => {
          batch.update(doc.ref, {
            status: AGENDA_ALERT_STATUS.CANCELLED,
            cancelReason: "notifications_disabled",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        });
        if (pending.size > 0) await batch.commit();
        return;
      }

      const oldLeads = beforeData ? parseLeadsFromNotifData(beforeData) : config.globalLeads;
      const newLeads = config.globalLeads;
      const addedLeads = newLeads.filter((l) => !oldLeads.includes(l));
      const removedLeads = oldLeads.filter((l) => !newLeads.includes(l));

      if (removedLeads.length > 0) {
        await cancelAgendaAlertsForRemovedLeads(db, uid, removedLeads);
      }

      const needsFullResync =
        !beforeData ||
        removedLeads.length > 0 ||
        didAgendaGlobalNotificationSettingsChange(beforeData, afterData);

      if (needsFullResync) {
        await resyncAgendaAlertsWindowForUser(db, uid, config, now);
      } else if (addedLeads.length > 0) {
        await appendAgendaAlertsForNewLeadsOnly(db, uid, config, addedLeads, now);
      } else {
        await refreshPendingAgendaAlertDeliveryFlags(db, uid, config);
      }

      await processDueAgendaAlertsForUser(db, uid, now);
    } catch (e) {
      console.warn("onAgendaNotificationSettingsWritten:", e?.message || e);
    }
  },
);


const WINDOW_MS = 15 * 60 * 1000;
/** Janela maior para "1 dia antes" (1440 min): 60 min para não perder o envio. */
const WINDOW_MS_ONE_DAY = 60 * 60 * 1000;
const AGENDA_BATCH_SIZE = 150;
/** Catch-up no servidor: imediato para push/e-mail ao salvar (app local usa ~45s). */
const AGENDA_CATCH_UP_DELAY_MS = 0;
/** Antecedências extras quando o evento é em até 3 h (cadastro em cima da hora). */
const AGENDA_IMMINENT_MAX_MINUTES = 180;

/** Evento ainda não começou — pode receber lembrete (push/e-mail/local). */
function isAgendaEventForwardEligible(eventAt, now) {
  const n = now || new Date();
  return eventAt.getTime() > n.getTime();
}

/** «1 dia antes» de evento HOJE não cai antes da meia-noite de hoje (Brasília). */
function isAgendaLeadBeforeTodayMidnightSkipped(eventAt, notifyAt, now) {
  const eventParts = getDatePartsBrasilia(eventAt);
  const nowParts = getDatePartsBrasilia(now);
  const startOfEventDay = dateInBrasilia(eventParts.year, eventParts.month + 1, eventParts.day, 0, 0, 0);
  const startOfToday = dateInBrasilia(nowParts.year, nowParts.month + 1, nowParts.day, 0, 0, 0);
  const isEventToday = startOfEventDay.getTime() === startOfToday.getTime();
  return isEventToday && notifyAt < startOfToday;
}

/** Horário exato do aviso para um lead — permite catch-up (notifyAt no passado, evento no futuro). */
function agendaNotifyAtForLead(eventAt, leadMin, now) {
  const n = now || new Date();
  if (!(eventAt > n)) return null;
  const notifyAt = new Date(eventAt.getTime() - leadMin * 60 * 1000);
  if (isAgendaLeadBeforeTodayMidnightSkipped(eventAt, notifyAt, n)) return null;
  if (!(notifyAt < eventAt)) return null;
  return notifyAt;
}

/** Slot entra na fila agendaAlerts (evento futuro; notifyAt pode já ter passado → cron envia na hora). */
function isAgendaLeadSlotSchedulable(eventAt, notifyAt, now) {
  if (!(eventAt > now)) return false;
  if (!(notifyAt < eventAt)) return false;
  if (isAgendaLeadBeforeTodayMidnightSkipped(eventAt, notifyAt, now)) return false;
  return true;
}

/** Antecedências globais (Configurações) — sem personalizado por evento. */
function reminderLeadsForDoc(_d, globalLeads) {
  const g = Array.isArray(globalLeads) ? globalLeads : [];
  const parsed = g.map((x) => parseInt(x, 10) || 0).filter((x) => x > 0);
  if (parsed.length > 0) return parsed;
  return [1440, 60];
}

/** Audiência em aberto ou compromisso não concluído. */
function isReminderOpenForNotify(d) {
  if (d.done === true) return false;
  const type = (d.type || "compromisso").toString().toLowerCase();
  if (type === "audiencia") {
    return (d.status || "EM_ABERTO").toString() === "EM_ABERTO";
  }
  return true;
}

/** Evento futuro ou ainda na janela de 24h do painel (audiência/compromisso). */
function isReminderEligibleForServerNotify(d, reminderAt, now) {
  if (!isReminderOpenForNotify(d)) return false;
  const type = (d.type || "compromisso").toString().toLowerCase();
  if (type === "audiencia" || type === "compromisso") {
    const panelEnd = new Date(reminderAt.getTime() + 24 * 60 * 60 * 1000);
    return now < panelEnd;
  }
  return reminderAt > now;
}

/** Lead vencido e elegível para envio (push/e-mail). */
function isScaleOrReminderLeadNotifyDue(eventAt, notifyAt, now) {
  if (now < notifyAt) return false;
  const eventParts = getDatePartsBrasilia(eventAt);
  const nowParts = getDatePartsBrasilia(now);
  const startOfEventDay = dateInBrasilia(eventParts.year, eventParts.month + 1, eventParts.day, 0, 0, 0);
  const startOfToday = dateInBrasilia(nowParts.year, nowParts.month + 1, nowParts.day, 0, 0, 0);
  const isEventToday = startOfEventDay.getTime() === startOfToday.getTime();
  // Evento HOJE: não reenviar antecedência que cairia antes de hoje 00:00 (ex.: «1 dia» perdido).
  if (isEventToday && notifyAt < startOfToday) return false;
  // Evento amanhã+: «1 dia antes» no dia anterior é válido (notifyAt < startOfEventDay).
  return true;
}

/** Monta mensagens de lembrete elegíveis (push/e-mail) para docs da coleção scales (plantões). */
function collectDueScaleMessages(
  scaleDocs,
  reminderLeadsFromSettings,
  now,
  notifEscalas = true,
  notifCompromissos = true,
  config = null,
) {
  const toSend = [];
  for (const doc of scaleDocs) {
    const d = doc.data();
    if (d.isAgendaMirror === true) continue;
    if (d.isProdutividadeFolgaMirror === true) continue;
    const isCompromisso = d.isCompromisso === true;
    if (isCompromisso && !notifCompromissos) continue;
    if (!isCompromisso && !notifEscalas) continue;
    const dateTs = d.date;
    const startStr = (d.start || "08:00").toString();
    if (!dateTs || !startStr) continue;
    const date = dateTs.toDate ? dateTs.toDate() : new Date(dateTs.seconds * 1000);
    const parts = getDatePartsBrasilia(date);
    const [h, m] = String(startStr).split(":").map((x) => parseInt(x, 10) || 0);
    const shiftStart = dateInBrasilia(parts.year, parts.month + 1, parts.day, h, m, 0);
    if (!isAgendaEventForwardEligible(shiftStart, now)) continue;
    if (shiftStart <= now) continue;
    const leads = reminderLeadsForDoc(d, reminderLeadsFromSettings);
    for (const leadMin of leads) {
      const built = agendaMsg.buildPushFromScale(d, shiftStart, startStr, leadMin, "", now);
      const channelKind = (built.channelKind || "escala").toString();
      if (
        config &&
        agendaDelivery.isAgendaLeadDeliveryComplete(d, leadMin, config, channelKind)
      ) {
        continue;
      }
      const notifyAt = agendaNotifyAtForLead(shiftStart, leadMin, now);
      if (!notifyAt) continue;
      if (!isScaleOrReminderLeadNotifyDue(shiftStart, notifyAt, now)) continue;
      toSend.push({
        title: built.title,
        body: built.body,
        channelKind: built.channelKind,
        path: notifTpl.agendaDeepLinkPath(channelKind, "scale"),
        scaleRef: doc.ref,
        scaleData: d,
        leadMin,
        date,
        startStr,
      });
    }
  }
  return toSend;
}

/** Monta mensagens de lembrete elegíveis (push/e-mail) para docs da coleção reminders. */
function collectDueReminderMessages(reminderDocs, reminderLeadsFromSettings, now, notifyConfig) {
  const toSend = [];
  for (const doc of reminderDocs) {
    const d = doc.data();
    const remType = (d.type || "compromisso").toString().toLowerCase();
    if (notifyConfig) {
      if (remType === "audiencia" && !notifyConfig.notifAudiencias) continue;
      if (remType !== "audiencia" && !notifyConfig.notifCompromissos) continue;
    }
    if (!isReminderOpenForNotify(d)) continue;
    if (d.notificado === true && (!Array.isArray(d.notificadoLeads) || d.notificadoLeads.length === 0)) continue;
    const dateTs = d.date;
    const timeStr = (d.time || "09:00").toString();
    if (!dateTs || !timeStr) continue;
    const date = dateTs.toDate ? dateTs.toDate() : new Date(dateTs.seconds * 1000);
    const parts = getDatePartsBrasilia(date);
    const [h, m] = timeStr.split(":").map((x) => parseInt(x, 10) || 0);
    const reminderAt = dateInBrasilia(parts.year, parts.month + 1, parts.day, h, m, 0);
    if (!isAgendaEventForwardEligible(reminderAt, now)) continue;
    if (!isReminderEligibleForServerNotify(d, reminderAt, now)) continue;
    const notificadoLeads = Array.isArray(d.notificadoLeads) ? d.notificadoLeads : [];
    const leads = reminderLeadsForDoc(d, reminderLeadsFromSettings);
    for (const leadMin of leads) {
      const remType = (d.type || "compromisso").toString().toLowerCase();
      const channelKind = remType === "audiencia" ? "audiencia" : "compromisso";
      if (
        notifyConfig &&
        agendaDelivery.isAgendaLeadDeliveryComplete(d, leadMin, notifyConfig, channelKind)
      ) {
        continue;
      }
      if (!notifyConfig && notificadoLeads.includes(leadMin)) continue;
      const notifyAt = agendaNotifyAtForLead(reminderAt, leadMin, now);
      if (!notifyAt) continue;
      if (!isScaleOrReminderLeadNotifyDue(reminderAt, notifyAt, now)) continue;
      const built = agendaMsg.buildPushFromReminder(d, reminderAt, leadMin, "", now);
      const builtChannelKind = (built.channelKind || channelKind).toString();
      toSend.push({
        title: built.title,
        body: built.body,
        channelKind: built.channelKind,
        path: notifTpl.agendaDeepLinkPath(builtChannelKind, "reminder"),
        reminderRef: doc.ref,
        reminderData: d,
        date,
        timeStr,
        leadMin,
      });
    }
  }
  return toSend;
}

/** Envia push/e-mail e marca leads notificados (scales e reminders). */
async function dispatchAgendaReminderMessages(db, uid, userData, tokens, toSend, config) {
  let pushSent = 0;
  let emailSent = 0;
  const hasEmail = (userData.email || "").toString().trim() && /^[^@]+@[^@]+\.[^@]+$/.test((userData.email || "").toString().trim());
  const email = (userData.email || "").toString().trim();
  const name = (userData.name || "").toString().trim() || "Usuário";
  const templates = await notifTpl.loadNotificationTemplates(db);

  const nowDispatch = new Date();
  for (const msg of toSend) {
    const enriched = agendaMsg.enrichDispatchMessage(msg, name, nowDispatch);
    const channelKind = (enriched.channelKind || msg.channelKind || "").toString();
    const sourceType = msg.reminderData
      ? "reminder"
      : msg.transactionData
        ? "transaction"
        : "scale";
    const path =
      enriched.path && enriched.path !== "/"
        ? enriched.path
        : notifTpl.agendaDeepLinkPath(channelKind, sourceType);
    const link = `${APP_DOMAIN}${path.startsWith("/") ? path : "/" + path}`;

    let alertPushEnabled = true;
    let alertEmailEnabled = true;
    let alertPushAlready = false;
    let alertEmailAlready = false;
    if (msg.agendaAlertRef) {
      const alertSnap = await msg.agendaAlertRef.get();
      const alertData = alertSnap.data() || {};
      alertPushEnabled = alertData.pushEnabled !== false;
      alertEmailEnabled = alertData.emailEnabled !== false;
      alertPushAlready = alertData.pushDelivered === true;
      alertEmailAlready = alertData.emailDelivered === true;
    }
    const wantPush =
      userData.pushEnabled !== false &&
      alertPushEnabled &&
      agendaDelivery.allowsPushForChannel(config, channelKind);
    const wantEmail =
      alertEmailEnabled &&
      hasEmail &&
      agendaDelivery.allowsEmailForChannel(config, channelKind);
    const allowPush = wantPush && !alertPushAlready;
    const allowEmail = wantEmail && !alertEmailAlready;

    let pushDelivered = false;
    let emailDelivered = false;
    if (allowPush && tokens.length > 0) {
      try {
        const soundId = (enriched.soundId || msg.soundId || "").toString();
        const resp = await admin.messaging().sendEachForMulticast({
          tokens,
          notification: { title: enriched.title, body: enriched.body },
          data: {
            url: link,
            type: "agenda_reminder",
            channelKind,
            soundId,
            title: enriched.title,
            body: enriched.body,
            iconUrl: APP_ICON_URL,
            ...(enriched.subtitle ? { subtitle: enriched.subtitle } : {}),
          },
          ...agendaReminderMulticastOptions(
            link,
            channelKind,
            {
              title: enriched.title,
              subtitle: enriched.subtitle,
              body: enriched.body,
            },
            templates,
          ),
        });
        pushSent += resp.successCount;
        if (resp.successCount > 0) pushDelivered = true;
        resp.responses.forEach((r, i) => {
          if (
            !r.success &&
            (r.error?.code === "messaging/invalid-registration-token" ||
              r.error?.code === "messaging/registration-token-not-registered")
          ) {
            const badToken = tokens[i];
            if (badToken) {
              deleteInvalidFcmToken(db, uid, badToken).catch(() => {});
            }
          }
        });
      } catch (err) {
        console.error(`[dispatchAgendaReminder] uid=${uid} push:`, err?.message || err);
      }
    }

    if (allowEmail) {
      const emailBuilt = agendaMsg.buildEmailForDispatch(msg, name, APP_DOMAIN);
      const html = agendaMsg.buildEmailBasePremium(
        emailBuilt.htmlTitle,
        emailBuilt.bodyHtml,
        emailBuilt.accent,
        templates,
      );
      const res = await sendEmailHtml(email, emailBuilt.subject, html);
      if (res.ok) {
        emailSent++;
        emailDelivered = true;
      }
    }

    const leadDelivered =
      pushDelivered ||
      emailDelivered ||
      (wantPush && alertPushAlready) ||
      (wantEmail && alertEmailAlready);
    const pushComplete = !wantPush || pushDelivered || alertPushAlready;
    const emailComplete = !wantEmail || emailDelivered || alertEmailAlready;
    const allChannelsComplete = pushComplete && emailComplete;
    if (!leadDelivered) {
      if (msg.agendaAlertRef) {
        const failReason =
          wantPush && tokens.length === 0
            ? "no_fcm_token"
            : wantEmail && !hasEmail
              ? "no_email"
              : "delivery_failed";
        const alertSnap = await msg.agendaAlertRef.get();
        const alertData = alertSnap.data() || {};
        const notifyAt = alertData.notifyAt?.toDate
          ? alertData.notifyAt.toDate()
          : new Date(alertData.notifyAt);
        const overdueMs = nowDispatch.getTime() - notifyAt.getTime();
        await updateAgendaAlertDoc(msg.agendaAlertRef, {
          lastDispatchFailAt: admin.firestore.FieldValue.serverTimestamp(),
          lastDispatchFailReason: failReason,
        });
        if (overdueMs >= 120 * 60 * 1000) {
          await updateAgendaAlertDoc(msg.agendaAlertRef, {
            status: AGENDA_ALERT_STATUS.SKIPPED,
            cancelReason: failReason,
          });
        }
      }
      continue;
    }

    if (msg.scaleRef) {
      const updateData = {};
      if (pushDelivered) {
        updateData.notificado = true;
        updateData.notificadoLeads = admin.firestore.FieldValue.arrayUnion(msg.leadMin);
        updateData.notificadoEm = admin.firestore.FieldValue.serverTimestamp();
      }
      if (emailDelivered) {
        updateData.emailNotificadoLeads = admin.firestore.FieldValue.arrayUnion(msg.leadMin);
        updateData.emailNotificadoEm = admin.firestore.FieldValue.serverTimestamp();
      }
      if (Object.keys(updateData).length > 0) {
        await msg.scaleRef.update(updateData);
      }
    }

    if (msg.reminderRef) {
      const updateData = {};
      if (pushDelivered) {
        updateData.notificadoLeads = admin.firestore.FieldValue.arrayUnion(msg.leadMin);
        updateData.notificadoEm = admin.firestore.FieldValue.serverTimestamp();
      }
      if (emailDelivered) {
        updateData.emailNotificadoLeads = admin.firestore.FieldValue.arrayUnion(msg.leadMin);
        updateData.emailNotificadoEm = admin.firestore.FieldValue.serverTimestamp();
      }
      if (Object.keys(updateData).length > 0) {
        await msg.reminderRef.update(updateData);
      }
    }

    if (msg.transactionRef) {
      const updateData = {};
      if (pushDelivered) {
        updateData.notificadoLeads = admin.firestore.FieldValue.arrayUnion(msg.leadMin);
        updateData.notificadoEm = admin.firestore.FieldValue.serverTimestamp();
      }
      if (emailDelivered) {
        updateData.emailNotificadoLeads = admin.firestore.FieldValue.arrayUnion(msg.leadMin);
        updateData.emailNotificadoEm = admin.firestore.FieldValue.serverTimestamp();
      }
      if (Object.keys(updateData).length > 0) {
        await msg.transactionRef.update(updateData);
      }
    }

    if (msg.agendaAlertRef) {
      const alertUpdates = {
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      if (pushDelivered) alertUpdates.pushDelivered = true;
      if (emailDelivered) alertUpdates.emailDelivered = true;
      if (allChannelsComplete) {
        alertUpdates.status = AGENDA_ALERT_STATUS.SENT;
        alertUpdates.sentAt = admin.firestore.FieldValue.serverTimestamp();
      }
      await msg.agendaAlertRef.update(alertUpdates);
    }
  }

  return { pushSent, emailSent };
}

// ---------------------------------------------------------------------------
// Controle central de alertas de agenda (audiência / compromisso / escala)
// Coleção: users/{uid}/agendaAlerts/{alertId}
// Ao criar/editar o evento → gera slots pending com notifyAt exato.
// Cron + onWrite → disparam push/e-mail só se config do usuário permitir.
// ---------------------------------------------------------------------------

const AGENDA_ALERTS_COLL = "agendaAlerts";
const AGENDA_ALERT_STATUS = {
  PENDING: "pending",
  SENT: "sent",
  CANCELLED: "cancelled",
  SKIPPED: "skipped",
};
const AGENDA_ALERT_PLAN_VERSION = 2;
/** Alinhado com `AgendaAlertsMigrationService.kMigrationVersion` no Flutter. */
const AGENDA_USER_MIGRATED_V = 5;
const AGENDA_RESYNC_WINDOW_DAYS = 60;
const AGENDA_ALERTS_DUE_LIMIT = 200;
/** Sent na fila: UI «Notificados» 0–3 dias, «Arquivadas» 3–7 dias; depois limpeza. */
const AGENDA_NOTIFIED_VISIBLE_DAYS = 3;
const AGENDA_ARCHIVED_VISIBLE_DAYS = 7;

function archivedAgendaAlertsVisibleSinceBrasilia(now) {
  const n = now || new Date();
  const parts = getDatePartsBrasilia(n);
  const startToday = dateInBrasilia(parts.year, parts.month + 1, parts.day, 0, 0, 0);
  startToday.setDate(startToday.getDate() - AGENDA_ARCHIVED_VISIBLE_DAYS);
  return startToday;
}

function agendaAlertDocId(sourceType, sourceId, leadMin) {
  const safeId = String(sourceId).replace(/[/\s]/g, "_");
  return `${sourceType}_${safeId}_${leadMin}`;
}

/** Configurações do usuário (settings/notifications). */
async function loadAgendaNotificationConfig(db, uid) {
  const notifSnap = await db.collection("users").doc(uid).collection("settings").doc("notifications").get();
  const notifData = notifSnap.data() || {};
  let globalLeads = [];
  if (Array.isArray(notifData.scaleReminderLeads) && notifData.scaleReminderLeads.length > 0) {
    globalLeads = notifData.scaleReminderLeads.map((x) => parseInt(x, 10) || 0).filter((x) => x > 0);
  }
  if (globalLeads.length === 0) globalLeads = [1440, 60];
  const delivery = agendaDelivery.parseDeliveryFieldsFromNotifData(notifData);
  const legacyCompromissosAudiencias = notifData.notifCompromissosAudiencias !== false;
  const notifCompromissos =
    notifData.notifCompromissos !== undefined
      ? notifData.notifCompromissos !== false
      : legacyCompromissosAudiencias;
  /** Audiências: padrão ligado (evento sério); usuário pode desligar depois. */
  const notifAudiencias =
    notifData.notifAudiencias !== undefined ? notifData.notifAudiencias !== false : true;
  /** Financeiro (contas a pagar/receber pendentes): padrão ligado. */
  const notifFinanceiro =
    notifData.notifFinanceiro !== undefined ? notifData.notifFinanceiro !== false : true;
  return {
    scaleReminderEnabled: notifData.scaleReminderEnabled !== false,
    notifEscalas: notifData.notifEscalas !== false,
    notifCompromissos,
    notifAudiencias,
    notifFinanceiro,
    notifCompromissosAudiencias: notifCompromissos && notifAudiencias,
    emailReminderEnabled: notifData.emailReminderEnabled !== false,
    dailyDigestEnabled: notifData.dailyDigestEnabled !== false,
    deliveryEscala: delivery.deliveryEscala,
    deliveryCompromisso: delivery.deliveryCompromisso,
    deliveryAudiencia: delivery.deliveryAudiencia,
    deliveryFinanceiro: delivery.deliveryFinanceiro,
    globalLeads,
  };
}

function parseLeadsFromNotifData(notifData) {
  const g = Array.isArray(notifData?.scaleReminderLeads) ? notifData.scaleReminderLeads : [];
  const parsed = g.map((x) => parseInt(x, 10) || 0).filter((x) => x > 0);
  return parsed.length > 0 ? parsed : [1440, 60];
}

function didAgendaGlobalNotificationSettingsChange(beforeData, afterData) {
  if (!beforeData || !afterData) return true;
  const fields = [
    "notifEscalas",
    "notifCompromissos",
    "notifAudiencias",
    "notifFinanceiro",
    "notifCompromissosAudiencias",
    "scaleReminderEnabled",
    "emailReminderEnabled",
    "deliveryEscala",
    "deliveryCompromisso",
    "deliveryAudiencia",
    "deliveryFinanceiro",
  ];
  return fields.some((f) => agendaContentStr(beforeData[f]) !== agendaContentStr(afterData[f]));
}

/** Re-sincroniza janela futura (reminders + scales) — usado em settings e rebuild. */
async function resyncAgendaAlertsWindowForUser(db, uid, config, now) {
  const cutoff = agendaForwardCutoffBrasilia(now);
  const cutoffTs = admin.firestore.Timestamp.fromDate(cutoff);
  const endDate = new Date(cutoff.getTime() + AGENDA_RESYNC_WINDOW_DAYS * 24 * 60 * 60 * 1000);
  endDate.setHours(23, 59, 59, 999);
  const endTs = admin.firestore.Timestamp.fromDate(endDate);

  if (config.notifAudiencias || config.notifCompromissos) {
    const remSnap = await db
      .collection("users")
      .doc(uid)
      .collection("reminders")
      .where("date", ">=", cutoffTs)
      .where("date", "<=", endTs)
      .limit(600)
      .get();
    for (const doc of remSnap.docs) {
      const slots = planReminderAgendaAlertSlots(doc, config, now);
      if (slots.length === 0) {
        await cancelAgendaAlertsForSource(db, uid, "reminder", doc.id);
      } else {
        await syncAgendaAlertSlots(db, uid, slots, config);
      }
    }
  }

  if (config.notifEscalas || config.notifCompromissos) {
    const scalesSnap = await db
      .collection("users")
      .doc(uid)
      .collection("scales")
      .where("date", ">=", cutoffTs)
      .where("date", "<=", endTs)
      .limit(600)
      .get();
    for (const doc of scalesSnap.docs) {
      const slots = planScaleAgendaAlertSlots(doc, config, now, config.notifEscalas);
      if (slots.length === 0) {
        await cancelAgendaAlertsForSource(db, uid, "scale", doc.id);
      } else {
        await syncAgendaAlertSlots(db, uid, slots, config);
      }
    }
  }

  if (config.notifFinanceiro) {
    const txSnap = await db
      .collection("users")
      .doc(uid)
      .collection("transactions")
      .where("status", "==", "pending")
      .where("date", ">=", cutoffTs)
      .where("date", "<=", endTs)
      .limit(600)
      .get();
    for (const doc of txSnap.docs) {
      const slots = planTransactionAgendaAlertSlots(doc, config, now);
      if (slots.length === 0) {
        await cancelAgendaAlertsForSource(db, uid, "transaction", doc.id);
      } else {
        await syncAgendaAlertSlots(db, uid, slots, config);
      }
    }
  }
}

/** Só adiciona slots das antecedências novas — não cancela as existentes. */
async function appendAgendaAlertSlots(db, uid, slots, config) {
  if (!slots.length) return;
  const coll = db.collection("users").doc(uid).collection(AGENDA_ALERTS_COLL);
  const nowTs = admin.firestore.FieldValue.serverTimestamp();
  let batch = db.batch();
  let ops = 0;
  for (const slot of slots) {
    const ref = coll.doc(slot.alertId);
    const prev = await ref.get();
    const prevData = prev.data() || {};
    if ((prevData.status || "").toString() === AGENDA_ALERT_STATUS.SENT) continue;

    const payload = {
      sourceType: slot.sourceType,
      sourceId: slot.sourceId,
      leadMin: slot.leadMin,
      notifyAt: admin.firestore.Timestamp.fromDate(slot.notifyAt),
      eventAt: admin.firestore.Timestamp.fromDate(slot.eventAt),
      channelKind: slot.channelKind,
      title: slot.title,
      body: slot.body,
      eventTitle: slot.eventTitle,
      timeStr: slot.timeStr || null,
      startStr: slot.startStr || null,
      pushEnabled: agendaDelivery.allowsPushForChannel(config, slot.channelKind),
      emailEnabled: agendaDelivery.allowsEmailForChannel(config, slot.channelKind),
      planVersion: AGENDA_ALERT_PLAN_VERSION,
      status: AGENDA_ALERT_STATUS.PENDING,
      createdAt: prevData.createdAt || nowTs,
      updatedAt: nowTs,
    };
    batch.set(ref, payload, { merge: true });
    ops++;
    if (ops >= 400) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  }
  if (ops > 0) await batch.commit();
}

async function appendAgendaAlertsForNewLeadsOnly(db, uid, config, addedLeads, now) {
  if (!addedLeads.length || !config.scaleReminderEnabled) return;
  const cutoff = agendaForwardCutoffBrasilia(now);
  const cutoffTs = admin.firestore.Timestamp.fromDate(cutoff);
  const endDate = new Date(cutoff.getTime() + AGENDA_RESYNC_WINDOW_DAYS * 24 * 60 * 60 * 1000);
  endDate.setHours(23, 59, 59, 999);
  const endTs = admin.firestore.Timestamp.fromDate(endDate);
  const leadSet = new Set(addedLeads);

  if (config.notifAudiencias || config.notifCompromissos) {
    const remSnap = await db
      .collection("users")
      .doc(uid)
      .collection("reminders")
      .where("date", ">=", cutoffTs)
      .where("date", "<=", endTs)
      .limit(600)
      .get();
    for (const doc of remSnap.docs) {
      const allSlots = planReminderAgendaAlertSlots(doc, config, now);
      const newSlots = allSlots.filter((s) => leadSet.has(s.leadMin));
      if (newSlots.length) await appendAgendaAlertSlots(db, uid, newSlots, config);
    }
  }

  if (config.notifEscalas || config.notifCompromissos) {
    const scalesSnap = await db
      .collection("users")
      .doc(uid)
      .collection("scales")
      .where("date", ">=", cutoffTs)
      .where("date", "<=", endTs)
      .limit(600)
      .get();
    for (const doc of scalesSnap.docs) {
      const allSlots = planScaleAgendaAlertSlots(doc, config, now, config.notifEscalas);
      const newSlots = allSlots.filter((s) => leadSet.has(s.leadMin));
      if (newSlots.length) await appendAgendaAlertSlots(db, uid, newSlots, config);
    }
  }

  if (config.notifFinanceiro) {
    const txSnap = await db
      .collection("users")
      .doc(uid)
      .collection("transactions")
      .where("status", "==", "pending")
      .where("date", ">=", cutoffTs)
      .where("date", "<=", endTs)
      .limit(600)
      .get();
    for (const doc of txSnap.docs) {
      const allSlots = planTransactionAgendaAlertSlots(doc, config, now);
      const newSlots = allSlots.filter((s) => leadSet.has(s.leadMin));
      if (newSlots.length) await appendAgendaAlertSlots(db, uid, newSlots, config);
    }
  }
}

async function cancelAgendaAlertsForRemovedLeads(db, uid, removedLeads) {
  const leadSet = new Set(removedLeads);
  const coll = db.collection("users").doc(uid).collection(AGENDA_ALERTS_COLL);
  const snap = await coll.where("status", "==", AGENDA_ALERT_STATUS.PENDING).limit(500).get();
  if (snap.empty) return;
  const batch = db.batch();
  const nowTs = admin.firestore.FieldValue.serverTimestamp();
  let ops = 0;
  for (const doc of snap.docs) {
    const leadMin = parseInt(doc.data().leadMin, 10) || 0;
    if (!leadSet.has(leadMin)) continue;
    batch.update(doc.ref, {
      status: AGENDA_ALERT_STATUS.CANCELLED,
      cancelReason: "lead_removed_from_settings",
      updatedAt: nowTs,
    });
    ops++;
  }
  if (ops > 0) await batch.commit();
}

async function refreshPendingAgendaAlertDeliveryFlags(db, uid, config) {
  const coll = db.collection("users").doc(uid).collection(AGENDA_ALERTS_COLL);
  const snap = await coll.where("status", "==", AGENDA_ALERT_STATUS.PENDING).limit(500).get();
  if (snap.empty) return;
  let batch = db.batch();
  let ops = 0;
  for (const doc of snap.docs) {
    const ch = (doc.data().channelKind || "").toString();
    batch.update(doc.ref, {
      pushEnabled: agendaDelivery.allowsPushForChannel(config, ch),
      emailEnabled: agendaDelivery.allowsEmailForChannel(config, ch),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    ops++;
    if (ops >= 400) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  }
  if (ops > 0) await batch.commit();
}

function reminderNotifyEnabledForChannel(config, channelKind) {
  const k = (channelKind || "").toString().toLowerCase();
  if (k === "audiencia") return config.notifAudiencias !== false;
  if (k === "compromisso") return config.notifCompromissos !== false;
  return config.notifCompromissos !== false || config.notifAudiencias !== false;
}

async function getUserFcmTokens(db, uid, userData) {
  const seen = new Set();
  const tokens = [];
  const addToken = (raw) => {
    const t = (raw || "").toString().trim();
    if (t.length > 20 && !seen.has(t)) {
      seen.add(t);
      tokens.push(t);
    }
  };
  const addDoc = (d) => {
    const data = d.data() || {};
    addToken(data.token || d.id);
  };
  const userRef = db.collection("users").doc(uid);
  const deviceSnap = await userRef.collection("deviceTokens").get();
  deviceSnap.docs.forEach(addDoc);
  const fcmSnap = await userRef.collection("fcmTokens").get();
  fcmSnap.docs.forEach(addDoc);
  addToken(userData?.fcmToken);
  return tokens;
}

function fcmTokenDocId(token) {
  const clean = (token || "").toString().trim();
  if (clean.length > 0 && clean.length <= 512 && !clean.includes("/")) return clean;
  return crypto.createHash("sha256").update(clean).digest("hex");
}

async function deleteInvalidFcmToken(db, uid, badToken) {
  const t = (badToken || "").toString().trim();
  if (!t || t.length < 8) return;
  const userRef = db.collection("users").doc(uid);
  const docIds = new Set([t, fcmTokenDocId(t)]);
  for (const sub of ["deviceTokens", "fcmTokens"]) {
    for (const docId of docIds) {
      await userRef.collection(sub).doc(docId).delete().catch(() => {});
    }
    try {
      const q = await userRef.collection(sub).where("token", "==", t).limit(8).get();
      for (const doc of q.docs) {
        await doc.ref.delete().catch(() => {});
      }
    } catch (_) {}
  }
  try {
    const snap = await userRef.get();
    const legacy = (snap.data()?.fcmToken || "").toString().trim();
    if (legacy === t) {
      await userRef.set({ fcmToken: admin.firestore.FieldValue.delete() }, { merge: true });
    }
  } catch (_) {}
}

/** Planeja slots de alerta para reminder (audiência/compromisso). */
function planReminderAgendaAlertSlots(docSnap, config, now) {
  const d = docSnap.data();
  const docId = docSnap.id;
  if (!isReminderOpenForNotify(d)) return [];
  const dateTs = d.date;
  const timeStr = (d.time || "09:00").toString();
  if (!dateTs || !timeStr) return [];
  const date = dateTs.toDate ? dateTs.toDate() : new Date(dateTs.seconds * 1000);
  const parts = getDatePartsBrasilia(date);
  const [h, m] = timeStr.split(":").map((x) => parseInt(x, 10) || 0);
  const reminderAt = dateInBrasilia(parts.year, parts.month + 1, parts.day, h, m, 0);
  if (!isAgendaEventForwardEligible(reminderAt, now)) return [];
  if (!isReminderEligibleForServerNotify(d, reminderAt, now)) return [];

  const type = (d.type || "compromisso").toString().toLowerCase();
  const channelKind = type === "audiencia" ? "audiencia" : "compromisso";
  if (type === "audiencia" && !config.notifAudiencias) return [];
  if (type !== "audiencia" && !config.notifCompromissos) return [];
  const eventTitle = (d.title || (type === "audiencia" ? "Audiência" : "Compromisso")).toString().trim();
  const isAud = type === "audiencia";
  const leads = reminderLeadsForDoc(d, config.globalLeads);
  const slots = [];

  for (const leadMin of leads) {
    if (agendaDelivery.isAgendaLeadDeliveryComplete(d, leadMin, config, channelKind)) continue;
    const notifyAt = agendaNotifyAtForLead(reminderAt, leadMin, now);
    if (!notifyAt || !isAgendaLeadSlotSchedulable(reminderAt, notifyAt, now)) continue;
    const leadLabel = agendaMsg.leadTitlePrefix(leadMin);
    const built = agendaMsg.buildAlertSlotForReminder(d, reminderAt, timeStr, leadMin, now);
    slots.push({
      alertId: agendaAlertDocId("reminder", docId, leadMin),
      sourceType: "reminder",
      sourceId: docId,
      leadMin,
      notifyAt,
      eventAt: reminderAt,
      channelKind: built.channelKind || channelKind,
      title: built.title,
      body: built.body,
      eventTitle,
      timeStr,
      date,
    });
  }
  return slots;
}

/** Planeja slots de alerta para escala/plantão. */
function planScaleAgendaAlertSlots(docSnap, config, now, notifEscalas) {
  const d = docSnap.data();
  const docId = docSnap.id;
  if (d.isAgendaMirror === true) return [];
  if (d.isProdutividadeFolgaMirror === true) return [];
  const isCompromisso = d.isCompromisso === true;
  if (isCompromisso && !config.notifCompromissos) return [];
  if (!isCompromisso && !config.notifEscalas) return [];

  const dateTs = d.date;
  const startStr = (d.start || "08:00").toString();
  if (!dateTs || !startStr) return [];
  const date = dateTs.toDate ? dateTs.toDate() : new Date(dateTs.seconds * 1000);
  const parts = getDatePartsBrasilia(date);
  const [h, m] = String(startStr).split(":").map((x) => parseInt(x, 10) || 0);
  const shiftStart = dateInBrasilia(parts.year, parts.month + 1, parts.day, h, m, 0);
  if (!isAgendaEventForwardEligible(shiftStart, now)) return [];
  if (shiftStart <= now) return [];

  const leads = reminderLeadsForDoc(d, config.globalLeads);
  const label = (d.label || d.scaleLocationName || d.abbreviation || "Plantão").toString().trim();
  const channelKind = isCompromisso ? "compromisso" : "escala";
  const slots = [];

  for (const leadMin of leads) {
    if (agendaDelivery.isAgendaLeadDeliveryComplete(d, leadMin, config, channelKind)) continue;
    const notifyAt = agendaNotifyAtForLead(shiftStart, leadMin, now);
    if (!notifyAt || !isAgendaLeadSlotSchedulable(shiftStart, notifyAt, now)) continue;
    const builtScale = agendaMsg.buildAlertSlotForScale(d, shiftStart, startStr, leadMin, now);
    slots.push({
      alertId: agendaAlertDocId("scale", docId, leadMin),
      sourceType: "scale",
      sourceId: docId,
      leadMin,
      notifyAt,
      eventAt: shiftStart,
      channelKind: builtScale.channelKind || channelKind,
      title: builtScale.title,
      body: builtScale.body,
      eventTitle: label || "Plantão",
      startStr,
      date,
    });
  }
  return slots;
}

/** Planeja slots de alerta para transação financeira pendente (conta a pagar/receber). */
function planTransactionAgendaAlertSlots(docSnap, config, now) {
  if (!config.notifFinanceiro) return [];
  const d = docSnap.data();
  const docId = docSnap.id;
  const status = (d.status || "").toString().toLowerCase();
  if (status !== "pending") return [];
  const type = (d.type || "expense").toString().toLowerCase();
  if (type !== "income" && type !== "expense") return [];
  const dateTs = d.date;
  if (!dateTs) return [];
  const date = dateTs.toDate ? dateTs.toDate() : new Date(dateTs.seconds * 1000);
  const parts = getDatePartsBrasilia(date);
  // Vencimento às 09:00 (Brasília) — mesmo horário usado no lembrete financeiro local.
  const dueAt = dateInBrasilia(parts.year, parts.month + 1, parts.day, 9, 0, 0);
  if (!isAgendaEventForwardEligible(dueAt, now)) return [];

  const channelKind = "financeiro";
  const leads = reminderLeadsForDoc(d, config.globalLeads);
  const eventTitle = type === "income" ? "Conta a receber" : "Conta a pagar";
  const slots = [];

  for (const leadMin of leads) {
    if (agendaDelivery.isAgendaLeadDeliveryComplete(d, leadMin, config, channelKind)) continue;
    const notifyAt = agendaNotifyAtForLead(dueAt, leadMin, now);
    if (!notifyAt || !isAgendaLeadSlotSchedulable(dueAt, notifyAt, now)) continue;
    const built = agendaMsg.buildAlertSlotForTransaction(d, dueAt, leadMin, now);
    slots.push({
      alertId: agendaAlertDocId("transaction", docId, leadMin),
      sourceType: "transaction",
      sourceId: docId,
      leadMin,
      notifyAt,
      eventAt: dueAt,
      channelKind: built.channelKind || channelKind,
      title: built.title,
      body: built.body,
      eventTitle,
      date,
    });
  }
  return slots;
}

function parseEventAtFromReminderData(d) {
  const dateTs = d?.date;
  const timeStr = (d?.time || "09:00").toString();
  if (!dateTs) return null;
  const date = dateTs.toDate ? dateTs.toDate() : new Date(dateTs.seconds * 1000);
  const parts = getDatePartsBrasilia(date);
  const [h, m] = timeStr.split(":").map((x) => parseInt(x, 10) || 0);
  return dateInBrasilia(parts.year, parts.month + 1, parts.day, h, m, 0);
}

function parseEventAtFromScaleData(d) {
  const dateTs = d?.date;
  const startStr = (d?.start || "08:00").toString();
  if (!dateTs) return null;
  const date = dateTs.toDate ? dateTs.toDate() : new Date(dateTs.seconds * 1000);
  const parts = getDatePartsBrasilia(date);
  const [h, m] = String(startStr).split(":").map((x) => parseInt(x, 10) || 0);
  return dateInBrasilia(parts.year, parts.month + 1, parts.day, h, m, 0);
}

function normalizeReminderLeadsKey(d) {
  const raw = Array.isArray(d?.reminderLeads) ? d.reminderLeads : [];
  return raw
    .map((x) => parseInt(x, 10) || 0)
    .filter((x) => x > 0)
    .sort((a, b) => a - b)
    .join(",");
}

/** Data/horário do evento mudou (horário de Brasília, 24h). */
function didAgendaScheduleChange(beforeData, afterData, sourceType) {
  if (!beforeData || !afterData) return false;
  const beforeAt =
    sourceType === "reminder"
      ? parseEventAtFromReminderData(beforeData)
      : parseEventAtFromScaleData(beforeData);
  const afterAt =
    sourceType === "reminder"
      ? parseEventAtFromReminderData(afterData)
      : parseEventAtFromScaleData(afterData);
  if (!beforeAt || !afterAt) return true;
  return beforeAt.getTime() !== afterAt.getTime();
}

function agendaContentStr(v) {
  if (v == null) return "";
  if (typeof v === "boolean") return v ? "1" : "0";
  return String(v).trim();
}

/** Título, local, SEI/ocorrência, etc. — recria fila e permite novo push. */
function didAgendaContentChange(beforeData, afterData, sourceType) {
  if (!beforeData || !afterData) return false;
  const reminderFields = [
    "title",
    "type",
    "notes",
    "localAudiencia",
    "linkSalaAudiencia",
    "numeroSei",
    "numeroOcorrencia",
    "status",
  ];
  const scaleFields = [
    "label",
    "abbreviation",
    "scaleLocationName",
    "notes",
    "scaleNumber",
    "isCompromisso",
    "end",
    "start",
  ];
  const fields = sourceType === "reminder" ? reminderFields : scaleFields;
  return fields.some((f) => agendaContentStr(beforeData[f]) !== agendaContentStr(afterData[f]));
}

/** Campos que o cliente grava só para «tocar» a fila — não replanejam sozinhos. */
const AGENDA_QUEUE_METADATA_FIELDS = new Set([
  "agendaQueueTouchedAt",
  "agendaLoginDaySyncAt",
  "agendaNotifResyncAt",
  "agendaNotifMigratedAt",
  "agendaNotifMigratedV",
  "agendaNotifRescheduledAt",
  "updatedAt",
]);

/** Escrita só com metadados de fila (sem mudar evento) — ignora onWrite pesado. */
function isAgendaNotificationMetadataOnlyChange(beforeData, afterData) {
  if (!beforeData || !afterData) return false;
  const keys = new Set([...Object.keys(beforeData), ...Object.keys(afterData)]);
  for (const key of keys) {
    if (AGENDA_QUEUE_METADATA_FIELDS.has(key)) continue;
    const b = beforeData[key];
    const a = afterData[key];
    if (JSON.stringify(b) !== JSON.stringify(a)) return false;
  }
  return true;
}

/** Antecedências ou som/modo de notificação mudaram (não inclui toques de fila do cliente). */
function didAgendaNotifyPlanChange(beforeData, afterData) {
  if (!beforeData || !afterData) return false;
  if (normalizeReminderLeadsKey(beforeData) !== normalizeReminderLeadsKey(afterData)) return true;
  const fields = ["notificationSoundId", "notificationDeliveryMode"];
  return fields.some((f) => (beforeData[f] || "").toString() !== (afterData[f] || "").toString());
}

/** Cliente limpou «já notificado» para reabrir push/e-mail (reprogramação manual/automática). */
function didAgendaDeliveryFieldsCleared(beforeData, afterData, sourceType) {
  if (!beforeData || !afterData) return false;
  const hadPush =
    (Array.isArray(beforeData.notificadoLeads) && beforeData.notificadoLeads.length > 0) ||
    beforeData.notificadoEm != null;
  const hadEmail =
    Array.isArray(beforeData.emailNotificadoLeads) &&
    beforeData.emailNotificadoLeads.length > 0;
  const hadScaleFlag = sourceType === "scale" && beforeData.notificado === true;
  if (!hadPush && !hadEmail && !hadScaleFlag) return false;
  const hasPush =
    (Array.isArray(afterData.notificadoLeads) && afterData.notificadoLeads.length > 0) ||
    afterData.notificadoEm != null;
  const hasEmail =
    Array.isArray(afterData.emailNotificadoLeads) &&
    afterData.emailNotificadoLeads.length > 0;
  const hasScaleFlag = sourceType === "scale" && afterData.notificado === true;
  return (hadPush && !hasPush) || (hadEmail && !hasEmail) || (hadScaleFlag && !hasScaleFlag);
}

/** Item deixou de estar pendente (done/status) — replanejar e cancelar fila antiga. */
function didAgendaOpenStateChange(beforeData, afterData, sourceType) {
  if (!beforeData || !afterData) return false;
  if (sourceType === "reminder") {
    return isReminderOpenForNotify(beforeData) !== isReminderOpenForNotify(afterData);
  }
  return false;
}

/** Migração cliente → fila agendaAlerts (v2): reconstrói slots sem apagar notificadoLeads. */
function didAgendaNotifMigrationBump(beforeData, afterData) {
  if (!afterData) return false;
  const beforeV = parseInt(beforeData?.agendaNotifMigratedV, 10) || 0;
  const afterV = parseInt(afterData?.agendaNotifMigratedV, 10) || 0;
  return afterV > beforeV && afterV >= 2;
}

/** Limpa entrega no documento fonte para permitir novo push/e-mail. */
async function clearAgendaDeliveryOnSource(ref, sourceType) {
  const update = {
    notificadoLeads: admin.firestore.FieldValue.delete(),
    emailNotificadoLeads: admin.firestore.FieldValue.delete(),
    notificadoEm: admin.firestore.FieldValue.delete(),
    emailNotificadoEm: admin.firestore.FieldValue.delete(),
    agendaNotifRescheduledAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (sourceType === "scale") {
    update.notificado = admin.firestore.FieldValue.delete();
  }
  await ref.update(update);
}

/** Remove fila antiga do evento (inclui alertas já enviados) para replanejar. */
async function purgeAgendaAlertsForSource(db, uid, sourceType, sourceId) {
  const coll = db.collection("users").doc(uid).collection(AGENDA_ALERTS_COLL);
  const snap = await coll.where("sourceType", "==", sourceType).where("sourceId", "==", sourceId).get();
  if (snap.empty) return;
  let batch = db.batch();
  let ops = 0;
  for (const doc of snap.docs) {
    batch.delete(doc.ref);
    ops++;
    if (ops >= 400) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  }
  if (ops > 0) await batch.commit();
}

/** Grava/atualiza fila agendaAlerts para um evento; remove slots obsoletos. */
async function syncAgendaAlertSlots(db, uid, slots, config) {
  const coll = db.collection("users").doc(uid).collection(AGENDA_ALERTS_COLL);
  const nowTs = admin.firestore.FieldValue.serverTimestamp();
  const desiredIds = new Set(slots.map((s) => s.alertId));
  const sourceKeys = new Set(slots.map((s) => `${s.sourceType}:${s.sourceId}`));

  if (slots.length > 0) {
    const existingById = new Map();
    for (const key of sourceKeys) {
      const [sourceType, sourceId] = key.split(":");
      const existing = await coll
        .where("sourceType", "==", sourceType)
        .where("sourceId", "==", sourceId)
        .get();
      existing.docs.forEach((doc) => existingById.set(doc.id, doc));
    }

    let batch = db.batch();
    let ops = 0;
    for (const slot of slots) {
      const ref = coll.doc(slot.alertId);
      const prev = existingById.get(slot.alertId);
      const prevData = prev?.data() || {};
      const prevStatus = (prevData.status || "").toString();
      const keepSent = prevStatus === AGENDA_ALERT_STATUS.SENT;

      const payload = {
        sourceType: slot.sourceType,
        sourceId: slot.sourceId,
        leadMin: slot.leadMin,
        notifyAt: admin.firestore.Timestamp.fromDate(slot.notifyAt),
        eventAt: admin.firestore.Timestamp.fromDate(slot.eventAt),
        channelKind: slot.channelKind,
        title: slot.title,
        body: slot.body,
        eventTitle: slot.eventTitle,
        timeStr: slot.timeStr || null,
        startStr: slot.startStr || null,
        pushEnabled: agendaDelivery.allowsPushForChannel(config, slot.channelKind),
        emailEnabled: agendaDelivery.allowsEmailForChannel(config, slot.channelKind),
        planVersion: AGENDA_ALERT_PLAN_VERSION,
        updatedAt: nowTs,
      };

      if (keepSent) {
        payload.status = AGENDA_ALERT_STATUS.SENT;
        if (prevData.sentAt != null) payload.sentAt = prevData.sentAt;
      } else {
        payload.status = AGENDA_ALERT_STATUS.PENDING;
        payload.createdAt = prevData.createdAt || nowTs;
        payload.sentAt = admin.firestore.FieldValue.delete();
        payload.cancelReason = admin.firestore.FieldValue.delete();
      }

      batch.set(ref, payload, { merge: true });
      ops++;
      if (ops >= 400) {
        await batch.commit();
        batch = db.batch();
        ops = 0;
      }
    }
    if (ops > 0) await batch.commit();
  }

  for (const key of sourceKeys) {
    const [sourceType, sourceId] = key.split(":");
    const existing = await coll.where("sourceType", "==", sourceType).where("sourceId", "==", sourceId).get();
    const cancelBatch = db.batch();
    let cancelOps = 0;
    for (const doc of existing.docs) {
      if (!desiredIds.has(doc.id)) {
        const st = (doc.data().status || "").toString();
        if (st === AGENDA_ALERT_STATUS.SENT) continue;
        cancelBatch.update(doc.ref, {
          status: AGENDA_ALERT_STATUS.CANCELLED,
          updatedAt: nowTs,
          cancelReason: "plan_outdated",
        });
        cancelOps++;
      }
    }
    if (cancelOps > 0) await cancelBatch.commit();
  }
}

async function updateAgendaAlertDoc(ref, fields) {
  await ref.update({
    ...fields,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

function didAgendaQueueTouchChange(beforeData, afterData) {
  if (!beforeData || !afterData) return false;
  return (
    agendaContentStr(beforeData.agendaLoginDaySyncAt) !== agendaContentStr(afterData.agendaLoginDaySyncAt) ||
    agendaContentStr(beforeData.agendaQueueTouchedAt) !== agendaContentStr(afterData.agendaQueueTouchedAt) ||
    agendaContentStr(beforeData.agendaNotifResyncAt) !== agendaContentStr(afterData.agendaNotifResyncAt)
  );
}

/** Cliente tocou fila (login / migração) — recria slots se faltarem e dispara vencidos. */
async function resyncAgendaAlertsAfterQueueTouch(db, uid, now, sourceType, docSnap, config) {
  if (sourceType === "reminder") {
    const d = docSnap.data() || {};
    if (!isReminderOpenForNotify(d)) {
      await cancelAgendaAlertsForSource(db, uid, "reminder", docSnap.id);
      return processDueAgendaAlertsForUser(db, uid, now);
    }
    const slots = planReminderAgendaAlertSlots(docSnap, config, now);
    if (slots.length === 0) {
      await cancelAgendaAlertsForSource(db, uid, "reminder", docSnap.id);
    } else {
      await syncAgendaAlertSlots(db, uid, slots, config);
    }
  } else {
    const d = docSnap.data() || {};
    if (d.isAgendaMirror === true || d.isProdutividadeFolgaMirror === true) {
      await cancelAgendaAlertsForSource(db, uid, "scale", docSnap.id);
      return processDueAgendaAlertsForUser(db, uid, now);
    }
    const slots = planScaleAgendaAlertSlots(docSnap, config, now, config.notifEscalas);
    if (slots.length === 0) {
      await cancelAgendaAlertsForSource(db, uid, "scale", docSnap.id);
    } else {
      await syncAgendaAlertSlots(db, uid, slots, config);
    }
  }
  return processDueAgendaAlertsForUser(db, uid, now);
}

/** Pendentes muito atrasados sem envio (sem token/e-mail) — sai de «A enviar». */
async function reconcileOverduePendingAgendaAlerts(db, uid, alertDocs, now) {
  const graceMs = 120 * 60 * 1000;
  for (const alertDoc of alertDocs) {
    const a = alertDoc.data();
    if ((a.status || "").toString() !== AGENDA_ALERT_STATUS.PENDING) continue;
    const notifyAt = a.notifyAt?.toDate ? a.notifyAt.toDate() : new Date(a.notifyAt);
    if (notifyAt > now) continue;
    if (now.getTime() - notifyAt.getTime() < graceMs) continue;
    await updateAgendaAlertDoc(alertDoc.ref, {
      status: AGENDA_ALERT_STATUS.SKIPPED,
      cancelReason: "delivery_timeout",
    });
  }
}

async function cancelAgendaAlertsForSource(db, uid, sourceType, sourceId) {
  const coll = db.collection("users").doc(uid).collection(AGENDA_ALERTS_COLL);
  const snap = await coll.where("sourceType", "==", sourceType).where("sourceId", "==", sourceId).get();
  if (snap.empty) return;
  const batch = db.batch();
  const nowTs = admin.firestore.FieldValue.serverTimestamp();
  snap.docs.forEach((doc) => {
    batch.update(doc.ref, {
      status: AGENDA_ALERT_STATUS.CANCELLED,
      updatedAt: nowTs,
      cancelReason: "source_deleted",
    });
  });
  await batch.commit();
}

/** Converte alertas vencidos em mensagens para dispatchAgendaReminderMessages. */
async function buildDispatchMessagesFromAgendaAlerts(db, uid, alertDocs, now) {
  const toSend = [];
  const reminderCache = new Map();
  const scaleCache = new Map();
  const transactionCache = new Map();

  for (const alertDoc of alertDocs) {
    const a = alertDoc.data();
    if (a.status !== AGENDA_ALERT_STATUS.PENDING) continue;
    const notifyAt = a.notifyAt?.toDate ? a.notifyAt.toDate() : new Date(a.notifyAt);
    if (notifyAt > now) continue;

    const eventAt = a.eventAt?.toDate ? a.eventAt.toDate() : null;
    if (eventAt && eventAt <= now) {
      await updateAgendaAlertDoc(alertDoc.ref, {
        status: AGENDA_ALERT_STATUS.SKIPPED,
        cancelReason: "event_started",
      });
      continue;
    }

    const sourceType = (a.sourceType || "").toString();
    const sourceId = (a.sourceId || "").toString();
    const leadMin = parseInt(a.leadMin, 10) || 0;
    if (!sourceId || leadMin <= 0) continue;

    if (sourceType === "reminder") {
      let src = reminderCache.get(sourceId);
      if (!src) {
        const ref = db.collection("users").doc(uid).collection("reminders").doc(sourceId);
        const snap = await ref.get();
        if (!snap.exists) {
          await alertDoc.ref.update({
            status: AGENDA_ALERT_STATUS.CANCELLED,
            cancelReason: "source_missing",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          continue;
        }
        src = { ref, snap };
        reminderCache.set(sourceId, src);
      }
      const d = src.snap.data();
      if (!isReminderOpenForNotify(d)) {
        await updateAgendaAlertDoc(alertDoc.ref, {
          status: AGENDA_ALERT_STATUS.CANCELLED,
          cancelReason: "event_closed",
        });
        continue;
      }
      const date = a.eventAt?.toDate ? a.eventAt.toDate() : (a.date?.toDate ? a.date.toDate() : new Date());
      const timeStr = (a.timeStr || d.time || "09:00").toString();
      const channelKind =
        (a.channelKind || "").toString() ||
        ((d.type || "").toString().toLowerCase() === "audiencia" ? "audiencia" : "compromisso");
      toSend.push({
        title: a.title,
        body: a.body,
        path: notifTpl.agendaDeepLinkPath(channelKind, "reminder"),
        reminderRef: src.ref,
        reminderData: d,
        date,
        timeStr,
        leadMin,
        agendaAlertRef: alertDoc.ref,
        channelKind,
      });
    } else if (sourceType === "scale") {
      let src = scaleCache.get(sourceId);
      if (!src) {
        const ref = db.collection("users").doc(uid).collection("scales").doc(sourceId);
        const snap = await ref.get();
        if (!snap.exists) {
          await alertDoc.ref.update({
            status: AGENDA_ALERT_STATUS.CANCELLED,
            cancelReason: "source_missing",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          continue;
        }
        src = { ref, snap };
        scaleCache.set(sourceId, src);
      }
      const d = src.snap.data();
      if (d.isAgendaMirror === true || d.isProdutividadeFolgaMirror === true) {
        await updateAgendaAlertDoc(alertDoc.ref, {
          status: AGENDA_ALERT_STATUS.CANCELLED,
          cancelReason: "agenda_mirror",
        });
        continue;
      }
      const date = a.eventAt?.toDate ? a.eventAt.toDate() : (a.date?.toDate ? a.date.toDate() : new Date());
      const startStr = (a.startStr || d.start || "08:00").toString();
      const channelKind =
        (a.channelKind || "").toString() ||
        (d.isCompromisso === true ? "compromisso" : "escala");
      toSend.push({
        title: a.title,
        body: a.body,
        path: notifTpl.agendaDeepLinkPath(channelKind, "scale"),
        scaleRef: src.ref,
        scaleData: d,
        date,
        startStr,
        leadMin,
        agendaAlertRef: alertDoc.ref,
        channelKind,
      });
    } else if (sourceType === "transaction") {
      let src = transactionCache.get(sourceId);
      if (!src) {
        const ref = db.collection("users").doc(uid).collection("transactions").doc(sourceId);
        const snap = await ref.get();
        if (!snap.exists) {
          await alertDoc.ref.update({
            status: AGENDA_ALERT_STATUS.CANCELLED,
            cancelReason: "source_missing",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          continue;
        }
        src = { ref, snap };
        transactionCache.set(sourceId, src);
      }
      const d = src.snap.data();
      // Conta já paga/baixada — não notificar mais.
      if ((d.status || "").toString().toLowerCase() === "paid") {
        await updateAgendaAlertDoc(alertDoc.ref, {
          status: AGENDA_ALERT_STATUS.CANCELLED,
          cancelReason: "event_closed",
        });
        continue;
      }
      const date = a.eventAt?.toDate ? a.eventAt.toDate() : (a.date?.toDate ? a.date.toDate() : new Date());
      toSend.push({
        title: a.title,
        body: a.body,
        path: notifTpl.agendaDeepLinkPath("financeiro", "transaction"),
        transactionRef: src.ref,
        transactionData: d,
        date,
        leadMin,
        agendaAlertRef: alertDoc.ref,
        channelKind: "financeiro",
      });
    }
  }
  return toSend;
}

/** Dispara alertas pending com notifyAt <= agora para um usuário. */
async function processDueAgendaAlertsForUser(db, uid, now) {
  const userDoc = await db.collection("users").doc(uid).get();
  if (!userDoc.exists) return { pushSent: 0, emailSent: 0 };
  const userData = userDoc.data();
  const config = await loadAgendaNotificationConfig(db, uid);
  if (!config.scaleReminderEnabled) return { pushSent: 0, emailSent: 0 };

  const coll = db.collection("users").doc(uid).collection(AGENDA_ALERTS_COLL);
  const eligible = [];
  let lastDoc = null;
  for (let page = 0; page < 5; page++) {
    let q = coll
      .where("status", "==", AGENDA_ALERT_STATUS.PENDING)
      .where("notifyAt", "<=", admin.firestore.Timestamp.fromDate(now))
      .orderBy("notifyAt")
      .limit(AGENDA_ALERTS_DUE_LIMIT);
    if (lastDoc) q = q.startAfter(lastDoc);
    const dueSnap = await q.get();
    if (dueSnap.empty) break;
    lastDoc = dueSnap.docs[dueSnap.docs.length - 1];

    for (const doc of dueSnap.docs) {
      const a = doc.data();
      if (a.pushEnabled === false && a.emailEnabled === false) continue;
      if (a.sourceType === "reminder") {
        const kind = (a.channelKind || "").toString();
        if (!reminderNotifyEnabledForChannel(config, kind)) continue;
      }
      if (a.sourceType === "scale") {
        const kind = (a.channelKind || "").toString();
        if (kind === "compromisso" && !config.notifCompromissos) continue;
        if (kind === "escala" && !config.notifEscalas) continue;
      }
      if (a.sourceType === "transaction" && !config.notifFinanceiro) continue;
      eligible.push(doc);
    }
    if (dueSnap.size < AGENDA_ALERTS_DUE_LIMIT) break;
  }

  if (eligible.length === 0) return { pushSent: 0, emailSent: 0 };

  const toSend = await buildDispatchMessagesFromAgendaAlerts(db, uid, eligible, now);

  let result = { pushSent: 0, emailSent: 0 };
  if (toSend.length > 0) {
    const tokens = await getUserFcmTokens(db, uid, userData);
    result = await dispatchAgendaReminderMessages(db, uid, userData, tokens, toSend, config);
  }

  await reconcileOverduePendingAgendaAlerts(db, uid, eligible, now);
  return result;
}

/** Cron: processa fila de alertas — só usuários com alertas vencidos (CG query). */
async function runProcessAgendaAlertQueue() {
  const db = admin.firestore();
  let totalPush = 0;
  let totalEmail = 0;
  const maxRounds = 20;

  for (let round = 0; round < maxRounds; round++) {
    const now = new Date();
    let dueSnap;
    try {
      dueSnap = await db
        .collectionGroup(AGENDA_ALERTS_COLL)
        .where("status", "==", AGENDA_ALERT_STATUS.PENDING)
        .where("notifyAt", "<=", admin.firestore.Timestamp.fromDate(now))
        .orderBy("notifyAt")
        .limit(AGENDA_ALERTS_DUE_LIMIT)
        .get();
    } catch (e) {
      console.error("[runProcessAgendaAlertQueue] collectionGroup failed:", e?.message || e);
      break;
    }

    if (dueSnap.empty) break;

    const uidSet = new Set();
    for (const doc of dueSnap.docs) {
      const uid = doc.ref.parent?.parent?.id;
      if (uid) uidSet.add(uid);
    }
    const uids = Array.from(uidSet);
    let roundPush = 0;
    let roundEmail = 0;

    for (let i = 0; i < uids.length; i += AGENDA_BATCH_SIZE) {
      const batch = uids.slice(i, i + AGENDA_BATCH_SIZE);
      const results = await Promise.all(
        batch.map((uid) => processDueAgendaAlertsForUser(db, uid, now)),
      );
      results.forEach((r) => {
        roundPush += r.pushSent;
        roundEmail += r.emailSent;
      });
    }

    totalPush += roundPush;
    totalEmail += roundEmail;

    if (dueSnap.size < AGENDA_ALERTS_DUE_LIMIT) break;
    if (roundPush === 0 && roundEmail === 0) break;
  }

  if (totalPush > 0 || totalEmail > 0) {
    console.log(
      `[runProcessAgendaAlertQueue] Push: ${totalPush}, E-mail: ${totalEmail}`,
    );
  }
}

/**
 * Reconstrói a fila agendaAlerts a partir de reminders/scales futuros (servidor).
 * Usado no login (callable) e evita leituras/gravações pesadas no app do usuário.
 */
async function rebuildUserAgendaAlertsWindow(db, uid, now, config) {
  if (!config.scaleReminderEnabled) {
    return { remindersSynced: 0, scalesSynced: 0 };
  }
  await resyncAgendaAlertsWindowForUser(db, uid, config, now);
  return { remindersSynced: 1, scalesSynced: 1 };
}

/**
 * Callable: monta/atualiza fila no servidor (login ou botão «Reorganizar»).
 * Cliente só dispara — push/e-mail e limpeza continuam no cron.
 */
async function resolveAgendaSyncUid(db, auth, requestedUid) {
  const authUid = auth.uid;
  const target = (requestedUid || authUid).toString().trim();
  if (!target || target === authUid) return authUid;
  const email = (auth.token?.email || "").toString().trim().toLowerCase();
  if (!email) {
    throw new functions.https.HttpsError("permission-denied", "Acesso negado.");
  }
  const snap = await db.collection("delegate_email_index").doc(email).get();
  const principalUid = (snap.data()?.principalUid || "").toString().trim();
  if (
    snap.exists &&
    snap.data()?.active === true &&
    principalUid === target
  ) {
    return target;
  }
  throw new functions.https.HttpsError("permission-denied", "Acesso negado.");
}

exports.ctResyncUserAgendaAlerts = onCall(
  { region: "us-central1", timeoutSeconds: 300 },
  async (req) => {
    if (!req.auth?.uid) {
      throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
    }
    const full = req.data?.full === true;
    const db = admin.firestore();
    const uid = await resolveAgendaSyncUid(db, req.auth, req.data?.targetUid);
    const now = new Date();
    const userRef = db.collection("users").doc(uid);

    if (!full) {
      const userSnap = await userRef.get();
      const v = parseInt(userSnap.data()?.agendaNotifUserMigratedV, 10) || 0;
      if (v >= AGENDA_USER_MIGRATED_V) {
        await processDueAgendaAlertsForUser(db, uid, now);
        return { ok: true, skipped: true, reminders: 0, scales: 0 };
      }
    }

    const config = await loadAgendaNotificationConfig(db, uid);
    const { remindersSynced, scalesSynced } = await rebuildUserAgendaAlertsWindow(
      db,
      uid,
      now,
      config,
    );
    await processDueAgendaAlertsForUser(db, uid, now);
    await userRef.set(
      {
        agendaNotifUserMigratedV: AGENDA_USER_MIGRATED_V,
        agendaNotifUserMigratedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return {
      ok: true,
      skipped: false,
      reminders: remindersSynced,
      scales: scalesSynced,
    };
  },
);

/** Dispara imediatamente alertas vencidos do usuário logado (catch-up manual). */
exports.ctProcessMyDueAgendaAlerts = onCall(
  { region: "us-central1", timeoutSeconds: 120 },
  async (req) => {
    if (!req.auth?.uid) {
      throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
    }
    const db = admin.firestore();
    const uid = await resolveAgendaSyncUid(db, req.auth, req.data?.targetUid);
    const now = new Date();
    const result = await processDueAgendaAlertsForUser(db, uid, now);
    const tokens = await getUserFcmTokens(db, uid, (await db.collection("users").doc(uid).get()).data() || {});
    return {
      ok: true,
      pushSent: result.pushSent,
      emailSent: result.emailSent,
      hasFcmToken: tokens.length > 0,
    };
  },
);

/** onWrite reminder: sincroniza fila + dispara o que já venceu. */
async function controlAgendaAlertsOnReminderWritten(event) {
  const db = admin.firestore();
  const uid = event.params.uid;
  const reminderId = event.params.reminderId;
  const before = event.data?.before;
  const after = event.data?.after;
  const now = new Date();

  if (!after?.exists) {
    await cancelAgendaAlertsForSource(db, uid, "reminder", reminderId);
    return;
  }

  const config = await loadAgendaNotificationConfig(db, uid);
  const isCreate = !before?.exists;
  const beforeData = before?.exists ? before.data() : null;
  const afterData = after.data();
  const remType = (afterData?.type || "compromisso").toString().toLowerCase();
  if (
    !config.scaleReminderEnabled ||
    (remType === "audiencia" && !config.notifAudiencias) ||
    (remType !== "audiencia" && !config.notifCompromissos)
  ) {
    await cancelAgendaAlertsForSource(db, uid, "reminder", reminderId);
    return;
  }

  if (!isCreate && beforeData && isAgendaNotificationMetadataOnlyChange(beforeData, afterData)) {
    if (didAgendaQueueTouchChange(beforeData, afterData)) {
      await resyncAgendaAlertsAfterQueueTouch(db, uid, now, "reminder", after, config);
    } else {
      await processDueAgendaAlertsForUser(db, uid, now);
    }
    return;
  }

  const migrationBump =
    !isCreate && beforeData && didAgendaNotifMigrationBump(beforeData, afterData);
  const mustReschedule =
    !isCreate &&
    beforeData &&
    (didAgendaScheduleChange(beforeData, afterData, "reminder") ||
      didAgendaNotifyPlanChange(beforeData, afterData) ||
      didAgendaDeliveryFieldsCleared(beforeData, afterData, "reminder") ||
      didAgendaOpenStateChange(beforeData, afterData, "reminder"));

  if (!isCreate && !mustReschedule && !migrationBump) {
    return;
  }

  if (mustReschedule) {
    await clearAgendaDeliveryOnSource(after.ref, "reminder");
    await purgeAgendaAlertsForSource(db, uid, "reminder", reminderId);
  } else if (migrationBump) {
    await purgeAgendaAlertsForSource(db, uid, "reminder", reminderId);
  }

  const freshSnap = mustReschedule || migrationBump ? await after.ref.get() : after;
  const freshData = freshSnap.data() || {};
  const slots = planReminderAgendaAlertSlots(freshSnap, config, now);
  if (!isReminderOpenForNotify(freshData) || slots.length === 0) {
    await cancelAgendaAlertsForSource(db, uid, "reminder", reminderId);
  } else {
    await syncAgendaAlertSlots(db, uid, slots, config);
  }
  const r = await processDueAgendaAlertsForUser(db, uid, now);
  if (r.pushSent > 0 || r.emailSent > 0 || mustReschedule || isCreate) {
    console.log(
      `[controlAgendaAlerts] reminder uid=${uid} id=${reminderId} created=${isCreate} rescheduled=${!!mustReschedule} slots=${slots.length} push=${r.pushSent} email=${r.emailSent}`,
    );
  }
}

/** onWrite scale: sincroniza fila + dispara o que já venceu. */
async function controlAgendaAlertsOnScaleWritten(event) {
  const db = admin.firestore();
  const uid = event.params.uid;
  const scaleId = event.params.scaleId;
  const before = event.data?.before;
  const after = event.data?.after;
  const now = new Date();

  if (!after?.exists) {
    await cancelAgendaAlertsForSource(db, uid, "scale", scaleId);
    return;
  }

  const d = after.data() || {};
  if (d.isAgendaMirror === true || d.isProdutividadeFolgaMirror === true) {
    await cancelAgendaAlertsForSource(db, uid, "scale", scaleId);
    return;
  }

  const config = await loadAgendaNotificationConfig(db, uid);
  if (!config.scaleReminderEnabled) {
    await cancelAgendaAlertsForSource(db, uid, "scale", scaleId);
    return;
  }
  const isCompromissoScale = d.isCompromisso === true;
  if (isCompromissoScale && !config.notifCompromissos) {
    await cancelAgendaAlertsForSource(db, uid, "scale", scaleId);
    return;
  }
  if (!isCompromissoScale && !config.notifEscalas) {
    await cancelAgendaAlertsForSource(db, uid, "scale", scaleId);
    return;
  }

  const isCreate = !before?.exists;
  const beforeData = before?.exists ? before.data() : null;
  const afterData = after.data();

  if (!isCreate && beforeData && isAgendaNotificationMetadataOnlyChange(beforeData, afterData)) {
    if (didAgendaQueueTouchChange(beforeData, afterData)) {
      await resyncAgendaAlertsAfterQueueTouch(db, uid, now, "scale", after, config);
    } else {
      await processDueAgendaAlertsForUser(db, uid, now);
    }
    return;
  }

  const migrationBump =
    !isCreate && beforeData && didAgendaNotifMigrationBump(beforeData, afterData);
  const mustReschedule =
    !isCreate &&
    beforeData &&
    (didAgendaScheduleChange(beforeData, afterData, "scale") ||
      didAgendaNotifyPlanChange(beforeData, afterData) ||
      didAgendaDeliveryFieldsCleared(beforeData, afterData, "scale"));

  if (!isCreate && !mustReschedule && !migrationBump) {
    return;
  }

  if (mustReschedule) {
    await clearAgendaDeliveryOnSource(after.ref, "scale");
    await purgeAgendaAlertsForSource(db, uid, "scale", scaleId);
  } else if (migrationBump) {
    await purgeAgendaAlertsForSource(db, uid, "scale", scaleId);
  }

  const freshSnap = mustReschedule || migrationBump ? await after.ref.get() : after;
  const slots = planScaleAgendaAlertSlots(freshSnap, config, now, config.notifEscalas);
  if (slots.length === 0) {
    await cancelAgendaAlertsForSource(db, uid, "scale", scaleId);
  } else {
    await syncAgendaAlertSlots(db, uid, slots, config);
  }
  const r = await processDueAgendaAlertsForUser(db, uid, now);
  if (r.pushSent > 0 || r.emailSent > 0 || mustReschedule || isCreate) {
    console.log(
      `[controlAgendaAlerts] scale uid=${uid} id=${scaleId} created=${isCreate} rescheduled=${!!mustReschedule} slots=${slots.length} push=${r.pushSent} email=${r.emailSent}`,
    );
  }
}

/** Vencimento, valor, descrição, tipo ou status mudaram (replaneja lembrete financeiro). */
function didTransactionScheduleOrContentChange(beforeData, afterData) {
  if (!beforeData || !afterData) return false;
  const bDate = beforeData.date?.toDate ? beforeData.date.toDate().getTime() : null;
  const aDate = afterData.date?.toDate ? afterData.date.toDate().getTime() : null;
  if (bDate !== aDate) return true;
  const fields = ["amount", "description", "category", "type", "status"];
  if (fields.some((f) => agendaContentStr(beforeData[f]) !== agendaContentStr(afterData[f]))) return true;
  return didAgendaNotifyPlanChange(beforeData, afterData);
}

/** Limpa marcas de entregue para permitir novo push quando a conta é reagendada. */
async function clearAgendaDeliveryOnTransaction(ref) {
  await ref.set(
    {
      notificadoLeads: admin.firestore.FieldValue.delete(),
      emailNotificadoLeads: admin.firestore.FieldValue.delete(),
      notificadoEm: admin.firestore.FieldValue.delete(),
      emailNotificadoEm: admin.firestore.FieldValue.delete(),
    },
    { merge: true },
  );
}

/** onWrite transação: sincroniza fila financeira + dispara o que já venceu. */
async function controlAgendaAlertsOnTransactionWritten(event) {
  const db = admin.firestore();
  const uid = event.params.uid;
  const txId = event.params.txId;
  const before = event.data?.before;
  const after = event.data?.after;
  const now = new Date();

  if (!after?.exists) {
    await cancelAgendaAlertsForSource(db, uid, "transaction", txId);
    return;
  }

  const afterData = after.data() || {};
  const config = await loadAgendaNotificationConfig(db, uid);
  const status = (afterData.status || "").toString().toLowerCase();
  if (!config.scaleReminderEnabled || !config.notifFinanceiro || status !== "pending") {
    await cancelAgendaAlertsForSource(db, uid, "transaction", txId);
    return;
  }

  const isCreate = !before?.exists;
  const beforeData = before?.exists ? before.data() : null;
  const mustReschedule =
    !isCreate && beforeData && didTransactionScheduleOrContentChange(beforeData, afterData);

  // Edição irrelevante (ex.: marca de entregue gravada no disparo) — o cron de 1 min cobre vencidos.
  if (!isCreate && !mustReschedule) {
    return;
  }

  if (mustReschedule) {
    await clearAgendaDeliveryOnTransaction(after.ref);
    await purgeAgendaAlertsForSource(db, uid, "transaction", txId);
  }

  const freshSnap = mustReschedule ? await after.ref.get() : after;
  const slots = planTransactionAgendaAlertSlots(freshSnap, config, now);
  if (slots.length === 0) {
    await cancelAgendaAlertsForSource(db, uid, "transaction", txId);
  } else {
    await syncAgendaAlertSlots(db, uid, slots, config);
  }
  const r = await processDueAgendaAlertsForUser(db, uid, now);
  if (r.pushSent > 0 || r.emailSent > 0 || mustReschedule || isCreate) {
    console.log(
      `[controlAgendaAlerts] transaction uid=${uid} id=${txId} created=${isCreate} rescheduled=${!!mustReschedule} slots=${slots.length} push=${r.pushSent} email=${r.emailSent}`,
    );
  }
}

/** Processa um único usuário no cron de lembretes (agenda/escalas). Retorna { pushSent, emailSent }. */
async function processOneUserPushScaleAgenda(db, userDoc, now) {
  let pushSent = 0;
  let emailSent = 0;
  const uid = userDoc.id;
  const userData = userDoc.data();
  const email = (userData.email || "").toString().trim();
  const tokens = await getUserFcmTokens(db, uid, userData);
  const hasEmail = email && /^[^@]+@[^@]+\.[^@]+$/.test(email);

  try {
    const config = await loadAgendaNotificationConfig(db, uid);
    const notifData =
      (await db.collection("users").doc(uid).collection("settings").doc("notifications").get()).data() ||
      {};
    let reminderLeadsFromSettings = config.globalLeads;

    const toSend = [];

    if (config.scaleReminderEnabled && (config.notifEscalas || config.notifCompromissos)) {
      const scalesSnap = await db.collection("users").doc(uid).collection("scales").get();
      toSend.push(
        ...collectDueScaleMessages(
          scalesSnap.docs,
          reminderLeadsFromSettings,
          now,
          config.notifEscalas,
          config.notifCompromissos,
          config,
        ),
      );
    }

    if (config.scaleReminderEnabled && (config.notifAudiencias || config.notifCompromissos)) {
      const remindersSnap = await db.collection("users").doc(uid).collection("reminders").get();
      toSend.push(
        ...collectDueReminderMessages(remindersSnap.docs, reminderLeadsFromSettings, now, config),
      );
    }

    if (toSend.length > 0) {
      const deliveryFields = agendaDelivery.parseDeliveryFieldsFromNotifData(notifData);
      const dispatchConfig = {
        ...config,
        ...deliveryFields,
      };
      const dispatched = await dispatchAgendaReminderMessages(
        db,
        uid,
        userData,
        tokens,
        toSend,
        dispatchConfig,
      );
      pushSent += dispatched.pushSent;
      emailSent += dispatched.emailSent;
    }
  } catch (e) {
    console.warn(`pushScaleAgenda uid=${uid}:`, e?.message || e);
  }
  return { pushSent, emailSent };
}

async function runPushScaleAgenda() {
  const db = admin.firestore();
  const now = new Date();

  const usersSnap = await db.collection("users").get();
  const docs = usersSnap.docs;
  let pushSent = 0;
  let emailSent = 0;

  for (let i = 0; i < docs.length; i += AGENDA_BATCH_SIZE) {
    const batch = docs.slice(i, i + AGENDA_BATCH_SIZE);
    const results = await Promise.all(batch.map((d) => processOneUserPushScaleAgenda(db, d, now)));
    results.forEach((r) => {
      pushSent += r.pushSent;
      emailSent += r.emailSent;
    });
  }

  if (pushSent > 0 || emailSent > 0) {
    console.log(`[verificarAgendaEDisparar] Push: ${pushSent}, E-mail: ${emailSent}`);
  }
}

/**
 * Envia lembretes (e-mail + push) a partir de hoje, incluindo retroativos: horário de lembrete já passou
 * mas o evento ainda é futuro e não foi notificado. Um envio por escala/compromisso elegível.
 */
async function runEnviarLembretesRetroativos() {
  const db = admin.firestore();
  const now = new Date();
  const todayStart = startOfDayBrasilia(now);
  const todayParts = getDatePartsBrasilia(now);
  // Janela ampla: desde ontem 00:00 BRT para não perder eventos de "hoje" gravados em UTC (ex.: 28/02 00:00 UTC ou 12:00 UTC).
  const windowStart = new Date(todayStart.getTime() - 24 * 60 * 60 * 1000);
  const windowStartTs = admin.firestore.Timestamp.fromDate(windowStart);

  let pushSent = 0;
  let emailSent = 0;
  let errors = [];

  const usersSnap = await db.collection("users").get();

  for (const userDoc of usersSnap.docs) {
    const uid = userDoc.id;
    const userData = userDoc.data();
    const email = (userData.email || "").toString().trim();
    const tokens = await getUserFcmTokens(db, uid, userData);
    const hasEmail = email && /^[^@]+@[^@]+\.[^@]+$/.test(email);
    const name = (userData.name || "").toString().trim() || "Usuário";

    try {
      const config = await loadAgendaNotificationConfig(db, uid);
      const reminderLeadsFromSettings = config.globalLeads;

      const toSend = [];

      if (config.scaleReminderEnabled && (config.notifEscalas || config.notifCompromissos)) {
        const scalesSnap = await db
          .collection("users")
          .doc(uid)
          .collection("scales")
          .where("date", ">=", windowStartTs)
          .get();
        const scaleDocsToday = scalesSnap.docs.filter((doc) => {
          const dateTs = doc.data().date;
          if (!dateTs) return false;
          const date = dateTs.toDate ? dateTs.toDate() : new Date(dateTs.seconds * 1000);
          const docParts = getDatePartsBrasilia(date);
          return !(
            docParts.year < todayParts.year ||
            docParts.month < todayParts.month ||
            docParts.day < todayParts.day
          );
        });
        toSend.push(
          ...collectDueScaleMessages(
            scaleDocsToday,
            reminderLeadsFromSettings,
            now,
            config.notifEscalas,
            config.notifCompromissos,
            config,
          ),
        );
      }

      if (config.scaleReminderEnabled && (config.notifAudiencias || config.notifCompromissos)) {
        const remindersSnap = await db
          .collection("users")
          .doc(uid)
          .collection("reminders")
          .where("date", ">=", windowStartTs)
          .get();
        const reminderDocsToday = remindersSnap.docs.filter((doc) => {
          const dateTs = doc.data().date;
          if (!dateTs) return false;
          const date = dateTs.toDate ? dateTs.toDate() : new Date(dateTs.seconds * 1000);
          const remParts = getDatePartsBrasilia(date);
          return !(
            remParts.year < todayParts.year ||
            remParts.month < todayParts.month ||
            remParts.day < todayParts.day
          );
        });
        toSend.push(
          ...collectDueReminderMessages(reminderDocsToday, reminderLeadsFromSettings, now, config),
        );
      }

      if (toSend.length > 0) {
        const dispatched = await dispatchAgendaReminderMessages(
          db,
          uid,
          userData,
          tokens,
          toSend,
          config,
        );
        pushSent += dispatched.pushSent;
        emailSent += dispatched.emailSent;
      }
    } catch (e) {
      errors.push(`uid=${uid}: ${e?.message || e}`);
    }
  }

  if (pushSent > 0 || emailSent > 0 || errors.length > 0) {
    console.log(`[ctEnviarLembretesRetroativos] Push: ${pushSent}, E-mail: ${emailSent}${errors.length ? `, Erros: ${errors.length}` : ""}`);
  }
  return { ok: true, pushSent, emailSent, errors: errors.slice(0, 20) };
}

/**
 * Limpa campos de notificação de escalas e lembretes cuja data já passou (dia anterior ou antes).
 * Remove notificado, notificadoEm, emailNotificadoLeads, emailNotificadoEm para não encher o banco.
 * Roda todo dia às 03:00 (BRT).
 */
exports.ctLimparNotificacoesPassadas = onSchedule(
  { schedule: "0 3 * * *", timeZone: "America/Sao_Paulo", region: "us-central1" },
  async () => {
    try {
      await runLimparNotificacoesPassadas();
    } catch (e) {
      console.error("ctLimparNotificacoesPassadas:", e?.message || e);
    }
  }
);

async function runLimparNotificacoesPassadas() {
  const db = admin.firestore();
  const hojeStart = admin.firestore.Timestamp.fromDate(startOfDayBrasilia(new Date()));

  const usersSnap = await db.collection("users").get();
  let scalesCleaned = 0;
  let remindersCleaned = 0;
  let alertsCleaned = 0;

  for (const userDoc of usersSnap.docs) {
    const uid = userDoc.id;

    const scalesSnap = await db
      .collection("users")
      .doc(uid)
      .collection("scales")
      .where("date", "<", hojeStart)
      .orderBy("date", "desc")
      .limit(300)
      .get();

    for (const doc of scalesSnap.docs) {
      const d = doc.data();
      if (d.notificado !== undefined || d.emailNotificadoLeads !== undefined) {
        await doc.ref.update({
          notificado: admin.firestore.FieldValue.delete(),
          notificadoEm: admin.firestore.FieldValue.delete(),
          emailNotificadoLeads: admin.firestore.FieldValue.delete(),
          emailNotificadoEm: admin.firestore.FieldValue.delete(),
        });
        scalesCleaned++;
      }
    }

    const remindersSnap = await db
      .collection("users")
      .doc(uid)
      .collection("reminders")
      .where("date", "<", hojeStart)
      .orderBy("date", "desc")
      .limit(300)
      .get();

    for (const doc of remindersSnap.docs) {
      const d = doc.data();
      if (d.notificado !== undefined || d.notificadoLeads !== undefined || d.emailNotificado !== undefined || d.emailNotificadoLeads !== undefined) {
        await doc.ref.update({
          notificado: admin.firestore.FieldValue.delete(),
          notificadoEm: admin.firestore.FieldValue.delete(),
          notificadoLeads: admin.firestore.FieldValue.delete(),
          emailNotificado: admin.firestore.FieldValue.delete(),
          emailNotificadoLeads: admin.firestore.FieldValue.delete(),
          emailNotificadoEm: admin.firestore.FieldValue.delete(),
        });
        remindersCleaned++;
      }
    }

    const cutoffArchived = archivedAgendaAlertsVisibleSinceBrasilia(new Date());
    const cutoffTs = admin.firestore.Timestamp.fromDate(cutoffArchived);

    const sentSnap = await db
      .collection("users")
      .doc(uid)
      .collection(AGENDA_ALERTS_COLL)
      .where("status", "==", AGENDA_ALERT_STATUS.SENT)
      .where("sentAt", "<", cutoffTs)
      .limit(300)
      .get();

    for (const doc of sentSnap.docs) {
      await doc.ref.delete().catch(() => {});
      alertsCleaned++;
    }

    const sentLegacySnap = await db
      .collection("users")
      .doc(uid)
      .collection(AGENDA_ALERTS_COLL)
      .where("status", "==", AGENDA_ALERT_STATUS.SENT)
      .where("notifyAt", "<", cutoffTs)
      .limit(200)
      .get();

    for (const doc of sentLegacySnap.docs) {
      const d = doc.data();
      if (d.sentAt) continue;
      await doc.ref.delete().catch(() => {});
      alertsCleaned++;
    }
  }

  if (scalesCleaned > 0 || remindersCleaned > 0 || alertsCleaned > 0) {
    console.log(
      `[ctLimparNotificacoesPassadas] Escalas: ${scalesCleaned}, Lembretes: ${remindersCleaned}, Arquivadas agendaAlerts: ${alertsCleaned}`,
    );
  }
}

/**
 * Robô diário: todo dia às 08:00 (America/Sao_Paulo) consulta a coleção "compromissos",
 * filtra por data == hoje e notificado == false, envia push FCM para usuario_token e marca notificado.
 * Estrutura esperada em compromissos: { data (YYYY-MM-DD), notificado (bool), tipo, titulo, usuario_token }.
 */
exports.verificarCompromissosDiarios = onSchedule(
  { schedule: "0 8 * * *", timeZone: "America/Sao_Paulo", region: "us-central1" },
  async () => {
    try {
      const db = admin.firestore();
      const hoje = todayBrasiliaISO();

      const snapshot = await db
        .collection("compromissos")
        .where("data", "==", hoje)
        .where("notificado", "==", false)
        .get();

      if (snapshot.empty) return null;

      const promessas = [];
      snapshot.forEach((doc) => {
        const dados = doc.data();
        const token = (dados.usuario_token || "").toString().trim();
        if (!token) return;

        const titulo = (dados.titulo || "Compromisso").toString().trim();
        const tipo = (dados.tipo || "compromisso").toString();

        const message = {
          token,
          notification: {
            title: `ALERTA: ${tipo.toUpperCase()}`,
            body: `Você tem: ${titulo} hoje. Não esqueça!`,
          },
          data: {
            id: doc.id,
            tipo,
          },
          webpush: {
            fcmOptions: { link: APP_DOMAIN },
          },
        };

        promessas.push(
          admin
            .messaging()
            .send(message)
            .then(() => doc.ref.update({ notificado: true, notificadoEm: admin.firestore.FieldValue.serverTimestamp() }))
            .catch((err) => {
              console.warn(`verificarCompromissosDiarios ${doc.id}:`, err?.message || err);
            })
        );
      });

      await Promise.all(promessas);
      return null;
    } catch (e) {
      console.error("verificarCompromissosDiarios:", e?.message || e);
      return null;
    }
  }
);

const PACKAGE_NAME = "br.com.controletotalapp";

/** Verifica se o usuário é admin (cargo: publicação nas lojas). */
async function requireAdmin(uid) {
  const userSnap = await admin.firestore().doc(`users/${uid}`).get();
  const data = userSnap.data() || {};
  const role = (data.role || "").toString().toLowerCase();
  if (role !== "admin" && role !== "master") {
    throw new functions.https.HttpsError("permission-denied", "Apenas administradores podem publicar nas lojas.");
  }
}

/** Verifica se o usuário tem acesso ao painel admin (role admin ou master). */
async function requireAdminPanel(uid) {
  const userSnap = await admin.firestore().doc(`users/${uid}`).get();
  const data = userSnap.data() || {};
  const role = (data.role || "").toString().toLowerCase();
  const isAdmin = role === "admin" || role === "master";
  if (!isAdmin) {
    throw new functions.https.HttpsError("permission-denied", "Acesso restrito a administradores.");
  }
}

function normalizeEmail(v) {
  return (v || "").toString().trim().toLowerCase();
}

function partnershipMemberDocId(email) {
  return crypto.createHash("sha1").update(normalizeEmail(email)).digest("hex");
}

function extractEmailsFromCsvText(raw) {
  const txt = (raw || "").toString();
  const rx = /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi;
  const found = txt.match(rx) || [];
  const set = new Set();
  for (const e of found) {
    const email = normalizeEmail(e);
    if (email.includes("@")) set.add(email);
  }
  return [...set].sort();
}

function endOfDayDate(d) {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59, 59, 999);
}

function addDaysFromBase(baseDate, days) {
  const b = new Date(baseDate.getFullYear(), baseDate.getMonth(), baseDate.getDate());
  return endOfDayDate(new Date(b.getFullYear(), b.getMonth(), b.getDate() + days));
}

function startOfDayDate(d) {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0, 0);
}

/** yyyy-MM-DD → Date local (meia-noite). */
function parseDateOnlyLocal(iso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec((iso || "").toString().trim());
  if (!m) return null;
  const y = parseInt(m[1], 10);
  const mo = parseInt(m[2], 10) - 1;
  const d = parseInt(m[3], 10);
  return new Date(y, mo, d);
}

function normalizePartnershipPlanCode(raw) {
  let s = (raw || "").toString().trim().toLowerCase().replace(/[^a-z0-9_]/g, "");
  if (!s) return "premium_assego";
  if (s.length > 80) s = s.slice(0, 80);
  return s;
}

function isRetailPremiumPlanNorm(planNorm) {
  return planNorm === "premium" || planNorm === "premium_monthly" || planNorm === "premium_annual";
}

async function applyPartnershipLicenseToUserRef(userRef, partnership) {
  const snap = await userRef.get();
  if (!snap.exists) return { updated: false, reason: "not-found" };
  const d = snap.data() || {};
  const p = partnership || {};
  const partnershipId = (p.id || "").toString().trim();
  const partnershipName = (p.name || p.slug || "Convênio").toString();
  const partnershipSlug = (p.slug || partnershipId || "").toString().trim();
  const durationDays = Number.isFinite(Number(p.durationDays))
    ? Math.max(1, Number(p.durationDays))
    : 365;
  const planCode = normalizePartnershipPlanCode(p.planCode);
  let contractEnds = null;
  const ceRaw = p.contractEndsAt;
  if (ceRaw && typeof ceRaw.toDate === "function") {
    contractEnds = ceRaw.toDate();
  }
  /** Dias extras após o fim do contrato (renovação em atraso). Clamp no patch do convênio. */
  const renewalExtra = Number.isFinite(Number(p.licenseRenewalExtensionDays))
    ? Math.max(0, Math.min(120, Math.floor(Number(p.licenseRenewalExtensionDays))))
    : 0;
  let newExp;
  let graceEnd;
  if (contractEnds) {
    let expDate = endOfDayDate(contractEnds);
    if (renewalExtra > 0) {
      const cal = new Date(expDate.getFullYear(), expDate.getMonth(), expDate.getDate());
      expDate = endOfDayDate(new Date(cal.getFullYear(), cal.getMonth(), cal.getDate() + renewalExtra));
    }
    newExp = expDate;
    graceEnd = endOfDayDate(new Date(newExp.getFullYear(), newExp.getMonth(), newExp.getDate() + 3));
  } else {
    const existing = d.licenseExpiresAt?.toDate?.() || null;
    const now = new Date();
    const nowDay = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const existingDay = existing ? new Date(existing.getFullYear(), existing.getMonth(), existing.getDate()) : null;
    const base = existingDay && existingDay > nowDay ? existingDay : nowDay;
    newExp = addDaysFromBase(base, durationDays);
    graceEnd = endOfDayDate(new Date(newExp.getFullYear(), newExp.getMonth(), newExp.getDate() + 3));
  }
  await userRef.set({
    plan: planCode,
    planStatus: "active",
    assegoMember: partnershipSlug === "assego",
    assegoGrantedAt: partnershipSlug === "assego" ? admin.firestore.FieldValue.serverTimestamp() : admin.firestore.FieldValue.delete(),
    partnershipId,
    partnershipName,
    partnershipSlug,
    partnershipGrantedAt: admin.firestore.FieldValue.serverTimestamp(),
    licenseExpiresAt: admin.firestore.Timestamp.fromDate(newExp),
    licenseValidUntilIncludingGrace: admin.firestore.Timestamp.fromDate(graceEnd),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  return { updated: true, newExpirationISO: newExp.toISOString() };
}

async function ensurePartnershipExists(partnershipId, defaults = {}) {
  const id = (partnershipId || "").toString().trim().toLowerCase();
  if (!id) {
    throw new functions.https.HttpsError("invalid-argument", "partnershipId obrigatório.");
  }
  const ref = admin.firestore().collection("partnerships").doc(id);
  const snap = await ref.get();
  if (!snap.exists) {
    const name = (defaults.name || id.toUpperCase()).toString();
    const slug = (defaults.slug || id).toString().toLowerCase();
    const durationDays = Number.isFinite(Number(defaults.durationDays))
      ? Math.max(1, Number(defaults.durationDays))
      : 365;
    const planCode = normalizePartnershipPlanCode(defaults.planCode);
    await ref.set({
      name,
      slug,
      active: true,
      durationDays,
      planCode,
      autoApplyOnSignup: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    return { id, ...(await ref.get()).data() };
  }
  return { id, ...(snap.data() || {}) };
}

async function upsertPartnershipMembers(partnershipId, emails, source = "admin_csv") {
  const clean = [...new Set((emails || []).map(normalizeEmail).filter((e) => e.includes("@")))];
  if (clean.length === 0) {
    throw new functions.https.HttpsError("invalid-argument", "Informe ao menos um e-mail válido.");
  }
  const partnership = await ensurePartnershipExists(partnershipId);
  const db = admin.firestore();
  let imported = 0;
  let updatedUsers = 0;
  const invalid = [];
  for (const email of clean) {
    if (!email.includes("@")) {
      invalid.push(email);
      continue;
    }
    const docId = partnershipMemberDocId(email);
    await db.collection("partnerships").doc(partnership.id).collection("members").doc(docId).set({
      email,
      active: true,
      source,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    if ((partnership.slug || partnership.id) === "assego") {
      await db.collection("assego_members").doc(docId).set({
        email,
        active: true,
        source,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }
    imported++;

    const userSnap = await db.collection("users").where("email", "==", email).limit(1).get();
    if (!userSnap.empty) {
      const userRef = userSnap.docs[0].ref;
      const r = await applyPartnershipLicenseToUserRef(userRef, partnership);
      if (r.updated) updatedUsers++;
    }
  }
  return {
    ok: true,
    partnershipId: partnership.id,
    imported,
    updatedUsers,
    invalidCount: invalid.length,
    invalid,
  };
}

/**
 * Remove e-mails do convênio: membro inactive + usuário perde partnershipId/plano do convênio (volta premium varejo).
 * Opcionalmente alinha usuário só por plan (sem partnershipId) igual ao planCode do convênio.
 */
async function removeEmailsFromPartnership(partnershipId, rawEmails, source = "admin_remove") {
  const pid = (partnershipId || "").toString().trim().toLowerCase();
  if (!pid) {
    throw new functions.https.HttpsError("invalid-argument", "partnershipId obrigatório.");
  }
  const db = admin.firestore();
  const pSnap = await db.collection("partnerships").doc(pid).get();
  if (!pSnap.exists) {
    throw new functions.https.HttpsError("not-found", "Convênio não encontrado.");
  }
  const pdata = pSnap.data() || {};
  const planNorm = normalizePartnershipPlanCode(pdata.planCode || "");
  const slug = (pdata.slug || pid).toString().trim().toLowerCase();
  const clean = [...new Set((rawEmails || []).map(normalizeEmail).filter((e) => e.includes("@")))];
  if (clean.length === 0) {
    throw new functions.https.HttpsError("invalid-argument", "Informe ao menos um e-mail válido.");
  }
  if (clean.length > 200) {
    throw new functions.https.HttpsError("invalid-argument", "Máximo 200 e-mails por lote.");
  }
  let removedMembers = 0;
  let updatedUsers = 0;
  for (const email of clean) {
    const docId = partnershipMemberDocId(email);
    await db.collection("partnerships").doc(pid).collection("members").doc(docId).set({
      email,
      active: false,
      sourceRemoved: source,
      removedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    removedMembers++;
    if (slug === "assego") {
      await db.collection("assego_members").doc(docId).set({
        email,
        active: false,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }
    const userSnap = await db.collection("users").where("email", "==", email).limit(1).get();
    if (userSnap.empty) continue;
    const udoc = userSnap.docs[0];
    const u = udoc.data() || {};
    const uPid = (u.partnershipId || "").toString().trim().toLowerCase();
    const uPlan = normalizePartnershipPlanCode((u.plan || "").toString());
    const matchPid = uPid === pid;
    const matchPlanOnly = !matchPid && uPlan === planNorm && uPid.length === 0;
    if (!matchPid && !matchPlanOnly) continue;
    const patch = {
      plan: "premium",
      planStatus: "active",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (matchPid) {
      patch.partnershipId = admin.firestore.FieldValue.delete();
      patch.partnershipName = admin.firestore.FieldValue.delete();
      patch.partnershipSlug = admin.firestore.FieldValue.delete();
      patch.partnershipGrantedAt = admin.firestore.FieldValue.delete();
      if (slug === "assego") {
        patch.assegoMember = false;
        patch.assegoGrantedAt = admin.firestore.FieldValue.delete();
      }
    }
    await udoc.ref.set(patch, { merge: true });
    updatedUsers++;
  }
  return {
    ok: true,
    partnershipId: pid,
    removedMembers,
    updatedUsers,
    requested: clean.length,
  };
}

exports.ctRemoveEmailsFromPartnership = onCall(async (req) => {
  if (!req.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
  }
  await requireAdminPanel(req.auth.uid);
  const partnershipId = (req.data?.partnershipId || "").toString().trim().toLowerCase();
  const raw = Array.isArray(req.data?.emails) ? req.data.emails : [];
  return removeEmailsFromPartnership(partnershipId, raw, (req.data?.source || "admin_panel").toString());
});

/** Processa texto CSV já obtido (URL ou upload manual). Se [csvUrlForDoc] for null, não altera csvSourceUrl no doc. */
async function syncPartnershipMembersFromCsvBody(partnershipId, body, source, csvUrlForDoc, opts = {}) {
  const removeMissingNotInCsv = opts.removeMissingNotInCsv === true;
  const pid = (partnershipId || "").toString().trim().toLowerCase();
  if (!pid) {
    throw new functions.https.HttpsError("invalid-argument", "partnershipId obrigatório.");
  }
  const partnership = await ensurePartnershipExists(pid);
  const pRef = admin.firestore().collection("partnerships").doc(partnership.id);
  const b = (body || "").toString();
  if (b.length < 2) {
    throw new functions.https.HttpsError("invalid-argument", "Conteúdo do CSV vazio.");
  }
  if (b.length > 900000) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "CSV muito grande (máximo ~900 KB por envio). Use importação por URL ou divida o arquivo."
    );
  }

  const hash = crypto.createHash("sha1").update(b).digest("hex");
  const receivedAt = nowStampForFileName();
  const receivedPath = `exports/partnerships/${pid}/received/source_${receivedAt}.csv`;
  try {
    await admin
      .storage()
      .bucket()
      .file(receivedPath)
      .save(b, {
        contentType: "text/csv; charset=utf-8",
        resumable: false,
        metadata: { cacheControl: "no-store" },
      });
  } catch (e) {
    console.warn(
      `[partnershipCsv] aviso: não foi possível salvar snapshot do CSV recebido (${pid}):`,
      e?.message || e
    );
  }
  const emails = extractEmailsFromCsvText(b);
  const urlPatch = csvUrlForDoc
    ? { csvSourceUrl: csvUrlForDoc.toString().trim() }
    : {
        csvLastManualImportAt: admin.firestore.FieldValue.serverTimestamp(),
        csvLastImportKind: "manual_upload",
      };
  if (emails.length === 0) {
    await pRef.set(
      {
        ...urlPatch,
        csvLastHash: hash,
        csvLastSyncStatus: "received_no_valid_emails",
        csvLastSyncCount: 0,
        csvLatestSourcePath: receivedPath,
        csvLastSyncError:
          "CSV recebido, mas sem e-mails válidos (aguardando arquivo com coluna de e-mail).",
        csvLastSyncAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    return {
      ok: true,
      skipped: true,
      imported: 0,
      updatedUsers: 0,
      count: 0,
      csvLatestSourcePath: receivedPath,
      message:
        "CSV recebido sem e-mails válidos. Nenhum membro foi importado; aguardando arquivo no formato de e-mail.",
    };
  }

  const pSnap = await pRef.get();
  const pData = pSnap.data() || {};
  if ((pData.csvLastHash || "") === hash) {
    await pRef.set(
      {
        ...urlPatch,
        csvLastHash: hash,
        csvLastSyncStatus: "ok_no_changes",
        csvLastSyncCount: emails.length,
        csvLastSyncAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    return { ok: true, skipped: true, imported: 0, updatedUsers: 0, count: emails.length };
  }

  let pruneSummary = null;
  if (removeMissingNotInCsv && emails.length > 0) {
    const incoming = new Set(emails.map(normalizeEmail));
    const toRemove = [];
    try {
      const activeSnap = await pRef.collection("members").where("active", "==", true).limit(5000).get();
      for (const doc of activeSnap.docs) {
        const em = normalizeEmail(doc.data().email || "");
        if (em && !incoming.has(em)) toRemove.push(em);
      }
    } catch (e) {
      console.warn(`[partnershipCsv] prune list (${pid}):`, e?.message || e);
    }
    if (toRemove.length > 0) {
      pruneSummary = await removeEmailsFromPartnership(pid, toRemove, `${source}_csv_prune`);
    }
  }

  const upsertRes = await upsertPartnershipMembers(partnership.id, emails, source);
  const csvRes = await rebuildPartnershipMembersCsv(partnership.id);
  await pRef.set(
    {
      ...urlPatch,
      csvLastHash: hash,
      csvLastSyncStatus: "ok",
      csvLastSyncCount: emails.length,
      csvLastImported: upsertRes.imported || 0,
      csvLastUpdatedUsers: upsertRes.updatedUsers || 0,
      csvLastSyncAt: admin.firestore.FieldValue.serverTimestamp(),
      csvLastSyncError: admin.firestore.FieldValue.delete(),
      csvLatestPath: csvRes.latestPath,
      csvLatestSourcePath: receivedPath,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  return {
    ok: true,
    skipped: false,
    partnershipId: partnership.id,
    count: emails.length,
    imported: upsertRes.imported || 0,
    updatedUsers: upsertRes.updatedUsers || 0,
    csvLatestPath: csvRes.latestPath,
    csvLatestSourcePath: receivedPath,
    pruneSummary,
  };
}

async function syncPartnershipMembersFromCsvUrl(partnershipId, csvUrl, source = "external_csv", opts = {}) {
  const pid = (partnershipId || "").toString().trim().toLowerCase();
  const url = (csvUrl || "").toString().trim();
  if (!pid) {
    throw new functions.https.HttpsError("invalid-argument", "partnershipId obrigatório.");
  }
  if (!/^https?:\/\//i.test(url)) {
    throw new functions.https.HttpsError("invalid-argument", "csvUrl deve ser http(s) válido.");
  }
  const partnership = await ensurePartnershipExists(pid);
  const pRef = admin.firestore().collection("partnerships").doc(partnership.id);

  let body = "";
  try {
    const res = await fetch(url, {
      method: "GET",
      headers: { "accept": "text/csv,text/plain,application/octet-stream,*/*" },
    });
    if (!res.ok) {
      throw new Error(`HTTP ${res.status}`);
    }
    body = await res.text();
  } catch (e) {
    await pRef.set({
      csvSourceUrl: url,
      csvLastSyncStatus: "error",
      csvLastSyncError: (e?.message || String(e)).toString().slice(0, 300),
      csvLastSyncAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    throw new functions.https.HttpsError(
      "failed-precondition",
      `Falha ao baixar CSV: ${(e?.message || String(e)).toString().slice(0, 180)}`
    );
  }

  return syncPartnershipMembersFromCsvBody(partnership.id, body, source, url, opts);
}

function csvSafe(value) {
  const raw = (value ?? "").toString().replace(/"/g, "\"\"");
  return `"${raw}"`;
}

function nowStampForFileName() {
  const d = new Date();
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  const hh = String(d.getHours()).padStart(2, "0");
  const mm = String(d.getMinutes()).padStart(2, "0");
  const ss = String(d.getSeconds()).padStart(2, "0");
  return `${y}${m}${day}_${hh}${mm}${ss}`;
}

async function rebuildPartnershipMembersCsv(partnershipId) {
  const pid = (partnershipId || "").toString().trim().toLowerCase();
  if (!pid) {
    throw new functions.https.HttpsError("invalid-argument", "partnershipId obrigatório.");
  }
  const membersSnap = await admin
    .firestore()
    .collection("partnerships")
    .doc(pid)
    .collection("members")
    .where("active", "==", true)
    .get();

  const rows = membersSnap.docs
    .map((doc) => {
      const d = doc.data() || {};
      const updatedAt = d.updatedAt?.toDate?.() || null;
      return {
        email: normalizeEmail(d.email || ""),
        source: (d.source || "").toString(),
        updatedAtISO: updatedAt ? updatedAt.toISOString() : "",
      };
    })
    .filter((r) => r.email.includes("@"))
    .sort((a, b) => a.email.localeCompare(b.email));

  const lines = [
    "email;ativo;origem;atualizado_em_iso",
    ...rows.map((r) => [csvSafe(r.email), "true", csvSafe(r.source), csvSafe(r.updatedAtISO)].join(";")),
  ];
  const csv = `${lines.join("\n")}\n`;

  const bucket = admin.storage().bucket();
  const basePath = `exports/partnerships/${pid}`;
  const latestPath = `${basePath}/${pid}_membros_latest.csv`;
  const historyPath = `${basePath}/historico/${pid}_membros_${nowStampForFileName()}.csv`;

  await bucket.file(latestPath).save(csv, {
    resumable: false,
    contentType: "text/csv; charset=utf-8",
    metadata: {
      cacheControl: "no-cache, max-age=0",
    },
  });
  await bucket.file(historyPath).save(csv, {
    resumable: false,
    contentType: "text/csv; charset=utf-8",
  });

  return { ok: true, count: rows.length, latestPath, historyPath };
}

exports.ctUpsertPartnershipMembers = onCall(async (req) => {
  if (!req.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
  }
  await requireAdminPanel(req.auth.uid);
  const partnershipId = (req.data?.partnershipId || "").toString().trim().toLowerCase();
  const raw = Array.isArray(req.data?.emails) ? req.data.emails : [];
  const source = (req.data?.source || "admin_csv").toString().trim() || "admin_csv";
  return upsertPartnershipMembers(partnershipId, raw, source);
});

async function publicPartnershipSignup(partnershipId, payload = {}) {
  const pid = (partnershipId || "").toString().trim().toLowerCase();
  if (!pid) {
    throw new functions.https.HttpsError("invalid-argument", "partnershipId obrigatório.");
  }
  const name = (payload.name || "").toString().trim();
  const email = normalizeEmail(payload.email || "");
  const phone = (payload.phone || "").toString().trim();
  const cpf = (payload.cpf || "").toString().trim();
  const notes = (payload.notes || "").toString().trim();

  if (!name || name.length < 3) {
    throw new functions.https.HttpsError("invalid-argument", "Informe o nome completo.");
  }
  if (!email || !email.includes("@")) {
    throw new functions.https.HttpsError("invalid-argument", "Informe um e-mail válido.");
  }

  await ensurePartnershipExists(pid, {
    name: pid.toUpperCase(),
    slug: pid,
    durationDays: 365,
    planCode: "premium_assego",
  });

  const db = admin.firestore();
  const submissionRef = db
    .collection("partnerships")
    .doc(pid)
    .collection("submissions")
    .doc();

  await submissionRef.set({
    name,
    email,
    phone,
    cpf,
    notes,
    source: "public_form",
    status: "novo",
    partnershipId: pid,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  const applyRes = await upsertPartnershipMembers(pid, [email], `${pid}_public_form`);
  const csvRes = await rebuildPartnershipMembersCsv(pid);

  await submissionRef.set({
    status: "processado",
    partnershipApplied: true,
    csvLatestPath: csvRes.latestPath,
    processedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  await db.collection("admin_notifications").add({
    type: "partnership_new_signup",
    title: `Novo cadastro ${pid.toUpperCase()}`,
    message: `${name} (${email}) enviado pelo link público do convênio ${pid.toUpperCase()}.`,
    email,
    partnershipId: pid,
    submissionPath: submissionRef.path,
    read: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  const convenioLabel = pid.toUpperCase();
  const html = buildEmailBase(
    `Novo cadastro ${convenioLabel}`,
    `<p>Um novo cadastro foi enviado no link público do convênio ${escapeHtml(convenioLabel)}.</p>
     <div class="row-item"><strong>Nome:</strong> ${escapeHtml(name)}</div>
     <div class="row-item"><strong>E-mail:</strong> ${escapeHtml(email)}</div>
     <div class="row-item"><strong>Telefone:</strong> ${escapeHtml(phone || "-")}</div>
     <div class="row-item"><strong>CPF:</strong> ${escapeHtml(cpf || "-")}</div>
     <div class="row-item"><strong>Observações:</strong> ${escapeHtml(notes || "-")}</div>
     <div class="row-item"><strong>Convênio:</strong> ${escapeHtml(convenioLabel)}</div>
     <p><strong>CSV atualizado:</strong> <code>${escapeHtml(csvRes.latestPath)}</code></p>`
  );
  const emailRes = await sendEmailHtml(
    "raihom@gmail.com",
    `Controle Total — Novo cadastro ${convenioLabel}`,
    html
  );
  await submissionRef.set({
    notifiedEmail: emailRes.ok === true,
    emailNotifyError: emailRes.ok ? admin.firestore.FieldValue.delete() : (emailRes.error || "erro"),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  return {
    ok: true,
    partnershipId: pid,
    submissionId: submissionRef.id,
    imported: applyRes.imported || 0,
    updatedUsers: applyRes.updatedUsers || 0,
    csvLatestPath: csvRes.latestPath,
    emailNotified: emailRes.ok === true,
  };
}

/**
 * Cadastro público de convênio (sem login):
 * 1) salva pré-cadastro
 * 2) aplica membro no convênio
 * 3) atualiza CSV em Storage
 * 4) notifica admin por e-mail e no painel
 */
exports.ctPublicPartnershipSignup = onCall(async (req) => {
  const partnershipId = (req.data?.partnershipId || "").toString().trim().toLowerCase();
  return publicPartnershipSignup(partnershipId, req.data || {});
});

// Compatibilidade: link antigo da ASSEGO continua funcionando.
exports.ctPublicAssegoSignup = onCall(async (req) => {
  return publicPartnershipSignup("assego", req.data || {});
});

exports.ctCreateOrUpdatePartnership = onCall(async (req) => {
  if (!req.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
  }
  await requireAdminPanel(req.auth.uid);
  const id = (req.data?.id || req.data?.slug || "").toString().trim().toLowerCase();
  if (!id) throw new functions.https.HttpsError("invalid-argument", "id/slug obrigatório.");
  const name = (req.data?.name || id.toUpperCase()).toString().trim();
  const slug = (req.data?.slug || id).toString().trim().toLowerCase();
  const active = req.data?.active !== false;
  const durationDays = Number.isFinite(Number(req.data?.durationDays))
    ? Math.max(1, Number(req.data.durationDays))
    : 365;
  const planCode = normalizePartnershipPlanCode(req.data?.planCode);
  const autoApplyOnSignup = req.data?.autoApplyOnSignup !== false;
  const patch = {
    name,
    slug,
    active,
    durationDays,
    planCode,
    autoApplyOnSignup,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  const csRaw = req.data?.contractStartsAt;
  const ceRaw = req.data?.contractEndsAt;
  if (csRaw === "" || csRaw === null) {
    patch.contractStartsAt = admin.firestore.FieldValue.delete();
  } else if (typeof csRaw === "string" && csRaw.trim()) {
    const d = parseDateOnlyLocal(csRaw.trim());
    if (d) patch.contractStartsAt = admin.firestore.Timestamp.fromDate(startOfDayDate(d));
  }
  if (ceRaw === "" || ceRaw === null) {
    patch.contractEndsAt = admin.firestore.FieldValue.delete();
  } else if (typeof ceRaw === "string" && ceRaw.trim()) {
    const d = parseDateOnlyLocal(ceRaw.trim());
    if (d) patch.contractEndsAt = admin.firestore.Timestamp.fromDate(endOfDayDate(d));
  }
  const extDaysRaw = req.data?.licenseRenewalExtensionDays;
  if (extDaysRaw === "" || extDaysRaw === null || typeof extDaysRaw === "undefined") {
    // não altera o campo se não enviado (compatível com clientes antigos)
  } else if (Number.isFinite(Number(extDaysRaw))) {
    patch.licenseRenewalExtensionDays = Math.max(0, Math.min(120, Math.floor(Number(extDaysRaw))));
  }
  await admin.firestore().collection("partnerships").doc(id).set(patch, { merge: true });
  return { ok: true, id, name, slug, active, durationDays, planCode, autoApplyOnSignup };
});

async function renewPartnershipLicenses(partnershipId, onlyActive = true, unionPlanMatch = false) {
  const db = admin.firestore();
  const pid = (partnershipId || "").toString().trim().toLowerCase();
  const pSnap = await db.collection("partnerships").doc(pid).get();
  if (!pSnap.exists) {
    throw new functions.https.HttpsError("not-found", "Convênio não encontrado.");
  }
  const partnership = { id: pid, ...(pSnap.data() || {}) };
  const planNorm = normalizePartnershipPlanCode(partnership.planCode);
  const refsToUpdate = [];
  const seen = new Set();

  let q = db.collection("users").where("partnershipId", "==", pid);
  if (onlyActive) q = q.where("planStatus", "==", "active");
  const snapPid = await q.get();
  for (const doc of snapPid.docs) {
    if (!seen.has(doc.id)) {
      seen.add(doc.id);
      refsToUpdate.push(doc.ref);
    }
  }

  if (unionPlanMatch && !isRetailPremiumPlanNorm(planNorm)) {
    let q2 = db.collection("users").where("plan", "==", planNorm);
    if (onlyActive) q2 = q2.where("planStatus", "==", "active");
    const snapPlan = await q2.limit(5000).get();
    for (const doc of snapPlan.docs) {
      if (!seen.has(doc.id)) {
        seen.add(doc.id);
        refsToUpdate.push(doc.ref);
      }
    }
  }

  let renewed = 0;
  for (const ref of refsToUpdate) {
    const r = await applyPartnershipLicenseToUserRef(ref, partnership);
    if (r.updated) renewed++;
  }
  return { ok: true, partnershipId: pid, renewed, total: refsToUpdate.length };
}

exports.ctRenewPartnershipLicenses = onCall(async (req) => {
  if (!req.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
  }
  await requireAdminPanel(req.auth.uid);
  const partnershipId = (req.data?.partnershipId || "").toString().trim().toLowerCase();
  const onlyActive = req.data?.onlyActive !== false;
  const unionPlanMatch = req.data?.unionPlanMatch === true;
  return renewPartnershipLicenses(partnershipId, onlyActive, unionPlanMatch);
});

exports.ctBulkMigrateUsersToPartnership = onCall(async (req) => {
  if (!req.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
  }
  await requireAdminPanel(req.auth.uid);
  const partnershipId = (req.data?.partnershipId || "").toString().trim().toLowerCase();
  const rawUids = req.data?.uids;
  if (!partnershipId) {
    throw new functions.https.HttpsError("invalid-argument", "partnershipId obrigatório.");
  }
  const uids = Array.isArray(rawUids)
    ? rawUids.map((u) => (u || "").toString().trim()).filter(Boolean)
    : [];
  if (uids.length === 0) {
    throw new functions.https.HttpsError("invalid-argument", "Informe ao menos um usuário (UID).");
  }
  if (uids.length > 300) {
    throw new functions.https.HttpsError("invalid-argument", "Máximo 300 usuários por lote.");
  }
  const db = admin.firestore();
  const pSnap = await db.collection("partnerships").doc(partnershipId).get();
  if (!pSnap.exists) {
    throw new functions.https.HttpsError("not-found", "Convênio não encontrado.");
  }
  let partnership = { id: partnershipId, ...(pSnap.data() || {}) };
  const overrideRaw = (req.data?.planCodeOverride ?? "").toString().trim();
  if (overrideRaw.length > 0) {
    partnership = { ...partnership, planCode: normalizePartnershipPlanCode(overrideRaw) };
  }
  let updated = 0;
  const errors = [];
  for (const uid of uids) {
    try {
      const r = await applyPartnershipLicenseToUserRef(db.collection("users").doc(uid), partnership);
      if (r.updated) updated++;
    } catch (e) {
      errors.push({ uid, err: (e && e.message) ? e.message : String(e) });
    }
  }
  return {
    ok: true,
    partnershipId,
    requested: uids.length,
    updated,
    errorCount: errors.length,
    errors: errors.slice(0, 12),
  };
});

/**
 * Sincroniza membros de convênio a partir de um CSV externo (URL pública).
 * Uso: programador externo publica CSV; sistema puxa e aplica automaticamente.
 */
exports.ctSyncPartnershipCsvSource = onCall(async (req) => {
  if (!req.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
  }
  await requireAdminPanel(req.auth.uid);
  const partnershipId = (req.data?.partnershipId || "").toString().trim().toLowerCase();
  const csvUrlRaw = (req.data?.csvUrl || "").toString().trim();
  if (!partnershipId) {
    throw new functions.https.HttpsError("invalid-argument", "partnershipId obrigatório.");
  }
  const pRef = admin.firestore().collection("partnerships").doc(partnershipId);
  const pSnap = await pRef.get();
  const pData = pSnap.data() || {};
  const csvUrl = csvUrlRaw || (pData.csvSourceUrl || "").toString().trim();
  if (!csvUrl) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "csvUrl não configurado para este convênio."
    );
  }
  const opts = { removeMissingNotInCsv: req.data?.removeMissingNotInCsv === true };
  return syncPartnershipMembersFromCsvUrl(partnershipId, csvUrl, "external_csv", opts);
});

/**
 * Importação manual: admin envia o texto do CSV (upload no app). Mesma lógica de extração de e-mails da URL.
 * Não altera csvSourceUrl do convênio; grava csvLastImportKind = manual_upload.
 */
exports.ctImportPartnershipCsvManual = onCall(async (req) => {
  if (!req.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
  }
  await requireAdminPanel(req.auth.uid);
  const partnershipId = (req.data?.partnershipId || "").toString().trim().toLowerCase();
  const csvText = (req.data?.csvText ?? "").toString();
  if (!partnershipId) {
    throw new functions.https.HttpsError("invalid-argument", "partnershipId obrigatório.");
  }
  const opts = { removeMissingNotInCsv: req.data?.removeMissingNotInCsv === true };
  return syncPartnershipMembersFromCsvBody(partnershipId, csvText, "admin_manual_upload", null, opts);
});

/** Atalho admin para ASSEGO. */
exports.ctSyncAssegoCsvSource = onCall(async (req) => {
  if (!req.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
  }
  await requireAdminPanel(req.auth.uid);
  const csvUrlRaw = (req.data?.csvUrl || "").toString().trim();
  const pRef = admin.firestore().collection("partnerships").doc("assego");
  const pSnap = await pRef.get();
  const pData = pSnap.data() || {};
  const csvUrl = csvUrlRaw || (pData.csvSourceUrl || "").toString().trim();
  if (!csvUrl) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "csvUrl do ASSEGO não configurado."
    );
  }
  return syncPartnershipMembersFromCsvUrl("assego", csvUrl, "external_csv");
});

/**
 * Cron: tenta sincronizar CSV externo da ASSEGO automaticamente.
 * Programador externo só atualiza o CSV no mesmo link.
 */
exports.ctSyncAssegoCsvScheduled = onSchedule(
  { schedule: "every 10 minutes", timeZone: TZ_BRASILIA, retryCount: 0 },
  async () => {
    const pRef = admin.firestore().collection("partnerships").doc("assego");
    const pSnap = await pRef.get();
    const pData = pSnap.data() || {};
    const csvUrl = (pData.csvSourceUrl || "").toString().trim();
    if (!csvUrl) {
      return null;
    }
    try {
      await syncPartnershipMembersFromCsvUrl("assego", csvUrl, "external_csv_scheduled");
    } catch (e) {
      console.warn("[ctSyncAssegoCsvScheduled]", e?.message || e);
    }
    return null;
  }
);

exports.ctApplyPartnershipOnUserCreate = onDocumentCreated("users/{uid}", async (event) => {
  const snap = event.data;
  if (!snap) return;
  const d = snap.data() || {};
  const email = normalizeEmail(d.email);
  if (!email) return;
  const memberId = partnershipMemberDocId(email);
  const ps = await admin.firestore().collection("partnerships").where("active", "==", true).get();
  for (const pDoc of ps.docs) {
    const pdata = pDoc.data() || {};
    if (pdata.autoApplyOnSignup === false) continue;
    const mSnap = await pDoc.ref.collection("members").doc(memberId).get();
    if (!mSnap.exists) continue;
    const md = mSnap.data() || {};
    if (md.active === false) continue;
    await applyPartnershipLicenseToUserRef(snap.ref, { id: pDoc.id, ...pdata });
    break;
  }
});

// Compatibilidade ASSEGO existente.
exports.ctUpsertAssegoMembers = onCall(async (req) => {
  if (!req.auth) throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
  await requireAdminPanel(req.auth.uid);
  await ensurePartnershipExists("assego", {
    name: "ASSEGO",
    slug: "assego",
    durationDays: 365,
    planCode: "premium_assego",
  });
  const raw = Array.isArray(req.data?.emails) ? req.data.emails : [];
  return upsertPartnershipMembers("assego", raw, "admin_csv");
});

exports.ctRenewAssegoLicenses = onCall(async (req) => {
  if (!req.auth) throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
  await requireAdminPanel(req.auth.uid);
  await ensurePartnershipExists("assego", {
    name: "ASSEGO",
    slug: "assego",
    durationDays: 365,
    planCode: "premium_assego",
  });
  const onlyActive = req.data?.onlyActive !== false;
  return renewPartnershipLicenses("assego", onlyActive);
});

/**
 * Apaga um documento e todas as subcolecoes recursivamente, em lotes (evita timeout e estouro de memoria).
 */
async function deleteFirestoreDocRecursive(docRef, depth = 0) {
  if (!docRef || depth > 30) return;
  const subCollections = await docRef.listCollections();
  const batchSize = 200;

  for (const col of subCollections) {
    // eslint-disable-next-line no-constant-condition
    while (true) {
      const snap = await col.limit(batchSize).get();
      if (snap.empty) break;
      for (const childDoc of snap.docs) {
        await deleteFirestoreDocRecursive(childDoc.ref, depth + 1);
      }
    }
  }

  try {
    await docRef.delete();
  } catch (_) {
    // Se ja nao existir, ignora.
  }
}

/** Remove arquivos do Storage em users/{uid}/ (comprovantes, orcamentos, anexos de agenda, etc.). */
async function deleteUserStorageFolder(uid) {
  try {
    const bucket = admin.storage().bucket();
    const prefix = `users/${uid}/`;
    const [files] = await bucket.getFiles({ prefix });
    const chunk = 40;
    for (let i = 0; i < files.length; i += chunk) {
      const slice = files.slice(i, i + chunk);
      await Promise.all(slice.map((f) => f.delete().catch(() => {})));
    }
  } catch (e) {
    console.error("deleteUserStorageFolder:", e?.message || e);
  }
}

/** Sugestoes/criticas ligadas ao uid. */
async function deleteUserFeedbackDocs(uid) {
  try {
    const db = admin.firestore();
    const snap = await db.collection("user_feedback").where("uid", "==", uid).get();
    if (snap.empty) return;
    let batch = db.batch();
    let n = 0;
    for (const d of snap.docs) {
      batch.delete(d.ref);
      n++;
      if (n >= 400) {
        await batch.commit();
        batch = db.batch();
        n = 0;
      }
    }
    if (n > 0) await batch.commit();
  } catch (e) {
    console.error("deleteUserFeedbackDocs:", e?.message || e);
  }
}

/** Resolve usuario por e-mail (Auth + Firestore em paralelo — mais rapido no painel). */
async function resolveUserAccountByEmail(email) {
  const norm = normalizeEmail(email);
  if (!norm || !norm.includes("@")) return null;

  const authPromise = admin
    .auth()
    .getUserByEmail(norm)
    .then((au) => ({ ok: true, uid: au.uid }))
    .catch((e) => {
      const code = (e?.code || "").toString();
      if (code === "auth/user-not-found") return { ok: false };
      throw e;
    });
  const usersPromise = admin.firestore().collection("users").where("email", "==", norm).limit(2).get();

  const [authRes, usersSnap] = await Promise.all([authPromise, usersPromise]);

  if (usersSnap.size > 1) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      `Mais de um usuario com o e-mail ${norm}. Corrija manualmente antes de migrar.`
    );
  }

  let uid = usersSnap.empty ? null : usersSnap.docs[0].id;
  let profile = usersSnap.empty ? null : usersSnap.docs[0].data() || {};
  const authExists = authRes.ok === true;
  if (authExists && authRes.uid) {
    uid = uid || authRes.uid;
    if (usersSnap.empty) {
      const profSnap = await admin.firestore().doc(`users/${authRes.uid}`).get();
      profile = profSnap.exists ? profSnap.data() || {} : {};
    }
  }
  if (!uid) return null;
  return { uid, email: norm, profile: profile || {}, authExists };
}

function licenseExpiryMs(data) {
  const ts = data?.licenseExpiresAt;
  if (!ts || typeof ts.toDate !== "function") return 0;
  return ts.toDate().getTime();
}

/** Campos de licenca/plano do perfil (prioridade na migracao). */
function extractLicenseProfileFields(data) {
  const d = data || {};
  const pick = {};
  const keys = [
    "plan",
    "planStatus",
    "licenseExpiresAt",
    "licenseValidUntilIncludingGrace",
    "partnershipId",
    "partnershipName",
    "partnershipSlug",
    "partnershipGrantedAt",
    "assegoMember",
    "assegoGrantedAt",
    "premiumPro",
    "isPremiumPro",
    "premiumProIncludedBankConnections",
    "lastPaymentDate",
    "name",
    "cpf",
    "cpfMasked",
    "profileComplete",
    "app",
  ];
  for (const k of keys) {
    if (d[k] !== undefined && d[k] !== null) pick[k] = d[k];
  }
  return pick;
}

/** Mescla perfil: licenca mais longa vence; demais campos do origem se destino vazio. */
function mergeUserProfileForMigration(sourceData, targetData, targetEmail) {
  const src = sourceData || {};
  const tgt = targetData || {};
  const out = { ...tgt, ...extractLicenseProfileFields(src) };
  if (licenseExpiryMs(tgt) > licenseExpiryMs(src)) {
    out.licenseExpiresAt = tgt.licenseExpiresAt;
    out.licenseValidUntilIncludingGrace = tgt.licenseValidUntilIncludingGrace;
    out.plan = tgt.plan ?? out.plan;
    out.planStatus = tgt.planStatus ?? out.planStatus;
  }
  if (!(out.name || "").toString().trim()) out.name = (src.name || tgt.name || "").toString();
  if (!(out.cpf || "").toString().trim()) out.cpf = (src.cpf || tgt.cpf || "").toString();
  if (!(out.cpfMasked || "").toString().trim()) out.cpfMasked = (src.cpfMasked || tgt.cpfMasked || "").toString();
  out.email = normalizeEmail(targetEmail);
  out.updatedAt = admin.firestore.FieldValue.serverTimestamp();
  out.migratedAt = admin.firestore.FieldValue.serverTimestamp();
  if (!out.createdAt && src.createdAt) out.createdAt = src.createdAt;
  return out;
}

async function countFirestoreCollectionDocs(colRef) {
  try {
    const snap = await colRef.count().get();
    return Number(snap.data()?.count || 0);
  } catch (_) {
    const snap = await colRef.limit(5000).get();
    return snap.size;
  }
}

/** Conta arquivos Storage com paginação (evita listar tudo de uma vez na simulação). */
async function countUserStorageFiles(uid, { fast = false } = {}) {
  try {
    const bucket = admin.storage().bucket();
    const prefix = `users/${uid}/`;
    if (!fast) {
      const [files] = await bucket.getFiles({ prefix });
      return { count: files.length, truncated: false };
    }
    let total = 0;
    let pageToken;
    const pageSize = 1000;
    const cap = 5000;
    do {
      const [files, , response] = await bucket.getFiles({
        prefix,
        maxResults: pageSize,
        autoPaginate: false,
        pageToken,
      });
      total += files.length;
      pageToken = response?.nextPageToken;
      if (total >= cap) return { count: cap, truncated: true };
    } while (pageToken);
    return { count: total, truncated: false };
  } catch (_) {
    return { count: 0, truncated: false };
  }
}

async function collectUserDataStats(uid, { fast = false } = {}) {
  const userRef = admin.firestore().doc(`users/${uid}`);
  const stats = { uid, collections: {}, fastStats: !!fast };
  const [cols, storage] = await Promise.all([
    userRef.listCollections(),
    countUserStorageFiles(uid, { fast }),
  ]);
  stats.storageFiles = storage.count;
  if (storage.truncated) stats.storageFilesNote = `${storage.count}+ (contagem limitada na simulacao)`;
  const countPairs = await Promise.all(
    cols.map(async (col) => [col.id, await countFirestoreCollectionDocs(col)])
  );
  for (const [id, n] of countPairs) stats.collections[id] = n;
  return stats;
}

/** Subcolecoes tipicas do usuario: documentos folha (sem subcolecoes aninhadas). */
const USER_LEAF_SUBCOLLECTIONS = new Set([
  "transactions",
  "scales",
  "reminders",
  "locations",
  "goals",
  "agendaAlerts",
  "deviceTokens",
  "bank_connections",
  "payments",
  "budgets",
  "quotes",
  "budget_templates",
  "category_types",
  "fixed_expenses",
  "fixed_incomes",
  "reports",
  "anotacoes",
  "ocorrencias",
  "receipts",
  "categories",
  "finance_accounts",
  "weekly_reports",
  "meta_snapshots",
  "imports",
  "exports",
]);

async function runTasksWithConcurrency(taskFns, limit = 8) {
  if (!taskFns.length) return;
  let idx = 0;
  async function worker() {
    while (idx < taskFns.length) {
      const i = idx++;
      await taskFns[i]();
    }
  }
  await Promise.all(
    Array.from({ length: Math.min(limit, taskFns.length) }, () => worker())
  );
}

async function copyFirestoreCollectionPaginated(sourceColRef, targetColRef, depth = 0, colId = "") {
  if (depth > 30) return 0;
  const collectionName = colId || sourceColRef.id || "";
  const skipNestedScan = depth === 0 && USER_LEAF_SUBCOLLECTIONS.has(collectionName);
  const pageSize = 400;
  let copied = 0;
  let lastDoc = null;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    let q = sourceColRef.orderBy(admin.firestore.FieldPath.documentId()).limit(pageSize);
    if (lastDoc) q = q.startAfter(lastDoc);
    const snap = await q.get();
    if (snap.empty) break;

    const bulkWriter = admin.firestore().bulkWriter();
    bulkWriter.onWriteError((error) => {
      if (error.failedAttempts < 4) return true;
      return false;
    });

    const docPairs = [];
    for (const doc of snap.docs) {
      const targetDocRef = targetColRef.doc(doc.id);
      bulkWriter.set(targetDocRef, doc.data(), { merge: true });
      copied++;
      if (!skipNestedScan) docPairs.push({ sourceRef: doc.ref, targetRef: targetDocRef });
    }
    await bulkWriter.close();

    if (docPairs.length > 0) {
      await runTasksWithConcurrency(
        docPairs.map(
          ({ sourceRef, targetRef }) => async () => {
            const subCols = await sourceRef.listCollections();
            await Promise.all(
              subCols.map((subCol) =>
                copyFirestoreCollectionPaginated(
                  subCol,
                  targetRef.collection(subCol.id),
                  depth + 1,
                  subCol.id
                )
              )
            );
          }
        ),
        10
      );
    }

    lastDoc = snap.docs[snap.docs.length - 1];
    if (snap.size < pageSize) break;
  }
  return copied;
}

async function copyUserFirestoreTree(sourceUid, targetUid, targetEmail) {
  const sourceRef = admin.firestore().doc(`users/${sourceUid}`);
  const targetRef = admin.firestore().doc(`users/${targetUid}`);
  const sourceSnap = await sourceRef.get();
  if (!sourceSnap.exists) {
    throw new functions.https.HttpsError("not-found", "Perfil de origem nao encontrado no Firestore.");
  }
  const targetSnap = await targetRef.get();
  const mergedProfile = mergeUserProfileForMigration(
    sourceSnap.data(),
    targetSnap.exists ? targetSnap.data() : {},
    targetEmail
  );
  mergedProfile.migratedFromUid = sourceUid;
  mergedProfile.migratedFromEmail = normalizeEmail((sourceSnap.data() || {}).email || "");
  await targetRef.set(mergedProfile, { merge: true });
  const subCols = await sourceRef.listCollections();
  const perCol = await Promise.all(
    subCols.map((col) =>
      copyFirestoreCollectionPaginated(col, targetRef.collection(col.id), 0, col.id)
    )
  );
  return perCol.reduce((sum, n) => sum + n, 0);
}

async function copyUserStorageFolder(sourceUid, targetUid) {
  const bucket = admin.storage().bucket();
  const prefix = `users/${sourceUid}/`;
  const [files] = await bucket.getFiles({ prefix });
  let copied = 0;
  const chunk = 25;
  for (let i = 0; i < files.length; i += chunk) {
    const slice = files.slice(i, i + chunk);
    const results = await Promise.all(
      slice.map(async (file) => {
        const destPath = file.name.replace(`users/${sourceUid}/`, `users/${targetUid}/`);
        try {
          await file.copy(bucket.file(destPath));
          return 1;
        } catch (e) {
          console.error("copyUserStorageFolder:", file.name, e?.message || e);
          return 0;
        }
      })
    );
    copied += results.reduce((a, b) => a + b, 0);
  }
  return copied;
}

async function migrateCpfIndexForUser(sourceUid, targetUid, targetEmail) {
  const db = admin.firestore();
  const snap = await db.collection("cpf_index").where("uid", "==", sourceUid).get();
  let updated = 0;
  for (const doc of snap.docs) {
    await doc.ref.set(
      { uid: targetUid, email: normalizeEmail(targetEmail), updatedAt: admin.firestore.FieldValue.serverTimestamp() },
      { merge: true }
    );
    updated++;
  }
  return updated;
}

async function migratePartnershipMemberEmail(oldEmail, newEmail, partnershipId) {
  const pid = (partnershipId || "").toString().trim();
  if (!pid) return 0;
  const db = admin.firestore();
  const oldId = partnershipMemberDocId(oldEmail);
  const newId = partnershipMemberDocId(newEmail);
  const oldRef = db.collection("partnerships").doc(pid).collection("members").doc(oldId);
  const oldSnap = await oldRef.get();
  if (!oldSnap.exists) return 0;
  const data = oldSnap.data() || {};
  await db.collection("partnerships").doc(pid).collection("members").doc(newId).set(
    {
      ...data,
      email: normalizeEmail(newEmail),
      active: data.active !== false,
      migratedFromEmail: normalizeEmail(oldEmail),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  await oldRef.set(
    { active: false, migratedToEmail: normalizeEmail(newEmail), updatedAt: admin.firestore.FieldValue.serverTimestamp() },
    { merge: true }
  );
  if (pid === "assego" || (data.slug || "") === "assego") {
    await db.collection("assego_members").doc(newId).set(
      { email: normalizeEmail(newEmail), active: data.active !== false, updatedAt: admin.firestore.FieldValue.serverTimestamp() },
      { merge: true }
    );
    await db.collection("assego_members").doc(oldId).set({ active: false }, { merge: true });
  }
  return 1;
}

async function reassignUserFeedbackUid(sourceUid, targetUid) {
  const db = admin.firestore();
  const snap = await db.collection("user_feedback").where("uid", "==", sourceUid).get();
  if (snap.empty) return 0;
  let batch = db.batch();
  let n = 0;
  let count = 0;
  for (const d of snap.docs) {
    batch.update(d.ref, { uid: targetUid, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
    n++;
    count++;
    if (n >= 400) {
      await batch.commit();
      batch = db.batch();
      n = 0;
    }
  }
  if (n > 0) await batch.commit();
  return count;
}

async function deactivateMigratedSourceAccount(sourceUid, sourceEmail, targetUid, targetEmail, deleteAfter) {
  const db = admin.firestore();
  const sourceRef = db.doc(`users/${sourceUid}`);
  const srcSnap = await sourceRef.get();
  const role = ((srcSnap.data() || {}).role || "").toString().toLowerCase();
  if (role === "admin" || role === "master") {
    throw new functions.https.HttpsError("failed-precondition", "Nao e permitido desativar conta admin/master como origem.");
  }
  if (deleteAfter) {
    await deleteUserStorageFolder(sourceUid);
    await deleteFirestoreDocRecursive(sourceRef, 0);
    try {
      await db.doc(`users_uid/${sourceUid}`).delete();
    } catch (_) {}
    await deleteUserFeedbackDocs(sourceUid);
    try {
      await admin.auth().deleteUser(sourceUid);
    } catch (e) {
      const code = (e?.code || "").toString();
      if (code !== "auth/user-not-found") throw e;
    }
    return { deactivated: true, deleted: true };
  }
  await sourceRef.set(
    {
      removedByAdminAt: admin.firestore.FieldValue.serverTimestamp(),
      migratedToUid: targetUid,
      migratedToEmail: normalizeEmail(targetEmail),
      plan: "free",
      planStatus: "canceled",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  try {
    await admin.auth().updateUser(sourceUid, { disabled: true });
  } catch (e) {
    const code = (e?.code || "").toString();
    if (code !== "auth/user-not-found") console.error("deactivateMigratedSourceAccount auth:", e?.message || e);
  }
  return { deactivated: true, deleted: false };
}

/**
 * Migração premium: troca de e-mail (mesma conta) ou transferencia completa entre contas.
 * Preserva licenca, lancamentos, escalas, Storage e demais subcolecoes.
 */
exports.ctMigrateUserEmailPremium = onCall(
  { timeoutSeconds: 540, memory: "2GiB", maxInstances: 5 },
  async (req) => {
    if (!req.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Login obrigatorio.");
    }
    await requireAdminPanel(req.auth.uid);

    const sourceEmail = normalizeEmail(req.data?.sourceEmail || req.data?.fromEmail || "");
    const targetEmail = normalizeEmail(req.data?.targetEmail || req.data?.toEmail || "");
    const mode = (req.data?.mode || "full_migration").toString().trim().toLowerCase();
    const dryRun = req.data?.dryRun === true;
    const createTargetIfMissing = req.data?.createTargetIfMissing !== false;
    const deactivateSource = req.data?.deactivateSource !== false;
    const deleteSourceAfter = req.data?.deleteSourceAfter === true;

    if (!sourceEmail || !sourceEmail.includes("@")) {
      throw new functions.https.HttpsError("invalid-argument", "Informe o e-mail de origem (conta antiga).");
    }
    if (!targetEmail || !targetEmail.includes("@")) {
      throw new functions.https.HttpsError("invalid-argument", "Informe o e-mail de destino (conta nova).");
    }
    if (sourceEmail === targetEmail) {
      throw new functions.https.HttpsError("invalid-argument", "Origem e destino devem ser e-mails diferentes.");
    }

    const source = await resolveUserAccountByEmail(sourceEmail);
    if (!source) {
      throw new functions.https.HttpsError("not-found", `Nenhuma conta encontrada com o e-mail de origem: ${sourceEmail}`);
    }
    const sourceUid = source.uid;
    if (sourceUid === req.auth.uid) {
      throw new functions.https.HttpsError("invalid-argument", "Nao migre a propria conta de administrador.");
    }
    const sourceRole = ((source.profile || {}).role || "").toString().toLowerCase();
    if (sourceRole === "admin" || sourceRole === "master") {
      throw new functions.https.HttpsError("failed-precondition", "Conta de origem e administrador. Remova o cargo antes.");
    }

    let target = await resolveUserAccountByEmail(targetEmail);
    if (!target && createTargetIfMissing && !dryRun) {
      const tempPass = crypto.randomBytes(18).toString("base64url") + "A1!";
      const created = await admin.auth().createUser({
        email: targetEmail,
        password: tempPass,
        emailVerified: false,
      });
      target = { uid: created.uid, email: targetEmail, profile: {}, authExists: true };
      await admin.firestore().doc(`users/${created.uid}`).set(
        {
          email: targetEmail,
          name: (source.profile?.name || "").toString(),
          role: "user",
          plan: "free",
          planStatus: "active",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }
    if (!target) {
      throw new functions.https.HttpsError(
        "not-found",
        `Nenhuma conta com o e-mail de destino: ${targetEmail}. Marque "Criar conta destino" ou peca ao usuario registrar-se primeiro.`
      );
    }
    const targetUid = target.uid;
    if (targetUid === sourceUid) {
      throw new functions.https.HttpsError("invalid-argument", "Origem e destino apontam para o mesmo UID.");
    }
    const targetRole = ((target.profile || {}).role || "").toString().toLowerCase();
    if (targetRole === "admin" || targetRole === "master") {
      throw new functions.https.HttpsError("failed-precondition", "Conta de destino e administrador.");
    }

    const statsFast = dryRun;
    const [sourceStats, targetStats] = await Promise.all([
      collectUserDataStats(sourceUid, { fast: statsFast }),
      collectUserDataStats(targetUid, { fast: statsFast }),
    ]);

    if (dryRun) {
      return {
        ok: true,
        dryRun: true,
        mode,
        sourceEmail,
        targetEmail,
        sourceUid,
        targetUid,
        sourceStats,
        targetStats,
        message: "Simulacao concluida. Nenhum dado foi alterado.",
      };
    }

    if (mode === "same_account" || mode === "update_email") {
      const targetOther = await resolveUserAccountByEmail(targetEmail);
      if (targetOther && targetOther.uid !== sourceUid) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          `O e-mail ${targetEmail} ja pertence a outra conta (UID ${targetOther.uid}). Use migracao completa.`
        );
      }
      try {
        await admin.auth().updateUser(sourceUid, { email: targetEmail });
      } catch (e) {
        const msg = (e?.message || String(e)).toString();
        throw new functions.https.HttpsError("failed-precondition", `Falha ao atualizar e-mail no login: ${msg.slice(0, 200)}`);
      }
      const sourceSnap = await admin.firestore().doc(`users/${sourceUid}`).get();
      const merged = mergeUserProfileForMigration(sourceSnap.data() || {}, {}, targetEmail);
      merged.email = targetEmail;
      delete merged.migratedFromEmail;
      delete merged.migratedFromUid;
      delete merged.migratedAt;
      await admin.firestore().doc(`users/${sourceUid}`).set(merged, { merge: true });
      await migrateCpfIndexForUser(sourceUid, sourceUid, targetEmail);
      const pid = (merged.partnershipId || source.profile?.partnershipId || "").toString();
      await migratePartnershipMemberEmail(sourceEmail, targetEmail, pid);
      return {
        ok: true,
        mode: "same_account",
        sourceEmail,
        targetEmail,
        uid: sourceUid,
        message: "E-mail atualizado na mesma conta. Todos os dados permanecem no mesmo login (UID).",
      };
    }

    const partnershipId = (source.profile?.partnershipId || "").toString();
    const [docsCopied, storageCopied, cpfIndexUpdated, partnershipMembers, feedbackMoved] =
      await Promise.all([
        copyUserFirestoreTree(sourceUid, targetUid, targetEmail),
        copyUserStorageFolder(sourceUid, targetUid),
        migrateCpfIndexForUser(sourceUid, targetUid, targetEmail),
        migratePartnershipMemberEmail(sourceEmail, targetEmail, partnershipId),
        reassignUserFeedbackUid(sourceUid, targetUid),
      ]);

    try {
      await admin.auth().updateUser(targetUid, { email: targetEmail });
    } catch (e) {
      console.error("ctMigrateUserEmailPremium target auth email:", e?.message || e);
    }
    await admin.firestore().doc(`users/${targetUid}`).set(
      { email: targetEmail, updatedAt: admin.firestore.FieldValue.serverTimestamp() },
      { merge: true }
    );

    let sourceResult = { deactivated: false, deleted: false };
    if (deactivateSource) {
      sourceResult = await deactivateMigratedSourceAccount(
        sourceUid,
        sourceEmail,
        targetUid,
        targetEmail,
        deleteSourceAfter
      );
    }

    return {
      ok: true,
      mode: "full_migration",
      sourceEmail,
      targetEmail,
      sourceUid,
      targetUid,
      docsCopied,
      storageCopied,
      cpfIndexUpdated,
      partnershipMembers,
      feedbackMoved,
      sourceDeactivated: sourceResult.deactivated,
      sourceDeleted: sourceResult.deleted,
      message:
        "Migracao concluida. O usuario deve entrar com o e-mail novo. Licenca e lancamentos foram transferidos.",
    };
  }
);

/**
 * EXCLUSAO TOTAL (Storage + Firestore recursivo + Auth + legados) para quem nao e mais cliente.
 * Requer: Admin no painel.
 */
exports.ctDeleteUserTotal = onCall(
  { timeoutSeconds: 300, memory: "1GiB", maxInstances: 20 },
  async (req) => {
    if (!req.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
    }
    await requireAdminPanel(req.auth.uid);

    const targetUid = (req.data?.uid || "").toString().trim();
    if (!targetUid) {
      throw new functions.https.HttpsError("invalid-argument", "uid obrigatorio.");
    }
    if (targetUid === req.auth.uid) {
      throw new functions.https.HttpsError("invalid-argument", "Nao e permitido excluir o proprio usuario admin.");
    }

    const userDocRef = admin.firestore().doc(`users/${targetUid}`);
    const targetSnap = await userDocRef.get();
    if (targetSnap.exists) {
      const d = targetSnap.data() || {};
      const tr = (d.role || "").toString().toLowerCase();
      const plan = (d.plan || "").toString().toLowerCase();
      if (tr === "admin" || tr === "master") {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "Nao e possivel excluir contas de administrador ou master pelo painel. Remova o cargo antes, se necessario."
        );
      }
    }

    // 1) Storage (nao depende do Firestore)
    await deleteUserStorageFolder(targetUid);

    // 2) Firestore: users/{uid} + todas as subcolecoes (transactions, notes, reminders, etc.)
    try {
      await deleteFirestoreDocRecursive(userDocRef, 0);
    } catch (e) {
      console.error("ctDeleteUserTotal: erro ao deletar Firestore:", e?.message || e);
      throw new functions.https.HttpsError(
        "internal",
        `Falha ao apagar dados do usuario no Firestore: ${(e?.message || e).toString().slice(0, 200)}`
      );
    }

    // 3) Legado users_uid/{uid}
    try {
      await admin.firestore().doc(`users_uid/${targetUid}`).delete();
    } catch (_) {}

    // 4) Feedbacks
    await deleteUserFeedbackDocs(targetUid);

    // 5) Firebase Auth
    try {
      await admin.auth().deleteUser(targetUid);
    } catch (e) {
      const code = (e?.code || "").toString();
      const msg = (e?.message || String(e)).toString();
      if (code !== "auth/user-not-found" && !/not[- ]found|User does not exist|no user record|uid does not exist/i.test(msg)) {
        console.error("ctDeleteUserTotal: erro ao deletar Auth:", msg);
        throw new functions.https.HttpsError(
          "internal",
          `Dados apagados, mas falha ao remover login (Auth): ${msg.slice(0, 180)}`
        );
      }
    }

    return { ok: true, deletedUid: targetUid };
  }
);

/**
 * Lista usuários inativos por faixa (30/60/90 dias) de forma paginada.
 * Escaneia users por páginas e avalia último lançamento em users/{uid}/transactions.
 */
exports.ctAdminListInactiveUsers = onCall(
  { timeoutSeconds: 300, memory: "1GiB", maxInstances: 20 },
  async (req) => {
    if (!req.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
    }
    await requireAdminPanel(req.auth.uid);

    const pageSizeRaw = Number(req.data?.pageSize || 250);
    const pageSize = Number.isFinite(pageSizeRaw)
      ? Math.max(50, Math.min(500, Math.trunc(pageSizeRaw)))
      : 250;
    const cursor = (req.data?.cursor || "").toString().trim();
    const appFilter = (req.data?.app || "").toString().trim();

    let usersQ = admin.firestore().collection("users")
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(pageSize);
    if (appFilter) {
      usersQ = usersQ.where("app", "==", appFilter);
    }
    if (cursor) {
      usersQ = usersQ.startAfter(cursor);
    }

    const usersSnap = await usersQ.get();
    if (usersSnap.empty) {
      return {
        ok: true,
        usersScanned: 0,
        inactive30: [],
        inactive60: [],
        inactive90: [],
        nextCursor: null,
      };
    }

    const now = new Date();
    const inactive30 = [];
    const inactive60 = [];
    const inactive90 = [];

    const docs = usersSnap.docs;
    const chunkSize = 25;
    for (let i = 0; i < docs.length; i += chunkSize) {
      const slice = docs.slice(i, i + chunkSize);
      const results = await Promise.all(slice.map(async (d) => {
        const data = d.data() || {};
        const uid = d.id;
        const name = (data.name || "").toString();
        const email = (data.email || "").toString();
        const plan = (data.plan || "").toString();

        let lastTxDate = null;
        try {
          const txSnap = await d.ref.collection("transactions")
            .orderBy("date", "desc")
            .limit(1)
            .get();
          if (!txSnap.empty) {
            const tx = txSnap.docs[0].data() || {};
            const ts = tx.date;
            if (ts?.toDate) {
              lastTxDate = ts.toDate();
            }
          }
        } catch (_) {
          lastTxDate = null;
        }

        const inactivityDays = lastTxDate
          ? Math.max(0, Math.floor((now.getTime() - lastTxDate.getTime()) / 86400000))
          : 99999;

        return {
          uid,
          name,
          email,
          plan,
          inactivityDays,
          lastMovementAt: lastTxDate ? lastTxDate.toISOString() : null,
        };
      }));

      for (const u of results) {
        if (u.inactivityDays > 30) inactive30.push(u);
        if (u.inactivityDays > 60) inactive60.push(u);
        if (u.inactivityDays > 90) inactive90.push(u);
      }
    }

    const lastDoc = docs[docs.length - 1];
    const nextCursor = docs.length < pageSize ? null : lastDoc.id;
    return {
      ok: true,
      usersScanned: docs.length,
      inactive30,
      inactive60,
      inactive90,
      nextCursor,
    };
  }
);

/** Lê credenciais do Play Store: Firestore settings/play_store ou env */
async function getPlayStoreConfig() {
  try {
    const snap = await admin.firestore().collection("settings").doc("play_store").get();
    if (snap.exists && snap.data()) {
      const d = snap.data();
      const json = (d.service_account_json || d.serviceAccountJson || "").toString().trim();
      if (json) return { credentials: JSON.parse(json) };
    }
  } catch (e) {
    console.warn("getPlayStoreConfig firestore:", e.message);
  }
  const envJson = process.env.PLAY_STORE_SERVICE_ACCOUNT_JSON;
  if (envJson) {
    try {
      return { credentials: JSON.parse(envJson) };
    } catch (_) {}
  }
  return null;
}

/**
 * Envia o AAB para a Play Store (track internal ou production).
 * Requer: settings/play_store com service_account_json OU env PLAY_STORE_SERVICE_ACCOUNT_JSON.
 * O AAB deve estar em Storage no path informado (ex: releases/app-release.aab).
 */
exports.ctSubmitToPlayStore = onCall(async (req) => {
  if (!req.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
  }
  await requireAdmin(req.auth.uid);

  const storagePath = (req.data?.storagePath || "releases/app-release.aab").toString().trim();
  if (!storagePath.startsWith("releases/")) {
    throw new functions.https.HttpsError("invalid-argument", "Caminho inválido. Use releases/...");
  }

  const config = await getPlayStoreConfig();
  if (!config?.credentials) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Play Store não configurado. Adicione em settings/play_store o campo service_account_json (JSON da service account) ou defina PLAY_STORE_SERVICE_ACCOUNT_JSON."
    );
  }

  const bucket = admin.storage().bucket();
  const file = bucket.file(storagePath);
  const [exists] = await file.exists();
  if (!exists) {
    throw new functions.https.HttpsError("not-found", `Arquivo não encontrado: ${storagePath}. Envie o AAB primeiro.`);
  }

  const [buffer] = await file.download();
  if (!buffer || buffer.length === 0) {
    throw new functions.https.HttpsError("internal", "Arquivo vazio.");
  }

  const { google } = require("googleapis");
  const auth = new google.auth.GoogleAuth({
    credentials: config.credentials,
    scopes: ["https://www.googleapis.com/auth/androidpublisher"],
  });
  const androidPublisher = google.androidpublisher({ version: "v3", auth });

  try {
    const editResponse = await androidPublisher.edits.insert({
      packageName: PACKAGE_NAME,
      requestBody: {},
    });
    const editId = editResponse.data.id;
    if (!editId) throw new Error("Edit ID não retornado");

    const bundleRes = await androidPublisher.edits.bundles.upload({
      editId,
      packageName: PACKAGE_NAME,
      media: {
        mimeType: "application/octet-stream",
        body: require("stream").Readable.from(buffer),
      },
    });
    const versionCode = bundleRes.data.versionCode;
    if (!versionCode) throw new Error("versionCode não retornado pelo upload");

    await androidPublisher.edits.tracks.update({
      editId,
      packageName: PACKAGE_NAME,
      track: "internal",
      requestBody: {
        releases: [
          {
            status: "completed",
            versionCodes: [String(versionCode)],
          },
        ],
      },
    });

    await androidPublisher.edits.commit({
      editId,
      packageName: PACKAGE_NAME,
    });

    return { ok: true, message: "AAB enviado para a Play Store (track internal) com sucesso." };
  } catch (e) {
    console.error("ctSubmitToPlayStore:", e);
    const msg = e.response?.data?.error?.message || e.message || String(e);
    throw new functions.https.HttpsError("internal", `Erro ao enviar para Play Store: ${msg}`);
  }
});

const DEFAULT_DRIVE_FOLDER_ID = "1fMXYKu7Pz934L4ElZnHWdldJHfaPJKqd";

/**
 * Testa a conexão com o Google Drive: cria um arquivo de teste na pasta configurada.
 * Requer: pasta do Drive compartilhada com a service account do Firebase (controletotal-4c867@appspot.gserviceaccount.com).
 */
exports.ctTestBackupToDrive = onCall(async (req) => {
  if (!req.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
  }
  await requireAdminPanel(req.auth.uid);

  const db = admin.firestore();
  const snap = await db.collection("settings").doc("googledrive").get();
  const d = snap.exists && snap.data() ? snap.data() : {};
  const folderId = (d.rootFolderId || DEFAULT_DRIVE_FOLDER_ID).toString().trim();
  if (!folderId) {
    throw new functions.https.HttpsError("invalid-argument", "ID da pasta raiz não configurado. Salve as configurações primeiro.");
  }

  const { google } = require("googleapis");
  // drive.file só acessa arquivos criados/abertos pelo app; para gravar em pasta compartilhada com a SA use drive.
  const auth = new google.auth.GoogleAuth({
    scopes: ["https://www.googleapis.com/auth/drive"],
  });
  const drive = google.drive({ version: "v3", auth });
  const now = new Date();
  const fileName = `teste-backup-controletotal-${now.toISOString().slice(0, 19).replace(/[:-]/g, "")}.txt`;
  const content = `Teste de backup - Controle Total App\nGerado em: ${now.toISOString()}\n\nSe este arquivo apareceu na pasta, a conexão com o Drive está funcionando.`;
  const { Readable } = require("stream");

  try {
    // supportsAllDrives: true é obrigatório quando a pasta está em um Shared Drive (ex.: CONTROLETOTAL)
    const res = await drive.files.create({
      requestBody: {
        name: fileName,
        parents: [folderId],
      },
      media: {
        mimeType: "text/plain",
        body: Readable.from(Buffer.from(content, "utf8")),
      },
      supportsAllDrives: true,
    });
    const fileId = res.data?.id;
    return {
      ok: true,
      message: "Arquivo de teste criado com sucesso na pasta do Drive. A conexão está funcionando.",
      fileId,
      fileName,
    };
  } catch (e) {
    const msg = e.message || String(e);
    const saEmail = "controletotal-4c867@appspot.gserviceaccount.com";
    let userMsg = msg;
    if (msg.includes("404") || msg.includes("not found")) {
      userMsg = `Pasta não encontrada. Compartilhe a pasta com "${saEmail}" como Editor. Se a pasta está em um Shared Drive (unidade compartilhada), adicione "${saEmail}" como membro do Shared Drive (Gerente de conteúdo ou Gravador).`;
    } else if (msg.includes("403") || msg.includes("forbidden") || msg.includes("Insufficient permissions") || msg.includes("parent")) {
      userMsg = `Sem permissão. Se a pasta está em um Shared Drive (ex.: CONTROLETOTAL): clique com o botão direito no nome do Shared Drive na barra lateral → Gerir membros → adicione "${saEmail}" como "Gerente de conteúdo". Se for pasta no "Meu Drive": Compartilhar → adicione "${saEmail}" como Editor.`;
    }
    throw new functions.https.HttpsError("internal", `Erro ao testar Drive: ${userMsg}`);
  }
});

/** Coleções do usuário para backup (mesmo schema do app). */
const USER_COLLECTIONS = [
  "settings", "locations", "reminders", "transactions", "scales",
  "budgets", "quotes", "goals", "payments", "category_types", "ocorrencias", "deviceTokens",
];

/** Converte Firestore Timestamp para ISO string. */
function sanitizeValue(v) {
  if (v == null) return null;
  if (v && typeof v.toDate === "function") return v.toDate().toISOString();
  if (typeof v === "object" && !Array.isArray(v)) return sanitizeMap(v);
  if (Array.isArray(v)) return v.map(sanitizeValue);
  return v;
}

function sanitizeMap(obj) {
  const out = {};
  for (const [k, v] of Object.entries(obj || {})) {
    out[k] = sanitizeValue(v);
  }
  return out;
}

/**
 * Cria backup completo no Firebase Storage (users, settings, app_config, config).
 * Admin only.
 */
exports.ctCreateFirebaseBackup = onCall(async (req) => {
  if (!req.auth) throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
  await requireAdminPanel(req.auth.uid);

  const db = admin.firestore();
  const bucket = admin.storage().bucket();
  const now = new Date();
  const suffix = now.toISOString().slice(0, 19).replace(/[:-]/g, "").replace("T", "_");
  const fileName = `backup_${suffix}.json`;
  const path = `backups/${fileName}`;

  const out = {
    exportedAt: now.toISOString(),
    version: 1,
    users: {},
    settings: {},
    app_config: {},
    config: {},
  };

  const usersSnap = await db.collection("users").get();
  for (const userDoc of usersSnap.docs) {
    const userData = userDoc.data();
    out.users[userDoc.id] = {
      profile: sanitizeMap(userData),
      collections: {},
    };
    for (const col of USER_COLLECTIONS) {
      const colSnap = await db.collection("users").doc(userDoc.id).collection(col).get();
      out.users[userDoc.id].collections[col] = colSnap.docs.map((d) => ({
        id: d.id,
        ...sanitizeMap(d.data()),
      }));
    }
  }

  const settingsSnap = await db.collection("settings").get();
  settingsSnap.docs.forEach((d) => { out.settings[d.id] = sanitizeMap(d.data()); });

  const appConfigSnap = await db.collection("app_config").get();
  appConfigSnap.docs.forEach((d) => { out.app_config[d.id] = sanitizeMap(d.data()); });

  const configSnap = await db.collection("config").get();
  configSnap.docs.forEach((d) => { out.config[d.id] = sanitizeMap(d.data()); });

  const json = JSON.stringify(out, null, 2);
  const buffer = Buffer.from(json, "utf8");
  const file = bucket.file(path);
  await file.save(buffer, {
    metadata: { contentType: "application/json" },
  });

  return {
    ok: true,
    fileName,
    path,
    size: buffer.length,
    message: `Backup criado: ${fileName} (${(buffer.length / 1024).toFixed(1)} KB)`,
  };
});

/**
 * Lista backups no Firebase Storage.
 * Admin only.
 */
exports.ctListFirebaseBackups = onCall(async (req) => {
  if (!req.auth) throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
  await requireAdminPanel(req.auth.uid);

  const bucket = admin.storage().bucket();
  const [files] = await bucket.getFiles({ prefix: "backups/", maxResults: 100 });
  const list = files
    .filter((f) => f.name.endsWith(".json"))
    .map((f) => ({
      name: f.name.split("/").pop(),
      path: f.name,
      size: f.metadata?.size ? parseInt(f.metadata.size, 10) : 0,
      updated: f.metadata?.updated || null,
    }))
    .sort((a, b) => (b.updated || "").localeCompare(a.updated || ""));

  return { ok: true, backups: list };
});

/**
 * Retorna URL assinada para download do backup.
 * Admin only.
 */
exports.ctGetFirebaseBackupDownloadUrl = onCall(async (req) => {
  if (!req.auth) throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
  await requireAdminPanel(req.auth.uid);

  const path = (req.data?.path || req.data?.fileName || "").toString().trim();
  const fullPath = path.startsWith("backups/") ? path : `backups/${path}`;
  if (!fullPath.startsWith("backups/") || !fullPath.endsWith(".json")) {
    throw new functions.https.HttpsError("invalid-argument", "Caminho inválido.");
  }

  const bucket = admin.storage().bucket();
  const file = bucket.file(fullPath);
  const [exists] = await file.exists();
  if (!exists) throw new functions.https.HttpsError("not-found", "Backup não encontrado.");

  const [url] = await file.getSignedUrl({
    action: "read",
    expires: Date.now() + 15 * 60 * 1000,
  });
  return { ok: true, url };
});

/**
 * Restaura backup do Firebase Storage para o Firestore.
 * Admin only. CUIDADO: sobrescreve dados existentes.
 */
exports.ctRestoreFirebaseBackup = onCall(async (req) => {
  if (!req.auth) throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
  await requireAdminPanel(req.auth.uid);

  const path = (req.data?.path || req.data?.fileName || "").toString().trim();
  const fullPath = path.startsWith("backups/") ? path : `backups/${path}`;
  if (!fullPath.startsWith("backups/") || !fullPath.endsWith(".json")) {
    throw new functions.https.HttpsError("invalid-argument", "Caminho inválido.");
  }

  const bucket = admin.storage().bucket();
  const file = bucket.file(fullPath);
  const [exists] = await file.exists();
  if (!exists) throw new functions.https.HttpsError("not-found", "Backup não encontrado.");

  const [buffer] = await file.download();
  const data = JSON.parse(buffer.toString("utf8"));
  const db = admin.firestore();

  function desanitizeValue(v) {
    if (v == null) return null;
    if (typeof v === "object" && !Array.isArray(v)) return desanitizeMap(v);
    if (Array.isArray(v)) return v.map(desanitizeValue);
    if (typeof v === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(v)) {
      return admin.firestore.Timestamp.fromDate(new Date(v));
    }
    return v;
  }
  function desanitizeMap(obj) {
    const out = {};
    for (const [k, v] of Object.entries(obj || {})) out[k] = desanitizeValue(v);
    return out;
  }

  for (const [uid, userData] of Object.entries(data.users || {})) {
    const userRef = db.collection("users").doc(uid);
    if (userData.profile && Object.keys(userData.profile).length > 0) {
      await userRef.set(desanitizeMap(userData.profile), { merge: true });
    }
    for (const [colName, docs] of Object.entries(userData.collections || {})) {
      if (!Array.isArray(docs) || docs.length === 0) continue;
      const colRef = userRef.collection(colName);
      for (let i = 0; i < docs.length; i += 500) {
        const batch = db.batch();
        const chunk = docs.slice(i, i + 500);
        for (const item of chunk) {
          const id = (item && item.id) ? String(item.id) : null;
          if (!id) continue;
          const { id: _id, ...docData } = item;
          batch.set(colRef.doc(id), desanitizeMap(docData), { merge: true });
        }
        await batch.commit();
      }
    }
  }

  for (const [docId, docData] of Object.entries(data.settings || {})) {
    if (docData && Object.keys(docData).length > 0) {
      await db.collection("settings").doc(docId).set(desanitizeMap(docData), { merge: true });
    }
  }
  for (const [docId, docData] of Object.entries(data.app_config || {})) {
    if (docData && Object.keys(docData).length > 0) {
      await db.collection("app_config").doc(docId).set(desanitizeMap(docData), { merge: true });
    }
  }
  for (const [docId, docData] of Object.entries(data.config || {})) {
    if (docData && Object.keys(docData).length > 0) {
      await db.collection("config").doc(docId).set(desanitizeMap(docData), { merge: true });
    }
  }

  return { ok: true, message: "Backup restaurado com sucesso." };
});

/**
 * Envio automático de push: quando um doc é criado em users/{uid}/notifications/{nid},
 * envia notificação FCM para todos os deviceTokens do usuário (web e mobile).
 * Crie documentos nessa coleção para disparar push (ex.: escala, agenda, conta).
 */
exports.pushOnNotificationCreate = onDocumentCreated("users/{uid}/notifications/{nid}", async (event) => {
    const snap = event.data;
    const uid = event.params.uid;
    const data = snap.data() || {};
    const title = (data.title || "Controle Total App").toString();
    const body = (data.body || "").toString();

    const db = admin.firestore();
    const userSnap = await db.collection("users").doc(uid).get();
    const userData = userSnap.exists ? userSnap.data() || {} : {};
    if (userData.pushEnabled === false) return null;

    const tokens = await getUserFcmTokens(db, uid, userData);
    if (!tokens.length) return null;

    const nested = data.data && typeof data.data === "object" ? data.data : {};
    const payload = { click_action: "FLUTTER_NOTIFICATION_CLICK" };
    for (const [k, v] of Object.entries(nested)) {
      if (v != null && typeof v !== "object") payload[k] = String(v);
    }
    const u = (data.url || payload.url || "").toString().trim();
    const fullLink = u.startsWith("http")
      ? u
      : u.startsWith("/")
        ? `${APP_DOMAIN}${u}`
        : "";
    if (fullLink) payload.url = fullLink;
    const channelKind = (payload.channelKind || nested.channelKind || "escala").toString();

    const msg = {
      notification: { title, body },
      tokens,
      data: payload,
      ...defaultPushMulticastOptions(fullLink, channelKind),
    };
    const resp = await admin.messaging().sendEachForMulticast(msg);
    resp.responses.forEach((r, i) => {
      if (
        !r.success &&
        (r.error?.code === "messaging/invalid-registration-token" ||
          r.error?.code === "messaging/registration-token-not-registered")
      ) {
        deleteInvalidFcmToken(db, uid, tokens[i]).catch(() => {});
      }
    });
    return resp;
});

/**
 * Broadcast: quando um doc é criado na coleção raiz "notifications" (ex.: painel admin "Disparar para todos"),
 * envia push para todos os dispositivos de todos os usuários (deviceTokens).
 * Campos do doc: title, body (opcional: data, url).
 */
exports.pushBroadcastOnCreate = onDocumentCreated("notifications/{nid}", async (event) => {
    const snap = event.data;
    const data = snap.data() || {};
    const title = (data.title || "Controle Total App").toString();
    const body = (data.body || "").toString();
    const url = (data.url || data.data?.url || "/").toString();
    const db = admin.firestore();
    const tokenToUid = new Map();

    const usersSnap = await db.collection("users").get();
    for (const userDoc of usersSnap.docs) {
      const udata = userDoc.data() || {};
      if (udata.pushEnabled === false) continue;
      const userTokens = await getUserFcmTokens(db, userDoc.id, udata);
      for (const t of userTokens) {
        if (!tokenToUid.has(t)) tokenToUid.set(t, userDoc.id);
      }
    }

    const uniqueTokens = [...tokenToUid.keys()];
    if (uniqueTokens.length === 0) return null;

    const fullLink = url.startsWith("http") ? url : `${APP_DOMAIN}${url.startsWith("/") ? url : "/" + url}`;
    const BATCH = 500;
    for (let i = 0; i < uniqueTokens.length; i += BATCH) {
      const batch = uniqueTokens.slice(i, i + BATCH);
      const resp = await admin.messaging().sendEachForMulticast({
        tokens: batch,
        notification: { title, body },
        data: { url: fullLink, click_action: "FLUTTER_NOTIFICATION_CLICK" },
        ...defaultPushMulticastOptions(fullLink, "escala"),
      });
      resp.responses.forEach((r, j) => {
        if (
          !r.success &&
          (r.error?.code === "messaging/invalid-registration-token" ||
            r.error?.code === "messaging/registration-token-not-registered")
        ) {
          const badToken = batch[j];
          const ownerUid = badToken ? tokenToUid.get(badToken) : null;
          if (ownerUid) deleteInvalidFcmToken(db, ownerUid, badToken).catch(() => {});
        }
      });
    }
    return null;
  });

/** Coleção domain_access: acessos ao domínio https://controletotalapp.com.br por data/hora (horário Brasília).
 *  Doc ID: YYYY-MM-DD. Campos: h0..h23 (acessos por hora), total (soma do dia).
 *  Escrita apenas via Cloud Functions. Leitura pelo admin via ctGetDomainAccessStats. */

/** Registra um acesso ao domínio. Chamado pelo app web no carregamento. Não requer autenticação. */
exports.ctLogDomainAccess = onCall({ cors: true }, async (req) => {
    const parts = getDatePartsBrasilia(new Date());
    const dateISO = `${parts.year}-${String(parts.month + 1).padStart(2, "0")}-${String(parts.day).padStart(2, "0")}`;
    const hour = Math.min(23, Math.max(0, parts.hour));
    const hourKey = `h${hour}`;
    const ref = admin.firestore().collection("domain_access").doc(dateISO);
    await ref.set(
      { [hourKey]: admin.firestore.FieldValue.increment(1), total: admin.firestore.FieldValue.increment(1), updatedAt: admin.firestore.FieldValue.serverTimestamp() },
      { merge: true }
    );
    return { ok: true, date: dateISO, hour };
});

/** Retorna estatísticas de acessos agregadas. Requer admin. Params: period (daily|weekly|monthly|yearly), dateISO (ex: 2025-02-27 para daily; usada como referência para weekly/monthly/yearly). */
exports.ctGetDomainAccessStats = onCall({ cors: true }, async (req) => {
    if (!req.auth || !req.auth.uid) {
      throw new functions.https.HttpsError("unauthenticated", "Requer autenticação.");
    }
    const userSnap = await admin.firestore().collection("users").doc(req.auth.uid).get();
    const role = userSnap.exists && userSnap.data() ? (userSnap.data().role || "").toString() : "";
    if (role !== "admin" && role !== "master" && role !== "partner" && role !== "socio") {
      const email = (req.auth.token?.email || "").toString().trim().toLowerCase();
      if (email !== "tarleypmgo@gmail.com") {
        throw new functions.https.HttpsError("permission-denied", "Apenas admin, master ou sócio.");
      }
    }
    const period = (req.data?.period || "daily").toString().toLowerCase();
    const dateISO = (req.data?.dateISO || todayBrasiliaISO()).toString();
    const [y, m, d] = dateISO.split("-").map((x) => parseInt(x, 10) || 0);
    if (!y || !m || !d) {
      throw new functions.https.HttpsError("invalid-argument", "dateISO inválido.");
    }
    const db = admin.firestore();
    const coll = db.collection("domain_access");

    if (period === "daily") {
      const doc = await coll.doc(dateISO).get();
      const data = doc.exists ? doc.data() : {};
      const hours = [];
      let total = 0;
      for (let h = 0; h < 24; h++) {
        const v = data[`h${h}`] || 0;
        hours.push({ hour: h, count: v });
        total += v;
      }
      return { period: "daily", dateISO, hours, total };
    }

    let startISO, endISO;
    if (period === "weekly") {
      const ref = new Date(y, m - 1, d);
      const day = ref.getDay();
      const diff = ref.getDate() - day + (day === 0 ? -6 : 1);
      const mon = new Date(ref);
      mon.setDate(diff);
      const sun = new Date(mon);
      sun.setDate(mon.getDate() + 6);
      startISO = mon.toISOString().slice(0, 10);
      endISO = sun.toISOString().slice(0, 10);
    } else if (period === "monthly") {
      startISO = `${y}-${String(m).padStart(2, "0")}-01`;
      const lastDay = new Date(y, m, 0).getDate();
      endISO = `${y}-${String(m).padStart(2, "0")}-${String(lastDay).padStart(2, "0")}`;
    } else if (period === "yearly") {
      startISO = `${y}-01-01`;
      endISO = `${y}-12-31`;
    } else {
      throw new functions.https.HttpsError("invalid-argument", "period inválido. Use daily|weekly|monthly|yearly.");
    }

    const snap = await coll.where(admin.firestore.FieldPath.documentId(), ">=", startISO).where(admin.firestore.FieldPath.documentId(), "<=", endISO).get();
    const byDay = {};
    snap.docs.forEach((doc) => {
      byDay[doc.id] = doc.data().total || 0;
    });
    let total = 0;
    const days = [];
    const start = new Date(startISO);
    const end = new Date(endISO);
    for (let d = new Date(start); d <= end; d.setDate(d.getDate() + 1)) {
      const iso = d.toISOString().slice(0, 10);
      const count = byDay[iso] || 0;
      days.push({ date: iso, count });
      total += count;
    }
    return { period, startISO, endISO, days, total };
  });

// --- Apple In-App Purchase (3.1.1): valida recibo e atualiza licença no Firestore ---

const IOS_BUNDLE_ID = "br.com.controletotalapp1.app";
const IOS_IAP_PRODUCT_IDS = new Set([
  "br.com.controletotalapp1.premium.monthly",
  "br.com.controletotalapp1.premium.annual",
]);

async function appleVerifyReceiptHttp(receiptBase64, password) {
  const body = {
    "receipt-data": receiptBase64,
    password,
    "exclude-old-transactions": false,
  };
  const post = async (url) => {
    const r = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    return r.json();
  };
  let j = await post("https://buy.itunes.apple.com/verifyReceipt");
  if (j.status === 21007) {
    j = await post("https://sandbox.itunes.apple.com/verifyReceipt");
  }
  return j;
}

function allIosReceiptTransactions(verifyJson) {
  const out = [];
  const a = verifyJson.latest_receipt_info;
  const b = verifyJson.receipt && verifyJson.receipt.in_app;
  if (Array.isArray(a)) out.push(...a);
  if (Array.isArray(b)) out.push(...b);
  return out;
}

function pickLatestIosSubscriptionExpiry(verifyJson) {
  if (verifyJson.status !== 0) {
    return { error: `Apple verifyReceipt status=${verifyJson.status}` };
  }
  const bid = (verifyJson.receipt && verifyJson.receipt.bundle_id) || "";
  if (bid !== IOS_BUNDLE_ID) {
    return { error: `bundle_id mismatch (expected ${IOS_BUNDLE_ID})` };
  }
  const latest = allIosReceiptTransactions(verifyJson);
  if (!latest.length) {
    return { error: "No subscription rows in receipt" };
  }
  let bestMs = 0;
  let productId = "";
  for (const t of latest) {
    const pid = (t.product_id || "").toString();
    if (!IOS_IAP_PRODUCT_IDS.has(pid)) continue;
    let ms = parseInt(t.expires_date_ms, 10);
    if (!Number.isFinite(ms) || ms <= 0) {
      const ed = (t.expires_date || "").toString().trim();
      if (ed) {
        const parsed = Date.parse(ed.replace(" ", "T"));
        if (Number.isFinite(parsed)) ms = parsed;
      }
    }
    if (!Number.isFinite(ms) || ms <= 0) continue;
    if (ms > bestMs) {
      bestMs = ms;
      productId = pid;
    }
  }
  if (bestMs === 0) {
    return { error: "No active subscription for Controle Total products in receipt" };
  }
  return { expiresMs: bestMs, productId };
}

/**
 * Cliente iOS envia receipt base64 (após compra / restaurar). Valida com Apple e grava licenseExpiresAt.
 * Requer utilizador autenticado; só atualiza users/{uid} do próprio token.
 */
exports.ctVerifyIosReceipt = onCall({ cors: true }, async (req) => {
  if (!req.auth || !req.auth.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
  }
  const receiptData = (req.data?.receiptData || "").toString().trim();
  if (!receiptData) {
    throw new functions.https.HttpsError("invalid-argument", "receiptData vazio.");
  }
  const passwordRaw = (appleIapSharedSecretParam.value() || "").toString().trim();
  const password =
    passwordRaw && passwordRaw !== APPLE_IAP_UNSET ? passwordRaw : "";
  if (!password) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "APPLE_IAP_SHARED_SECRET não configurado. App Store Connect → App Information → App-Specific Shared Secret; defina o parâmetro no Firebase (mesmo nome)."
    );
  }
  let verifyJson;
  try {
    verifyJson = await appleVerifyReceiptHttp(receiptData, password);
  } catch (e) {
    console.error("ctVerifyIosReceipt fetch:", e);
    throw new functions.https.HttpsError("internal", "Falha ao contactar Apple verifyReceipt.");
  }
  const picked = pickLatestIosSubscriptionExpiry(verifyJson);
  if (picked.error) {
    throw new functions.https.HttpsError("invalid-argument", picked.error);
  }
  const expDate = new Date(picked.expiresMs);
  const uid = req.auth.uid;
  const userRef = admin.firestore().doc(`users/${uid}`);

  const novaDataExpiracao = admin.firestore.Timestamp.fromDate(endOfDayBrasilia(expDate));
  const graceDayStart = new Date(expDate.getTime());
  graceDayStart.setUTCDate(graceDayStart.getUTCDate() + 3);
  const licenseValidUntilIncludingGrace = admin.firestore.Timestamp.fromDate(endOfDayBrasilia(graceDayStart));

  await userRef.set(
    {
      plan: "premium",
      planStatus: "active",
      licenseExpiresAt: novaDataExpiracao,
      licenseValidUntilIncludingGrace,
      lastIosIapProductId: picked.productId,
      lastIosIapVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  return {
    ok: true,
    productId: picked.productId,
    licenseExpiresAt: expDate.toISOString(),
  };
});

// Agregados mensais (saldo de abertura do gráfico no painel) + reconstrução one-shot por utilizador.
const {
  financeMonthBucketsOnTransactionWrite,
  ctFinanceRebuildOpeningBuckets,
} = require("./financeMonthBuckets");
exports.financeMonthBucketsOnTransactionWrite = financeMonthBucketsOnTransactionWrite;
exports.ctFinanceRebuildOpeningBuckets = ctFinanceRebuildOpeningBuckets;

const {
  ctFinanceCreateTransferHandler,
  ctFinanceGetTransferPairHandler,
} = require("./financeTransfers");
exports.ctFinanceCreateTransfer = onCall({ region: "us-central1", memory: "256MiB" }, ctFinanceCreateTransferHandler);
exports.ctFinanceGetTransferPair = onCall({ region: "us-central1", memory: "256MiB" }, ctFinanceGetTransferPairHandler);

// Dicas financeiras — push agendado (coleção `financial_tips`, mesmas condições que o app).
const { financialTipsInsightPushScheduled } = require("./financialTipsInsightPushScheduled");
exports.financialTipsInsightPushScheduled = financialTipsInsightPushScheduled;

const { generateFinancialTipWithAI } = require("./generateFinancialTipAI");
exports.ctGenerateFinancialTipWithAI = onCall(
  { region: "us-central1", memory: "256MiB" },
  async (req) => {
    if (!req.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
    }
    const uid = req.auth.uid;
    const userSnap = await admin.firestore().doc(`users/${uid}`).get();
    const role = ((userSnap.data() || {}).role || "").toString();
    const email = (req.auth.token?.email || "").toString();
    if (role !== "admin" && email !== "raihom@gmail.com") {
      throw new functions.https.HttpsError("permission-denied", "Somente admin.");
    }
    const data = req.data && typeof req.data === "object" ? req.data : {};
    return generateFinancialTipWithAI({
      tema: data.tema || data.topic || "",
      categoria: data.categoria || data.category || "educacao",
      tom: data.tom || data.tone || "",
    });
  },
);

// Migração financeira em massa (admin / token APP_VERSION_SECRET).
const { importFinanceMigration, consolidateToSantanderAccount } = require("./financeMigrationImport");
exports.ctAdminFinanceMigrationImport = onRequest(
  { region: "us-central1", memory: "1GiB", timeoutSeconds: 540 },
  async (req, res) => {
    try {
      let secret = (appVersionSecret.value() || process.env.APP_VERSION_SECRET || "").toString().trim();
      if (!secret) {
        try {
          const cfg = functions.config();
          secret = (cfg?.app?.version_secret || "").toString().trim();
        } catch (_) {}
      }
      const token = (req.query.token || req.body?.token || "").toString().trim();
      if (!secret || token !== secret) {
        return res.status(401).json({ ok: false, error: "token invalido" });
      }
      const body = req.body && typeof req.body === "object" ? req.body : {};
      const uid = (req.query.uid || body.uid || "").toString().trim();
      if (!uid) {
        return res.status(400).json({ ok: false, error: "uid obrigatorio" });
      }
      const result = await importFinanceMigration(uid, body);
      return res.status(200).json(result);
    } catch (e) {
      console.error("ctAdminFinanceMigrationImport:", e);
      return res.status(500).json({ ok: false, error: String(e?.message || e) });
    }
  },
);

exports.ctAdminFinanceConsolidateSantander = onRequest(
  { region: "us-central1", memory: "1GiB", timeoutSeconds: 540 },
  async (req, res) => {
    try {
      let secret = (appVersionSecret.value() || process.env.APP_VERSION_SECRET || "").toString().trim();
      if (!secret) {
        try {
          const cfg = functions.config();
          secret = (cfg?.app?.version_secret || "").toString().trim();
        } catch (_) {}
      }
      const token = (req.query.token || req.body?.token || "").toString().trim();
      if (!secret || token !== secret) {
        return res.status(401).json({ ok: false, error: "token invalido" });
      }
      const body = req.body && typeof req.body === "object" ? req.body : {};
      const uid = (req.query.uid || body.uid || "").toString().trim();
      if (!uid) {
        return res.status(400).json({ ok: false, error: "uid obrigatorio" });
      }
      const result = await consolidateToSantanderAccount(uid, body);
      return res.status(200).json(result);
    } catch (e) {
      console.error("ctAdminFinanceConsolidateSantander:", e);
      return res.status(500).json({ ok: false, error: String(e?.message || e) });
    }
  },
);