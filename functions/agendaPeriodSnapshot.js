const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const MAX_REMINDERS = 2500;

function asJsDate(iso) {
  const d = new Date((iso || "").toString());
  return Number.isNaN(d.getTime()) ? null : d;
}

/** Ano/mês/dia em America/Sao_Paulo (Brasil sem horário de verão: UTC−3). */
function brDateParts(date) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Sao_Paulo",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const get = (k) => parseInt(parts.find((x) => x.type === k)?.value || "0", 10);
  return { y: get("year"), m: get("month"), d: get("day") };
}

function serializeTs(value) {
  if (!value || typeof value.toDate !== "function") return null;
  return value.toDate().toISOString();
}

function serializeReminder(doc) {
  const d = doc.data() || {};
  return {
    id: doc.id,
    title: (d.title || "").toString(),
    time: (d.time || "").toString(),
    type: (d.type || "").toString(),
    status: (d.status || "").toString(),
    done: d.done === true,
    color: (d.color || "").toString(),
    notes: (d.notes || "").toString(),
    source: (d.source || "").toString(),
    googleEventId: (d.googleEventId || "").toString(),
    repeatYearly: d.repeatYearly === true,
    isYearlyRepeatTemplate: d.isYearlyRepeatTemplate === true,
    yearlyRepeatTemplateId: (d.yearlyRepeatTemplateId || "").toString(),
    yearlyRepeatInstanceYear: d.yearlyRepeatInstanceYear ?? null,
    yearlyRepeatWeekdays: Array.isArray(d.yearlyRepeatWeekdays) ? d.yearlyRepeatWeekdays : [],
    dateISO: serializeTs(d.date),
  };
}

/** Lembretes/compromissos num intervalo — evita `.snapshots()` sem filtro no cliente. */
exports.ctAgendaRemindersForRange = onCall(
  { region: "us-central1", memory: "256MiB", timeoutSeconds: 60 },
  async (req) => {
    if (!req.auth) {
      throw new HttpsError("unauthenticated", "Login obrigatório.");
    }
    const uid = req.auth.uid;
    const from = asJsDate(req.data?.fromISO);
    const to = asJsDate(req.data?.toISO);
    if (!from || !to) {
      throw new HttpsError("invalid-argument", "Período inválido.");
    }
    // Dias civis em Brasília (servidor em UTC): 00:00–23:59:59 de São Paulo.
    const f = brDateParts(from);
    const t = brDateParts(to);
    const start = new Date(Date.UTC(f.y, f.m - 1, f.d, 3, 0, 0, 0));
    const end = new Date(Date.UTC(t.y, t.m - 1, t.d + 1, 2, 59, 59, 999));
    const snap = await admin
      .firestore()
      .collection("users")
      .doc(uid)
      .collection("reminders")
      .where("date", ">=", admin.firestore.Timestamp.fromDate(start))
      .where("date", "<=", admin.firestore.Timestamp.fromDate(end))
      .orderBy("date", "asc")
      .limit(MAX_REMINDERS)
      .get();
    return {
      ok: true,
      items: snap.docs.map(serializeReminder),
      truncated: snap.size >= MAX_REMINDERS,
    };
  },
);
