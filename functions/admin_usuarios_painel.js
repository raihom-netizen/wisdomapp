/**
 * `ctAdminUsuariosPainel` — «Usuários · Painel» do Painel Admin do WISDOMAPP
 * (porte do Controle Total, 02/10/2026, adaptado aos planos daqui).
 *
 * Base real de cadastros e situação de cada conta, montada no SERVIDOR:
 *  - contagem real (`count()` em users) e a classificação igual à do app
 *    (`lib/utils/admin_user_search.dart`): titular (e-mail completo), sub-login
 *    (`accountType/plan == delegate` ou `linkedPrincipalUid`), fantasma (sem
 *    e-mail), removido (`removedByAdminAt`);
 *  - data de cadastro de verdade: `createdAt` e, em doc antigo sem o campo, o
 *    `createTime` do documento;
 *  - situação comercial por conta: pagante ativo / não renovou (pagou pelo
 *    Mercado Pago, `mp_payments` aprovado), convênio (`partnershipId` ou plano
 *    `premium_<parceiro>`), cortesia (premium/premium_pro sem pagamento), free,
 *    equipe (role admin/master), sub-conta;
 *  - KPIs (novos hoje/7/30/mês, plataforma, licença ativa/vencida/vencendo,
 *    último acesso 7/30 dias), séries diária (60 d) e mensal (12 m), recentes;
 *  - receita do mês (mp_payments aprovados − estornos) e dos últimos 6 meses.
 *
 * Planos do WISDOMAPP: free, premium, premium_pro (+ planos de convênio
 * premium_*). Licença: `planStatus` + `licenseExpiresAt`.
 *
 * Permissão: admin/suporte (master sempre). Só leitura, com limite e
 * `.select(...)`; cache de 10 min em `admin_stats/usuarios_painel`
 * (`{forcar: true}` refaz).
 */

"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const { requireAdminLevel } = require("./admin_auth");

const REGIAO = "us-central1";
const CACHE_DOC = "admin_stats/usuarios_painel";
const CACHE_MS = 10 * 60 * 1000;
const DIA = 86400000;
const BRT = 3 * 3600000; // Brasília
const LIMITE_USERS = 5000;
const LIMITE_PAGAMENTOS = 10000;
const EMAIL_RX = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const STATUS_ESTORNO = new Set(["refunded", "charged_back"]);

function num(v) {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}
function cent(v) {
  return Math.round(num(v) * 100) / 100;
}
function ms(v) {
  if (!v) return 0;
  if (typeof v.toMillis === "function") return v.toMillis();
  if (v instanceof Date) return v.getTime();
  if (typeof v === "number") return v;
  if (typeof v === "string") {
    const t = Date.parse(v);
    return Number.isFinite(t) ? t : 0;
  }
  if (typeof v === "object" && v.seconds != null) return num(v.seconds) * 1000;
  return 0;
}
function diaBr(t) {
  return new Date(t - BRT).toISOString().slice(0, 10);
}
function mesBr(t) {
  return diaBr(t).slice(0, 7);
}
function mesesAntes(chave, n) {
  const [a, m] = chave.split("-").map(Number);
  const d = new Date(Date.UTC(a, m - 1 - n, 1));
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}`;
}

/** 'fantasma' | 'sublogin' | 'titular' (mesmas regras do app). */
function classificarPerfil(id, d) {
  const email = String(d.email || "").trim().toLowerCase();
  if (!email || !EMAIL_RX.test(email)) return "fantasma";
  const plan = String(d.plan || "").trim().toLowerCase();
  const tipo = String(d.accountType || "").trim().toLowerCase();
  if (tipo === "delegate" || plan === "delegate") return "sublogin";
  const titular = String(d.linkedPrincipalUid || d.principalUid || "").trim();
  if (titular && titular !== id) return "sublogin";
  return "titular";
}

function plataformaDe(d) {
  const t = d.clientTelemetry || {};
  const p = String(t.platform || "").trim().toLowerCase();
  if (!p) return "";
  if (p.includes("android")) return "android";
  if (p.includes("ios") || p.includes("iphone") || p.includes("ipad")) return "ios";
  if (p.includes("web")) return "web";
  return "outra";
}

/** Pagamento aprovado/estornado do Mercado Pago (tira saídas do admin). */
function lerPagamento(d) {
  if (!d || d.isOutgoing === true) return null;
  const raw = d.raw || {};
  const status = String(d.status || raw.status || "").toLowerCase();
  const bruto = num(d.transaction_amount != null ? d.transaction_amount : raw.transaction_amount);
  if (bruto <= 0) return null;
  const liquido = num((raw.transaction_details || {}).net_received_amount) || bruto;
  const quando = ms(d.dateApprovedAt) || ms(raw.date_approved) || ms(raw.date_created) || ms(d.updatedAt);
  const planCode = String(d.planCode || d.plan || "").toLowerCase();
  return {
    uid: String(d.uid || "").trim(),
    status,
    bruto,
    liquido,
    quando,
    addon: planCode.includes("extra_bank") || planCode.includes("addon"),
  };
}

/**
 * Situação comercial (régua única do painel).
 * @return {string} equipe | convenio | pagante_ativo | pagante_vencido | cortesia | free
 */
function situacaoDe(d, agora, pagouLicenca) {
  const role = String(d.role || "").toLowerCase();
  if (role === "admin" || role === "master") return "equipe";
  const plan = String(d.plan || "free").trim().toLowerCase() || "free";
  const parceria = String(d.partnershipId || "").trim();
  const vence = ms(d.licenseExpiresAt);
  const ativoLicenca = String(d.planStatus || "active").toLowerCase() === "active" && vence >= agora;
  if (parceria || (plan.startsWith("premium_") && plan !== "premium_pro")) return "convenio";
  if (pagouLicenca) return ativoLicenca ? "pagante_ativo" : "pagante_vencido";
  if (plan === "free") return "free";
  return "cortesia";
}

/**
 * Agregação PURA (testável): perfis + pagamentos → painel.
 * @param {Array<{id:string,data:object,createTime:number}>} docs
 * @param {Array<object>} pagamentosDados dados crus de mp_payments
 * @param {number} agora
 * @param {number} totalDocs count() de users
 */
function montarPainel(docs, pagamentosDados, agora, totalDocs) {
  const hojeK = diaBr(agora);
  const mesK = mesBr(agora);
  const mesAnteriorK = mesesAntes(mesK, 1);

  // ── Pagamentos ────────────────────────────────────────────────────────────
  const pagoPorUid = {};
  const licencaPorUid = new Set();
  const porMes = {};
  for (const raw of pagamentosDados) {
    const p = lerPagamento(raw);
    if (!p) continue;
    const aprovado = p.status === "approved";
    const estorno = STATUS_ESTORNO.has(p.status);
    if (!aprovado && !estorno) continue;
    const mk = p.quando ? mesBr(p.quando) : "";
    if (mk) {
      const m = (porMes[mk] ||= { bruto: 0, liquido: 0, estornos: 0, pagamentos: 0 });
      if (aprovado) {
        m.bruto += p.bruto;
        m.liquido += p.liquido;
        m.pagamentos += 1;
      } else {
        m.estornos += p.bruto;
      }
    }
    if (aprovado && p.uid) {
      const g = (pagoPorUid[p.uid] ||= { bruto: 0, qtd: 0, ultimo: 0 });
      g.bruto += p.bruto;
      g.qtd += 1;
      if (p.quando > g.ultimo) g.ultimo = p.quando;
      if (!p.addon) licencaPorUid.add(p.uid);
    }
  }

  // ── Perfis ────────────────────────────────────────────────────────────────
  const cont = {
    totalDocs,
    lidos: docs.length,
    titulares: 0,
    sublogins: 0,
    fantasmas: 0,
    removidos: 0,
    equipe: 0,
    novosHoje: 0,
    novos7: 0,
    novos30: 0,
    novosMes: 0,
    novosMesAnterior: 0,
    semCreatedAt: 0,
    licencaAtiva: 0,
    licencaVencida: 0,
    semLicenca: 0,
    vencendo7: 0,
    vencendo30: 0,
    pagante_ativo: 0,
    pagante_vencido: 0,
    cortesia: 0,
    convenio: 0,
    free: 0,
    porPlano: {},
    plataforma: { android: 0, ios: 0, web: 0, outra: 0, sem_registro: 0 },
    ativos7: 0,
    ativos30: 0,
  };
  const usuarios = [];
  const serieDia = {};
  const serieMes = {};
  for (const doc of docs) {
    const d = doc.data || {};
    const classe = classificarPerfil(doc.id, d);
    if (classe === "fantasma") {
      cont.fantasmas += 1;
      continue;
    }
    const createdAt = ms(d.createdAt);
    const criado = createdAt || num(doc.createTime);
    const ping = ms((d.clientTelemetry || {}).lastPingAt);
    const plataforma = plataformaDe(d);
    const plan = String(d.plan || "free").trim().toLowerCase() || "free";
    const vence = ms(d.licenseExpiresAt);
    const removido = !!d.removedByAdminAt;
    const base = {
      uid: doc.id,
      nome: String(d.name || d.displayName || d.nome || "").trim(),
      email: String(d.email || "").trim(),
      plano: plan,
      planStatus: String(d.planStatus || ""),
      convenio: String(d.partnershipName || d.partnershipId || "").trim(),
      criadoEm: criado,
      criadoFonte: createdAt ? "createdAt" : "createTime",
      vence,
      ultimoAcesso: ping,
      plataforma,
      versao: String((d.clientTelemetry || {}).appVersion || ""),
      removido,
    };
    if (classe === "sublogin") {
      cont.sublogins += 1;
      usuarios.push({ ...base, situacao: "subconta", totalPago: 0, pagamentos: 0, ultimoPagamento: 0 });
      continue;
    }
    cont.titulares += 1;
    if (!createdAt) cont.semCreatedAt += 1;
    if (removido) cont.removidos += 1;
    cont.porPlano[plan] = (cont.porPlano[plan] || 0) + 1;
    cont.plataforma[plataforma || "sem_registro"] = (cont.plataforma[plataforma || "sem_registro"] || 0) + 1;
    if (ping && agora - ping <= 7 * DIA) cont.ativos7 += 1;
    if (ping && agora - ping <= 30 * DIA) cont.ativos30 += 1;
    if (criado) {
      const k = diaBr(criado);
      if (k === hojeK) cont.novosHoje += 1;
      if (agora - criado <= 7 * DIA) cont.novos7 += 1;
      if (agora - criado <= 30 * DIA) cont.novos30 += 1;
      const mk = k.slice(0, 7);
      if (mk === mesK) cont.novosMes += 1;
      if (mk === mesAnteriorK) cont.novosMesAnterior += 1;
      if (agora - criado <= 60 * DIA) serieDia[k] = (serieDia[k] || 0) + 1;
      serieMes[mk] = (serieMes[mk] || 0) + 1;
    }
    if (!removido && plan !== "free") {
      if (!vence) cont.semLicenca += 1;
      else if (vence < agora) cont.licencaVencida += 1;
      else {
        cont.licencaAtiva += 1;
        if (vence - agora <= 7 * DIA) cont.vencendo7 += 1;
        if (vence - agora <= 30 * DIA) cont.vencendo30 += 1;
      }
    }
    const situacao = situacaoDe(d, agora, licencaPorUid.has(doc.id));
    if (situacao === "equipe") cont.equipe += 1;
    else cont[situacao] = (cont[situacao] || 0) + 1;
    const pago = pagoPorUid[doc.id];
    usuarios.push({
      ...base,
      situacao,
      totalPago: pago ? cent(pago.bruto) : 0,
      pagamentos: pago ? pago.qtd : 0,
      ultimoPagamento: pago ? pago.ultimo : 0,
    });
  }

  const serieDiaria = [];
  for (let i = 59; i >= 0; i--) {
    const k = diaBr(agora - i * DIA);
    serieDiaria.push({ dia: k, novos: serieDia[k] || 0 });
  }
  const serieMensal = [];
  for (let i = 11; i >= 0; i--) {
    const k = mesesAntes(mesK, i);
    serieMensal.push({ mes: k, novos: serieMes[k] || 0 });
  }
  const historico = [];
  for (let i = 5; i >= 0; i--) {
    const k = mesesAntes(mesK, i);
    const m = porMes[k] || { bruto: 0, liquido: 0, estornos: 0, pagamentos: 0 };
    historico.push({
      mes: k,
      receitaBruta: cent(m.bruto),
      receitaLiquida: cent(m.liquido),
      estornos: cent(m.estornos),
      receita: cent(m.bruto - m.estornos),
      pagamentos: m.pagamentos,
    });
  }
  const recentes = usuarios
    .filter((u) => u.situacao !== "subconta")
    .sort((a, b) => b.criadoEm - a.criadoEm)
    .slice(0, 30)
    .map((u) => u.uid);

  return {
    geradoEm: agora,
    hoje: hojeK,
    mesAtual: mesK,
    contagem: cont,
    serieDiaria,
    serieMensal,
    historico,
    financeiroMes: historico[historico.length - 1],
    recentes,
    usuarios,
  };
}

async function montar(db) {
  const agora = Date.now();
  const avisos = [];
  const [totalAgg, usersSnap, pagsSnap] = await Promise.all([
    db.collection("users").count().get(),
    db
      .collection("users")
      .select(
        "name", "displayName", "nome", "email", "plan", "planStatus", "role", "accountType",
        "principalUid", "linkedPrincipalUid", "partnershipId", "partnershipName",
        "licenseExpiresAt", "removedByAdminAt", "createdAt", "clientTelemetry",
      )
      .limit(LIMITE_USERS)
      .get(),
    db
      .collection("mp_payments")
      .select(
        "uid", "status", "transaction_amount", "dateApprovedAt", "isOutgoing", "planCode", "plan",
        "updatedAt", "raw.status", "raw.transaction_amount", "raw.date_approved", "raw.date_created",
        "raw.transaction_details.net_received_amount",
      )
      .limit(LIMITE_PAGAMENTOS)
      .get()
      .catch((e) => {
        avisos.push(`mp_payments ilegível: ${e.message}`);
        return null;
      }),
  ]);
  const totalDocs = totalAgg.data().count || 0;
  if (usersSnap.size >= LIMITE_USERS) {
    avisos.push(`Base com ${totalDocs} perfis — lidos os primeiros ${LIMITE_USERS}.`);
  }
  if (pagsSnap && pagsSnap.size >= LIMITE_PAGAMENTOS) {
    avisos.push(`Mais de ${LIMITE_PAGAMENTOS} pagamentos — total pago pode estar incompleto.`);
  }
  const docs = usersSnap.docs.map((d) => ({
    id: d.id,
    data: d.data() || {},
    createTime: d.createTime ? d.createTime.toMillis() : 0,
  }));
  const pagamentos = pagsSnap ? pagsSnap.docs.map((d) => d.data() || {}) : [];
  const r = montarPainel(docs, pagamentos, agora, totalDocs);
  r.avisos = avisos;
  return r;
}

exports.ctAdminUsuariosPainel = onCall(
  { region: REGIAO, timeoutSeconds: 120, memory: "1GiB", cors: true, maxInstances: 5 },
  async (req) => {
    await requireAdminLevel(req, ["admin", "suporte"]);
    const db = admin.firestore();
    const forcar = !!(req.data && req.data.forcar === true);
    const ref = db.doc(CACHE_DOC);
    if (!forcar) {
      try {
        const s = await ref.get();
        const c = s.exists ? s.data() || {} : {};
        if (c.json && Date.now() - Number(c.geradoEm || 0) < CACHE_MS) {
          return { ...JSON.parse(c.json), doCache: true };
        }
      } catch (e) {
        console.warn("[ctAdminUsuariosPainel] cache ilegível, refazendo", e.message);
      }
    }
    let r;
    try {
      r = await montar(db);
    } catch (e) {
      console.error("[ctAdminUsuariosPainel]", e);
      throw new HttpsError("internal", "Não foi possível montar o painel agora.");
    }
    try {
      const json = JSON.stringify(r);
      if (json.length < 900000) {
        await ref.set({ geradoEm: r.geradoEm, json, geradoPor: req.auth.uid });
      }
    } catch (e) {
      console.warn("[ctAdminUsuariosPainel] não gravou o cache", e.message);
    }
    return { ...r, doCache: false };
  },
);

exports._montarPainel = montarPainel;
exports._situacaoDe = situacaoDe;
exports._classificarPerfil = classificarPerfil;
