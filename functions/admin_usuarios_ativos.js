/**
 * `ctAdminUsuariosAtivos` — «Usuários ativos» do Painel Admin do WISDOMAPP
 * (porte do Controle Total, 02/10/2026).
 *
 * Quem USA o sistema de verdade, dia a dia (fuso de Brasília) — não só quem
 * baixou/cadastrou. Um usuário conta como ativo num dia quando:
 *  - abriu o app naquele dia: `users.clientTelemetry.lastPingAt` (gravado pelo
 *    app a cada ~25 min de uso em `UserClientTelemetryService.pingIfDue`). Como
 *    o campo é sobrescrito, a rotina `ctAdminAtivosDiario` (23:55) guarda o
 *    retrato do dia em `admin_stats_ativos/{AAAA-MM-DD}`;
 *  - ou criou/alterou um lançamento (`transactions`) ou compromisso
 *    (`reminders`) naquele dia — reconstrói os dias anteriores à rotina.
 *
 * «Cliente real» = ativo em pelo menos `MIN_DIAS_CLIENTE_REAL` dias do período.
 *
 * Permissão: admin/suporte (master sempre). Só leitura pelo Admin SDK, com
 * limite e `.select(...)`. Resultado em cache por 10 min em
 * `admin_stats/usuarios_ativos_<dias>` (coleção sem regra = só servidor);
 * `{forcar: true}` refaz a leitura.
 */

"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const { requireAdminLevel } = require("./admin_auth");

const REGIAO = "us-central1";
const COLL_RETRATOS = "admin_stats_ativos";
const CACHE_MS = 10 * 60 * 1000;
const MIN_DIAS_CLIENTE_REAL = 3;
const FUSO_MS = 3 * 3600 * 1000; // Brasília (UTC−3, sem horário de verão)
const DIA = 86400000;
const LIMITE_USERS = 5000;
const LIMITE_REGISTROS = 20000;

function ms(v) {
  if (!v) return 0;
  if (typeof v.toMillis === "function") return v.toMillis();
  if (v instanceof Date) return v.getTime();
  if (typeof v === "string") {
    const t = Date.parse(v);
    return Number.isFinite(t) ? t : 0;
  }
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

/** «2026-09-18» no fuso de Brasília. */
function diaDe(msUtc) {
  return new Date(msUtc - FUSO_MS).toISOString().slice(0, 10);
}

/** Lista de dias (mais antigo → hoje). */
function listaDeDias(agora, dias) {
  const out = [];
  for (let i = dias - 1; i >= 0; i--) out.push(diaDe(agora - i * DIA));
  return out;
}

/**
 * uid → Set(dias) a partir de lançamentos e compromissos criados/alterados
 * desde `desdeMs`. Tenta a consulta filtrada (precisa de índice de grupo em
 * createdAt/updatedAt); sem índice, lê com limite e devolve aviso.
 */
async function diasPorRegistros(db, desdeMs, avisos) {
  const porUid = new Map();
  const marcar = (uid, t) => {
    if (!uid || !t || t < desdeMs) return;
    let s = porUid.get(uid);
    if (!s) porUid.set(uid, (s = new Set()));
    s.add(diaDe(t));
  };
  const ler = (snap) => {
    for (const doc of snap.docs) {
      const seg = doc.ref.path.split("/");
      if (seg[0] !== "users" || seg.length !== 4) continue;
      const d = doc.data() || {};
      marcar(seg[1], ms(d.createdAt));
      marcar(seg[1], ms(d.updatedAt));
    }
  };
  const desde = admin.firestore.Timestamp.fromMillis(desdeMs);
  for (const coll of ["transactions", "reminders"]) {
    let filtrado = true;
    for (const campo of ["createdAt", "updatedAt"]) {
      try {
        const snap = await db
          .collectionGroup(coll)
          .where(campo, ">=", desde)
          .select("createdAt", "updatedAt")
          .limit(LIMITE_REGISTROS)
          .get();
        ler(snap);
        if (snap.size >= LIMITE_REGISTROS) {
          avisos.push(`${coll}: mais de ${LIMITE_REGISTROS} registros no período — contagem parcial.`);
        }
      } catch (e) {
        filtrado = false;
        break;
      }
    }
    if (!filtrado) {
      // Sem índice de grupo: leitura com limite (aproximada).
      const snap = await db
        .collectionGroup(coll)
        .select("createdAt", "updatedAt")
        .limit(LIMITE_REGISTROS)
        .get();
      ler(snap);
      if (snap.size >= LIMITE_REGISTROS) {
        avisos.push(
          `${coll}: sem índice de grupo em createdAt/updatedAt — lidos só ${LIMITE_REGISTROS} registros (aproximado).`,
        );
      }
    }
  }
  return porUid;
}

/**
 * Agregação PURA (testável): junta retratos guardados, registros e o último
 * acesso de cada perfil em séries por dia e resumo.
 * @param {object} p
 * @param {number} p.agora
 * @param {number} p.dias
 * @param {Object<string,string[]>} p.retratos dia → uids
 * @param {Map<string,Set<string>>|Object<string,string[]>} p.registros uid → dias
 * @param {Array<object>} p.perfis {uid,nome,email,criadoEm,role,plano,plataforma,versao,ultimoAcesso,subLogin}
 */
function agregar({ agora, dias, retratos, registros, perfis }) {
  const listaDias = listaDeDias(agora, dias);
  const hoje = listaDias[listaDias.length - 1];
  const desdeMs = Date.parse(`${listaDias[0]}T00:00:00.000Z`) + FUSO_MS;
  const ativos = new Map(listaDias.map((d) => [d, new Set()]));
  const add = (dia, uid) => {
    const s = ativos.get(dia);
    if (s && uid) s.add(uid);
  };
  for (const [dia, uids] of Object.entries(retratos || {})) {
    for (const uid of uids || []) add(dia, uid);
  }
  const regEntries = registros instanceof Map ? [...registros.entries()] : Object.entries(registros || {});
  for (const [uid, set] of regEntries) for (const d of set) add(d, uid);

  const conhecidos = new Set();
  for (const p of perfis) {
    conhecidos.add(p.uid);
    if (p.ultimoAcesso >= desdeMs) add(diaDe(p.ultimoAcesso), p.uid);
  }
  // Atividade de quem não tem perfil válido (sub-coleção órfã) não entra.
  for (const set of ativos.values()) {
    for (const uid of [...set]) if (!conhecidos.has(uid)) set.delete(uid);
  }

  const diasDoUsuario = {};
  for (const [dia, set] of ativos) {
    for (const uid of set) {
      const x = (diasDoUsuario[uid] ||= { dias: 0, ultimoDia: "" });
      x.dias += 1;
      if (dia > x.ultimoDia) x.ultimoDia = dia;
    }
  }
  const serie = listaDias.map((d) => ({ dia: d, total: ativos.get(d).size, uids: [...ativos.get(d)] }));
  const ult7 = serie.slice(-7);
  const usuarios = perfis.map((p) => ({
    ...p,
    diasAtivos: (diasDoUsuario[p.uid] || {}).dias || 0,
    ultimoDiaAtivo: (diasDoUsuario[p.uid] || {}).ultimoDia || "",
  }));
  const ativosPeriodo = usuarios.filter((u) => u.diasAtivos > 0).length;
  const clientesReais = usuarios.filter((u) => u.diasAtivos >= MIN_DIAS_CLIENTE_REAL).length;
  const plataformasHoje = {};
  for (const u of usuarios) {
    if (u.ultimoDiaAtivo === hoje) {
      const k = u.plataforma || "desconhecida";
      plataformasHoje[k] = (plataformasHoje[k] || 0) + 1;
    }
  }
  return {
    geradoEm: agora,
    dias,
    hoje,
    minDiasClienteReal: MIN_DIAS_CLIENTE_REAL,
    serie,
    usuarios,
    resumo: {
      cadastrados: usuarios.length,
      ativosHoje: ativos.get(hoje).size,
      ativos7: new Set(ult7.flatMap((s) => s.uids)).size,
      ativosPeriodo,
      mediaDiaria7: Math.round((ult7.reduce((a, s) => a + s.total, 0) / Math.max(1, ult7.length)) * 10) / 10,
      clientesReais,
      usaramPouco: ativosPeriodo - clientesReais,
      soCadastro: usuarios.length - ativosPeriodo,
      plataformasHoje,
    },
  };
}

/** Perfil do doc users/{uid}; null para fantasma (sem e-mail completo). */
function perfilDe(id, d) {
  const email = String(d.email || "").trim();
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return null;
  const t = d.clientTelemetry || {};
  const titular = String(d.linkedPrincipalUid || d.principalUid || "").trim();
  return {
    uid: id,
    nome: String(d.name || d.displayName || d.nome || "").trim(),
    email,
    criadoEm: ms(d.createdAt),
    role: String(d.role || ""),
    plano: String(d.plan || d.licensePlan || ""),
    plataforma: String(t.platform || ""),
    versao: String(t.appVersion || ""),
    ultimoAcesso: ms(t.lastPingAt),
    subLogin: !!titular && titular !== id,
  };
}

async function montar(db, dias) {
  const agora = Date.now();
  const avisos = [];
  const listaDias = listaDeDias(agora, dias);
  const desdeMs = Date.parse(`${listaDias[0]}T00:00:00.000Z`) + FUSO_MS;

  const [guardados, usersSnap, registros] = await Promise.all([
    db
      .collection(COLL_RETRATOS)
      .where(admin.firestore.FieldPath.documentId(), ">=", listaDias[0])
      .limit(200)
      .get()
      .catch(() => null),
    db
      .collection("users")
      .select(
        "name", "displayName", "nome", "email", "createdAt", "role", "plan", "licensePlan",
        "clientTelemetry", "linkedPrincipalUid", "principalUid",
      )
      .limit(LIMITE_USERS)
      .get(),
    diasPorRegistros(db, desdeMs, avisos),
  ]);
  if (usersSnap.size >= LIMITE_USERS) {
    avisos.push(`Mais de ${LIMITE_USERS} perfis — lista cortada nos primeiros ${LIMITE_USERS}.`);
  }
  const retratos = {};
  if (guardados) {
    for (const g of guardados.docs) retratos[g.id] = (g.data() || {}).uids || [];
  }
  const perfis = [];
  for (const u of usersSnap.docs) {
    const p = perfilDe(u.id, u.data() || {});
    if (p) perfis.push(p);
  }
  const r = agregar({ agora, dias, retratos, registros, perfis });
  r.retratosGuardados = Object.keys(retratos).length;
  r.avisos = avisos;
  return r;
}

/** Retrato de hoje: quem abriu o app hoje + quem registrou algo hoje. */
async function retratoDoDia(db, agora = Date.now()) {
  const hoje = diaDe(agora);
  const users = await db.collection("users").select("clientTelemetry", "email").limit(LIMITE_USERS).get();
  const uids = new Set();
  const porPlataforma = {};
  for (const u of users.docs) {
    const t = (u.data() || {}).clientTelemetry || {};
    const ping = ms(t.lastPingAt);
    if (ping > 0 && diaDe(ping) === hoje) {
      uids.add(u.id);
      const p = String(t.platform || "desconhecida");
      porPlataforma[p] = (porPlataforma[p] || 0) + 1;
    }
  }
  const inicioHoje = Date.parse(`${hoje}T00:00:00.000Z`) + FUSO_MS;
  const reg = await diasPorRegistros(db, inicioHoje, []);
  for (const [uid, dias] of reg) if (dias.has(hoje)) uids.add(uid);
  return { dia: hoje, uids: [...uids], total: uids.size, porPlataforma };
}

/** 23:55 de Brasília: guarda quem usou hoje (o último acesso é sobrescrito). */
exports.ctAdminAtivosDiario = onSchedule(
  {
    schedule: "55 23 * * *",
    timeZone: "America/Sao_Paulo",
    region: REGIAO,
    memory: "512MiB",
    timeoutSeconds: 300,
  },
  async () => {
    const db = admin.firestore();
    const r = await retratoDoDia(db);
    await db.collection(COLL_RETRATOS).doc(r.dia).set({
      ...r,
      geradoEm: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`[ctAdminAtivosDiario] ${r.dia}: ${r.total} ativos`);
  },
);

exports.ctAdminUsuariosAtivos = onCall(
  { region: REGIAO, timeoutSeconds: 180, memory: "1GiB", cors: true, maxInstances: 5 },
  async (req) => {
    await requireAdminLevel(req, ["admin", "suporte"]);
    const db = admin.firestore();
    const data = req.data || {};
    const dias = Math.min(90, Math.max(7, Math.round(Number(data.dias) || 30)));
    const forcar = data.forcar === true;
    const ref = db.doc(`admin_stats/usuarios_ativos_${dias}`);
    if (!forcar) {
      try {
        const s = await ref.get();
        const c = s.exists ? s.data() || {} : {};
        if (c.json && Date.now() - Number(c.geradoEm || 0) < CACHE_MS) {
          return { ...JSON.parse(c.json), doCache: true };
        }
      } catch (e) {
        console.warn("[ctAdminUsuariosAtivos] cache ilegível, refazendo", e.message);
      }
    }
    let r;
    try {
      r = await montar(db, dias);
    } catch (e) {
      console.error("[ctAdminUsuariosAtivos]", e);
      throw new HttpsError("internal", "Não foi possível montar os usuários ativos agora.");
    }
    try {
      // Texto: a lista por uid passaria do limite de índices de um documento.
      const json = JSON.stringify(r);
      if (json.length < 900000) {
        await ref.set({ geradoEm: r.geradoEm, json, geradoPor: req.auth.uid });
      }
    } catch (e) {
      console.warn("[ctAdminUsuariosAtivos] não gravou o cache", e.message);
    }
    return { ...r, doCache: false };
  },
);

exports._agregar = agregar;
exports._perfilDe = perfilDe;
exports._diaDe = diaDe;
