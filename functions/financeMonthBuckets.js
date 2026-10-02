/**
 * Agregados mensais para saldo de abertura (painel + Financeiro).
 * users/{uid}/finance_month_buckets/{yyyy-MM} → { netPaid, updatedAt }
 * users/{uid}/finance_account_month_buckets/{yyyy-MM} → { netByAccount: { [accountId]: net }, updatedAt }
 * Alinhado a America/Sao_Paulo (igual utilitário Flutter FinanceLineOpening).
 */
const admin = require("firebase-admin");
const functions = require("firebase-functions");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onCall } = require("firebase-functions/v2/https");

// 3 (02/10/2026): bumpAccountMonthNet gravava `netByAccount.<id>` com set() —
// virava um campo literal com ponto e o mapa netByAccount ficava vazio. A versão
// nova força um rebuild por usuário (o app chama ctFinanceRebuildOpeningBuckets).
// 4 (02/10/2026, regra do Controle Total — `accountBucketDelta`): compra paga
// pela fatura (`paidFromFinanceAccountId`) entra na conta que PAGOU, não no
// cartão. Ex.: compra de 300 no cartão Nubank paga pela conta Itaú → antes
// netByAccount { nubank: −300 } (Itaú sem o débito); agora { itau: −300 }.
// O total (netPaid) não muda. O rebuild deixou de usar merge (chave velha de
// cartão ficava presa no mapa).
const OPENING_BUCKETS_VERSION = 4;

function monthKeyBr(ts) {
  if (!ts || typeof ts.toDate !== "function") return "1970-01";
  const d = ts.toDate();
  const fmt = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Sao_Paulo",
    year: "numeric",
    month: "2-digit",
  });
  const parts = fmt.formatToParts(d);
  const y = parts.find((p) => p.type === "year")?.value || "1970";
  const m = parts.find((p) => p.type === "month")?.value || "01";
  return `${y}-${m}`;
}

function openingContribution(data) {
  if (!data) return 0;
  const isPaid = (data.status || "paid").toString() === "paid";
  if (!isPaid) return 0;
  const type = (data.type || "expense").toString();
  const amount = Number(data.amount) || 0;
  if (type === "income") return amount;
  return -Math.abs(amount);
}

function effectiveTs(data) {
  if (!data) return null;
  if (data.effectiveDate && typeof data.effectiveDate.toDate === "function") return data.effectiveDate;
  if (data.paidAt && typeof data.paidAt.toDate === "function") return data.paidAt;
  if (data.date && typeof data.date.toDate === "function") return data.date;
  return null;
}

function accountIdFrom(data) {
  if (!data) return null;
  const id = ((data.financeAccountId || "") + "").trim();
  return id || null;
}

/** Chave segura em netByAccount (Firestore não aceita '.' no nome do campo). */
function safeAccountFieldId(accountId) {
  return accountId.replace(/\./g, "\uFF0E");
}

function restoreAccountFieldId(fieldKey) {
  return fieldKey.replace(/\uFF0E/g, ".");
}

async function applyMonthBucketDelta(userId, before, after) {
  const bEff = before ? effectiveTs(before) : null;
  const aEff = after ? effectiveTs(after) : null;
  const bC = before ? openingContribution(before) : 0;
  const aC = after ? openingContribution(after) : 0;
  const bKey = bEff ? monthKeyBr(bEff) : null;
  const aKey = aEff ? monthKeyBr(aEff) : null;

  const db = admin.firestore();
  const inc = admin.firestore.FieldValue.increment;
  const ts = admin.firestore.FieldValue.serverTimestamp();

  if (bKey && aKey && bKey === aKey) {
    const net = aC - bC;
    if (net !== 0) {
      await db.doc(`users/${userId}/finance_month_buckets/${bKey}`).set(
        { netPaid: inc(net), updatedAt: ts },
        { merge: true },
      );
    }
    return;
  }
  if (bKey && bC !== 0) {
    await db.doc(`users/${userId}/finance_month_buckets/${bKey}`).set(
      { netPaid: inc(-bC), updatedAt: ts },
      { merge: true },
    );
  }
  if (aKey && aC !== 0) {
    await db.doc(`users/${userId}/finance_month_buckets/${aKey}`).set(
      { netPaid: inc(aC), updatedAt: ts },
      { merge: true },
    );
  }
}

async function bumpAccountMonthNet(userId, monthKey, accountId, delta) {
  if (!monthKey || !accountId || delta === 0) return;
  const db = admin.firestore();
  const inc = admin.firestore.FieldValue.increment;
  const ts = admin.firestore.FieldValue.serverTimestamp();
  const field = safeAccountFieldId(accountId);
  await db.doc(`users/${userId}/finance_account_month_buckets/${monthKey}`).set(
    {
      // Mapa aninhado: com set()+merge, a chave `netByAccount.x` NÃO é caminho —
      // criava um campo literal com ponto e o app lia o mapa vazio.
      netByAccount: { [field]: inc(delta) },
      updatedAt: ts,
    },
    { merge: true },
  );
}

/**
 * Conta que o lançamento movimenta no bucket por conta (regra do Controle
 * Total, `accountBucketDelta`, igual ao app em
 * `FinanceAccountBalanceUtils.openingPaidByAccountFromDocMaps`): despesa paga
 * com `paidFromFinanceAccountId` (compra no cartão quitada pela fatura) sai da
 * conta que PAGOU; o resto, da própria `financeAccountId`.
 */
function accountBucketDelta(data) {
  if (!data) return { accountId: null, delta: 0 };
  const isPaid = (data.status || "paid").toString() === "paid";
  if (!isPaid) return { accountId: null, delta: 0 };
  const type = (data.type || "expense").toString();
  const amount = Math.abs(Number(data.amount) || 0);
  if (amount <= 0) return { accountId: null, delta: 0 };
  const paidFrom = ((data.paidFromFinanceAccountId || "") + "").trim();
  const accountId = ((data.financeAccountId || "") + "").trim();
  if (paidFrom && type === "expense") {
    return { accountId: paidFrom, delta: -amount };
  }
  if (!accountId) return { accountId: null, delta: 0 };
  return { accountId, delta: openingContribution(data) };
}

async function applyAccountMonthBucketDelta(userId, before, after) {
  const bEff = before ? effectiveTs(before) : null;
  const aEff = after ? effectiveTs(after) : null;
  const bKey = bEff ? monthKeyBr(bEff) : null;
  const aKey = aEff ? monthKeyBr(aEff) : null;
  const bSlot = accountBucketDelta(before);
  const aSlot = accountBucketDelta(after);

  if (
    bKey &&
    aKey &&
    bKey === aKey &&
    bSlot.accountId &&
    aSlot.accountId &&
    bSlot.accountId === aSlot.accountId
  ) {
    const net = aSlot.delta - bSlot.delta;
    if (net !== 0) await bumpAccountMonthNet(userId, bKey, bSlot.accountId, net);
    return;
  }
  if (bKey && bSlot.accountId && bSlot.delta !== 0) {
    await bumpAccountMonthNet(userId, bKey, bSlot.accountId, -bSlot.delta);
  }
  if (aKey && aSlot.accountId && aSlot.delta !== 0) {
    await bumpAccountMonthNet(userId, aKey, aSlot.accountId, aSlot.delta);
  }
}

async function applyAllBucketDeltas(userId, before, after) {
  await applyMonthBucketDelta(userId, before, after);
  await applyAccountMonthBucketDelta(userId, before, after);
}

const financeMonthBucketsOnTransactionWrite = onDocumentWritten(
  {
    document: "users/{userId}/transactions/{txId}",
    region: "us-central1",
    memory: "256MiB",
  },
  async (event) => {
    const userId = event.params.userId;
    const before = event.data.before.exists ? event.data.before.data() : null;
    const after = event.data.after.exists ? event.data.after.data() : null;
    try {
      await applyAllBucketDeltas(userId, before, after);
    } catch (e) {
      console.error("financeMonthBucketsOnTransactionWrite", userId, e?.message || e);
    }
  },
);

/**
 * Reconstrói buckets a partir de todos os lançamentos (one-shot após deploy,
 * migração, ou quando o usuário exclui uma conta/lançamentos em massa).
 *
 * NÃO usa `merge: true` de propósito: o gatilho incremental
 * (`financeMonthBucketsOnTransactionWrite`) só soma/subtrai o que muda a cada
 * lançamento — se uma exclusão em lote falhar silenciosamente pra um ou dois
 * documentos (erro transiente, cota, etc.), o decremento correspondente nunca
 * acontece e um resíduo fica preso no bucket pra sempre, mesmo com a conta e
 * todos os lançamentos já apagados. Com `merge: true`, o rebuild também não
 * resolveria isso: ele só sobrescreve as chaves que aparecem no cálculo novo,
 * nunca remove uma chave de conta/mês que não tem lançamento nenhum. Por
 * isso aqui o documento é substituído por inteiro (mês sem lançamento vira
 * `delete()`, mês com lançamento grava `netByAccount` do zero).
 */
const ctFinanceRebuildOpeningBuckets = onCall({ region: "us-central1", memory: "512MiB", timeoutSeconds: 300 }, async (req) => {
  if (!req.auth || !req.auth.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Login obrigatório.");
  }
  const uid = req.auth.uid;
  const db = admin.firestore();
  const metaRef = db.doc(`users/${uid}/finance_stats/meta`);

  const monthSums = new Map();
  /** @type {Map<string, Map<string, number>>} */
  const accountMonthSums = new Map();

  const txCol = db.collection(`users/${uid}/transactions`);
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
      const slot = accountBucketDelta(d);
      if (slot.accountId && slot.delta !== 0) {
        if (!accountMonthSums.has(k)) accountMonthSums.set(k, new Map());
        const m = accountMonthSums.get(k);
        m.set(slot.accountId, (m.get(slot.accountId) || 0) + slot.delta);
      }
    }
    last = snap.docs[snap.docs.length - 1];
    if (snap.size < 400) break;
  }

  // Documentos que já existem — qualquer um que não aparecer no cálculo novo
  // não tem mais lançamento nenhum por trás e precisa ser apagado, não só
  // deixado de fora do próximo write.
  const [existingMonthDocs, existingAccountMonthDocs] = await Promise.all([
    db.collection(`users/${uid}/finance_month_buckets`).listDocuments(),
    db.collection(`users/${uid}/finance_account_month_buckets`).listDocuments(),
  ]);

  const monthEntries = [...monthSums.entries()];
  const monthKeysAtivos = new Set(monthEntries.map(([k]) => k));
  const monthWrites = monthEntries.map(([k, v]) => ({
    ref: db.doc(`users/${uid}/finance_month_buckets/${k}`),
    data: { netPaid: v, updatedAt: admin.firestore.FieldValue.serverTimestamp() },
  }));
  const monthDeletes = existingMonthDocs
    .filter((ref) => !monthKeysAtivos.has(ref.id))
    .map((ref) => ref);

  for (let i = 0; i < monthWrites.length; i += 400) {
    const batch = db.batch();
    for (const w of monthWrites.slice(i, i + 400)) batch.set(w.ref, w.data);
    await batch.commit();
  }
  for (let i = 0; i < monthDeletes.length; i += 400) {
    const batch = db.batch();
    for (const ref of monthDeletes.slice(i, i + 400)) batch.delete(ref);
    await batch.commit();
  }

  const accountMonthEntries = [...accountMonthSums.entries()];
  const accountMonthKeysAtivos = new Set(accountMonthEntries.map(([k]) => k));
  const accountMonthWrites = accountMonthEntries.map(([monthKey, accMap]) => {
    const netByAccount = {};
    for (const [acc, val] of accMap.entries()) {
      netByAccount[safeAccountFieldId(acc)] = val;
    }
    return {
      ref: db.doc(`users/${uid}/finance_account_month_buckets/${monthKey}`),
      data: { netByAccount, updatedAt: admin.firestore.FieldValue.serverTimestamp() },
    };
  });
  const accountMonthDeletes = existingAccountMonthDocs
    .filter((ref) => !accountMonthKeysAtivos.has(ref.id))
    .map((ref) => ref);

  for (let i = 0; i < accountMonthWrites.length; i += 200) {
    const batch = db.batch();
    for (const w of accountMonthWrites.slice(i, i + 200)) batch.set(w.ref, w.data);
    await batch.commit();
  }
  for (let i = 0; i < accountMonthDeletes.length; i += 400) {
    const batch = db.batch();
    for (const ref of accountMonthDeletes.slice(i, i + 400)) batch.delete(ref);
    await batch.commit();
  }

  await metaRef.set(
    {
      openingBucketsVersion: OPENING_BUCKETS_VERSION,
      rebuiltAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  return {
    ok: true,
    months: monthWrites.length,
    monthsRemoved: monthDeletes.length,
    accountMonths: accountMonthWrites.length,
    accountMonthsRemoved: accountMonthDeletes.length,
    version: OPENING_BUCKETS_VERSION,
  };
});

module.exports = {
  financeMonthBucketsOnTransactionWrite,
  ctFinanceRebuildOpeningBuckets,
  monthKeyBr,
  effectiveTs,
  openingContribution,
  accountBucketDelta,
  accountIdFrom,
  safeAccountFieldId,
  restoreAccountFieldId,
  OPENING_BUCKETS_VERSION,
};
