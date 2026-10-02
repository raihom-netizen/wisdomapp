/**
 * Remoção automática dos AVISOS vencidos (fila users/{uid}/agendaAlerts).
 *
 * Regra do dono (02/10/2026): aviso de financeiro ou compromisso cujo evento
 * já passou há mais de 24 h sai sozinho da central. Apaga SÓ o aviso — nunca
 * o compromisso (reminders) nem o lançamento (transactions).
 *
 * Usa o índice de grupo já existente (status ASC, notifyAt ASC): como o aviso
 * é sempre disparado antes (ou no) evento, notifyAt < corte é pré-filtro, e a
 * data do evento (eventAt) é conferida no código antes de apagar.
 */

const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

const HORAS_APOS_EVENTO = 24;
const LOTE = 450;
const MAX_LOTES_POR_STATUS = 20;
const STATUS = ["sent", "pending", "cancelled", "skipped"];

function dataDe(v) {
  if (!v) return null;
  if (typeof v.toDate === "function") return v.toDate();
  if (v instanceof Date) return v;
  return null;
}

/** Apaga os avisos com evento há mais de 24 h. Devolve quantos saíram. */
async function expirarAvisosVencidos(db, agora) {
  const corte = new Date((agora || new Date()).getTime() - HORAS_APOS_EVENTO * 3600 * 1000);
  const corteTs = admin.firestore.Timestamp.fromDate(corte);
  let removidos = 0;

  for (const status of STATUS) {
    let ultimo = null;
    for (let i = 0; i < MAX_LOTES_POR_STATUS; i++) {
      let q = db
        .collectionGroup("agendaAlerts")
        .where("status", "==", status)
        .where("notifyAt", "<", corteTs)
        .orderBy("notifyAt", "asc")
        .limit(LOTE);
      if (ultimo) q = q.startAfter(ultimo);
      const snap = await q.get();
      if (snap.empty) break;
      ultimo = snap.docs[snap.docs.length - 1];

      const batch = db.batch();
      let n = 0;
      for (const doc of snap.docs) {
        const d = doc.data() || {};
        // Só a fila da agenda de um usuário (users/{uid}/agendaAlerts).
        if (doc.ref.parent.parent?.parent?.id !== "users") continue;
        const evento = dataDe(d.eventAt) || dataDe(d.notifyAt);
        if (!evento || evento >= corte) continue;
        batch.delete(doc.ref);
        n++;
      }
      if (n) {
        await batch.commit();
        removidos += n;
      }
      if (snap.size < LOTE) break;
    }
  }
  return removidos;
}

/** A cada 3 h (Brasília): limpa avisos com mais de 1 dia após o evento. */
exports.ctExpirarAvisosAgenda = onSchedule(
  {
    schedule: "every 3 hours",
    timeZone: "America/Sao_Paulo",
    region: "us-central1",
    memory: "256MiB",
    timeoutSeconds: 540,
  },
  async () => {
    try {
      const n = await expirarAvisosVencidos(admin.firestore(), new Date());
      console.log(`[ctExpirarAvisosAgenda] avisos vencidos removidos: ${n}`);
    } catch (e) {
      console.error("[ctExpirarAvisosAgenda]", e?.message || e);
    }
  },
);

exports.expirarAvisosVencidos = expirarAvisosVencidos;
exports.HORAS_APOS_EVENTO = HORAS_APOS_EVENTO;
