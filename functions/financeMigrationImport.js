/**
 * Importação financeira em massa (migração de app legado) — servidor Admin SDK.
 */
const admin = require("firebase-admin");
const {
  monthKeyBr,
  openingContribution,
  effectiveTs,
  safeAccountFieldId,
  OPENING_BUCKETS_VERSION,
} = require("./financeMonthBuckets");

const FieldValue = admin.firestore.FieldValue;
const Timestamp = admin.firestore.Timestamp;

function slugAccount(name) {
  return (
    "mig_acc_" +
    name
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "_")
      .replace(/^_|_$/g, "")
  );
}

function parseDateTimeBr(dateStr, timeStr) {
  const d = (dateStr || "").toString().trim();
  const m = d.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
  if (!m) return new Date();
  const day = Number(m[1]);
  const month = Number(m[2]);
  const year = Number(m[3]);
  let hh = 12;
  let mm = 0;
  const t = (timeStr || "").toString().trim();
  if (t) {
    const ampm = t.match(/^(\d{1,2}):(\d{2})\s*(am|pm)$/i);
    const h24 = t.match(/^(\d{1,2}):(\d{2})$/);
    if (ampm) {
      hh = Number(ampm[1]) % 12;
      mm = Number(ampm[2]);
      if (ampm[3].toLowerCase() === "pm") hh += 12;
    } else if (h24) {
      hh = Number(h24[1]);
      mm = Number(h24[2]);
    }
  }
  return new Date(year, month - 1, day, hh, mm, 0);
}

async function rebuildOpeningBuckets(userId) {
  const db = admin.firestore();
  const monthSums = new Map();
  const accountMonthSums = new Map();
  const txCol = db.collection(`users/${userId}/transactions`);
  let last = null;
  for (;;) {
    let q = txCol.orderBy("date", "asc").limit(400);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;
    for (const doc of snap.docs) {
      const d = doc.data();
      const eff = effectiveTs(d);
      if (!eff) continue;
      const k = monthKeyBr(eff);
      const c = openingContribution(d);
      monthSums.set(k, (monthSums.get(k) || 0) + c);
      const acc = ((d.financeAccountId || "") + "").trim();
      if (acc && c !== 0) {
        if (!accountMonthSums.has(k)) accountMonthSums.set(k, new Map());
        const m = accountMonthSums.get(k);
        m.set(acc, (m.get(acc) || 0) + c);
      }
    }
    last = snap.docs[snap.docs.length - 1];
    if (snap.size < 400) break;
  }

  const monthEntries = [...monthSums.entries()];
  for (let i = 0; i < monthEntries.length; i += 400) {
    const batch = db.batch();
    for (const [k, v] of monthEntries.slice(i, i + 400)) {
      batch.set(
        db.doc(`users/${userId}/finance_month_buckets/${k}`),
        { netPaid: v, updatedAt: FieldValue.serverTimestamp() },
        { merge: true },
      );
    }
    await batch.commit();
  }

  const accountMonthEntries = [...accountMonthSums.entries()];
  for (let i = 0; i < accountMonthEntries.length; i += 200) {
    const batch = db.batch();
    for (const [monthKey, accMap] of accountMonthEntries.slice(i, i + 200)) {
      const netByAccount = {};
      for (const [acc, val] of accMap.entries()) {
        netByAccount[safeAccountFieldId(acc)] = val;
      }
      batch.set(
        db.doc(`users/${userId}/finance_account_month_buckets/${monthKey}`),
        { netByAccount, updatedAt: FieldValue.serverTimestamp() },
        { merge: true },
      );
    }
    await batch.commit();
  }

  await db.doc(`users/${userId}/finance_stats/meta`).set(
    {
      openingBucketsVersion: OPENING_BUCKETS_VERSION,
      rebuiltAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  return { months: monthEntries.length, accountMonths: accountMonthEntries.length };
}

async function mergeCategories(userId, transactions) {
  const income = new Set();
  const expense = new Set();
  for (const r of transactions) {
    const cat = (r.cat || r.category || "").toString().trim();
    if (!cat) continue;
    const tipo = (r.tipo || r.type || "").toString().toLowerCase();
    if (tipo.startsWith("rec") || tipo === "income") income.add(cat);
    else expense.add(cat);
  }
  const ref = admin.firestore().doc(`users/${userId}/settings/custom_categories`);
  const snap = await ref.get();
  const data = snap.exists ? snap.data() || {} : {};
  const merge = (base, add) => {
    const map = new Map();
    for (const x of base) {
      const t = (x || "").toString().trim();
      if (t) map.set(t.toLowerCase(), t);
    }
    for (const x of add) {
      const t = (x || "").toString().trim();
      if (t) map.set(t.toLowerCase(), t);
    }
    return [...map.values()].sort((a, b) => a.localeCompare(b, "pt-BR"));
  };
  await ref.set(
    {
      income: merge(Array.isArray(data.income) ? data.income : [], income),
      expense: merge(Array.isArray(data.expense) ? data.expense : [], expense),
      updatedAt: FieldValue.serverTimestamp(),
      migrationMergedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

/**
 * @param {string} uid
 * @param {{ accounts: object[], transactions: object[], email?: string, label?: string }} payload
 */
async function importFinanceMigration(uid, payload) {
  const db = admin.firestore();
  const userRef = db.collection("users").doc(uid);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    throw new Error("Usuario nao encontrado: " + uid);
  }

  const metaRef = userRef.collection("migration_meta").doc("finance_elismar");
  const metaSnap = await metaRef.get();
  if (metaSnap.exists && !payload.force) {
    const m = metaSnap.data() || {};
    return {
      ok: true,
      skipped: true,
      uid,
      accountsWritten: m.accounts || 0,
      txWritten: m.transactionsImported || 0,
      txSkipped: m.transactionsSkipped || 0,
      buckets: m.buckets || null,
    };
  }

  const accounts = Array.isArray(payload.accounts) ? payload.accounts : [];
  const transactions = Array.isArray(payload.transactions) ? payload.transactions : [];
  const accountMap = {};

  let accountsWritten = 0;
  for (const c of accounts) {
    const legado = (c.legado || c.ContaLegado || c.nome || "").toString().trim();
    if (!legado) continue;
    const docId = slugAccount(legado);
    accountMap[legado] = docId;
    const ref = userRef.collection("finance_accounts").doc(docId);
    const snap = await ref.get();
    const pt = (c.productType || c.TipoProduto || "checking").toString().trim();
    await ref.set(
      {
        presetId: (c.presetId || c.PresetId || "outro_banco").toString().trim(),
        productType: pt,
        kind: pt === "card" ? "card" : "bank",
        nickname: (c.nickname || c.NomeExibicao || legado).toString().trim(),
        sortOrder: Number(c.ordem || c.Ordem) || accountsWritten,
        migrationLegacyAccount: legado,
        migrationSource: "sqlite_legacy",
        createdAt: snap.exists ? snap.data()?.createdAt || FieldValue.serverTimestamp() : FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    accountsWritten++;
  }

  let txWritten = 0;
  let txSkipped = 0;
  const batchSize = 400;
  for (let i = 0; i < transactions.length; i += batchSize) {
    const slice = transactions.slice(i, i + batchSize);
    const batch = db.batch();
    let ops = 0;
    for (const r of slice) {
      const legacyId = (r.id || r.IDLegado || "").toString().trim();
      if (!legacyId) continue;
      const docId = `mig_tx_${legacyId}`;
      const ref = userRef.collection("transactions").doc(docId);
      const contaLegado = (r.conta || r.Conta || "").toString().trim();
      const financeAccountId = accountMap[contaLegado] || "";
      const tipoRaw = (r.tipo || r.Tipo || r.type || "").toString().toLowerCase();
      const type = tipoRaw.startsWith("rec") || tipoRaw === "income" ? "income" : "expense";
      const amount = Number(r.valor ?? r.amount ?? r.Valor);
      if (!Number.isFinite(amount) || amount <= 0) continue;

      const category = (r.cat || r.category || r.Categoria || "Outros").toString().trim() || "Outros";
      const description = (r.desc || r.description || r.Descrição || category).toString().trim();
      const dt = parseDateTimeBr(r.date || r.Data, r.hora || r.Hora);
      const ts = Timestamp.fromDate(dt);
      const statusRaw = (r.status || r.Situação || r.Situacao || "paid").toString().toLowerCase();
      const status = statusRaw.startsWith("pag") || statusRaw === "paid" ? "paid" : "pending";

      const doc = {
        type,
        amount,
        category,
        description,
        status,
        date: ts,
        effectiveDate: ts,
        recurrence: "none",
        installmentCount: 1,
        installmentIndex: 1,
        source: "migration_legacy",
        migrationLegacyId: legacyId,
        migrationLegacyAccount: contaLegado,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      };
      if (status === "paid") doc.paidAt = ts;
      if (financeAccountId) doc.financeAccountId = financeAccountId;

      batch.set(ref, doc, { merge: false });
      ops++;
      txWritten++;
    }
    if (ops > 0) await batch.commit();
  }

  await mergeCategories(uid, transactions);
  const buckets = await rebuildOpeningBuckets(uid);

  await userRef.collection("migration_meta").doc("finance_elismar").set(
    {
      completedAt: FieldValue.serverTimestamp(),
      accounts: accountsWritten,
      transactionsImported: txWritten,
      transactionsSkipped: txSkipped,
      email: (payload.email || "").toString(),
      label: (payload.label || "sqlite_legacy").toString(),
      buckets,
    },
    { merge: true },
  );

  return {
    ok: true,
    uid,
    accountsWritten,
    txWritten,
    txSkipped,
    buckets,
  };
}

module.exports = {
  importFinanceMigration,
  consolidateToSantanderAccount,
  slugAccount,
  rebuildOpeningBuckets,
};

/**
 * Uma conta Santander + saldo de jun/2026 alinhado ao app legado.
 */
/** Alinha date, paidAt e effectiveDate — data efetiva é a referência (igual buckets e painel). */
async function normalizePaidTransactionDates(uid) {
  const db = admin.firestore();
  const txCol = db.collection(`users/${uid}/transactions`);
  let last = null;
  let normalized = 0;
  for (;;) {
    let q = txCol.orderBy("date", "asc").limit(400);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;
    const batch = db.batch();
    let ops = 0;
    for (const doc of snap.docs) {
      const d = doc.data() || {};
      if ((d.status || "paid").toString() !== "paid") continue;
      const dateTs = d.date;
      const eff = effectiveTs(d);
      const canonical = eff || dateTs;
      if (!canonical || typeof canonical.toMillis !== "function") continue;
      const patch = {};
      if (!dateTs || dateTs.toMillis() !== canonical.toMillis()) patch.date = canonical;
      if (!d.effectiveDate || d.effectiveDate.toMillis() !== canonical.toMillis()) {
        patch.effectiveDate = canonical;
      }
      if (!d.paidAt || d.paidAt.toMillis() !== canonical.toMillis()) patch.paidAt = canonical;
      if (Object.keys(patch).length === 0) continue;
      patch.updatedAt = FieldValue.serverTimestamp();
      batch.update(doc.ref, patch);
      ops++;
      normalized++;
    }
    if (ops > 0) await batch.commit();
    last = snap.docs[snap.docs.length - 1];
    if (snap.size < 400) break;
  }
  return normalized;
}

async function consolidateToSantanderAccount(uid, opts = {}) {
  const targetOpeningJune2026 = Number(opts.targetOpeningJune2026 ?? 10753.14);
  const targetCurrentJune2026 = Number(opts.targetCurrentJune2026 ?? -5213.26);
  const santanderDocId = (opts.santanderDocId || "mig_acc_santander").toString().trim();
  const force = opts.force === true;

  const db = admin.firestore();
  const userRef = db.collection("users").doc(uid);
  const userSnap = await userRef.get();
  if (!userSnap.exists) throw new Error("Usuario nao encontrado: " + uid);

  const accCol = userRef.collection("finance_accounts");
  const accSnap = await accCol.get();
  const santanderRef = accCol.doc(santanderDocId);
  const santanderId = santanderDocId;

  await santanderRef.set(
    {
      presetId: "santander",
      productType: "checking",
      kind: "bank",
      nickname: "Santander",
      sortOrder: 0,
      migrationSource: "consolidate_santander",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  const txCol = userRef.collection("transactions");
  let last = null;
  let reassigned = 0;
  for (;;) {
    let q = txCol.orderBy("date", "asc").limit(400);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;
    const batch = db.batch();
    let ops = 0;
    for (const doc of snap.docs) {
      const d = doc.data() || {};
      if (!force && (d.financeAccountId || "") === santanderId) continue;
      batch.update(doc.ref, {
        financeAccountId: santanderId,
        updatedAt: FieldValue.serverTimestamp(),
      });
      ops++;
      reassigned++;
    }
    if (ops > 0) await batch.commit();
    last = snap.docs[snap.docs.length - 1];
    if (snap.size < 400) break;
  }

  const toDelete = accSnap.docs.filter((d) => d.id !== santanderId);
  for (const d of toDelete) {
    await d.ref.delete();
  }

  const categoriesSynced = await syncCategoriesFromAllTransactions(uid);
  const datesNormalized = await normalizePaidTransactionDates(uid);

  const adjRef = txCol.doc("mig_tx_opening_align_202606");
  const currentAdjRef = txCol.doc("mig_tx_current_align_202606");
  if (force) {
    await adjRef.delete().catch(() => {});
    await currentAdjRef.delete().catch(() => {});
  }

  await rebuildOpeningBuckets(uid);

  let openingBeforeJune = await computeOpeningBeforeMonth(uid, 2026, 6);
  let adj = Math.round((targetOpeningJune2026 - openingBeforeJune) * 100) / 100;
  let adjustment = null;
  if (Math.abs(adj) >= 0.01) {
    const adjDate = new Date(2026, 4, 31, 23, 59, 0);
    const ts = Timestamp.fromDate(adjDate);
    const isIncome = adj > 0;
    await adjRef.set(
      {
        type: isIncome ? "income" : "expense",
        amount: Math.abs(adj),
        category: "Ajuste migração",
        description: "Ajuste saldo abertura (alinhamento app anterior)",
        status: "paid",
        date: ts,
        paidAt: ts,
        effectiveDate: ts,
        recurrence: "none",
        installmentCount: 1,
        installmentIndex: 1,
        source: "migration_legacy",
        financeAccountId: santanderId,
        migrationLegacyId: "opening_align_202606",
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    adjustment = { amount: adj, type: isIncome ? "income" : "expense" };
    await rebuildOpeningBuckets(uid);
    openingBeforeJune = await computeOpeningBeforeMonth(uid, 2026, 6);
  }

  let verify = await verifyJune2026Balance(uid, santanderId, 2026, 6);
  let currentAdjustment = null;
  const currentGap = Math.round((targetCurrentJune2026 - verify.current) * 100) / 100;
  if (Math.abs(currentGap) >= 0.01) {
    const adjDate = new Date(2026, 5, 30, 12, 0, 0);
    const ts = Timestamp.fromDate(adjDate);
    const isIncome = currentGap > 0;
    await currentAdjRef.set(
      {
        type: isIncome ? "income" : "expense",
        amount: Math.abs(currentGap),
        category: "Ajuste migração",
        description: "Ajuste saldo período (alinhamento app anterior)",
        status: "paid",
        date: ts,
        paidAt: ts,
        effectiveDate: ts,
        recurrence: "none",
        installmentCount: 1,
        installmentIndex: 1,
        source: "migration_legacy",
        financeAccountId: santanderId,
        migrationLegacyId: "current_align_202606",
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    currentAdjustment = { amount: currentGap, type: isIncome ? "income" : "expense" };
    await rebuildOpeningBuckets(uid);
    verify = await verifyJune2026Balance(uid, santanderId, 2026, 6);
  }

  const categoriesJune = await verifyJune2026ExpenseCategories(uid, santanderId, 2026, 6);

  await userRef.collection("settings").doc("finance_advanced").set(
    { defaultFinanceAccountId: santanderId, updatedAt: FieldValue.serverTimestamp() },
    { merge: true },
  );
  await userRef.collection("migration_meta").doc("finance_elismar").set(
    {
      santanderConsolidatedAt: FieldValue.serverTimestamp(),
      santanderAccountId: santanderId,
      accountsDeleted: toDelete.length,
      transactionsReassigned: reassigned,
      categoriesSynced,
      datesNormalized,
      targetOpeningJune2026,
      targetCurrentJune2026,
      openingBeforeJune,
      adjustment,
      currentAdjustment,
      verify,
      categoriesJune,
    },
    { merge: true },
  );

  return {
    ok: true,
    uid,
    santanderAccountId: santanderId,
    accountsDeleted: toDelete.length,
    transactionsReassigned: reassigned,
    categoriesSynced,
    datesNormalized,
    openingBeforeJune,
    adjustment,
    currentAdjustment,
    verify,
    categoriesJune,
    expectedCurrent: targetCurrentJune2026,
  };
}

/** Sincroniza listas custom_categories a partir de todos os lançamentos migrados. */
async function syncCategoriesFromAllTransactions(uid) {
  const db = admin.firestore();
  const income = new Set();
  const expense = new Set();
  let last = null;
  for (;;) {
    let q = db.collection(`users/${uid}/transactions`).orderBy("date", "asc").limit(500);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;
    for (const doc of snap.docs) {
      const d = doc.data() || {};
      const cat = (d.category || "").toString().trim();
      if (!cat || cat === "Ajuste migração") continue;
      if ((d.type || "") === "income") income.add(cat);
      else expense.add(cat);
    }
    last = snap.docs[snap.docs.length - 1];
    if (snap.size < 500) break;
  }
  const sortPt = (a, b) => a.localeCompare(b, "pt-BR");
  const incList = [...income].sort(sortPt);
  const expList = [...expense].sort(sortPt);
  await db.doc(`users/${uid}/settings/custom_categories`).set(
    {
      income: incList,
      expense: expList,
      updatedAt: FieldValue.serverTimestamp(),
      migrationCategoriesSyncedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return { income: incList.length, expense: expList.length };
}

async function verifyJune2026ExpenseCategories(uid, accountId, year, month) {
  const db = admin.firestore();
  const start = new Date(year, month - 1, 1, 0, 0, 0);
  const end = new Date(year, month, 0, 23, 59, 59);
  const startTs = Timestamp.fromDate(start);
  const endTs = Timestamp.fromDate(end);
  const snap = await db
    .collection(`users/${uid}/transactions`)
    .where("effectiveDate", ">=", startTs)
    .where("effectiveDate", "<=", endTs)
    .get();

  const byCat = new Map();
  snap.docs.forEach((d) => {
    const data = d.data() || {};
    if ((data.status || "paid") !== "paid") return;
    if ((data.financeAccountId || "") !== accountId) return;
    if ((data.type || "") === "income") return;
    const cat = (data.category || "Outros").toString().trim();
    const amt = Number(data.amount) || 0;
    const prev = byCat.get(cat) || { count: 0, total: 0 };
    prev.count += 1;
    prev.total += amt;
    byCat.set(cat, prev);
  });
  const rows = [...byCat.entries()]
    .map(([category, v]) => ({
      category,
      count: v.count,
      total: Math.round(v.total * 100) / 100,
    }))
    .sort((a, b) => b.total - a.total);
  return rows;
}

async function computeOpeningBeforeMonth(uid, year, month) {
  const db = admin.firestore();
  const partialKey = `${year}-${String(month).padStart(2, "0")}`;
  const buckets = await db
    .collection(`users/${uid}/finance_month_buckets`)
    .orderBy(admin.firestore.FieldPath.documentId())
    .where(admin.firestore.FieldPath.documentId(), "<", partialKey)
    .get();
  let sum = 0;
  buckets.docs.forEach((d) => {
    sum += Number(d.data()?.netPaid) || 0;
  });
  return Math.round(sum * 100) / 100;
}

async function verifyJune2026Balance(uid, accountId, year, month) {
  const db = admin.firestore();
  const start = new Date(year, month - 1, 1, 0, 0, 0);
  const end = new Date(year, month, 0, 23, 59, 59);
  const startTs = Timestamp.fromDate(start);
  const endTs = Timestamp.fromDate(end);

  const opening = await computeOpeningBeforeMonth(uid, year, month);
  const snap = await db
    .collection(`users/${uid}/transactions`)
    .where("effectiveDate", ">=", startTs)
    .where("effectiveDate", "<=", endTs)
    .get();

  let income = 0;
  let expense = 0;
  let txCount = 0;
  snap.docs.forEach((d) => {
    const data = d.data() || {};
    if ((data.status || "paid") !== "paid") return;
    if ((data.financeAccountId || "") !== accountId) return;
    txCount++;
    const amt = Number(data.amount) || 0;
    if ((data.type || "") === "income") income += amt;
    else expense += amt;
  });
  income = Math.round(income * 100) / 100;
  expense = Math.round(expense * 100) / 100;
  const current = Math.round((opening + income - expense) * 100) / 100;
  return { opening, income, expense, current, txCount };
}
