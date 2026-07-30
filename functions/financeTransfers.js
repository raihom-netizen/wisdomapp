const admin = require("firebase-admin");
const { HttpsError } = require("firebase-functions/v2/https");

function _transferTimestamp(dateISO) {
  const d = new Date((dateISO || "").toString());
  if (!Number.isFinite(d.getTime())) return admin.firestore.Timestamp.now();
  return admin.firestore.Timestamp.fromDate(d);
}

function _buildPairPayload({
  pairId,
  amount,
  fromId,
  toId,
  fromLabel,
  toLabel,
  note,
  transferTs,
}) {
  const histLine = `${fromLabel} → ${toLabel}`;
  const notePart = note ? ` • ${note}` : "";
  const base = {
    amount,
    category: "Transferência",
    status: "paid",
    date: transferTs,
    paidAt: transferTs,
    effectiveDate: transferTs,
    transferPairId: pairId,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  return {
    out: {
      ...base,
      type: "expense",
      financeAccountId: fromId,
      transferDirection: "out",
      transferCounterpartyAccountId: toId,
      transferCounterpartyLabel: toLabel,
      description: `Saída • Transferência • ${histLine}${notePart}`,
    },
    in: {
      ...base,
      type: "income",
      financeAccountId: toId,
      transferDirection: "in",
      transferCounterpartyAccountId: fromId,
      transferCounterpartyLabel: fromLabel,
      description: `Entrada • Transferência • ${histLine}${notePart}`,
    },
  };
}

async function ctFinanceCreateTransferHandler(req) {
  if (!req.auth) {
    throw new HttpsError("unauthenticated", "Login obrigatório.");
  }
  const uid = req.auth.uid;
  const amount = Math.abs(Number(req.data?.amount || 0));
  const fromId = (req.data?.fromAccountId || "").toString().trim();
  const toId = (req.data?.toAccountId || "").toString().trim();
  const fromLabel = (req.data?.fromLabel || fromId).toString().trim();
  const toLabel = (req.data?.toLabel || toId).toString().trim();
  const note = (req.data?.note || "").toString().trim();

  if (!Number.isFinite(amount) || amount <= 0) {
    throw new HttpsError("invalid-argument", "Valor inválido.");
  }
  if (!fromId || !toId || fromId === toId) {
    throw new HttpsError("invalid-argument", "Contas de origem e destino inválidas.");
  }

  const transferTs = _transferTimestamp(req.data?.dateISO);
  const pairId = `tr_${Date.now()}_${Math.random().toString(36).slice(2, 9)}`;
  const txCol = admin.firestore().collection("users").doc(uid).collection("transactions");
  const batch = admin.firestore().batch();
  const outRef = txCol.doc();
  const inRef = txCol.doc();
  const payload = _buildPairPayload({
    pairId,
    amount,
    fromId,
    toId,
    fromLabel,
    toLabel,
    note,
    transferTs,
  });

  batch.set(outRef, {
    ...payload.out,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  batch.set(inRef, {
    ...payload.in,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await batch.commit();

  return { ok: true, pairId, outId: outRef.id, inId: inRef.id };
}

async function ctFinanceGetTransferPairHandler(req) {
  if (!req.auth) {
    throw new HttpsError("unauthenticated", "Login obrigatório.");
  }
  const uid = req.auth.uid;
  const pairId = (req.data?.pairId || "").toString().trim();
  if (!pairId) {
    throw new HttpsError("invalid-argument", "pairId obrigatório.");
  }

  const snap = await admin
    .firestore()
    .collection("users")
    .doc(uid)
    .collection("transactions")
    .where("transferPairId", "==", pairId)
    .limit(4)
    .get();

  if (snap.empty) {
    throw new HttpsError("not-found", "Transferência não encontrada.");
  }

  let outDoc = null;
  let inDoc = null;
  for (const d of snap.docs) {
    const dir = (d.data().transferDirection || "").toString();
    if (dir === "out") outDoc = d;
    if (dir === "in") inDoc = d;
  }
  outDoc = outDoc || snap.docs[0];
  inDoc = inDoc || snap.docs[1] || snap.docs[0];

  const out = outDoc.data() || {};
  const inn = inDoc.data() || {};
  const date = out.date?.toDate?.() || out.paidAt?.toDate?.() || new Date();

  return {
    ok: true,
    pairId,
    outId: outDoc.id,
    inId: inDoc.id,
    amount: Math.abs(Number(out.amount || 0)),
    fromAccountId: (out.financeAccountId || "").toString(),
    toAccountId: (inn.financeAccountId || "").toString(),
    dateISO: date.toISOString(),
    note: _extractTransferNote(out.description),
  };
}

function _extractTransferNote(description) {
  const raw = (description || "").toString();
  if (!raw.includes("•")) return "";
  const parts = raw.split("•").map((p) => p.trim());
  return parts.length > 2 ? parts[parts.length - 1] : "";
}

module.exports = {
  ctFinanceCreateTransferHandler,
  ctFinanceGetTransferPairHandler,
};
