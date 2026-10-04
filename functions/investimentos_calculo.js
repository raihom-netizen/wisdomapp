"use strict";

/**
 * Carteira de Investimentos — cálculo PURO (sem Firestore), espelho do
 * `flutter_app/lib/features/investimentos/investimentos_calculo.dart`.
 * Qualquer mudança aqui precisa ir para lá também (e para os dois testes:
 * `teste_investimentos_calculo.js` e `test/investimentos_calculo_test.dart`).
 *
 * São ESTIMATIVAS com as taxas oficiais do Banco Central (SGS): o banco pode
 * arredondar dia a dia de outro jeito e o valor dele variar alguns centavos.
 *
 * Convenções
 *  - Datas sempre em texto «aaaa-mm-dd» (dia civil de Brasília), sem fuso.
 *  - Juros de um dia útil D entram no valor a partir de D+1: a posição na
 *    data X soma os dias úteis do intervalo [início, X).
 *  - Aplicação = lote (data, principal). Resgate consome do lote MAIS ANTIGO
 *    (FIFO), para o IR regressivo de cada lote ficar certo.
 *  - Resgate é o valor LÍQUIDO que caiu na conta (é o que o banco mostra).
 */

// ── Datas ────────────────────────────────────────────────────────────────────

function iso(d) {
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}-${String(d.getUTCDate()).padStart(2, "0")}`;
}

function parseIso(s) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(s || ""));
  if (!m) return null;
  return new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3])));
}

function addDias(s, n) {
  const d = parseIso(s);
  d.setUTCDate(d.getUTCDate() + n);
  return iso(d);
}

/** Soma meses mantendo o dia (31/01 + 1 mês = 28 ou 29/02, como os bancos). */
function addMeses(s, n) {
  const d = parseIso(s);
  const alvoMes = d.getUTCMonth() + n;
  const ano = d.getUTCFullYear() + Math.floor(alvoMes / 12);
  const mes = ((alvoMes % 12) + 12) % 12;
  const ultimo = new Date(Date.UTC(ano, mes + 1, 0)).getUTCDate();
  return iso(new Date(Date.UTC(ano, mes, Math.min(d.getUTCDate(), ultimo))));
}

function diasCorridos(a, b) {
  return Math.round((parseIso(b) - parseIso(a)) / 86400000);
}

function mesDe(s) {
  return String(s).slice(0, 7);
}

function primeiroDoMes(s) {
  return `${mesDe(s)}-01`;
}

/** Domingo de Páscoa (algoritmo de Meeus/Jones/Butcher). */
function pascoa(ano) {
  const a = ano % 19;
  const b = Math.floor(ano / 100);
  const c = ano % 100;
  const d = Math.floor(b / 4);
  const e = b % 4;
  const f = Math.floor((b + 8) / 25);
  const g = Math.floor((b - f + 1) / 3);
  const h = (19 * a + b - d - g + 15) % 30;
  const i = Math.floor(c / 4);
  const k = c % 4;
  const l = (32 + 2 * e + 2 * i - h - k) % 7;
  const m = Math.floor((a + 11 * h + 22 * l) / 451);
  const mes = Math.floor((h + l - 7 * m + 114) / 31);
  const dia = ((h + l - 7 * m + 114) % 31) + 1;
  return iso(new Date(Date.UTC(ano, mes - 1, dia)));
}

const _feriadosCache = new Map();

/** Feriados nacionais (calendário ANBIMA): fixos + Carnaval, Paixão, Corpus Christi. */
function feriadosDoAno(ano) {
  if (_feriadosCache.has(ano)) return _feriadosCache.get(ano);
  const p = pascoa(ano);
  const fixos = ["01-01", "04-21", "05-01", "09-07", "10-12", "11-02", "11-15", "12-25"];
  // Consciência Negra virou feriado nacional em 2024 (Lei 14.759/2023).
  if (ano >= 2024) fixos.push("11-20");
  const set = new Set(fixos.map((x) => `${ano}-${x}`));
  set.add(addDias(p, -48)); // segunda de Carnaval
  set.add(addDias(p, -47)); // terça de Carnaval
  set.add(addDias(p, -2)); // Sexta-feira Santa
  set.add(addDias(p, 60)); // Corpus Christi
  _feriadosCache.set(ano, set);
  return set;
}

function ehDiaUtilCalendario(s) {
  const d = parseIso(s);
  const dow = d.getUTCDay();
  if (dow === 0 || dow === 6) return false;
  return !feriadosDoAno(d.getUTCFullYear()).has(s);
}

// ── Índices (formato gravado em indices_bcb/{serie}) ─────────────────────────

const SERIES = Object.freeze({
  cdi: 12, // CDI diário, % a.d.
  selic: 11, // Selic diária, % a.d.
  ipca: 433, // IPCA mensal, % a.m.
  tr: 226, // TR por período (data → datafim), % no período
  poupanca: 195, // Rentabilidade da poupança por data de aniversário (pós 04/05/2012)
  metaSelic: 432, // Meta Selic do Copom, % a.a.
});

/** Mapa {aaaa-mm-dd: número} a partir do `meses: {aaaa-mm: {dd: valor}}` do doc. */
function mapaDiario(doc) {
  const out = new Map();
  const meses = (doc && doc.meses) || {};
  for (const mes of Object.keys(meses).sort()) {
    const dias = meses[mes] || {};
    for (const dia of Object.keys(dias).sort()) {
      const v = Number(dias[dia]);
      if (Number.isFinite(v)) out.set(`${mes}-${dia}`, v);
    }
  }
  return out;
}

function serieOrdenada(mapa) {
  const chaves = [...mapa.keys()].sort();
  return { mapa, chaves, primeira: chaves[0] || "", ultima: chaves[chaves.length - 1] || "" };
}

/**
 * Índices prontos para o cálculo. `docs` = {12: doc, 11: doc, …} (dados de
 * `indices_bcb/{serie}`); série ausente vira vazia (cálculo cai no padrão).
 */
function montarIndices(docs) {
  const d = docs || {};
  const ipcaMensal = new Map();
  for (const [k, v] of mapaDiario(d[SERIES.ipca])) ipcaMensal.set(k.slice(0, 7), v);
  return {
    cdi: serieOrdenada(mapaDiario(d[SERIES.cdi])),
    selic: serieOrdenada(mapaDiario(d[SERIES.selic])),
    ipca: serieOrdenada(ipcaMensal),
    tr: serieOrdenada(mapaDiario(d[SERIES.tr])),
    poupanca: serieOrdenada(mapaDiario(d[SERIES.poupanca])),
    metaSelic: serieOrdenada(mapaDiario(d[SERIES.metaSelic])),
  };
}

/** Último valor com chave <= k (busca binária); sem nenhum, o primeiro. */
function valorAte(serie, k) {
  const ch = serie.chaves;
  if (!ch.length) return null;
  let lo = 0;
  let hi = ch.length - 1;
  let achou = -1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if (ch[mid] <= k) {
      achou = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return serie.mapa.get(ch[achou >= 0 ? achou : 0]);
}

/**
 * Dia útil: dentro do período publicado da série diária (CDI), vale a própria
 * série — dia com taxa = dia útil; fora dele, o calendário de feriados.
 */
function ehDiaUtil(s, idx) {
  const serie = idx && idx.cdi;
  if (serie && serie.chaves.length && s >= serie.primeira && s <= serie.ultima) {
    return serie.mapa.has(s);
  }
  return ehDiaUtilCalendario(s);
}

/** Dias úteis no intervalo [a, b). */
function diasUteis(a, b, idx) {
  let n = 0;
  for (let s = a; s < b; s = addDias(s, 1)) if (ehDiaUtil(s, idx)) n++;
  return n;
}

/** Taxa diária (% a.d.) da série no dia útil s — dia sem publicação usa a última. */
function taxaDoDia(serie, s) {
  if (!serie || !serie.chaves.length) return null;
  const v = serie.mapa.get(s);
  if (v !== undefined) return v;
  return valorAte(serie, s);
}

// ── Impostos ─────────────────────────────────────────────────────────────────

/** IR regressivo da renda fixa por dias corridos (Lei 11.033/2004). */
function irAliquota(dias) {
  if (dias <= 180) return 22.5;
  if (dias <= 360) return 20;
  if (dias <= 720) return 17.5;
  return 15;
}

/** IOF regressivo (Decreto 6.306/2007, anexo): % do rendimento por dias corridos. */
const TABELA_IOF = [
  100, 96, 93, 90, 86, 83, 80, 76, 73, 70, 66, 63, 60, 56, 53, 50,
  46, 43, 40, 36, 33, 30, 26, 23, 20, 16, 13, 10, 6, 3, 0,
];

function iofAliquota(dias) {
  if (dias >= 30) return 0;
  if (dias < 0) return 100;
  return TABELA_IOF[dias];
}

/** Próxima mudança de faixa do IR (dias corridos), ou null quando já é 15%. */
function proximaFaixaIr(dias) {
  for (const limite of [181, 361, 721]) if (dias < limite) return limite;
  return null;
}

// ── Tipos de aplicação ───────────────────────────────────────────────────────

const TIPOS = Object.freeze({
  cdb: { rotulo: "CDB", indexador: "cdi", isentoIR: false, isentoIOF: false },
  lci: { rotulo: "LCI", indexador: "cdi", isentoIR: true, isentoIOF: false },
  lca: { rotulo: "LCA", indexador: "cdi", isentoIR: true, isentoIOF: false },
  lc: { rotulo: "LC", indexador: "cdi", isentoIR: false, isentoIOF: false },
  caixinha: { rotulo: "Caixinha / cofrinho", indexador: "cdi", isentoIR: false, isentoIOF: false },
  tesouro_selic: { rotulo: "Tesouro Selic", indexador: "selic", isentoIR: false, isentoIOF: false },
  tesouro_prefixado: { rotulo: "Tesouro Prefixado", indexador: "pre", isentoIR: false, isentoIOF: false },
  tesouro_ipca: { rotulo: "Tesouro IPCA+", indexador: "ipca", isentoIR: false, isentoIOF: false },
  poupanca: { rotulo: "Poupança", indexador: "poupanca", isentoIR: true, isentoIOF: true },
  previdencia: { rotulo: "Previdência", indexador: "manual", isentoIR: true, isentoIOF: true, semImposto: true },
  fundo: { rotulo: "Fundo", indexador: "manual", isentoIR: true, isentoIOF: true, semImposto: true },
  acoes: { rotulo: "Ações", indexador: "manual", isentoIR: true, isentoIOF: true, semImposto: true },
  fii: { rotulo: "FII", indexador: "manual", isentoIR: true, isentoIOF: true, semImposto: true },
  outro: { rotulo: "Outro", indexador: "manual", isentoIR: true, isentoIOF: true, semImposto: true },
});

const INDEXADORES = ["cdi", "selic", "pre", "ipca", "poupanca", "manual"];

function infoTipo(tipo) {
  return TIPOS[tipo] || TIPOS.outro;
}

function indexadorDe(inv) {
  const ix = String((inv && inv.indexador) || "");
  return INDEXADORES.includes(ix) ? ix : infoTipo(inv && inv.tipo).indexador;
}

function isentoIR(inv) {
  if (inv && typeof inv.isentoIR === "boolean") return inv.isentoIR;
  return infoTipo(inv && inv.tipo).isentoIR;
}

function isentoIOF(inv) {
  return infoTipo(inv && inv.tipo).isentoIOF;
}

function num(v) {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

function fmtPct(v) {
  return num(v).toFixed(2).replace(".", ",").replace(/,00$/, "");
}

/** «110% do CDI», «IPCA + 6%», «12,5% a.a.», «Selic», «Poupança», «Valor informado». */
function rotuloTaxa(inv) {
  const t = num(inv && inv.taxa);
  switch (indexadorDe(inv)) {
    case "cdi":
      return `${fmtPct(t || 100)}% do CDI`;
    case "selic":
      return t ? `Selic + ${fmtPct(t)}%` : "Selic";
    case "pre":
      return `${fmtPct(t)}% a.a.`;
    case "ipca":
      return `IPCA + ${fmtPct(t)}%`;
    case "poupanca":
      return "Poupança";
    default:
      return "Valor informado";
  }
}

// ── Poupança ─────────────────────────────────────────────────────────────────

/**
 * Rendimento de UM mês da poupança (Lei 12.703/2012), em %: meta Selic acima
 * de 8,5% a.a. → 0,5% a.m. + TR; senão 70% da meta Selic mensalizada + TR.
 * TR e juros se compõem: (1 + TR)(1 + juros) − 1.
 */
function poupancaMensal(metaSelicAA, trPct) {
  const juros = num(metaSelicAA) > 8.5
    ? 0.5
    : (Math.pow(1 + (0.7 * num(metaSelicAA)) / 100, 1 / 12) - 1) * 100;
  return ((1 + juros / 100) * (1 + num(trPct) / 100) - 1) * 100;
}

/** Taxa do mês da poupança que começa em s: série 195 (oficial) ou a regra. */
function taxaPoupancaEm(s, idx) {
  const oficial = idx && idx.poupanca && idx.poupanca.mapa.get(s);
  if (oficial !== undefined && oficial !== null) return oficial;
  const meta = idx && idx.metaSelic ? valorAte(idx.metaSelic, s) : null;
  const tr = idx && idx.tr ? idx.tr.mapa.get(s) : undefined;
  return poupancaMensal(meta === null ? 10 : meta, tr === undefined ? 0 : tr);
}

/** Aniversário: depósito em 29, 30 ou 31 rende a partir do dia 1º seguinte. */
function inicioPoupanca(s) {
  const d = parseIso(s);
  if (d.getUTCDate() <= 28) return s;
  return iso(new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 1)));
}

// ── Fator de correção ────────────────────────────────────────────────────────

/**
 * Fator de [inicio, fim) para 1 real aplicado em `inicio`.
 *  - cdi:   Π (1 + CDI_d × taxa%)      — capitalizado dia a dia útil
 *  - selic: Π (1 + Selic_d) × (1 + taxa)^(du/252)
 *  - pre:   (1 + taxa)^(du/252)
 *  - ipca:  Π_mês (1 + IPCA_m)^(du no mês / du do mês) × (1 + taxa)^(du/252)
 *  - poupanca: Π (1 + rentabilidade do mês) por aniversário completo
 */
function fator(indexador, taxa, inicio, fim, idx) {
  if (!inicio || !fim || fim <= inicio) return 1;
  const t = num(taxa);
  switch (indexador) {
    case "cdi": {
      const p = (t || 100) / 100;
      let f = 1;
      for (let s = inicio; s < fim; s = addDias(s, 1)) {
        if (!ehDiaUtil(s, idx)) continue;
        const d = taxaDoDia(idx && idx.cdi, s);
        f *= 1 + (num(d) / 100) * p;
      }
      return f;
    }
    case "selic": {
      let f = 1;
      let du = 0;
      for (let s = inicio; s < fim; s = addDias(s, 1)) {
        if (!ehDiaUtil(s, idx)) continue;
        du++;
        f *= 1 + num(taxaDoDia(idx && idx.selic, s)) / 100;
      }
      return f * Math.pow(1 + t / 100, du / 252);
    }
    case "pre":
      return Math.pow(1 + t / 100, diasUteis(inicio, fim, idx) / 252);
    case "ipca": {
      let f = 1;
      let duTotal = 0;
      let mes = primeiroDoMes(inicio);
      while (mes < fim) {
        const proxMes = addMeses(mes, 1);
        const a = inicio > mes ? inicio : mes;
        const b = fim < proxMes ? fim : proxMes;
        const duNoPeriodo = diasUteis(a, b, idx);
        const duDoMes = diasUteis(mes, proxMes, idx) || 1;
        duTotal += duNoPeriodo;
        const ipcaMes = idx && idx.ipca ? valorAte(idx.ipca, mesDe(mes)) : null;
        f *= Math.pow(1 + num(ipcaMes) / 100, duNoPeriodo / duDoMes);
        mes = proxMes;
      }
      return f * Math.pow(1 + t / 100, duTotal / 252);
    }
    case "poupanca": {
      const ini = inicioPoupanca(inicio);
      let f = 1;
      for (let k = 0; ; k++) {
        const s = addMeses(ini, k);
        const prox = addMeses(ini, k + 1);
        if (prox > fim) break;
        f *= 1 + taxaPoupancaEm(s, idx) / 100;
      }
      return f;
    }
    default:
      return 1;
  }
}

// ── Lotes, FIFO e posição ────────────────────────────────────────────────────

function movimentosOrdenados(inv) {
  const lista = Array.isArray(inv && inv.movimentos) ? inv.movimentos : [];
  return lista
    .filter((m) => m && parseIso(m.data) && num(m.valor) > 0)
    .map((m, i) => ({ ...m, _i: i }))
    // Mesmo dia: aplicação antes do resgate.
    .sort((a, b) => (a.data < b.data ? -1 : a.data > b.data ? 1 : (a.tipo === "resgate") - (b.tipo === "resgate") || a._i - b._i));
}

/** Impostos de um lote se resgatado em `data`. */
function impostosDoLote(inv, lote, bruto, data) {
  const rend = bruto - lote.principal;
  const dias = diasCorridos(lote.data, data);
  if (rend <= 0) return { rend, iof: 0, ir: 0, dias };
  const iof = isentoIOF(inv) ? 0 : (rend * iofAliquota(dias)) / 100;
  const ir = isentoIR(inv) ? 0 : ((rend - iof) * irAliquota(dias)) / 100;
  return { rend, iof, ir, dias };
}

/**
 * Consome `liquido` dos lotes (mais antigo primeiro) na `data`. Muda `lotes`
 * no lugar e devolve o que saiu: principal, rendimento bruto, IOF, IR.
 * Valor acima do estimado (o banco pagou um pouco mais) vira `excedente`.
 */
function consumirFifo(inv, lotes, data, liquido, brutoDoLote) {
  let falta = liquido;
  const out = { liquido, principal: 0, rendimento: 0, iof: 0, ir: 0, excedente: 0 };
  for (const lote of lotes) {
    if (falta <= 0.000001) break;
    if (lote.principal <= 0.000001) continue;
    const bruto = brutoDoLote(lote);
    const imp = impostosDoLote(inv, lote, bruto, data);
    const liqLote = bruto - imp.iof - imp.ir;
    if (liqLote <= 0.000001) continue;
    const pega = Math.min(falta, liqLote);
    const frac = pega / liqLote;
    out.principal += lote.principal * frac;
    out.rendimento += imp.rend * frac;
    out.iof += imp.iof * frac;
    out.ir += imp.ir * frac;
    lote.principal -= lote.principal * frac;
    falta -= pega;
  }
  if (falta > 0.005) out.excedente = falta;
  return out;
}

/**
 * Posição da aplicação na `data` (movimentos até essa data).
 * Valor manual (ações, FII, fundo, previdência): o último valor informado
 * (`valorAtual`), repartido entre os lotes pelo principal.
 */
function posicao(inv, idx, data) {
  const ix = indexadorDe(inv);
  const taxa = num(inv && inv.taxa);
  const lotes = [];
  const resgates = [];
  const manual = ix === "manual";
  for (const m of movimentosOrdenados(inv)) {
    if (m.data > data) break;
    if (m.tipo === "resgate") {
      const brutoDoLote = manual
        ? (l) => l.principal
        : (l) => l.principal * fator(ix, taxa, l.data, m.data, idx);
      const r = consumirFifo(inv, lotes, m.data, num(m.valor), brutoDoLote);
      resgates.push({ id: m.id || "", data: m.data, ...r });
    } else {
      lotes.push({ id: m.id || "", data: m.data, principal: num(m.valor), aplicado: num(m.valor) });
    }
  }
  const vivos = lotes.filter((l) => l.principal > 0.000001);
  const investido = vivos.reduce((a, l) => a + l.principal, 0);
  const valorManual = num(inv && inv.valorAtual);
  const out = { data, bruto: 0, investido, rendimento: 0, iof: 0, ir: 0, liquido: 0, lotes: [], resgates };
  for (const l of vivos) {
    const bruto = manual
      ? (valorManual > 0 && investido > 0 ? (valorManual * l.principal) / investido : l.principal)
      : l.principal * fator(ix, taxa, l.data, data, idx);
    const imp = manual ? { rend: bruto - l.principal, iof: 0, ir: 0, dias: diasCorridos(l.data, data) } : impostosDoLote(inv, l, bruto, data);
    out.bruto += bruto;
    out.iof += imp.iof;
    out.ir += imp.ir;
    out.lotes.push({ id: l.id, data: l.data, principal: l.principal, bruto, iof: imp.iof, ir: imp.ir, dias: imp.dias });
  }
  out.rendimento = out.bruto - out.investido;
  out.liquido = out.bruto - out.iof - out.ir;
  return out;
}

/** Aplicações (+) e resgates líquidos (−) com data em (a, b]. */
function fluxoEntre(inv, a, b) {
  let aportes = 0;
  let resgates = 0;
  for (const m of movimentosOrdenados(inv)) {
    if (m.data <= a || m.data > b) continue;
    if (m.tipo === "resgate") resgates += num(m.valor);
    else aportes += num(m.valor);
  }
  return { aportes, resgates };
}

/**
 * Rendimento BRUTO entre as datas a e b (posições), descontando o dinheiro
 * que entrou/saiu: bruto(b) − bruto(a) − aplicações + resgates (+ IR/IOF
 * retidos nos resgates, que também eram rendimento).
 */
function rendimentoEntre(inv, idx, a, b) {
  if (indexadorDe(inv) === "manual") return null;
  const pa = posicao(inv, idx, a);
  const pb = posicao(inv, idx, b);
  const f = fluxoEntre(inv, a, b);
  const retidos = pb.resgates
    .filter((r) => r.data > a && r.data <= b)
    .reduce((s, r) => s + r.iof + r.ir, 0);
  return pb.bruto - pa.bruto - f.aportes + f.resgates + retidos;
}

/** Dia útil anterior a s. */
function diaUtilAnterior(s, idx) {
  let d = addDias(s, -1);
  for (let i = 0; i < 15 && !ehDiaUtil(d, idx); i++) d = addDias(d, -1);
  return d;
}

/**
 * Resumo da aplicação em `hoje`: posição, rendimento do dia (último dia útil),
 * do mês (desde o dia 1º) e acumulado (bruto − investido + o que os resgates
 * já renderam), e os marcos de imposto (IOF zera, IR muda de faixa).
 */
function resumo(inv, idx, hoje) {
  const pos = posicao(inv, idx, hoje);
  const ontemUtil = diaUtilAnterior(hoje, idx);
  const rendDia = indexadorDe(inv) === "manual" ? null : rendimentoEntre(inv, idx, ontemUtil, hoje);
  const rendMes = rendimentoEntre(inv, idx, primeiroDoMes(hoje), hoje);
  const realizado = pos.resgates.reduce((s, r) => s + r.rendimento, 0);
  return {
    ...pos,
    rendDia,
    rendMes,
    rendAcumulado: pos.rendimento + realizado,
    marcos: marcosDeImposto(inv, pos, hoje),
  };
}

/** IOF zerado (30 dias) e mudança de faixa do IR (181/361/721 dias) de cada lote. */
function marcosDeImposto(inv, pos, hoje) {
  const out = [];
  for (const l of pos.lotes || []) {
    if (!isentoIOF(inv) && l.dias < 30) {
      out.push({ tipo: "iof_zero", lote: l.id, data: addDias(l.data, 30) });
    }
    if (!isentoIR(inv)) {
      const prox = proximaFaixaIr(l.dias);
      if (prox) {
        out.push({ tipo: "ir_faixa", lote: l.id, data: addDias(l.data, prox), aliquota: irAliquota(prox) });
      }
    }
  }
  return out.filter((m) => m.data >= hoje).sort((a, b) => (a.data < b.data ? -1 : 1));
}

/**
 * Resgate simulado (sem gravar): quanto do valor LÍQUIDO pedido é principal
 * e quanto é rendimento. `tudo` = resgatar a posição inteira.
 */
function simularResgate(inv, idx, data, liquido, { tudo = false } = {}) {
  const pos = posicao(inv, idx, data);
  const valor = tudo ? pos.liquido : num(liquido);
  // Cópia dos lotes com o bruto de hoje por real de principal.
  const lotes = pos.lotes.map((l) => ({ id: l.id, data: l.data, principal: l.principal, porReal: l.principal > 0 ? l.bruto / l.principal : 1 }));
  const r = consumirFifo(inv, lotes, data, valor, (l) => l.principal * l.porReal);
  // Rendimento LÍQUIDO que chegou = valor − principal devolvido.
  return { ...r, rendimentoLiquido: Math.max(0, valor - r.principal), disponivel: pos.liquido };
}

/**
 * Rentabilidade do mês (em %) de 1 real aplicado no 1º dia do mês, já com o
 * IR da faixa de hoje (aplicações isentas: bruto). Para o aviso «rende menos
 * que a poupança».
 */
function taxaMesLiquida(inv, idx, mesIso, diasDoLoteMaisAntigo) {
  const ix = indexadorDe(inv);
  if (ix === "manual" || ix === "poupanca") return null;
  const ini = primeiroDoMes(mesIso);
  const fim = addMeses(ini, 1);
  const bruto = (fator(ix, inv.taxa, ini, fim, idx) - 1) * 100;
  if (isentoIR(inv)) return bruto;
  return bruto * (1 - irAliquota(diasDoLoteMaisAntigo || 0) / 100);
}

/** Taxa da poupança para o mês (aniversário dia 1º). */
function taxaPoupancaMes(idx, mesIso) {
  return taxaPoupancaEm(primeiroDoMes(mesIso), idx);
}

/**
 * Mesmos movimentos simulados em outro indexador (comparação «se estivesse
 * no CDI 100%» / «na poupança»).
 */
function comoSeFosse(inv, indexador, taxa) {
  return { ...inv, tipo: indexador === "poupanca" ? "poupanca" : "cdb", indexador, taxa, isentoIR: indexador === "poupanca" };
}

/** Bruto no 1º dia de cada mês (fim do mês anterior), dos últimos `n` meses até hoje. */
function evolucaoMensal(inv, idx, hoje, n = 12) {
  const pontos = [];
  let mes = addMeses(primeiroDoMes(hoje), -(n - 1));
  for (let i = 0; i < n; i++) {
    const fimMes = addMeses(mes, 1);
    const data = fimMes > hoje ? hoje : fimMes;
    const p = posicao(inv, idx, data);
    pontos.push({ mes: mesDe(mes), bruto: p.bruto, investido: p.investido, liquido: p.liquido });
    mes = fimMes;
  }
  return pontos;
}

module.exports = {
  SERIES,
  TIPOS,
  INDEXADORES,
  TABELA_IOF,
  iso,
  parseIso,
  addDias,
  addMeses,
  diasCorridos,
  pascoa,
  feriadosDoAno,
  ehDiaUtilCalendario,
  ehDiaUtil,
  diasUteis,
  mapaDiario,
  montarIndices,
  irAliquota,
  iofAliquota,
  proximaFaixaIr,
  infoTipo,
  indexadorDe,
  isentoIR,
  isentoIOF,
  rotuloTaxa,
  poupancaMensal,
  taxaPoupancaEm,
  inicioPoupanca,
  fator,
  posicao,
  rendimentoEntre,
  diaUtilAnterior,
  resumo,
  marcosDeImposto,
  simularResgate,
  taxaMesLiquida,
  taxaPoupancaMes,
  comoSeFosse,
  evolucaoMensal,
};
