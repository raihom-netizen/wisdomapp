/**

 * Biblioteca premium de mensagens — push e e-mail (audiência, compromisso, escala).

 * Títulos: «1 dia antes — Escala»; corpo com amanhã/hoje + início e término.

 */



const BRAND_APP = "Controle Total App";



function escapeHtml(s) {

  return String(s || "")

    .replace(/&/g, "&amp;")

    .replace(/</g, "&lt;")

    .replace(/>/g, "&gt;")

    .replace(/"/g, "&quot;");

}



function greetUser(name) {

  const n = (name || "").toString().trim();

  if (!n) return "Olá";

  const parts = n.split(/\s+/).filter(Boolean);

  if (parts.length >= 2 && parts[0].length <= 4) {

    return `Olá, ${parts[0]} ${parts[1]}`;

  }

  return `Olá, ${parts[0]}`;

}



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



/** Normaliza antecedência para buckets padrão (1440, 60, 30, 15). */

function normalizeLeadMinutes(leadMin) {

  const m = parseInt(leadMin, 10) || 0;

  if (m <= 0) return 0;

  for (const bucket of [1440, 60, 30, 15]) {

    if (Math.abs(m - bucket) <= 5) return bucket;

  }

  return m;

}



/** Título push/e-mail: «1 dia antes», «1 hora antes», «30 minutos antes»… */

function leadTitlePrefix(leadMin) {

  const m = normalizeLeadMinutes(leadMin);

  if (m <= 0) return "Lembrete";

  if (m >= 1440) {

    const d = Math.round(m / 1440);

    return d === 1 ? "1 dia antes" : `${d} dias antes`;

  }

  if (m === 60) return "1 hora antes";

  if (m === 30) return "30 minutos antes";

  if (m === 15) return "15 minutos antes";

  if (m > 60) {

    const h = Math.round(m / 60);

    return h === 1 ? "1 hora antes" : `${h} horas antes`;

  }

  return m === 1 ? "1 minuto antes" : `${m} minutos antes`;

}



function leadLabelLong(leadMin) {

  return leadTitlePrefix(leadMin);

}



function channelKindLabel(channelKind) {

  const k = (channelKind || "").toString().toLowerCase();

  if (k === "escala") return "Escala";

  if (k === "audiencia") return "Audiência";

  if (k === "compromisso") return "Compromisso";

  if (k === "financeiro") return "Financeiro";

  return "Agenda";

}



/** Cores e agrupamento por tipo (push Android + e-mail + thread iOS). */

function channelTheme(channelKind) {

  const k = (channelKind || "").toString().toLowerCase();

  if (k === "audiencia") {

    return {

      accent: "#5B21B6",

      accent2: "#7C3AED",

      emoji: "⚖️",

      label: "Audiência",

      androidColor: "#5B21B6",

      threadId: "controletotal_audiencia",

    };

  }

  if (k === "compromisso") {

    return {

      accent: "#2563EB",

      accent2: "#1D4ED8",

      emoji: "📌",

      label: "Compromisso",

      androidColor: "#2563EB",

      threadId: "controletotal_compromisso",

    };

  }

  if (k === "financeiro") {

    return {

      accent: "#0D9488",

      accent2: "#14B8A6",

      emoji: "💳",

      label: "Financeiro",

      androidColor: "#0D9488",

      threadId: "controletotal_financeiro",

    };

  }

  if (k === "folga") {

    return {

      accent: "#7C3AED",

      accent2: "#6D28D9",

      emoji: "🌴",

      label: "Folga",

      androidColor: "#7C3AED",

      threadId: "controletotal_folga",

    };

  }

  return {

    accent: "#EA580C",

    accent2: "#C2410C",

    emoji: "🕒",

    label: "Escala",

    androidColor: "#EA580C",

    threadId: "controletotal_escala",

  };

}



function prependPushGreeting(body, userName) {

  const g = greetUser(userName);

  if (!g || g === "Olá" || !body) return body;

  return `${g},\n\n${body}`;

}



function pushSubtitle(channelKind, leadMin) {

  return `${channelKindLabel(channelKind)} · ${leadTitlePrefix(leadMin)}`;

}



function emailRowLine(html) {

  return `<div style="padding:10px 12px;margin:8px 0;background:#fff;border-radius:10px;border-left:4px solid #e2e8f0;font-size:14px;line-height:1.45">${html}</div>`;

}



/** Online (link / «on LINE») vs presencial (endereço) — neutro, sem «Trabalhista». */

function resolveAudienciaModality(d) {

  const local = (d.localAudiencia || "").toString().trim();

  const link = (d.linkSalaAudiencia || "").toString().trim();

  const ll = local.toLowerCase().replace(/\s+/g, " ");

  const isOnline =

    link.length > 0 || ll === "on line" || ll === "online" || ll.includes("on line");

  if (isOnline) {

    return { isOnline: true, modalityLabel: "ON LINE", link, address: "" };

  }

  let address = local;

  if (ll === "presencial") address = "";

  if (!address) address = "Endereço não informado";

  return { isOnline: false, modalityLabel: "PRESENCIAL", link: "", address };

}



function eventDayContext(eventAt, now) {

  const n = now || new Date();

  if (!eventAt) {

    return { headline: "", whenWord: "", dateStr: "" };

  }

  const sameDay =

    eventAt.getFullYear() === n.getFullYear() &&

    eventAt.getMonth() === n.getMonth() &&

    eventAt.getDate() === n.getDate();

  const tomorrow = new Date(n.getFullYear(), n.getMonth(), n.getDate() + 1);

  const isTomorrow =

    eventAt.getFullYear() === tomorrow.getFullYear() &&

    eventAt.getMonth() === tomorrow.getMonth() &&

    eventAt.getDate() === tomorrow.getDate();

  const dateStr = formatDateBr(eventAt);

  if (isTomorrow) return { headline: "Amanhã", whenWord: "amanhã", dateStr };

  if (sameDay) return { headline: "Hoje", whenWord: "hoje", dateStr };

  return { headline: "", whenWord: "", dateStr };

}



function leadTimingPhrase(leadMin) {

  const m = normalizeLeadMinutes(leadMin);

  if (m >= 1440) return null;

  if (m === 60) return "em 1 hora";

  if (m === 30) return "em 30 minutos";

  if (m === 15) return "em 15 minutos";

  if (m > 60) {

    const h = Math.round(m / 60);

    return h === 1 ? "em 1 hora" : `em ${h} horas`;

  }

  return m === 1 ? "em 1 minuto" : `em ${m} minutos`;

}



function buildPushTitle(leadMin, channelKind) {

  return `${leadTitlePrefix(leadMin)} — ${channelKindLabel(channelKind)}`;

}

function compactTitleDetail(value, max = 42) {
  const clean = (value || "").toString().trim().replace(/\s+/g, " ");
  if (!clean) return "";
  if (clean.length <= max) return clean;
  return `${clean.slice(0, max - 1).trimEnd()}…`;
}



function reminderContext(d, eventAt, leadMin) {

  const type = (d.type || "compromisso").toString().toLowerCase();

  const isAud = type === "audiencia";

  const title = (d.title || "").toString().trim();

  const timeStr = (d.time || "09:00").toString();

  const localAud = (d.localAudiencia || "").toString().trim();

  const linkSala = (d.linkSalaAudiencia || "").toString().trim();

  const sei = (d.numeroSei || "").toString().trim();

  const oco = (d.numeroOcorrencia || "").toString().trim();

  const status = (d.status || "EM_ABERTO").toString();

  const confirmed = status === "REALIZADO" || d.done === true;

  return {

    isAud,

    channelKind: isAud ? "audiencia" : "compromisso",

    eventTitle: title || (isAud ? "Audiência" : "Compromisso"),

    timeStr,

    endStr: "",

    local: localAud,

    sala: linkSala,

    processo: sei,

    numeroOcorrencia: oco,

    cliente: (d.cliente || d.notes || "").toString().trim(),

    confirmed,

    modality: isAud ? resolveAudienciaModality(d) : null,

    eventAt,

    leadMin: normalizeLeadMinutes(leadMin),

  };

}



function buildAudienciaBody(ctx, now) {

  const day = eventDayContext(ctx.eventAt, now);

  const startHm = formatTimeHm(ctx.timeStr);

  const dateStr = day.dateStr || formatDateBr(ctx.eventAt);

  const mod = ctx.modality || { modalityLabel: "PRESENCIAL" };

  const lines = [`📅 ${dateStr} · 🕒 ${startHm}`];

  if (ctx.processo) lines.push(`📂 Nº SEI: ${ctx.processo}`);

  if (ctx.numeroOcorrencia) lines.push(`🏷️ Nº Ocorrência: ${ctx.numeroOcorrencia}`);

  lines.push(`📍 ${mod.modalityLabel}`);

  if (ctx.eventTitle && ctx.eventTitle !== "Audiência") lines.push(`📝 ${ctx.eventTitle}`);

  lines.push("", "Toque para abrir os detalhes.");

  return lines.join("\n");

}



function buildCompromissoBody(ctx, now) {

  const day = eventDayContext(ctx.eventAt, now);

  const startHm = formatTimeHm(ctx.timeStr);

  const dateStr = day.dateStr || formatDateBr(ctx.eventAt);

  const titulo = ctx.eventTitle || "Compromisso";

  const lines = [`📅 ${dateStr} · 🕒 ${startHm}`, `📝 ${titulo}`];

  if (ctx.cliente) lines.push(`👤 Cliente: ${ctx.cliente}`);

  if (ctx.local) lines.push(`📍 ${ctx.local}`);

  lines.push("", "Toque para abrir a agenda.");

  return lines.join("\n");

}



function buildEscalaBody(ctx, now) {

  const day = eventDayContext(ctx.eventAt, now);

  const startHm = formatTimeHm(ctx.timeStr);

  const endHm = formatTimeHm(ctx.endStr || "18:00");

  const dateStr = day.dateStr || formatDateBr(ctx.eventAt);

  const lines = [`📅 ${dateStr} · 🕒 ${startHm} – ${endHm}`];

  if (ctx.eventTitle && ctx.eventTitle !== "Plantão") lines.push(`📝 ${ctx.eventTitle}`);

  if (ctx.local && ctx.local !== "Plantão") lines.push(`📍 ${ctx.local}`);

  lines.push("", "Toque para ver a escala.");

  return lines.join("\n");

}



function buildAudienciaPush(ctx, userName, now) {

  const detail = compactTitleDetail(
    ctx.eventTitle && ctx.eventTitle !== "Audiência"
      ? ctx.eventTitle
      : (ctx.processo ? `SEI ${ctx.processo}` : "")
  );

  const title = detail
    ? `${leadTitlePrefix(ctx.leadMin)} — Audiência: ${detail}`
    : buildPushTitle(ctx.leadMin, "audiencia");

  const body = prependPushGreeting(buildAudienciaBody(ctx, now), userName);

  return { title, body, channelKind: "audiencia", subtitle: pushSubtitle("audiencia", ctx.leadMin) };

}



function buildCompromissoPush(ctx, userName, now) {

  const detail = compactTitleDetail(ctx.eventTitle || "Compromisso");

  const title = detail && detail !== "Compromisso"
    ? `${leadTitlePrefix(ctx.leadMin)} — Compromisso: ${detail}`
    : buildPushTitle(ctx.leadMin, "compromisso");

  const body = prependPushGreeting(buildCompromissoBody(ctx, now), userName);

  return { title, body, channelKind: "compromisso", subtitle: pushSubtitle("compromisso", ctx.leadMin) };

}



function buildEscalaPush(ctx, userName, now) {

  const escalaNome =
    ctx.eventTitle && ctx.eventTitle !== "Plantão" ? ctx.eventTitle : ctx.local;
  const detail = compactTitleDetail(escalaNome);

  const title = detail && detail !== "Plantão"
    ? `${leadTitlePrefix(ctx.leadMin)} — Escala: ${detail}`
    : buildPushTitle(ctx.leadMin, "escala");

  const body = prependPushGreeting(buildEscalaBody(ctx, now), userName);

  return { title, body, channelKind: "escala", subtitle: pushSubtitle("escala", ctx.leadMin) };

}



/** Push premium a partir de reminder Firestore. */

function buildPushFromReminder(d, eventAt, leadMin, userName, now) {

  const ctx = reminderContext(d, eventAt, leadMin);

  return ctx.isAud

    ? buildAudienciaPush(ctx, userName, now)

    : buildCompromissoPush(ctx, userName, now);

}



/** Push premium a partir de escala Firestore. */

function buildPushFromScale(d, eventAt, startStr, leadMin, userName, now) {

  const isCompromisso = d.isCompromisso === true;

  const label = (d.label || d.scaleLocationName || d.abbreviation || "Plantão").toString().trim();

  const abbr = (d.abbreviation || "").toString().trim();

  const local = abbr || label || "Plantão";

  const endStr = (d.end || "18:00").toString();

  const ctx = {

    eventTitle: label || "Plantão",

    local,

    timeStr: startStr,

    endStr,

    eventAt,

    leadMin: normalizeLeadMinutes(leadMin),

    confirmed: false,

  };

  if (isCompromisso) {

    ctx.eventTitle = label || "Compromisso";

    ctx.cliente = (d.notes || "").toString().trim();

    ctx.local = (d.notes || "").toString().trim();

    ctx.channelKind = "compromisso";

    const built = buildCompromissoPush(ctx, userName, now);

    return { ...built, channelKind: "compromisso" };

  }

  const built = buildEscalaPush(ctx, userName, now);

  return { ...built, channelKind: "escala" };

}



/** Valor em Real (R$ 1.234,56) — sem libs externas. */
function formatBrlAmount(v) {
  const n = Number(v) || 0;
  const parts = Math.abs(n).toFixed(2).split(".");
  const intPart = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ".");
  return `R$ ${intPart},${parts[1]}`;
}

/** Contexto de uma transação financeira pendente (conta a pagar/receber). */
function transactionContext(d, eventAt, leadMin) {
  const type = (d.type || "expense").toString().toLowerCase();
  const isIncome = type === "income";
  const desc = (d.description || d.category || (isIncome ? "Receita" : "Despesa")).toString().trim();
  return {
    isIncome,
    channelKind: "financeiro",
    eventTitle: isIncome ? "Conta a receber" : "Conta a pagar",
    desc: desc || (isIncome ? "Receita" : "Despesa"),
    amount: d.amount,
    eventAt,
    leadMin: normalizeLeadMinutes(leadMin),
  };
}

function buildFinanceiroBody(ctx, now) {
  const day = eventDayContext(ctx.eventAt, now);
  const dateStr = day.dateStr || formatDateBr(ctx.eventAt);
  const vence = day.whenWord ? `Vence ${day.whenWord} (${dateStr})` : `Vence em ${dateStr}`;
  const lines = [
    `${ctx.isIncome ? "💵" : "💳"} ${vence}`,
    `💰 ${formatBrlAmount(ctx.amount)}`,
    `📝 ${ctx.desc}`,
    "",
    "Toque para abrir o financeiro.",
  ];
  return lines.join("\n");
}

/** Push premium a partir de uma transação financeira (Firestore). */
function buildPushFromTransaction(d, eventAt, leadMin, userName, now) {
  const ctx = transactionContext(d, eventAt, leadMin);
  const detail = compactTitleDetail(ctx.desc);
  const title = detail
    ? `${leadTitlePrefix(leadMin)} — Financeiro: ${detail}`
    : `${leadTitlePrefix(leadMin)} — ${ctx.eventTitle}`;
  const body = prependPushGreeting(buildFinanceiroBody(ctx, now), userName);
  return { title, body, channelKind: "financeiro", subtitle: pushSubtitle("financeiro", leadMin) };
}

function buildAlertSlotForTransaction(d, eventAt, leadMin, now) {
  return buildPushFromTransaction(d, eventAt, leadMin, "", now);
}

/** Slots agendaAlerts — texto sem nome (nome entra no disparo). */

function buildAlertSlotForReminder(d, eventAt, timeStr, leadMin, now) {

  return buildPushFromReminder(d, eventAt, leadMin, "", now);

}



function buildAlertSlotForScale(d, eventAt, startStr, leadMin, now) {

  return buildPushFromScale(d, eventAt, startStr, leadMin, "", now);

}



/** Reenriquece mensagem no disparo com nome do usuário. */

function enrichDispatchMessage(msg, userName, now) {

  const n = now || new Date();

  if (msg.reminderData) {

    const eventAt = msg.date instanceof Date ? msg.date : new Date(msg.date);

    const built = buildPushFromReminder(msg.reminderData, eventAt, msg.leadMin, userName, n);

    return {

      ...msg,

      title: built.title,

      body: built.body,

      subtitle: built.subtitle || pushSubtitle(built.channelKind, msg.leadMin),

      channelKind: built.channelKind,

    };

  }

  if (msg.scaleData) {

    const eventAt = msg.date instanceof Date ? msg.date : new Date(msg.date);

    const built = buildPushFromScale(

      msg.scaleData,

      eventAt,

      msg.startStr || "08:00",

      msg.leadMin,

      userName,

      n,

    );

    return {

      ...msg,

      title: built.title,

      body: built.body,

      subtitle: built.subtitle || pushSubtitle(built.channelKind, msg.leadMin),

      channelKind: built.channelKind,

    };

  }

  if (msg.transactionData) {

    const eventAt = msg.date instanceof Date ? msg.date : new Date(msg.date);

    const built = buildPushFromTransaction(msg.transactionData, eventAt, msg.leadMin, userName, n);

    return {

      ...msg,

      title: built.title,

      body: built.body,

      subtitle: built.subtitle || pushSubtitle("financeiro", msg.leadMin),

      channelKind: "financeiro",

    };

  }

  return msg;

}



function premiumEmailCard(accent, emoji, title, rowsHtml) {

  const theme = { accent, accent2: accent, emoji, label: title };

  return premiumEmailHeroCard(theme, title, rowsHtml);

}



function premiumEmailHeroCard(theme, cardTitle, rowsHtml) {

  return `<div style="border-radius:16px;overflow:hidden;margin:18px 0;box-shadow:0 10px 28px ${theme.accent}40">

<div style="background:linear-gradient(135deg,${theme.accent} 0%,${theme.accent2} 100%);padding:16px 18px;color:#fff">

<div style="font-size:28px;line-height:1">${theme.emoji}</div>

<div style="font-size:11px;font-weight:700;letter-spacing:.1em;opacity:.92;margin-top:8px">${escapeHtml(theme.label).toUpperCase()}</div>

<div style="font-size:18px;font-weight:800;margin-top:4px">${escapeHtml(cardTitle)}</div>

</div>

<div style="background:#f8fafc;padding:12px 14px;color:#0f172a">${rowsHtml}</div>

</div>`;

}



function btnHtml(label, href, color) {

  return `<p style="text-align:center;margin:20px 0"><a href="${href}" class="btn" style="background:${color}">${escapeHtml(label)}</a></p>`;

}



/** E-mail HTML premium — audiência. */

function buildEmailAudiencia({ userName, d, date, timeStr, leadMin, appDomain }) {

  const greet = greetUser(userName);

  const ctx = reminderContext(d, date, leadMin);

  const lead = leadTitlePrefix(leadMin);

  const startHm = formatTimeHm(timeStr);

  const day = eventDayContext(date, new Date());

  const mod = ctx.modality || resolveAudienciaModality(d);

  const theme = channelTheme("audiencia");

  const rows = [

    emailRowLine("⚖️ <strong>Audiência</strong>"),

    emailRowLine(`📅 Data: <strong>${formatDateBr(date)}</strong>`),

    emailRowLine(`🕒 Horário: <strong>${escapeHtml(startHm)}</strong>`),

    ctx.processo ? emailRowLine(`📂 Nº SEI: <strong>${escapeHtml(ctx.processo)}</strong>`) : "",

    ctx.numeroOcorrencia

      ? emailRowLine(`🏷️ Nº Ocorrência: <strong>${escapeHtml(ctx.numeroOcorrencia)}</strong>`)

      : "",

    emailRowLine(

      `📍 <strong>${mod.isOnline ? "ON LINE" : "PRESENCIAL"}</strong>`,

    ),

    mod.isOnline && mod.link

      ? emailRowLine(

          `🔗 Link da sala: <a href="${escapeHtml(mod.link)}" style="color:${theme.accent};font-weight:700;word-break:break-all">${escapeHtml(mod.link)}</a>`,

        )

      : "",

    !mod.isOnline && mod.address

      ? emailRowLine(`📍 Endereço: <strong>${escapeHtml(mod.address)}</strong>`)

      : "",

  ].filter(Boolean);

  const card = premiumEmailHeroCard(theme, leadTitlePrefix(leadMin) + " — Audiência", rows.join(""));

  const preview = buildAudienciaBody(ctx, new Date()).split("\n")[0];

  const ctaHref = mod.isOnline && mod.link ? mod.link : `${appDomain}/`;

  const ctaLabel = mod.isOnline && mod.link ? "ACESSAR SALA (ON LINE)" : "ABRIR AUDIÊNCIA";

  const body = `<p>${greet} 👋</p>

<p>${escapeHtml(preview)}</p>

<p style="color:#64748b;font-size:13px"><strong>${escapeHtml(lead)}</strong></p>

${card}

${btnHtml(ctaLabel, ctaHref, "#5B21B6")}

<p style="margin-top:28px;color:#64748b;font-size:13px">Equipe ${BRAND_APP}</p>`;

  return {

    htmlTitle: `${lead} — Audiência · ${BRAND_APP}`,

    subject: `${lead} — Audiência · ${BRAND_APP}`,

    bodyHtml: body,

    accent: "#5B21B6",

  };

}



function buildEmailCompromisso({ userName, d, date, timeStr, leadMin, appDomain }) {

  const greet = greetUser(userName);

  const ctx = reminderContext(d, date, leadMin);

  const titulo = ctx.eventTitle;

  const lead = leadTitlePrefix(leadMin);

  const startHm = formatTimeHm(timeStr);

  const theme = channelTheme("compromisso");

  const rows = [

    emailRowLine(`📝 <strong>${escapeHtml(titulo)}</strong>`),

    emailRowLine(`📅 Data: <strong>${formatDateBr(date)}</strong> · 🕒 <strong>${escapeHtml(startHm)}</strong>`),

    ctx.cliente ? emailRowLine(`👤 Cliente: <strong>${escapeHtml(ctx.cliente)}</strong>`) : "",

    ctx.local ? emailRowLine(`📍 <strong>${escapeHtml(ctx.local)}</strong>`) : "",

  ].filter(Boolean);

  const card = premiumEmailHeroCard(theme, `${lead} — Compromisso`, rows.join(""));

  const preview = buildCompromissoBody(ctx, new Date()).split("\n")[0];

  const body = `<p>${greet} 👋</p>

<p>${escapeHtml(preview)}</p>

${card}

${btnHtml("ABRIR AGENDA", `${appDomain}/`, "#2563EB")}

<p style="margin-top:28px;color:#64748b;font-size:13px">Equipe ${BRAND_APP}</p>`;

  return {

    htmlTitle: `${lead} — Compromisso · ${BRAND_APP}`,

    subject: `${lead} — ${escapeHtml(titulo)} · ${BRAND_APP}`,

    bodyHtml: body,

    accent: "#2563EB",

  };

}



function buildEmailEscala({ userName, scaleData, date, startStr, leadMin, appDomain }) {

  const greet = greetUser(userName);

  const endStr = (scaleData.end || "18:00").toString();

  const ctx = {

    eventTitle: (scaleData.label || scaleData.scaleLocationName || "Plantão").toString().trim(),

    local: (scaleData.abbreviation || scaleData.label || "Plantão").toString().trim(),

    timeStr: startStr,

    endStr,

    eventAt: date,

    leadMin: normalizeLeadMinutes(leadMin),

  };

  const lead = leadTitlePrefix(leadMin);

  const startHm = formatTimeHm(startStr);

  const endHm = formatTimeHm(endStr);

  const theme = channelTheme("escala");

  const rows = [

    emailRowLine(`📍 <strong>${escapeHtml(ctx.local || "Plantão")}</strong>`),

    emailRowLine(`📅 Data: <strong>${formatDateBr(date)}</strong>`),

    emailRowLine(

      `🕒 Horário: <strong>${escapeHtml(startHm)}</strong> – <strong>${escapeHtml(endHm)}</strong>`,

    ),

  ].join("");

  const card = premiumEmailHeroCard(theme, `${lead} — Escala`, rows);

  const preview = buildEscalaBody(ctx, new Date()).split("\n")[0];

  const body = `<p>${greet} 👋</p>

<p>${escapeHtml(preview)}</p>

${card}

${btnHtml("ABRIR ESCALA", `${appDomain}/`, "#EA580C")}

<p style="margin-top:28px;color:#64748b;font-size:13px">Equipe ${BRAND_APP}</p>`;

  return {

    htmlTitle: `${lead} — Escala · ${BRAND_APP}`,

    subject: `${lead} — Escala · ${BRAND_APP}`,

    bodyHtml: body,

    accent: "#EA580C",

  };

}



function buildEmailFinanceiro({ userName, d, date, leadMin, appDomain }) {
  const greet = greetUser(userName);
  const ctx = transactionContext(d, date, leadMin);
  const lead = leadTitlePrefix(leadMin);
  const theme = channelTheme("financeiro");
  const day = eventDayContext(date, new Date());
  const dateStr = day.dateStr || formatDateBr(date);
  const rows = [
    emailRowLine(`${ctx.isIncome ? "💵" : "💳"} <strong>${escapeHtml(ctx.eventTitle)}</strong>`),
    emailRowLine(`📝 ${escapeHtml(ctx.desc)}`),
    emailRowLine(`💰 Valor: <strong>${escapeHtml(formatBrlAmount(ctx.amount))}</strong>`),
    emailRowLine(`📅 Vencimento: <strong>${escapeHtml(dateStr)}</strong>`),
  ].join("");
  const card = premiumEmailHeroCard(theme, `${lead} — ${ctx.eventTitle}`, rows);
  const preview = buildFinanceiroBody(ctx, new Date()).split("\n")[0];
  const body = `<p>${greet} 👋</p>
<p>${escapeHtml(preview)}</p>
${card}
${btnHtml("ABRIR FINANCEIRO", `${appDomain}/`, theme.accent)}
<p style="margin-top:28px;color:#64748b;font-size:13px">Equipe ${BRAND_APP}</p>`;
  return {
    htmlTitle: `${lead} — ${ctx.eventTitle} · ${BRAND_APP}`,
    subject: `${lead} — ${ctx.eventTitle} · ${BRAND_APP}`,
    bodyHtml: body,
    accent: theme.accent,
  };
}

function buildEmailForDispatch(msg, userName, appDomain) {

  if (msg.transactionData) {

    return buildEmailFinanceiro({

      userName,

      d: msg.transactionData,

      date: msg.date,

      leadMin: msg.leadMin,

      appDomain,

    });

  }

  if (msg.reminderData) {

    const isAud = (msg.reminderData.type || "").toString().toLowerCase() === "audiencia";

    if (isAud) {

      return buildEmailAudiencia({

        userName,

        d: msg.reminderData,

        date: msg.date,

        timeStr: msg.timeStr,

        leadMin: msg.leadMin,

        appDomain,

      });

    }

    return buildEmailCompromisso({

      userName,

      d: msg.reminderData,

      date: msg.date,

      timeStr: msg.timeStr,

      leadMin: msg.leadMin,

      appDomain,

    });

  }

  if (msg.scaleData) {

    return buildEmailEscala({

      userName,

      scaleData: msg.scaleData,

      date: msg.date,

      startStr: msg.startStr,

      leadMin: msg.leadMin,

      appDomain,

    });

  }

  return {

    htmlTitle: BRAND_APP,

    subject: `${BRAND_APP} — Lembrete`,

    bodyHtml: `<p>${greetUser(userName)} 👋</p><p>Lembrete da sua agenda.</p>`,

    accent: "#2D5BFF",

  };

}



function buildEmailBasePremium(title, bodyHtml, accent, templates) {

  const tpl = templates || {};

  const ac = accent || "#2D5BFF";

  const brand = (tpl.brandName || BRAND_APP).toString();

  const footer = (tpl.emailFooter || `© ${BRAND_APP} — Gestão financeira, escalas e metas.`).toString();

  const intro = (tpl.emailIntro || "").toString().trim();

  const introBlock = intro ? `<p style="color:#475569;font-size:14px">${escapeHtml(intro)}</p>` : "";

  return `<!DOCTYPE html>

<html>

<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1.0">

<style>body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;background:linear-gradient(180deg,#f0f4ff 0%,#f4f7fa 100%);margin:0;padding:0;color:#1e293b;line-height:1.65}

.container{max-width:560px;margin:0 auto;padding:24px;background:#fff;border-radius:20px;box-shadow:0 8px 32px rgba(45,91,255,.12)}

.header{text-align:center;padding:20px 0;border-bottom:none;background:linear-gradient(135deg,${ac},${ac}cc);margin:-24px -24px 20px -24px;border-radius:20px 20px 0 0}

.logo{font-size:20px;font-weight:800;color:#fff;letter-spacing:.5px}

.footer{text-align:center;padding-top:24px;font-size:12px;color:#64748b}

.btn{display:inline-block;padding:14px 28px;background:${ac};color:#fff!important;text-decoration:none;border-radius:12px;font-weight:800;font-size:14px;letter-spacing:.3px}

.row-item{padding:14px;background:#f8fafc;border-radius:12px;margin:10px 0;border-left:4px solid ${ac}}

</style></head>

<body><div class="container">

<div class="header"><span class="logo">${escapeHtml(brand)}</span></div>

<h2 style="margin:8px 0 16px;color:#0f172a;font-size:20px">${title}</h2>

${introBlock}

${bodyHtml}

<div class="footer">${escapeHtml(footer)}</div>

</div></body></html>`;

}



module.exports = {

  escapeHtml,

  greetUser,

  emailRowLine,

  premiumEmailHeroCard,

  buildPushFromReminder,

  buildPushFromScale,

  buildAlertSlotForReminder,

  buildAlertSlotForScale,

  buildPushFromTransaction,

  buildAlertSlotForTransaction,

  enrichDispatchMessage,

  buildEmailForDispatch,

  buildEmailBasePremium,

  channelTheme,

  pushSubtitle,

  leadLabelLong,

  leadTitlePrefix,

  normalizeLeadMinutes,

};
