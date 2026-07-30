"use strict";

/**
 * Cron (a cada 6h): para usuários com licença ativa e token FCM, avalia lançamentos recentes
 * contra `financial_tips` e envia uma notificação com a primeira dica aplicável.
 * Rate limit: 1 push / 12h por usuário (doc users/{uid}/insights_cache/push_rate).
 */
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

const TZ_BRASILIA = "America/Sao_Paulo";
const APP_DOMAIN = "https://controletotalapp.com.br";
const COLLECTION_TIPS = "financial_tips";
const BATCH_USERS = 80;
const RATE_LIMIT_MS = 12 * 60 * 60 * 1000;
const DAYS_LOOKBACK = 30;

function multicastWebPushApnsLink(link) {
  if (!link || typeof link !== "string") return {};
  return {
    webpush: { fcmOptions: { link } },
    apns: { fcmOptions: { link } },
  };
}

function userHasActiveLicense(userData) {
  const exp = userData.licenseExpiresAt;
  if (!exp) return true;
  let ms;
  if (typeof exp.toMillis === "function") ms = exp.toMillis();
  else if (exp.seconds != null) ms = exp.seconds * 1000;
  else return true;
  return Date.now() < ms + 3 * 24 * 60 * 60 * 1000;
}

function aggregateTransactions(docs) {
  let totalEntrada = 0;
  let totalSaida = 0;
  const categorias = {};
  for (const doc of docs) {
    const d = doc.data();
    const type = (d.type || "expense").toString();
    const amt = Math.abs(parseFloat(d.amount) || 0);
    if (type === "income") totalEntrada += amt;
    else if (type === "expense") {
      totalSaida += amt;
      const cat = (d.category || "").toString().trim() || "Sem categoria";
      categorias[cat] = (categorias[cat] || 0) + amt;
    }
  }
  let topName = null;
  let topShare = null;
  const keys = Object.keys(categorias);
  if (keys.length > 0 && totalSaida > 0.0001) {
    topName = keys.reduce((a, b) => (categorias[a] >= categorias[b] ? a : b));
    topShare = (categorias[topName] / totalSaida) * 100;
  }
  return {
    totalEntrada,
    totalSaida,
    categorias,
    topExpenseCategoryName: topName,
    topExpenseCategorySharePct: topShare,
  };
}

function sameCategoryName(a, b) {
  return (a || "").trim().toLowerCase() === (b || "").trim().toLowerCase();
}

function valorCategoria(categorias, wanted) {
  const w = (wanted || "").trim().toLowerCase();
  if (!w) return 0;
  for (const k of Object.keys(categorias)) {
    if (k.trim().toLowerCase() === w) return categorias[k];
  }
  return 0;
}

function validarCondicao(cond, agg) {
  if (!cond || typeof cond !== "object") return false;
  const tipo = (cond.tipo || "").toString().trim();
  const entrada = agg.totalEntrada;
  const saida = agg.totalSaida;
  const categorias = agg.categorias;
  if (tipo === "sempre") return true;
  if (tipo === "gasto_maior_receita") return saida > entrada + 0.01;
  if (tipo === "categoria_maior") {
    const cat = (cond.categoria || "").toString();
    const min = parseFloat(cond.valor_min) || 0;
    return valorCategoria(categorias, cat) > min;
  }
  if (tipo === "concentracao_categoria") {
    const cat = (cond.categoria || "").toString();
    const minPct = parseFloat(cond.pct_min) || 0;
    if (!agg.topExpenseCategoryName || agg.topExpenseCategorySharePct == null) return false;
    if (!sameCategoryName(agg.topExpenseCategoryName, cat)) return false;
    return agg.topExpenseCategorySharePct >= minPct;
  }
  return false;
}

async function loadTipsOrdered(db) {
  const snap = await db.collection(COLLECTION_TIPS).get();
  return snap.docs.sort((a, b) => {
    const oa = a.data().ordem != null ? Number(a.data().ordem) : 999;
    const ob = b.data().ordem != null ? Number(b.data().ordem) : 999;
    return oa - ob;
  });
}

function matchingTips(agg, tipDocs) {
  const out = [];
  for (const doc of tipDocs) {
    const data = doc.data() || {};
    if (data.ativo === false) continue;
    const cond = data.condicao;
    if (!validarCondicao(cond, agg)) continue;
    const titulo = (data.titulo || "").toString().trim();
    const descricao = (data.descricao || "").toString().trim();
    if (!titulo && !descricao) continue;
    out.push({ id: doc.id, titulo: titulo || "Dica", body: descricao || titulo });
  }
  return out;
}

exports.financialTipsInsightPushScheduled = onSchedule(
  {
    schedule: "every 6 hours",
    timeZone: TZ_BRASILIA,
    region: "us-central1",
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    const db = admin.firestore();
    let tipDocs;
    try {
      tipDocs = await loadTipsOrdered(db);
    } catch (e) {
      console.warn("[financialTipsInsightPushScheduled] load tips:", e?.message || e);
      return null;
    }
    if (!tipDocs.length) return null;

    const usersSnap = await db.collection("users").get();
    const userDocs = usersSnap.docs;
    let sent = 0;

    for (let i = 0; i < userDocs.length; i += BATCH_USERS) {
      const slice = userDocs.slice(i, i + BATCH_USERS);
      for (const userDoc of slice) {
        const uid = userDoc.id;
        const userData = userDoc.data() || {};
        if (!userHasActiveLicense(userData)) continue;

        const notifSnap = await db.collection("users").doc(uid).collection("settings").doc("notifications").get();
        const notif = notifSnap.data() || {};
        if (notif.financeTipsPushEnabled === false) continue;

        const rateRef = db.collection("users").doc(uid).collection("insights_cache").doc("push_rate");
        const rateSnap = await rateRef.get();
        const last = rateSnap.data()?.lastFinanceTipPushAt;
        if (last && typeof last.toMillis === "function" && Date.now() - last.toMillis() < RATE_LIMIT_MS) {
          continue;
        }

        const fcmTokenLegacy = (userData.fcmToken || "").toString().trim();
        const tokensSnap = await db.collection("users").doc(uid).collection("deviceTokens").get();
        let tokens = tokensSnap.docs.map((d) => d.id).filter(Boolean);
        if (tokens.length === 0 && fcmTokenLegacy) tokens = [fcmTokenLegacy];
        if (tokens.length === 0) continue;

        const since = new Date(Date.now() - DAYS_LOOKBACK * 24 * 60 * 60 * 1000);
        const sinceTs = admin.firestore.Timestamp.fromDate(since);
        let txDocs;
        try {
          const txSnap = await db
            .collection("users")
            .doc(uid)
            .collection("transactions")
            .where("date", ">=", sinceTs)
            .get();
          txDocs = txSnap.docs;
        } catch (e) {
          continue;
        }

        const agg = aggregateTransactions(txDocs);
        const tips = matchingTips(agg, tipDocs);
        if (tips.length === 0) continue;
        const first = tips[0];
        const link = `${APP_DOMAIN}/?tab=finance`;

        try {
          const resp = await admin.messaging().sendEachForMulticast({
            tokens,
            notification: { title: first.titulo, body: first.body },
            data: { url: link, kind: "finance_tip", tipId: first.id },
            ...multicastWebPushApnsLink(link),
          });
          sent += resp.successCount;
          resp.responses.forEach((r, i) => {
            if (!r.success && (r.error?.code === "messaging/invalid-registration-token" || r.error?.code === "messaging/registration-token-not-registered")) {
              const badToken = tokens[i];
              if (badToken) {
                db.collection("users").doc(uid).collection("deviceTokens").doc(badToken).delete().catch(() => {});
              }
            }
          });
          await rateRef.set(
            {
              lastFinanceTipPushAt: admin.firestore.FieldValue.serverTimestamp(),
              lastTipId: first.id,
            },
            { merge: true }
          );
        } catch (e) {
          console.warn(`[financialTipsInsightPushScheduled] uid=${uid}`, e?.message || e);
        }
      }
    }

    if (sent > 0) console.log(`[financialTipsInsightPushScheduled] multicast ok count ~ ${sent}`);
    return null;
  }
);
