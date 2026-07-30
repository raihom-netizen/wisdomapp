const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

const TZ_BRASILIA = "America/Sao_Paulo";

function getDatePartsBrasilia(d) {
  const fmt = new Intl.DateTimeFormat("en-CA", {
    timeZone: TZ_BRASILIA,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  });
  const parts = fmt.formatToParts(d || new Date());
  const get = (type) => parts.find((p) => p.type === type)?.value || "0";
  return {
    year: Number.parseInt(get("year"), 10),
    month: Number.parseInt(get("month"), 10),
    day: Number.parseInt(get("day"), 10),
    hour: Number.parseInt(get("hour"), 10),
    minute: Number.parseInt(get("minute"), 10),
    second: Number.parseInt(get("second"), 10),
  };
}

function parseHourMinute(raw, fallbackHour, fallbackMinute) {
  const txt = (raw || "").toString().trim();
  const m = /^(\d{1,2}):(\d{2})$/.exec(txt);
  if (!m) return { hour: fallbackHour, minute: fallbackMinute };
  const hour = Number.parseInt(m[1], 10);
  const minute = Number.parseInt(m[2], 10);
  if (Number.isNaN(hour) || Number.isNaN(minute)) {
    return { hour: fallbackHour, minute: fallbackMinute };
  }
  return { hour, minute };
}

function parseScaleDateAsBrasiliaParts(data) {
  const ts = data?.date;
  if (!ts || typeof ts.toDate !== "function") return null;
  const dt = ts.toDate();
  // O app salva a data como meio-dia UTC para evitar off-by-one.
  // Aqui usamos os componentes UTC para manter o mesmo dia civil salvo.
  return {
    year: dt.getUTCFullYear(),
    month: dt.getUTCMonth() + 1,
    day: dt.getUTCDate(),
  };
}

function buildDateUtcFromBrasiliaParts(year, month, day, hour, minute) {
  // Brasília UTC-3; representamos o horário local como UTC+3.
  return new Date(Date.UTC(year, month - 1, day, hour + 3, minute, 0, 0));
}

function computeCutoffDate(data) {
  const dateParts = parseScaleDateAsBrasiliaParts(data);
  if (!dateParts) return null;

  const startHm = parseHourMinute(data?.start, 8, 0);
  const endHm = parseHourMinute(data?.end, 18, 0);

  const start = buildDateUtcFromBrasiliaParts(
    dateParts.year,
    dateParts.month,
    dateParts.day,
    startHm.hour,
    startHm.minute
  );
  let end = buildDateUtcFromBrasiliaParts(
    dateParts.year,
    dateParts.month,
    dateParts.day,
    endHm.hour,
    endHm.minute
  );
  // Turno cruzando meia-noite.
  if (end <= start) end = new Date(end.getTime() + 24 * 60 * 60 * 1000);
  return new Date(end.getTime() + 10 * 60 * 1000);
}

async function runAutoConfirmScalesByEndTime() {
  const db = admin.firestore();
  const now = new Date();
  const p = getDatePartsBrasilia(now);
  const tomorrowAtEnd = buildDateUtcFromBrasiliaParts(
    p.year,
    p.month,
    p.day + 1,
    23,
    59
  );
  const limitDate = admin.firestore.Timestamp.fromDate(tomorrowAtEnd);

  // Índice collectionGroup: scales (paid + date) — evita N×get em todos os users.
  let updated = 0;
  let scanned = 0;
  let batch = db.batch();
  let ops = 0;
  let lastDoc = null;
  const pageSize = 400;

  for (;;) {
    let q = db
      .collectionGroup("scales")
      .where("paid", "==", false)
      .where("date", "<=", limitDate)
      .orderBy("date")
      .limit(pageSize);
    if (lastDoc) q = q.startAfter(lastDoc);

    const scalesSnap = await q.get();
    if (scalesSnap.empty) break;

    for (const scaleDoc of scalesSnap.docs) {
      scanned++;
      const data = scaleDoc.data() || {};
      if (data.isAgendaMirror === true) continue;
      if (data.isProdutividadeFolgaMirror === true) continue;
      const cutoff = computeCutoffDate(data);
      if (!cutoff) continue;
      if (now >= cutoff) {
        batch.update(scaleDoc.ref, { paid: true });
        updated++;
        ops++;
      }
      if (ops >= 400) {
        await batch.commit();
        batch = db.batch();
        ops = 0;
      }
    }
    lastDoc = scalesSnap.docs[scalesSnap.docs.length - 1];
    if (scalesSnap.size < pageSize) break;
  }

  if (ops > 0) await batch.commit();

  if (updated > 0) {
    console.log(
      `[ctAutoConfirmScalesByEndTimeScheduled] confirmados=${updated} analisados=${scanned}`
    );
  }
  return { ok: true, updated, scanned };
}

const ctAutoConfirmScalesByEndTimeScheduled = onSchedule(
  { schedule: "every 5 minutes", timeZone: TZ_BRASILIA, region: "us-central1" },
  async () => {
    try {
      await runAutoConfirmScalesByEndTime();
    } catch (e) {
      console.error("ctAutoConfirmScalesByEndTimeScheduled:", e?.message || e);
    }
  }
);

module.exports = {
  ctAutoConfirmScalesByEndTimeScheduled,
  runAutoConfirmScalesByEndTime,
};
