"use strict";

/**
 * `ctAdminResultado` — «Receitas & Despesas» do Painel Admin do WISDOMAPP
 * (porte do `admin_resultado.js` do Controle Total, 02/10/2026).
 *
 * Só LEITURA agregada para o admin; não mexe em nada do usuário.
 *
 * Receita  = pagamentos do Mercado Pago gravados em `mp_payments` pelo
 *            webhook/sync do WISDOMAPP (status `approved`). Estornos e
 *            chargebacks (`refunded` / `charged_back`) entram e saem inteiros
 *            (o saldo deles fica zero, mas o painel mostra quanto voltou).
 *            Saída da conta (`isOutgoing`, admin pagando) fica fora.
 * Taxa MP  = bruto − líquido (`raw.transaction_details.net_received_amount`,
 *            senão `raw.fee_details`, senão estimativa 0,99% Pix / 4,99% cartão
 *            — as mesmas taxas do Resumo do admin).
 * Despesas = taxa MP + custos fixos mensais lançados pelo admin, guardados em
 *            `admin_stats/custos_fixos` (só o servidor lê/grava; sem regra no
 *            Firestore). Se ainda não existir, usa a lista antiga do próprio
 *            admin em `users/{uid}/settings/admin_costs` (só para mostrar).
 *            O custo fixo do mês é rateado entre quem pagou naquele mês.
 *
 * iOS (App Store): o WISDOMAPP não grava valor de compra da Apple (só
 * `users.lastIosIapProductId` + vencimento), então não entra aqui em R$ —
 * aparece na «Previsão & planos» como contagem/estimativa.
 *
 * Ações (`req.data.acao`):
 *   'resumo' (padrão) → { meses: 1..24 (12), forcar } — P&L por mês e por
 *                        usuário (top pagantes). Cache de 10 min em
 *                        `admin_stats/resultado_<meses>`.
 *   'salvarCustos'    → { itens: [{nome, valorMensal}] } — grava a lista.
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const { requireAdminLevel, logAdmin } = require("./admin_auth");

const REGIAO = "us-central1";
const CACHE_MS = 10 * 60 * 1000;
const CUSTOS_DOC = "admin_stats/custos_fixos";
const LIMITE_PAGAMENTOS = 5000;
const TOP_USUARIOS = 100;
const SEM_USUARIO = "_sem_usuario";
const FUSO_MS = 3 * 3600000; // Brasília (UTC−3, sem horário de verão)
const TAXA_PIX = 0.0099;
const TAXA_CARTAO = 0.0499;
const STATUS_ESTORNO = new Set(["refunded", "charged_back"]);
const STATUS_LIDOS = ["approved", "refunded", "charged_back"];

/** Campos de `mp_payments` usados aqui e na previsão (select = só isso). */
const CAMPOS_PAGAMENTO = [
  "uid",
  "status",
  "plan",
  "planCode",
  "entitlementType",
  "isOutgoing",
  "transaction_amount",
  "transactionAmountGross",
  "transactionAmountNet",
  "transactionFeeAmount",
  "dateApprovedAt",
  "updatedAt",
  "raw.transaction_amount",
  "raw.transaction_details.net_received_amount",
  "raw.fee_details",
  "raw.payment_method_id",
  "raw.date_approved",
  "raw.date_created",
  "raw.payer.email",
];

function num(v, padrao = 0) {
  const n = Number(v);
  return Number.isFinite(n) ? n : padrao;
}

function cent(v) {
  return Math.round(num(v) * 100) / 100;
}

function ms(v) {
  if (!v) return 0;
  if (typeof v.toMillis === "function") return v.toMillis();
  if (v instanceof Date) return v.getTime();
  if (typeof v === "number") return Number.isFinite(v) ? v : 0;
  if (typeof v === "object" && Number.isFinite(Number(v._seconds))) {
    return Number(v._seconds) * 1000;
  }
  const t = Date.parse(String(v));
  return Number.isFinite(t) ? t : 0;
}

/** Chave AAAA-MM no fuso de Brasília. */
function chaveMes(quandoMs) {
  return new Date(quandoMs - FUSO_MS).toISOString().slice(0, 7);
}

/** Lista das [n] últimas chaves de mês (mais antiga → atual). */
function ultimosMeses(agora, n) {
  const b = new Date(agora - FUSO_MS);
  const out = [];
  for (let i = n - 1; i >= 0; i--) {
    const d = new Date(Date.UTC(b.getUTCFullYear(), b.getUTCMonth() - i, 1));
    out.push(d.toISOString().slice(0, 7));
  }
  return out;
}

/** Início (ms) do mês AAAA-MM em Brasília. */
function inicioMes(chave) {
  const [a, m] = chave.split("-").map(Number);
  return Date.UTC(a, m - 1, 1) + FUSO_MS;
}

/**
 * Pagamento do `mp_payments` → forma única usada nas contas.
 * Devolve null quando não é receita do app (saída, valor zerado, status
 * que não interessa).
 */
function normalizarPagamento(id, d) {
  if (!d || d.isOutgoing === true) return null;
  const raw = d.raw && typeof d.raw === "object" ? d.raw : {};
  const status = String(d.status || raw.status || "").toLowerCase();
  if (status !== "approved" && !STATUS_ESTORNO.has(status)) return null;
  const bruto = num(
    raw.transaction_amount != null
      ? raw.transaction_amount
      : d.transaction_amount != null
        ? d.transaction_amount
        : d.transactionAmountGross,
  );
  if (bruto <= 0) return null;
  const pix = String(raw.payment_method_id || "").toLowerCase() === "pix";
  const det = raw.transaction_details || {};
  let liquido = num(det.net_received_amount);
  let taxaEstimada = false;
  if (!(liquido > 0)) {
    const fees = Array.isArray(raw.fee_details) ? raw.fee_details : null;
    if (fees && fees.length) {
      liquido = bruto - fees.reduce((s, f) => s + num(f && f.amount), 0);
    } else if (num(d.transactionAmountNet) > 0 && num(d.transactionFeeAmount) > 0) {
      liquido = num(d.transactionAmountNet);
    } else {
      liquido = bruto * (1 - (pix ? TAXA_PIX : TAXA_CARTAO));
      taxaEstimada = true;
    }
  }
  liquido = Math.min(bruto, Math.max(0, liquido));
  const quando =
    ms(d.dateApprovedAt) || ms(raw.date_approved) || ms(raw.date_created) || ms(d.updatedAt);
  if (!quando) return null;
  const payer = raw.payer && typeof raw.payer === "object" ? raw.payer : {};
  return {
    id: String(id || ""),
    uid: String(d.uid || "").trim(),
    estorno: STATUS_ESTORNO.has(status),
    bruto,
    liquido,
    taxa: Math.max(0, bruto - liquido),
    taxaEstimada,
    pix,
    quando,
    planCode: String(d.planCode || d.plan || "").trim().toLowerCase(),
    entitlementType: String(d.entitlementType || "").trim(),
    email: String(payer.email || "").trim().toLowerCase(),
  };
}

/** Rótulo curto do que o pagamento comprou. */
function rotuloPlano(planCode, entitlementType) {
  const c = String(planCode || "").toLowerCase();
  if (entitlementType === "extra_bank_connection" || c.includes("extra_bank")) {
    return "Conexão bancária extra";
  }
  const anual = c.includes("annual") || c.includes("anual") || c.includes("year");
  if (c.includes("premium_pro") || c === "pro") {
    return anual ? "Premium PRO anual" : "Premium PRO mensal";
  }
  if (!c) return "Outros";
  return anual ? "Premium anual" : "Premium mensal";
}

/** Lista de custos válida: [{nome, valorMensal}] (até 50, valores 0..1 mi). */
function limparCustos(itens) {
  if (!Array.isArray(itens)) return [];
  const out = [];
  for (const it of itens.slice(0, 50)) {
    if (!it || typeof it !== "object") continue;
    const nome = String(it.nome || "").trim().slice(0, 60);
    const valor = cent(it.valorMensal);
    if (!nome || !(valor >= 0) || valor > 1000000) continue;
    out.push({ nome, valorMensal: valor });
  }
  return out;
}

/**
 * Agregação pura (testável sem Firestore).
 * @param {object} p
 * @param {Array} p.pagamentos  saídas de normalizarPagamento (já sem null)
 * @param {Array} p.custos      [{nome, valorMensal}]
 * @param {number} p.agora      ms
 * @param {number} p.meses      quantos meses (inclui o atual)
 */
function agregar({ pagamentos, custos, agora, meses }) {
  const chaves = ultimosMeses(agora, meses);
  const inicio = inicioMes(chaves[0]);
  const custoFixoMes = (custos || []).reduce((s, c) => s + num(c.valorMensal), 0);

  const porMes = {};
  for (const k of chaves) {
    porMes[k] = {
      mes: k,
      receitaBruta: 0,
      estornos: 0,
      taxaMp: 0,
      pagamentos: 0,
      pagantes: new Set(),
      porPlano: {},
    };
  }
  const porUid = new Map();
  const linhaDe = (uid) => {
    const k = uid || SEM_USUARIO;
    if (!porUid.has(k)) {
      porUid.set(k, {
        uid: k,
        receitaBruta: 0,
        estornos: 0,
        taxaMp: 0,
        pagamentos: 0,
        custoRateado: 0,
        ultimoPagamento: 0,
        ultimoPlano: "",
        receitaMesAtual: 0,
        email: "",
        meses: new Set(),
      });
    }
    return porUid.get(k);
  };

  let taxasEstimadas = 0;
  for (const p of pagamentos) {
    if (p.quando < inicio || p.quando > agora + 86400000) continue;
    const k = chaveMes(p.quando);
    const m = porMes[k];
    if (!m) continue;
    const l = linhaDe(p.uid);
    if (!l.email && p.email) l.email = p.email;
    if (p.estorno) {
      m.receitaBruta += p.bruto;
      m.estornos += p.bruto;
      l.receitaBruta += p.bruto;
      l.estornos += p.bruto;
      continue;
    }
    m.receitaBruta += p.bruto;
    m.taxaMp += p.taxa;
    m.pagamentos += 1;
    if (p.uid) m.pagantes.add(p.uid);
    const rot = rotuloPlano(p.planCode, p.entitlementType);
    m.porPlano[rot] = (m.porPlano[rot] || 0) + p.bruto;
    l.receitaBruta += p.bruto;
    l.taxaMp += p.taxa;
    l.pagamentos += 1;
    l.meses.add(k);
    if (p.taxaEstimada) taxasEstimadas += 1;
    if (p.quando > l.ultimoPagamento) {
      l.ultimoPagamento = p.quando;
      l.ultimoPlano = rot;
    }
    if (k === chaves[chaves.length - 1]) l.receitaMesAtual += p.bruto;
  }

  // Custo fixo do mês rateado entre quem pagou naquele mês.
  for (const k of chaves) {
    const pagantes = porMes[k].pagantes;
    if (!pagantes.size || custoFixoMes <= 0) continue;
    const parte = custoFixoMes / pagantes.size;
    for (const uid of pagantes) linhaDe(uid).custoRateado += parte;
  }

  const listaMeses = chaves.map((k) => {
    const m = porMes[k];
    const receitaLiquida = m.receitaBruta - m.estornos - m.taxaMp;
    const despesas = m.taxaMp + custoFixoMes;
    const resultado = m.receitaBruta - m.estornos - despesas;
    const efetiva = m.receitaBruta - m.estornos;
    return {
      mes: k,
      receitaBruta: cent(m.receitaBruta),
      estornos: cent(m.estornos),
      taxaMp: cent(m.taxaMp),
      receitaLiquida: cent(receitaLiquida),
      custosFixos: cent(custoFixoMes),
      despesas: cent(despesas),
      resultado: cent(resultado),
      margem: efetiva > 0 ? Math.round((resultado / efetiva) * 1000) / 10 : null,
      pagamentos: m.pagamentos,
      pagantes: m.pagantes.size,
      porPlano: Object.fromEntries(Object.entries(m.porPlano).map(([a, b]) => [a, cent(b)])),
    };
  });

  const soma = (campo) => listaMeses.reduce((s, m) => s + num(m[campo]), 0);
  const receitaBruta = soma("receitaBruta");
  const estornos = soma("estornos");
  const despesas = soma("despesas");
  const resultado = receitaBruta - estornos - despesas;
  const pagantesUnicos = [...porUid.keys()].filter(
    (u) => u !== SEM_USUARIO && porUid.get(u).pagamentos > 0,
  ).length;
  const porPlano = {};
  for (const m of listaMeses) {
    for (const [k, v] of Object.entries(m.porPlano)) porPlano[k] = cent((porPlano[k] || 0) + v);
  }

  const usuarios = [...porUid.values()]
    .filter((l) => l.receitaBruta > 0)
    .map((l) => {
      const liquido = l.receitaBruta - l.estornos - l.taxaMp;
      return {
        uid: l.uid,
        email: l.email,
        receitaBruta: cent(l.receitaBruta),
        estornos: cent(l.estornos),
        taxaMp: cent(l.taxaMp),
        receitaLiquida: cent(liquido),
        custoRateado: cent(l.custoRateado),
        resultado: cent(liquido - l.custoRateado),
        pagamentos: l.pagamentos,
        mesesPagos: l.meses.size,
        ultimoPagamento: l.ultimoPagamento,
        ultimoPlano: l.ultimoPlano,
        receitaMesAtual: cent(l.receitaMesAtual),
      };
    })
    .sort((a, b) => b.receitaBruta - a.receitaBruta);

  const atual = listaMeses[listaMeses.length - 1];
  return {
    meses: listaMeses,
    mesAtual: atual,
    total: {
      receitaBruta: cent(receitaBruta),
      estornos: cent(estornos),
      taxaMp: cent(soma("taxaMp")),
      receitaLiquida: cent(soma("receitaLiquida")),
      custosFixos: cent(soma("custosFixos")),
      despesas: cent(despesas),
      resultado: cent(resultado),
      margem:
        receitaBruta - estornos > 0
          ? Math.round((resultado / (receitaBruta - estornos)) * 1000) / 10
          : null,
      pagamentos: listaMeses.reduce((s, m) => s + m.pagamentos, 0),
      pagantesUnicos,
      ticketMedio: pagantesUnicos > 0 ? cent((receitaBruta - estornos) / pagantesUnicos) : 0,
      porPlano,
      taxasEstimadas,
      noPrejuizo: usuarios.filter((u) => u.uid !== SEM_USUARIO && u.resultado < 0).length,
    },
    custoFixoMes: cent(custoFixoMes),
    usuarios,
  };
}

/** Lê `mp_payments` (só campos usados, com teto) e normaliza. */
async function lerPagamentos(db) {
  const snap = await db
    .collection("mp_payments")
    .where("status", "in", STATUS_LIDOS)
    .select(...CAMPOS_PAGAMENTO)
    .limit(LIMITE_PAGAMENTOS)
    .get();
  const lista = [];
  for (const doc of snap.docs) {
    const p = normalizarPagamento(doc.id, doc.data());
    if (p) lista.push(p);
  }
  return { lista, limiteAtingido: snap.size >= LIMITE_PAGAMENTOS };
}

/** Custos fixos: doc do servidor; senão a lista antiga do admin que chamou. */
async function lerCustos(db, uid) {
  const s = await db.doc(CUSTOS_DOC).get();
  if (s.exists) {
    const d = s.data() || {};
    return {
      itens: limparCustos(d.itens),
      origem: "servidor",
      atualizadoEm: ms(d.atualizadoEm),
    };
  }
  if (uid) {
    try {
      const a = await db.doc(`users/${uid}/settings/admin_costs`).get();
      const itens = limparCustos((a.data() || {}).itens);
      if (itens.length) return { itens, origem: "lista_antiga_do_admin", atualizadoEm: 0 };
    } catch (e) {
      console.warn("[ctAdminResultado] lista antiga de custos ilegível", e.message);
    }
  }
  return { itens: [], origem: "vazio", atualizadoEm: 0 };
}

/** Nome/e-mail/plano dos top pagantes (getAll com fieldMask). */
async function lerPerfis(db, uids) {
  const out = new Map();
  for (let i = 0; i < uids.length; i += 100) {
    const refs = uids.slice(i, i + 100).map((u) => db.doc(`users/${u}`));
    if (!refs.length) continue;
    const snaps = await db.getAll(...refs, {
      fieldMask: ["name", "displayName", "email", "plan", "licenseExpiresAt", "role"],
    });
    for (const s of snaps) out.set(s.id, s.exists ? s.data() || {} : null);
  }
  return out;
}

async function montar(db, uid, meses) {
  const agora = Date.now();
  const [{ lista, limiteAtingido }, custos] = await Promise.all([
    lerPagamentos(db),
    lerCustos(db, uid),
  ]);
  const r = agregar({ pagamentos: lista, custos: custos.itens, agora, meses });

  const top = r.usuarios.slice(0, TOP_USUARIOS);
  const perfis = await lerPerfis(
    db,
    top.map((u) => u.uid).filter((u) => u !== SEM_USUARIO),
  );
  for (const u of top) {
    if (u.uid === SEM_USUARIO) {
      u.nome = "Pagamentos sem usuário identificado";
      u.existe = true;
      continue;
    }
    const p = perfis.get(u.uid);
    u.existe = !!p;
    u.nome = p ? String(p.name || p.displayName || "").trim() : "";
    if (p && p.email) u.email = String(p.email).trim();
    u.planoConta = p ? String(p.plan || "") : "";
    u.vence = p ? ms(p.licenseExpiresAt) : 0;
  }

  let usuariosBase = 0;
  try {
    usuariosBase = (await db.collection("users").count().get()).data().count || 0;
  } catch (e) {
    console.warn("[ctAdminResultado] count users", e.message);
  }

  return {
    geradoEm: agora,
    mesesPedidos: meses,
    meses: r.meses,
    mesAtual: r.mesAtual,
    total: r.total,
    custos: { ...custos, totalMensal: r.custoFixoMes },
    usuarios: top,
    usuariosComPagamento: r.usuarios.length,
    usuariosBase,
    limiteAtingido,
    taxas: { pix: TAXA_PIX, cartao: TAXA_CARTAO },
  };
}

exports.ctAdminResultado = onCall(
  { region: REGIAO, timeoutSeconds: 120, memory: "512MiB", cors: true },
  async (req) => {
    await requireAdminLevel(req, ["admin", "financeiro"]);
    const uid = req.auth.uid;
    const db = admin.firestore();
    const data = req.data || {};
    const acao = String(data.acao || "resumo");

    if (acao === "salvarCustos") {
      const itens = limparCustos(data.itens);
      await db.doc(CUSTOS_DOC).set({
        itens,
        atualizadoEm: admin.firestore.FieldValue.serverTimestamp(),
        atualizadoPor: uid,
      });
      // Os resumos em cache (aqui e na previsão) ficaram velhos.
      const caches = await db
        .collection("admin_stats")
        .where(admin.firestore.FieldPath.documentId(), ">=", "resultado_")
        .where(admin.firestore.FieldPath.documentId(), "<", "resultado_~")
        .select()
        .get();
      await Promise.all([
        ...caches.docs.map((d) => d.ref.delete()),
        db.doc("admin_stats/previsao_receita").delete(),
      ]);
      const total = itens.reduce((s, c) => s + c.valorMensal, 0);
      await logAdmin(
        req,
        "Custos fixos do app",
        `${itens.length} item(ns), R$ ${total.toFixed(2)}/mês`,
      );
      return { ok: true, itens, totalMensal: cent(total) };
    }

    if (acao !== "resumo") throw new HttpsError("invalid-argument", "Ação inválida.");
    const meses = Math.min(24, Math.max(1, Math.trunc(num(data.meses, 12)) || 12));
    const forcar = data.forcar === true;
    const ref = db.doc(`admin_stats/resultado_${meses}`);
    if (!forcar) {
      try {
        const s = await ref.get();
        const c = s.exists ? s.data() || {} : {};
        if (c.json && Date.now() - num(c.geradoEm) < CACHE_MS) {
          return { ...JSON.parse(c.json), doCache: true };
        }
      } catch (e) {
        console.warn("[ctAdminResultado] cache ilegível, refazendo", e.message);
      }
    }
    let r;
    try {
      r = await montar(db, uid, meses);
    } catch (e) {
      console.error("[ctAdminResultado]", e);
      throw new HttpsError("internal", "Não foi possível calcular agora.");
    }
    try {
      await ref.set({ geradoEm: r.geradoEm, json: JSON.stringify(r), geradoPor: uid });
    } catch (e) {
      console.warn("[ctAdminResultado] não gravou o cache", e.message);
    }
    return { ...r, doCache: false };
  },
);

// Funções puras / leitores reaproveitados pela previsão e pelos testes.
exports._normalizarPagamento = normalizarPagamento;
exports._rotuloPlano = rotuloPlano;
exports._limparCustos = limparCustos;
exports._agregar = agregar;
exports._ultimosMeses = ultimosMeses;
exports._chaveMes = chaveMes;
exports._lerPagamentos = lerPagamentos;
exports._lerCustos = lerCustos;
exports._ms = ms;
exports._cent = cent;
exports._num = num;
