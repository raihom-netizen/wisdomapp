/**
 * Recálculo em massa — Banco de Horas GO (períodos em config/scale_rates.ratePeriods).
 * Atualiza plantões com data >= início do 2º período (ex.: 01/07/2026 00:00).
 */
const admin = require("firebase-admin");

const DEFAULT_DIURNO = [36.41, 26.47, 26.47, 26.47, 26.47, 36.41, 36.41];
const DEFAULT_NOTURNO = [41.38, 29.8, 29.8, 29.8, 29.8, 41.38, 41.38];

function parseRateList(v, fallback) {
  if (!Array.isArray(v)) return fallback.slice();
  return v.map((e) => (typeof e === "number" ? e : parseFloat(e) || 0));
}

function ratesFromMap(data) {
  const d = data || {};
  return {
    nightStart: (d.nightStart || "22:00").toString(),
    nightEnd: (d.nightEnd || "05:00").toString(),
    valueDiurno: parseRateList(d.valueDiurno, DEFAULT_DIURNO),
    valueNoturno: parseRateList(d.valueNoturno, DEFAULT_NOTURNO),
    ac4NightAnchorPreviousDay: d.ac4NightAnchorPreviousDay !== false,
  };
}

function parseEffectiveFrom(raw) {
  if (raw && typeof raw.toDate === "function") return raw.toDate();
  if (raw instanceof Date) return raw;
  const s = (raw || "").toString();
  const p = Date.parse(s);
  if (!Number.isNaN(p)) return new Date(p);
  return new Date(2024, 5, 1);
}

function bootstrapPeriods() {
  return [
    {
      id: "ac4_jun2024",
      label: "ANEXO I — jun/2024",
      effectiveFrom: new Date(2024, 5, 1),
      rates: ratesFromMap({}),
    },
    {
      id: "goias_ac4_july2026",
      label: "ANEXO I — jul/2026",
      effectiveFrom: new Date(2026, 6, 1),
      rates: ratesFromMap({
        valueDiurno: [40, 30, 30, 30, 30, 40, 40],
        valueNoturno: [45, 33, 33, 33, 33, 45, 45],
      }),
    },
  ];
}

function loadPeriodsFromConfig(data) {
  const raw = data && data.ratePeriods;
  if (!Array.isArray(raw) || raw.length === 0) return bootstrapPeriods();
  const out = raw.map((item) => ({
    id: (item.id || item.scheduleId || "period").toString(),
    label: (item.label || "Período AC4").toString(),
    effectiveFrom: parseEffectiveFrom(item.effectiveFrom || item.effectiveFromIso),
    rates: ratesFromMap(item.rates || {}),
  }));
  out.sort((a, b) => a.effectiveFrom - b.effectiveFrom);
  return out.length ? out : bootstrapPeriods();
}

function weekdayToIndex(dartWeekday) {
  return dartWeekday % 7;
}

function parseMinutes(hhmm) {
  const parts = (hhmm || "00:00").split(":");
  const h = parseInt(parts[0], 10) || 0;
  const m = parseInt(parts[1], 10) || 0;
  return h * 60 + m;
}

function noturnoRateIndexForMinute(cur, nightStartMin, nightEndMin) {
  const minuteOfDay = cur.getHours() * 60 + cur.getMinutes();
  if (minuteOfDay >= nightStartMin) return weekdayToIndex(cur.getDay());
  const prev = new Date(cur.getTime() - 86400000);
  return weekdayToIndex(prev.getDay());
}

function ratesForInstant(instant, periods) {
  let hit = periods[0];
  for (const p of periods) {
    if (p.effectiveFrom <= instant) hit = p;
    else break;
  }
  return hit ? hit.rates : ratesFromMap({});
}

function computeShift(start, end, periods) {
  let dayMin = 0;
  let nightMin = 0;
  let totalValue = 0;
  let cur = new Date(start.getTime());
  let endDt = end < start ? new Date(end.getTime() + 86400000) : new Date(end.getTime());

  while (cur < endDt) {
    const rates = ratesForInstant(cur, periods);
    const nightStartMin = parseMinutes(rates.nightStart);
    const nightEndMin = parseMinutes(rates.nightEnd);
    const minuteOfDay = cur.getHours() * 60 + cur.getMinutes();
    const isNight = minuteOfDay >= nightStartMin || minuteOfDay < nightEndMin;
    const wd = weekdayToIndex(cur.getDay());
    const noturnoIdx = rates.ac4NightAnchorPreviousDay
      ? noturnoRateIndexForMinute(cur, nightStartMin, nightEndMin)
      : wd;
    const rate = isNight ? rates.valueNoturno[noturnoIdx] : rates.valueDiurno[wd];
    const inc = rate / 60;
    if (isNight) nightMin += 1;
    else dayMin += 1;
    totalValue += inc;
    cur = new Date(cur.getTime() + 60000);
  }

  return {
    hoursDay: dayMin / 60,
    hoursNight: nightMin / 60,
    total: totalValue,
  };
}

function isLastDayOfMonth(d) {
  const last = new Date(d.getFullYear(), d.getMonth() + 1, 0);
  return d.getDate() === last.getDate();
}

function computeShiftMainEntryLastDayOfMonth(start, end, entryDate, periods) {
  if (!isLastDayOfMonth(entryDate)) return computeShift(start, end, periods);
  const startDay = new Date(entryDate.getFullYear(), entryDate.getMonth(), entryDate.getDate());
  const endDay = new Date(end.getFullYear(), end.getMonth(), end.getDate());
  if (startDay.getTime() === endDay.getTime()) return computeShift(start, end, periods);
  const dayEnd = new Date(
    entryDate.getFullYear(),
    entryDate.getMonth(),
    entryDate.getDate(),
    23,
    59,
    59
  );
  return computeShift(start, dayEnd, periods);
}

function shiftBounds(entry) {
  const date = entry.date.toDate ? entry.date.toDate() : new Date(entry.date);
  const sp = (entry.start || "08:00").split(":");
  const ep = (entry.end || "18:00").split(":");
  const sh = parseInt(sp[0], 10) || 8;
  const sm = parseInt(sp[1], 10) || 0;
  const eh = parseInt(ep[0], 10) || 18;
  const em = parseInt(ep[1], 10) || 0;
  let startDt = new Date(date.getFullYear(), date.getMonth(), date.getDate(), sh, sm);
  let endDt = new Date(date.getFullYear(), date.getMonth(), date.getDate(), eh, em);
  if (endDt <= startDt) endDt = new Date(endDt.getTime() + 86400000);
  return { startDt, endDt, date };
}

function recalcVersionKey(periods) {
  return periods.map((p) => `${p.id}@${p.effectiveFrom.getTime()}`).join("|");
}

function recalcFromDate(periods) {
  if (periods.length < 2) return null;
  return periods[1].effectiveFrom;
}

async function usesGlobalGoiasRates(db, uid) {
  const snap = await db.doc(`users/${uid}/settings/controle_total_config`).get();
  const src = (snap.data()?.hoursSource || "global_goias").toString();
  return src !== "personal";
}

async function recalcUserScales(db, uid, periods, fromDate, version) {
  if (!(await usesGlobalGoiasRates(db, uid))) {
    return { updated: 0, skipped: true };
  }

  const flagRef = db.doc(`users/${uid}/settings/goias_rates_recalc`);
  const flagSnap = await flagRef.get();
  if (flagSnap.exists && (flagSnap.data()?.version || "") === version) {
    return { updated: 0, skipped: true, alreadyDone: true };
  }

  const fromTs = admin.firestore.Timestamp.fromDate(fromDate);
  const scalesSnap = await db
    .collection(`users/${uid}/scales`)
    .where("date", ">=", fromTs)
    .limit(500)
    .get();

  let updated = 0;
  let batch = db.batch();
  let ops = 0;

  for (const doc of scalesSnap.docs) {
    const d = doc.data();
    if (d.isCompromisso === true) continue;
    const total = parseFloat(d.totalValue) || 0;
    if (total <= 0) continue;

    const { startDt, endDt, date } = shiftBounds(d);
    const res = computeShiftMainEntryLastDayOfMonth(startDt, endDt, date, periods);
    const ratesDay = ratesForInstant(
      new Date(date.getFullYear(), date.getMonth(), date.getDate()),
      periods
    );
    const wd = weekdayToIndex(date.getDay());
    const newDayRate = ratesDay.valueDiurno[wd];
    const newNightRate = ratesDay.valueNoturno[wd];

    const changed =
      Math.abs((res.total || 0) - total) > 0.009 ||
      Math.abs((res.hoursDay || 0) - (parseFloat(d.hoursDay) || 0)) > 0.009 ||
      Math.abs((res.hoursNight || 0) - (parseFloat(d.hoursNight) || 0)) > 0.009;

    if (!changed) continue;

    batch.update(doc.ref, {
      totalValue: res.total,
      hoursDay: res.hoursDay,
      hoursNight: res.hoursNight,
      dayRate: newDayRate,
      nightRate: newNightRate,
      goiasRatesRecalcAt: admin.firestore.FieldValue.serverTimestamp(),
      goiasRatesRecalcVersion: version,
    });
    updated++;
    ops++;
    if (ops >= 400) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  }

  if (ops > 0) await batch.commit();

  await flagRef.set({
    version,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    recalculated: updated,
    source: "cloud_function",
  });

  return { updated, skipped: false };
}

async function ensureRatePeriodsSeeded(db) {
  const ref = db.doc("config/scale_rates");
  const snap = await ref.get();
  const data = snap.data() || {};
  if (Array.isArray(data.ratePeriods) && data.ratePeriods.length > 0) {
    return loadPeriodsFromConfig(data);
  }
  const periods = bootstrapPeriods();
  const active = periods[periods.length - 1].rates;
  await ref.set(
    {
      ...active,
      nightStart: active.nightStart,
      nightEnd: active.nightEnd,
      valueDiurno: active.valueDiurno,
      valueNoturno: active.valueNoturno,
      ratePeriods: periods.map((p) => ({
        id: p.id,
        label: p.label,
        effectiveFrom: admin.firestore.Timestamp.fromDate(p.effectiveFrom),
        effectiveFromIso: p.effectiveFrom.toISOString(),
        rates: {
          nightStart: p.rates.nightStart,
          nightEnd: p.rates.nightEnd,
          valueDiurno: p.rates.valueDiurno,
          valueNoturno: p.rates.valueNoturno,
          ac4NightAnchorPreviousDay: p.rates.ac4NightAnchorPreviousDay,
        },
      })),
      ratePeriodsSyncedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  return periods;
}

/**
 * Recalcula plantões GO para todos os usuários (admin).
 */
async function runGoiasScaleRatesRecalcAllUsers(db, { force = false } = {}) {
  const periods = await ensureRatePeriodsSeeded(db);
  const fromDate = recalcFromDate(periods);
  if (!fromDate) {
    return { ok: true, users: 0, updatedScales: 0, message: "Sem período de reajuste." };
  }
  const version = recalcVersionKey(periods);

  const usersSnap = await db.collection("users").select().get();
  let usersProcessed = 0;
  let updatedScales = 0;
  let skipped = 0;

  for (const userDoc of usersSnap.docs) {
    const uid = userDoc.id;
    try {
      if (force) {
        await db.doc(`users/${uid}/settings/goias_rates_recalc`).delete();
      }
      const r = await recalcUserScales(db, uid, periods, fromDate, version);
      usersProcessed++;
      updatedScales += r.updated || 0;
      if (r.skipped) skipped++;
    } catch (e) {
      console.warn(`goias recalc uid=${uid}`, e.message);
    }
  }

  return {
    ok: true,
    users: usersProcessed,
    updatedScales,
    skippedUsers: skipped,
    recalcFrom: fromDate.toISOString(),
    version,
  };
}

module.exports = {
  runGoiasScaleRatesRecalcAllUsers,
  ensureRatePeriodsSeeded,
  loadPeriodsFromConfig,
  bootstrapPeriods,
};
