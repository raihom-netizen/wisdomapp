/**
 * Resumo diário da agenda (e-mail + push opcional) — padrão 20h Brasília.
 */

const admin = require("firebase-admin");
const agendaMsg = require("./agenda_message_templates");
const notifTpl = require("./notification_templates_config");

function formatDateBr(date) {
  const dd = String(date.getDate()).padStart(2, "0");
  const mm = String(date.getMonth() + 1).padStart(2, "0");
  return `${dd}/${mm}/${date.getFullYear()}`;
}

function formatTimeHm(str) {
  const parts = String(str || "").split(":");
  const h = String(parseInt(parts[0], 10) || 0).padStart(2, "0");
  const m = String(parseInt(parts[1], 10) || 0).padStart(2, "0");
  return `${h}h${m}`;
}

function dateKeyBrasilia(date) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Sao_Paulo",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const y = parts.find((p) => p.type === "year")?.value;
  const m = parts.find((p) => p.type === "month")?.value;
  const d = parts.find((p) => p.type === "day")?.value;
  return `${y}-${m}-${d}`;
}

/** Início/fim do dia-alvo em Brasília (Date UTC instants). */
function dayBoundsBrasilia(targetDate) {
  const key = dateKeyBrasilia(targetDate);
  const [y, mo, d] = key.split("-").map((x) => parseInt(x, 10));
  const start = new Date(Date.UTC(y, mo - 1, d, 3, 0, 0, 0));
  const end = new Date(Date.UTC(y, mo - 1, d + 1, 2, 59, 59, 999));
  return { start, end, key };
}

function isSameCalendarDayBrasilia(tsDate, bounds) {
  const t = tsDate.getTime();
  return t >= bounds.start.getTime() && t <= bounds.end.getTime();
}

function buildDigestRows(items) {
  if (!items.length) return "";
  return items
    .map((it) => {
      const icon = it.kind === "audiencia" ? "⚖️" : it.kind === "compromisso" ? "📌" : "🕒";
      return agendaMsg.emailRowLine(
        `${icon} <strong>${agendaMsg.escapeHtml(it.time)}</strong> — ${agendaMsg.escapeHtml(it.label)}`,
      );
    })
    .join("");
}

function buildDigestEmailHtml(userName, dateLabel, sections, appDomain, templates) {
  const greet = agendaMsg.greetUser(userName);
  const brand = (templates.brandName || "Controle Total App").toString();
  const footer = (templates.emailFooter || `© ${brand}`).toString();
  let body = `<p>${greet} 👋</p><p>Seu resumo para <strong>${agendaMsg.escapeHtml(dateLabel)}</strong>:</p>`;
  for (const sec of sections) {
    if (!sec.items.length) continue;
    const theme = agendaMsg.channelTheme(sec.kind);
    const card = agendaMsg.premiumEmailHeroCard(
      notifTpl.mergeChannelTheme(theme, templates, sec.kind),
      sec.title,
      buildDigestRows(sec.items),
    );
    body += card;
  }
  body += `<p style="text-align:center;margin:20px 0"><a href="${appDomain}/?tab=agenda" class="btn" style="background:#2D5BFF;color:#fff!important;text-decoration:none;padding:14px 28px;border-radius:12px;font-weight:800">ABRIR AGENDA</a></p>`;
  body += `<p style="margin-top:20px;color:#64748b;font-size:13px">${agendaMsg.escapeHtml(footer)}</p>`;
  return agendaMsg.buildEmailBasePremium(
    `Sua agenda de amanhã · ${brand}`,
    body,
    "#2D5BFF",
    templates,
  );
}

/**
 * Modelo da série anual (`isYearlyRepeatTemplate`) não é compromisso do dia —
 * as ocorrências `{id}_yAAAA` já entram; contar o modelo dava o anual em dobro.
 */
function isYearlyRepeatTemplateDoc(d) {
  if (!d) return false;
  return d.isYearlyRepeatTemplate === true ||
    String(d.source || "") === "yearly_repeat_template";
}

/** Só os docs do dia-alvo (antes lia a coleção inteira de cada usuário). */
function dayRangeQuery(col, bounds) {
  return col
    .where("date", ">=", admin.firestore.Timestamp.fromDate(bounds.start))
    .where("date", "<=", admin.firestore.Timestamp.fromDate(bounds.end));
}

async function collectTomorrowAgendaItems(db, uid, bounds) {
  const items = { audiencia: [], compromisso: [], escala: [] };

  const remSnap = await dayRangeQuery(
    db.collection("users").doc(uid).collection("reminders"),
    bounds,
  ).get();
  for (const doc of remSnap.docs) {
    const d = doc.data();
    if (isYearlyRepeatTemplateDoc(d)) continue;
    const date = d.date?.toDate ? d.date.toDate() : null;
    if (!date || !isSameCalendarDayBrasilia(date, bounds)) continue;
    const type = (d.type || "compromisso").toString().toLowerCase();
    const time = formatTimeHm(d.time || "09:00");
    const title = (d.title || "").toString().trim();
    if (type === "audiencia") {
      if ((d.status || "EM_ABERTO").toString() !== "EM_ABERTO" && d.done === true) continue;
      items.audiencia.push({ kind: "audiencia", time, label: title || "Audiência" });
    } else {
      if (d.done === true) continue;
      items.compromisso.push({ kind: "compromisso", time, label: title || "Compromisso" });
    }
  }

  const scalesSnap = await dayRangeQuery(
    db.collection("users").doc(uid).collection("scales"),
    bounds,
  ).get();
  for (const doc of scalesSnap.docs) {
    const d = doc.data();
    if (d.isAgendaMirror === true || d.isProdutividadeFolgaMirror === true) continue;
    if (isYearlyRepeatTemplateDoc(d)) continue;
    const date = d.date?.toDate ? d.date.toDate() : null;
    if (!date || !isSameCalendarDayBrasilia(date, bounds)) continue;
    const isComp = d.isCompromisso === true;
    const time = formatTimeHm(d.start || "08:00");
    const label = (d.label || d.scaleLocationName || d.abbreviation || "Plantão").toString().trim();
    if (isComp) {
      items.compromisso.push({ kind: "compromisso", time, label: label || "Compromisso" });
    } else {
      items.escala.push({ kind: "escala", time, label: label || "Escala" });
    }
  }

  for (const k of Object.keys(items)) {
    items[k].sort((a, b) => a.time.localeCompare(b.time));
  }
  return items;
}

async function processUserDailyDigest(db, uid, userData, bounds, templates, appDomain, sendEmailHtml, sendPushFn) {
  const notifSnap = await db.collection("users").doc(uid).collection("settings").doc("notifications").get();
  const notif = notifSnap.data() || {};
  if (notif.emailReminderEnabled === false) return { email: 0, push: 0 };
  if (notif.dailyDigestEnabled === false) return { email: 0, push: 0 };
  if (templates.digestEnabled === false) return { email: 0, push: 0 };

  const lastKey = (notif.lastDailyDigestKey || "").toString();
  if (lastKey === bounds.key) return { email: 0, push: 0 };

  const items = await collectTomorrowAgendaItems(db, uid, bounds);
  const total =
    items.audiencia.length + items.compromisso.length + items.escala.length;
  const notifRef = db.collection("users").doc(uid).collection("settings").doc("notifications");
  if (total === 0) {
    await notifRef.set(
      { lastDailyDigestKey: bounds.key, updatedAt: admin.firestore.FieldValue.serverTimestamp() },
      { merge: true },
    );
    return { email: 0, push: 0 };
  }

  const name = (userData.name || "").toString().trim() || "Usuário";
  const email = (userData.email || "").toString().trim();
  const dateLabel = formatDateBr(bounds.start);
  const sections = [
    { kind: "audiencia", title: `Audiências (${items.audiencia.length})`, items: items.audiencia },
    { kind: "compromisso", title: `Compromissos (${items.compromisso.length})`, items: items.compromisso },
    { kind: "escala", title: `Escalas (${items.escala.length})`, items: items.escala },
  ];
  const html = buildDigestEmailHtml(name, dateLabel, sections, appDomain, templates);
  const brand = (templates.brandName || "Controle Total App").toString();
  const subject = `Sua agenda de amanhã (${dateLabel}) · ${brand}`;

  let emailOk = false;
  if (email && /^[^@]+@[^@]+\.[^@]+$/.test(email)) {
    const res = await sendEmailHtml(email, subject, html);
    emailOk = res.ok;
  }

  let pushOk = false;
  if (templates.digestPushEnabled !== false && typeof sendPushFn === "function") {
    pushOk = await sendPushFn(uid, userData, {
      title: `Amanhã: ${total} item(ns) na agenda`,
      body: `${items.audiencia.length} audiência(s), ${items.compromisso.length} compromisso(s), ${items.escala.length} escala(s).`,
      link: `${appDomain}/?tab=agenda`,
    });
  }

  if (emailOk || pushOk) {
    await notifRef.set(
      { lastDailyDigestKey: bounds.key, updatedAt: admin.firestore.FieldValue.serverTimestamp() },
      { merge: true },
    );
  }

  return { email: emailOk ? 1 : 0, push: pushOk ? 1 : 0 };
}

async function runDailyAgendaDigest(db, appDomain, sendEmailHtml, sendPushFn) {
  const templates = await notifTpl.loadNotificationTemplates(db);
  if (templates.digestEnabled === false) return { users: 0, email: 0, push: 0 };

  const now = new Date();
  const tomorrow = new Date(now.getTime() + 24 * 60 * 60 * 1000);
  const bounds = dayBoundsBrasilia(tomorrow);

  let lastDoc = null;
  const pageSize = 40;
  let users = 0;
  let email = 0;
  let push = 0;

  while (true) {
    let q = db.collection("users").orderBy(admin.firestore.FieldPath.documentId()).limit(pageSize);
    if (lastDoc) q = q.startAfter(lastDoc);
    const snap = await q.get();
    if (snap.empty) break;

    for (const userDoc of snap.docs) {
      const r = await processUserDailyDigest(
        db,
        userDoc.id,
        userDoc.data(),
        bounds,
        templates,
        appDomain,
        sendEmailHtml,
        sendPushFn,
      );
      users += 1;
      email += r.email;
      push += r.push;
    }

    lastDoc = snap.docs[snap.docs.length - 1];
    if (snap.size < pageSize) break;
  }

  if (email > 0 || push > 0) {
    console.log(
      `[runDailyAgendaDigest] key=${bounds.key} users=${users} email=${email} push=${push}`,
    );
  }
  return { users, email, push };
}

module.exports = {
  runDailyAgendaDigest,
  dayBoundsBrasilia,
  dateKeyBrasilia,
  collectTomorrowAgendaItems,
  isYearlyRepeatTemplateDoc,
};
