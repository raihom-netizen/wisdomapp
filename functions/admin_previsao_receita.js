"use strict";

/**
 * `ctAdminPrevisaoReceita` — «Previsão & planos» com receita REAL, do Painel
 * Admin do WISDOMAPP (porte do Controle Total, 02/10/2026).
 *
 * O card antigo multiplicava «todo premium» × preço mensal — mas premium em
 * teste/cortesia/convênio não paga. Aqui só entra quem PAGA de verdade:
 *
 *  - pagante ativo   = tem pagamento de licença aprovado em `mp_payments` e a
 *                      licença (`users.licenseExpiresAt`) vale hoje;
 *  - pagante vencido = já pagou, mas a licença venceu (não renovou);
 *  - App Store (iOS) = `users.lastIosIapProductId` preenchido; a Apple não
 *                      manda o valor, então a receita é ESTIMADA pelo preço do
 *                      checkout (`app_config/mp_checkout_prices`) e fica à
 *                      parte do MRR real;
 *  - licença sem pagamento (teste, cortesia, convênio) = contagem, fora da
 *                      previsão.
 *
 * Valor de cada pagante = o que ele PAGOU no último pagamento de licença,
 * convertido para mês (anual ÷ 12). Custo do mês = custos fixos do admin
 * (`admin_stats/custos_fixos`, mesmos do «Receitas & Despesas») + taxa média
 * do Mercado Pago observada nos pagamentos.
 *
 * Não lê `users` inteiro: perfis só dos pagantes (getAll com fieldMask),
 * iOS por consulta com teto e o resto por `count()`. Cache de 10 min em
 * `admin_stats/previsao_receita`; `{forcar: true}` refaz. `{resumo: true}`
 * devolve só o bloco `resumo` (usado pelo card do Dashboard).
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const { requireAdminLevel } = require("./admin_auth");
const {
  _lerPagamentos: lerPagamentos,
  _lerCustos: lerCustos,
  _rotuloPlano: rotuloPlano,
  _ms: ms,
  _cent: cent,
  _num: num,
} = require("./admin_resultado");

const REGIAO = "us-central1";
const CACHE_DOC = "admin_stats/previsao_receita";
const CACHE_MS = 10 * 60 * 1000;
const DIA = 86400000;
const FUSO_MS = 3 * 3600000;
const LIMITE_IOS = 2000;
const LISTA_MAX = 300;

/** Mesmo padrão do servidor (`MP_PRICE_BY_PLAN_DEFAULT` no index.js). */
const PRECO_PADRAO = {
  premium_monthly: 14.99,
  premium_annual: 169.9,
  premium_pro_monthly: 25.9,
  premium_pro_annual: 299.9,
  extra_bank_connection_monthly: 5.9,
  extra_bank_connection_annual: 59.9,
};

function precoCampo(v) {
  if (v == null || v === "") return null;
  if (typeof v === "number") return Number.isFinite(v) && v > 0 ? v : null;
  const n = Number(String(v).trim().replace(/\s/g, "").replace(",", "."));
  return Number.isFinite(n) && n > 0 ? n : null;
}

/** Plano/ciclo do pagamento: id estável + se é licença + dias cobertos. */
function planoDoPagamento(p) {
  const c = String(p.planCode || "").toLowerCase();
  const anual = c.includes("annual") || c.includes("anual") || c.includes("year");
  if (p.entitlementType === "extra_bank_connection" || c.includes("extra_bank")) {
    return { id: anual ? "extra_banco_anual" : "extra_banco_mensal", licenca: false, dias: anual ? 365 : 30 };
  }
  if (c.includes("premium_pro") || c === "pro") {
    return { id: anual ? "premium_pro_anual" : "premium_pro_mensal", licenca: true, dias: anual ? 365 : 30 };
  }
  return { id: anual ? "premium_anual" : "premium_mensal", licenca: true, dias: anual ? 365 : 30 };
}

const ROTULO = {
  premium_mensal: "Premium mensal",
  premium_anual: "Premium anual",
  premium_pro_mensal: "Premium PRO mensal",
  premium_pro_anual: "Premium PRO anual",
  extra_banco_mensal: "Conexão bancária extra (mensal)",
  extra_banco_anual: "Conexão bancária extra (anual)",
};

function fimDoMes(agora) {
  const b = new Date(agora - FUSO_MS);
  return Date.UTC(b.getUTCFullYear(), b.getUTCMonth() + 1, 1) + FUSO_MS;
}
function inicioDoMes(agora) {
  const b = new Date(agora - FUSO_MS);
  return Date.UTC(b.getUTCFullYear(), b.getUTCMonth(), 1) + FUSO_MS;
}

/**
 * Agregação pura (testável sem Firestore).
 * @param {object} p
 * @param {Array} p.pagamentos  normalizados (admin_resultado._normalizarPagamento)
 * @param {Map|Object} p.perfis uid → dados do users (ou null = conta apagada)
 * @param {Array} p.ios         [{uid, plan, licenseExpiresAt, lastIosIapProductId, role}]
 * @param {Object} p.precos     mapa de preços do checkout
 * @param {number} p.custoFixoMes
 * @param {Object} p.contagens  {usuarios, free, licencaValida, convenio}
 * @param {number} p.agora
 */
function agregar({ pagamentos, perfis, ios, precos, custoFixoMes, contagens, agora }) {
  const perfil = (uid) => (perfis instanceof Map ? perfis.get(uid) : perfis[uid]);
  const iniMes = inicioDoMes(agora);
  const fimMes = fimDoMes(agora);
  const em30 = agora + 30 * DIA;
  const desde12m = agora - 365 * DIA;

  // Pagamentos aprovados por uid (estornos ficam fora da previsão).
  const porUid = new Map();
  let semDono = 0;
  let bruto12m = 0;
  let taxa12m = 0;
  for (const p of pagamentos) {
    if (p.estorno) continue;
    if (p.quando >= desde12m) {
      bruto12m += p.bruto;
      taxa12m += p.taxa;
    }
    if (!p.uid) {
      semDono += 1;
      continue;
    }
    if (!porUid.has(p.uid)) porUid.set(p.uid, []);
    porUid.get(p.uid).push({ ...p, plano: planoDoPagamento(p) });
  }
  const taxaMedia = bruto12m > 0 ? taxa12m / bruto12m : 0.03;

  const planos = {};
  const pl = (id) =>
    (planos[id] ||= {
      id,
      rotulo: ROTULO[id] || id,
      ativos: 0,
      vencidos: 0,
      mrr: 0,
      renovam30: 0,
      valorRenovam30: 0,
      aReceberMes: 0,
      pagoMes: 0,
      pagoTotal: 0,
    });

  const linhas = [];
  let pagoContasApagadas = 0;
  const cont = { pagante_ativo: 0, pagante_vencido: 0, equipe: 0 };
  for (const [uid, lista] of porUid) {
    lista.sort((a, b) => b.quando - a.quando);
    for (const p of lista) {
      const x = pl(p.plano.id);
      x.pagoTotal += p.bruto;
      if (p.quando >= iniMes && p.quando < fimMes) x.pagoMes += p.bruto;
    }
    const d = perfil(uid);
    if (d === undefined || d === null) {
      pagoContasApagadas += lista.reduce((a, p) => a + p.bruto, 0);
      continue;
    }
    const lic = lista.filter((p) => p.plano.licenca);
    const ultimo = lic[0] || null;
    const role = String(d.role || "").toLowerCase();
    const vence = ms(d.licenseExpiresAt) || ms(d.licenseValidUntilIncludingGrace);
    let classe;
    if (role === "admin" || role === "master") classe = "equipe";
    else if (!ultimo) classe = "so_adicional";
    else if (vence >= agora) classe = "pagante_ativo";
    else classe = "pagante_vencido";
    if (cont[classe] !== undefined) cont[classe] += 1;

    const mensal = ultimo ? (ultimo.bruto / ultimo.plano.dias) * 30 : 0;
    if (ultimo) {
      const x = pl(ultimo.plano.id);
      if (classe === "pagante_ativo") {
        x.ativos += 1;
        x.mrr += mensal;
        if (vence <= em30) {
          x.renovam30 += 1;
          x.valorRenovam30 += ultimo.bruto;
        }
        if (vence < fimMes) x.aReceberMes += ultimo.bruto;
      } else if (classe === "pagante_vencido") {
        x.vencidos += 1;
      }
    }
    linhas.push({
      uid,
      nome: String(d.name || d.displayName || "").trim(),
      email: String(d.email || (lista[0] && lista[0].email) || "").trim(),
      classe,
      planoConta: String(d.plan || ""),
      plano: ultimo ? ultimo.plano.id : "",
      rotuloPlano: ultimo ? ROTULO[ultimo.plano.id] : rotuloPlano(lista[0].planCode, lista[0].entitlementType),
      ultimoPagamento: ultimo ? ultimo.quando : lista[0].quando,
      ultimoValor: cent(ultimo ? ultimo.bruto : 0),
      mensalEquivalente: cent(mensal),
      vence,
      pagamentos: lista.length,
      totalPago: cent(lista.reduce((a, p) => a + p.bruto, 0)),
      ios: !!d.lastIosIapProductId,
    });
  }

  // iOS (App Store): estimativa pelo preço do checkout; não duplica quem já
  // é pagante ativo pelo Mercado Pago.
  const ativosMp = new Set(linhas.filter((l) => l.classe === "pagante_ativo").map((l) => l.uid));
  const precoMensal = num(precos.premium_monthly, PRECO_PADRAO.premium_monthly);
  const precoAnual = num(precos.premium_annual, PRECO_PADRAO.premium_annual);
  const iosR = { ativos: 0, vencidos: 0, mensais: 0, anuais: 0, mrrEstimado: 0, renovam30: 0 };
  for (const u of ios || []) {
    const role = String(u.role || "").toLowerCase();
    if (role === "admin" || role === "master") continue;
    if (ativosMp.has(u.uid)) continue;
    const vence = ms(u.licenseExpiresAt);
    const anual = String(u.lastIosIapProductId || "").toLowerCase().includes("annual");
    if (vence >= agora) {
      iosR.ativos += 1;
      if (anual) {
        iosR.anuais += 1;
        iosR.mrrEstimado += precoAnual / 12;
      } else {
        iosR.mensais += 1;
        iosR.mrrEstimado += precoMensal;
      }
      if (vence <= em30) iosR.renovam30 += 1;
    } else {
      iosR.vencidos += 1;
    }
  }

  const listaPlanos = Object.values(planos)
    .map((p) => ({
      ...p,
      licenca: !p.id.startsWith("extra_banco"),
      mrr: cent(p.mrr),
      valorRenovam30: cent(p.valorRenovam30),
      aReceberMes: cent(p.aReceberMes),
      pagoMes: cent(p.pagoMes),
      pagoTotal: cent(p.pagoTotal),
    }))
    .sort((a, b) => b.mrr - a.mrr || b.pagoTotal - a.pagoTotal);

  const mrr = listaPlanos.reduce((a, p) => a + p.mrr, 0);
  const pagoMesLicenca = listaPlanos.filter((p) => p.licenca).reduce((a, p) => a + p.pagoMes, 0);
  const pagoMesTotal = listaPlanos.reduce((a, p) => a + p.pagoMes, 0);
  const aReceberMes = listaPlanos.reduce((a, p) => a + p.aReceberMes, 0);
  const renovam30 = listaPlanos.reduce((a, p) => a + p.valorRenovam30, 0);
  const receitaPrevistaMes = pagoMesTotal + aReceberMes;
  const taxaPrevista = receitaPrevistaMes * taxaMedia;
  const c = contagens || {};
  const ativos = cont.pagante_ativo;
  const semPagamento = Math.max(0, num(c.licencaValida) - ativos - iosR.ativos);

  linhas.sort(
    (a, b) =>
      (a.classe === "pagante_ativo" ? 0 : 1) - (b.classe === "pagante_ativo" ? 0 : 1) ||
      (a.classe === "pagante_ativo" ? a.vence - b.vence : b.ultimoPagamento - a.ultimoPagamento),
  );

  return {
    resumo: {
      pagantesAtivos: ativos,
      pagantesVencidos: cont.pagante_vencido,
      equipeComPagamento: cont.equipe,
      iosAtivos: iosR.ativos,
      iosVencidos: iosR.vencidos,
      usuarios: num(c.usuarios),
      free: num(c.free),
      licencaValida: num(c.licencaValida),
      licencaSemPagamento: semPagamento,
      convenio: num(c.convenio),
      mrr: cent(mrr),
      arr: cent(mrr * 12),
      iosMrrEstimado: cent(iosR.mrrEstimado),
      pagoMesLicenca: cent(pagoMesLicenca),
      pagoMesTotal: cent(pagoMesTotal),
      aReceberMes: cent(aReceberMes),
      receitaPrevistaMes: cent(receitaPrevistaMes),
      renovam30: cent(renovam30),
      ticketMedio: ativos ? cent(mrr / ativos) : 0,
      taxaMediaMp: Math.round(taxaMedia * 10000) / 100,
      taxaPrevistaMes: cent(taxaPrevista),
      custoFixoMes: cent(custoFixoMes),
      custoMes: cent(custoFixoMes + taxaPrevista),
      lucroPrevistoMes: cent(receitaPrevistaMes - taxaPrevista - custoFixoMes),
      pagoContasApagadas: cent(pagoContasApagadas),
      pagamentosSemDono: semDono,
    },
    planos: listaPlanos,
    ios: { ...iosR, mrrEstimado: cent(iosR.mrrEstimado), precoMensal, precoAnual },
    usuarios: linhas.slice(0, LISTA_MAX),
    usuariosTotal: linhas.length,
  };
}

async function lerPrecos(db) {
  const out = { ...PRECO_PADRAO };
  try {
    const s = await db.doc("app_config/mp_checkout_prices").get();
    const d = s.exists ? s.data() || {} : {};
    for (const k of Object.keys(out)) {
      const v = precoCampo(d[k]);
      if (v != null) out[k] = v;
    }
  } catch (e) {
    console.warn("[ctAdminPrevisaoReceita] preços", e.message);
  }
  return out;
}

async function contar(q) {
  try {
    return (await q.count().get()).data().count || 0;
  } catch (e) {
    console.warn("[ctAdminPrevisaoReceita] count", e.message);
    return 0;
  }
}

async function montar(db, uid) {
  const agora = Date.now();
  const users = db.collection("users");
  const [{ lista, limiteAtingido }, custos, precos, iosSnap, usuarios, free, licencaValida, convenio] =
    await Promise.all([
      lerPagamentos(db),
      lerCustos(db, uid),
      lerPrecos(db),
      users
        .where("lastIosIapProductId", ">", "")
        .select("lastIosIapProductId", "licenseExpiresAt", "plan", "role")
        .limit(LIMITE_IOS)
        .get(),
      contar(users),
      contar(users.where("plan", "==", "free")),
      contar(users.where("licenseExpiresAt", ">=", admin.firestore.Timestamp.fromMillis(agora))),
      contar(users.where("partnershipId", ">", "")),
    ]);

  const uids = [...new Set(lista.filter((p) => p.uid && !p.estorno).map((p) => p.uid))];
  const perfis = new Map();
  for (let i = 0; i < uids.length; i += 100) {
    const refs = uids.slice(i, i + 100).map((u) => db.doc(`users/${u}`));
    const snaps = await db.getAll(...refs, {
      fieldMask: [
        "name",
        "displayName",
        "email",
        "plan",
        "role",
        "licenseExpiresAt",
        "licenseValidUntilIncludingGrace",
        "lastIosIapProductId",
      ],
    });
    for (const s of snaps) perfis.set(s.id, s.exists ? s.data() || {} : null);
  }

  const ios = iosSnap.docs.map((d) => ({ uid: d.id, ...(d.data() || {}) }));
  const custoFixoMes = custos.itens.reduce((s, c) => s + num(c.valorMensal), 0);
  const r = agregar({
    pagamentos: lista,
    perfis,
    ios,
    precos,
    custoFixoMes,
    contagens: { usuarios, free, licencaValida, convenio },
    agora,
  });
  return {
    geradoEm: agora,
    mes: new Date(agora - FUSO_MS).toISOString().slice(0, 7),
    ...r,
    precos,
    custosOrigem: custos.origem,
    limiteAtingido,
    iosLimiteAtingido: iosSnap.size >= LIMITE_IOS,
  };
}

exports.ctAdminPrevisaoReceita = onCall(
  { region: REGIAO, timeoutSeconds: 120, memory: "512MiB", cors: true },
  async (req) => {
    await requireAdminLevel(req, ["admin", "financeiro"]);
    const uid = req.auth.uid;
    const db = admin.firestore();
    const data = req.data || {};
    const forcar = data.forcar === true;
    const soResumo = data.resumo === true;
    const recorte = (r) =>
      soResumo
        ? { geradoEm: r.geradoEm, mes: r.mes, resumo: r.resumo, doCache: r.doCache }
        : r;
    const ref = db.doc(CACHE_DOC);
    if (!forcar) {
      try {
        const s = await ref.get();
        const c = s.exists ? s.data() || {} : {};
        if (c.json && Date.now() - num(c.geradoEm) < CACHE_MS) {
          return recorte({ ...JSON.parse(c.json), doCache: true });
        }
      } catch (e) {
        console.warn("[ctAdminPrevisaoReceita] cache ilegível, refazendo", e.message);
      }
    }
    let r;
    try {
      r = await montar(db, uid);
    } catch (e) {
      console.error("[ctAdminPrevisaoReceita]", e);
      throw new HttpsError("internal", "Não foi possível calcular a previsão agora.");
    }
    try {
      await ref.set({ geradoEm: r.geradoEm, json: JSON.stringify(r), geradoPor: uid });
    } catch (e) {
      console.warn("[ctAdminPrevisaoReceita] não gravou o cache", e.message);
    }
    return recorte({ ...r, doCache: false });
  },
);

exports._agregar = agregar;
exports._planoDoPagamento = planoDoPagamento;
