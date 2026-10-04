"use strict";

/**
 * Taxas oficiais do Banco Central (API pública SGS) para a Carteira de
 * Investimentos. O app NUNCA chama o BCB: lê `indices_bcb/{serie}` (leitura
 * para logados, escrita só pelo servidor).
 *
 * Séries (conferir em https://www3.bcb.gov.br/sgspub):
 *   12  CDI diário (% a.d.)              11  Selic diária (% a.d.)
 *   433 IPCA mensal (% a.m.)             226 TR (% no período data → datafim)
 *   195 Poupança — rentabilidade por data de aniversário (depósitos após 04/05/2012)
 *   432 Meta Selic do Copom (% a.a.) — regra da poupança quando a 195 ainda não saiu
 *
 * Doc: { serie, nome, meses: { "aaaa-mm": { "dd": valor } }, ultimaData,
 *        primeiraData, atualizadoEm } — um doc por série (≈ 30 KB por 5 anos de
 * série diária), uma leitura por série no app.
 *
 * Agendada em dias úteis às 21h30 (Brasília): o CDI do dia sai no fim da
 * tarde. Busca os últimos 45 dias (cobre correções e o IPCA do mês anterior);
 * série sem doc ainda faz a CARGA INICIAL desde 2019.
 */

const admin = require("firebase-admin");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const C = require("./investimentos_calculo");

const COLECAO = "indices_bcb";
const INICIO_CARGA = "2019-01-01";
const DIAS_ATUALIZACAO = 45;

const NOMES = {
  12: "CDI diário (% a.d.)",
  11: "Selic diária (% a.d.)",
  433: "IPCA mensal (% a.m.)",
  226: "TR (% no período)",
  195: "Poupança — rentabilidade no período (%)",
  432: "Meta Selic Copom (% a.a.)",
};

const SERIES_LISTA = [12, 11, 433, 226, 195, 432];

function dataBr(isoData) {
  const [a, m, d] = isoData.split("-");
  return `${d}/${m}/${a}`;
}

function urlSerie(serie, de, ate) {
  return `https://api.bcb.gov.br/dados/serie/bcdata.sgs.${serie}/dados?formato=json&dataInicial=${dataBr(de)}&dataFinal=${dataBr(ate)}`;
}

/** A API recusa consultas diárias acima de 10 anos — fatia em janelas. */
function janelas(de, ate, anos = 9) {
  const out = [];
  let a = de;
  while (a <= ate) {
    let b = C.addDias(C.addMeses(a, anos * 12), -1);
    if (b > ate) b = ate;
    out.push([a, b]);
    a = C.addDias(b, 1);
  }
  return out;
}

/** Resposta do SGS → { "aaaa-mm": { "dd": número } } (chave = data inicial). */
function paraMeses(json) {
  const meses = {};
  for (const item of Array.isArray(json) ? json : []) {
    const m = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(String((item && item.data) || "").trim());
    if (!m) continue;
    const v = Number(String(item.valor || "").replace(",", "."));
    if (!Number.isFinite(v)) continue;
    const mes = `${m[3]}-${m[2]}`;
    (meses[mes] = meses[mes] || {})[m[1]] = v;
  }
  return meses;
}

function mesclar(velho, novo) {
  const out = {};
  for (const [mes, dias] of Object.entries(velho || {})) out[mes] = { ...dias };
  for (const [mes, dias] of Object.entries(novo || {})) out[mes] = { ...(out[mes] || {}), ...dias };
  return out;
}

function ultimaData(meses) {
  const ms = Object.keys(meses || {}).sort();
  if (!ms.length) return "";
  const mes = ms[ms.length - 1];
  const dias = Object.keys(meses[mes]).sort();
  return `${mes}-${dias[dias.length - 1]}`;
}

function primeiraData(meses) {
  const ms = Object.keys(meses || {}).sort();
  if (!ms.length) return "";
  return `${ms[0]}-${Object.keys(meses[ms[0]]).sort()[0]}`;
}

/** Hoje em Brasília (aaaa-mm-dd). */
function hojeBrasilia(agora = new Date()) {
  return C.iso(new Date(agora.getTime() - 3 * 60 * 60 * 1000));
}

async function buscarJson(url, fetchFn) {
  const f = fetchFn || global.fetch;
  let ultimoErro = null;
  for (let tentativa = 0; tentativa < 3; tentativa++) {
    try {
      const resp = await f(url, { headers: { Accept: "application/json" } });
      // 404 = sem dado no intervalo (ex.: IPCA do mês ainda não saiu).
      if (resp.status === 404) return [];
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
      return await resp.json();
    } catch (e) {
      ultimoErro = e;
      await new Promise((r) => setTimeout(r, 1500 * (tentativa + 1)));
    }
  }
  throw ultimoErro || new Error("falha ao buscar");
}

/** Atualiza uma série: carga inicial (sem doc) ou últimos 45 dias. */
async function atualizarSerie(db, serie, { hoje = hojeBrasilia(), fetchFn } = {}) {
  const ref = db.collection(COLECAO).doc(String(serie));
  const snap = await ref.get();
  const atual = snap.exists ? snap.data() || {} : {};
  const temHistorico = atual.meses && Object.keys(atual.meses).length > 0 && (atual.primeiraData || "") <= INICIO_CARGA.slice(0, 7) + "-31";
  const de = temHistorico ? C.addDias(hoje, -DIAS_ATUALIZACAO) : INICIO_CARGA;
  let novo = {};
  for (const [a, b] of janelas(de, hoje)) {
    novo = mesclar(novo, paraMeses(await buscarJson(urlSerie(serie, a, b), fetchFn)));
  }
  const meses = mesclar(atual.meses || {}, novo);
  await ref.set({
    serie,
    nome: NOMES[serie] || String(serie),
    fonte: "Banco Central do Brasil — SGS",
    meses,
    primeiraData: primeiraData(meses),
    ultimaData: ultimaData(meses),
    atualizadoEm: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { serie, carga: !temHistorico, ultimaData: ultimaData(meses) };
}

async function atualizarTodas(db, opts = {}) {
  const out = [];
  for (const s of SERIES_LISTA) {
    try {
      out.push(await atualizarSerie(db, s, opts));
    } catch (e) {
      console.error(`[indices_bcb] série ${s}:`, (e && e.message) || e);
      out.push({ serie: s, erro: (e && e.message) || String(e) });
    }
  }
  return out;
}

/** Lê os docs das séries e monta os índices do cálculo (cache de 10 min por instância). */
let _cache = null;
async function carregarIndices(db) {
  if (_cache && Date.now() - _cache.em < 10 * 60 * 1000) return _cache.idx;
  const docs = {};
  const snaps = await Promise.all(SERIES_LISTA.map((s) => db.collection(COLECAO).doc(String(s)).get()));
  snaps.forEach((s, i) => {
    if (s.exists) docs[SERIES_LISTA[i]] = s.data();
  });
  const idx = C.montarIndices(docs);
  _cache = { em: Date.now(), idx };
  return idx;
}

const investimentosIndicesBcb = onSchedule(
  {
    schedule: "30 21 * * 1-5",
    timeZone: "America/Sao_Paulo",
    region: "us-central1",
    timeoutSeconds: 300,
    memory: "512MiB",
  },
  async () => {
    const r = await atualizarTodas(admin.firestore());
    console.log("[indices_bcb]", JSON.stringify(r));
  },
);

module.exports = {
  COLECAO,
  SERIES_LISTA,
  urlSerie,
  janelas,
  paraMeses,
  mesclar,
  ultimaData,
  primeiraData,
  hojeBrasilia,
  atualizarSerie,
  atualizarTodas,
  carregarIndices,
  investimentosIndicesBcb,
};
