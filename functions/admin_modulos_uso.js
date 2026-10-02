/**
 * `ctAdminModulosUso` — painel «Uso dos módulos» do admin do WISDOMAPP
 * (porte do Controle Total, 02/10/2026, adaptado aos módulos daqui).
 *
 * Um item por módulo (financeiro, contas fixas, carteiras, objetivos, agenda,
 * escalas, produtividade, orçamentos, locais, cursos) com quantos e quais
 * usuários usam, registros, últimos 30 dias e último uso por usuário; mais
 * `financeiroTotais` (receitas x despesas realizadas, pendentes e futuras) e
 * `atividade` (último acesso do app por usuário: hoje / 7 / 30 dias e
 * plataforma, de `users.clientTelemetry`).
 *
 * Só admin/master (o painel esconde de gestor/sócio/editor). Lê pelo Admin
 * SDK com `collectionGroup(...).select(...)` (só os campos usados). O
 * resultado fica em `admin_stats/modulos_uso` por 10 min — `{forcar: true}`
 * refaz a leitura. A coleção `admin_stats` não tem regra no Firestore: só o
 * servidor lê/grava.
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const { requireAdminLevel } = require("./admin_auth");

const REGIAO = "us-central1";
const CACHE_DOC = "admin_stats/modulos_uso";
const CACHE_MS = 10 * 60 * 1000;
const DIA = 86400000;

/** Acima disso o lançamento é tratado como valor de teste (fora das somas). */
const VALOR_MAXIMO = 10000000;

// 02/10/2026: tetos de leitura — antes lia `users`, cada collectionGroup e
// TODAS as `transactions` sem limite. Contagens totais saem por `count()`
// (sem baixar documento); listas por usuário usam os mais recentes até o teto
// e o resultado diz `parcial: true` quando bateu nele.
const LIMITE_USUARIOS = 5000;
const LIMITE_POR_COLECAO = 15000;
const LIMITE_TRANSACOES = 30000;
const LIMITE_VIEWERS = 10000;

const round2 = (n) => Math.round((Number(n) || 0) * 100) / 100;

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

/** Lê até [limite] docs (sem orderBy: ordenar por um campo descartaria os
 *  documentos que não o têm). */
function lerComTeto(q, limite) {
  return q.limit(limite).get();
}

async function contarDocs(q) {
  try {
    const a = await q.count().get();
    return a.data().count || 0;
  } catch (e) {
    console.warn("[ctAdminModulosUso] count falhou", e.message);
    return null;
  }
}

/**
 * uid dono de um doc pelo caminho: `users/{uid}/<sub>/{id}` (profundidade 4)
 * ou, com `aninhado`, `users/{uid}/<pai>/{id}/<sub>/{id}` (6). Ignora
 * coleções homônimas fora de `users`.
 */
function uidPeloCaminho(doc, aninhado) {
  const seg = doc.ref.path.split("/");
  if (seg[0] !== "users") return "";
  if (aninhado) {
    if (seg.length !== 6 || seg[2] !== aninhado) return "";
  } else if (seg.length !== 4) {
    return "";
  }
  return seg[1];
}

/** Catálogo dos módulos do WISDOMAPP medidos por subcoleção de users/{uid}. */
const CATALOGO = [
  {
    id: "contas_fixas",
    titulo: "Contas fixas",
    descricao: "Despesas e receitas fixas/parceladas",
    colecoes: [{ nome: "fixed_expenses" }, { nome: "fixed_incomes" }],
  },
  {
    id: "carteiras",
    titulo: "Contas e carteiras",
    descricao: "Bancos, cartões e cofres do Financeiro",
    colecoes: [{ nome: "finance_accounts" }],
  },
  {
    id: "objetivos",
    titulo: "Objetivos financeiros",
    descricao: "Objetivos e depósitos (desafios, 52 semanas…)",
    colecoes: [{ nome: "goals" }, { nome: "contributions", aninhado: "goals" }],
  },
  {
    id: "orcamentos",
    titulo: "Orçamentos",
    descricao: "Orçamentos, modelos e planejamentos",
    colecoes: [{ nome: "quotes" }, { nome: "budgets" }, { nome: "budget_templates" }],
  },
  {
    id: "agenda",
    titulo: "Agenda / compromissos",
    descricao: "Compromissos e lembretes da Agenda",
    colecoes: [{ nome: "reminders" }],
  },
  {
    id: "escalas",
    titulo: "Escalas / plantões",
    descricao: "Plantões e escalas (sem compromissos espelhados)",
    colecoes: [
      { nome: "scales", campos: ["isCompromisso"], filtro: (d) => d.isCompromisso !== true },
    ],
  },
  {
    id: "produtividade",
    titulo: "Produtividade / folgas",
    descricao: "Ocorrências com pontuação e folgas",
    colecoes: [{ nome: "ocorrencias" }],
  },
  {
    id: "locais",
    titulo: "Locais",
    descricao: "Locais salvos (plantão, trabalho…)",
    colecoes: [{ nome: "locations" }],
  },
];

/** Quando o registro foi feito: criado > alterado > data do item (se já passou). */
function quandoDoc(d, agora) {
  const criado = ms(d.createdAt) || ms(d.updatedAt) || ms(d.timestamp);
  if (criado) return criado;
  const data = ms(d.date) || ms(d.data);
  return data && data <= agora ? data : 0;
}

async function montar(db) {
  const agora = Date.now();
  const limite30 = agora - 30 * DIA;
  const porModulo = {};
  const linha = (mod, uid) =>
    ((porModulo[mod] ||= {})[uid] ||= { qtd: 0, ultimos30: 0, ultima: 0 });
  const contar = (g, quando) => {
    g.qtd += 1;
    if (quando >= limite30 && quando <= agora + DIA) g.ultimos30 += 1;
    if (quando > g.ultima && quando <= agora + DIA) g.ultima = quando;
  };
  const camposBase = ["createdAt", "updatedAt", "timestamp", "date", "data"];

  // Uma leitura por nome de coleção.
  const leituras = {};
  const ler = (nome, campos) => {
    leituras[nome] ||= new Set(camposBase);
    for (const c of campos || []) leituras[nome].add(c);
  };
  for (const m of CATALOGO) for (const c of m.colecoes) ler(c.nome, c.campos);
  ler("transactions", ["type", "amount", "status", "transferPairId", "goalReserve"]);
  const nomes = Object.keys(leituras);
  const tetoDe = (n) => (n === "transactions" ? LIMITE_TRANSACOES : LIMITE_POR_COLECAO);
  const [usuariosSnap, viewersSnap, ...snaps] = await Promise.all([
    lerComTeto(
      db
        .collection("users")
        .select("name", "displayName", "email", "role", "plan", "createdAt", "clientTelemetry"),
      LIMITE_USUARIOS,
    ),
    db
      .collectionGroup("viewers")
      .select("lastActivityAt", "lastWatchedAt", "updatedAt", "createdAt")
      .limit(LIMITE_VIEWERS)
      .get(),
    ...nomes.map((n) =>
      lerComTeto(db.collectionGroup(n).select(...leituras[n]), tetoDe(n)),
    ),
  ]);
  const snapDe = Object.fromEntries(nomes.map((n, i) => [n, snaps[i]]));
  // Totais reais (sem baixar documentos) e onde a leitura bateu no teto.
  const [totalUsuarios, ...totaisColecao] = await Promise.all([
    contarDocs(db.collection("users")),
    ...nomes.map((n) => contarDocs(db.collectionGroup(n))),
  ]);
  const limites = {
    usuarios: { lidos: usuariosSnap.size, total: totalUsuarios, teto: LIMITE_USUARIOS },
    viewers: { lidos: viewersSnap.size, teto: LIMITE_VIEWERS },
  };
  nomes.forEach((n, i) => {
    limites[n] = { lidos: snapDe[n].size, total: totaisColecao[i], teto: tetoDe(n) };
  });
  const parcial = Object.values(limites).some((l) => l.lidos >= l.teto);

  // ── Pessoas + atividade (último acesso do app) ────────────────────────────
  const usuarios = {};
  const atividade = {
    hoje: 0,
    dias7: 0,
    dias30: 0,
    semRegistro: 0,
    total: 0,
    plataformas: {},
    versoes: {},
  };
  const inicioHoje = (() => {
    const b = new Date(agora - 3 * 3600000); // Brasília
    return Date.UTC(b.getUTCFullYear(), b.getUTCMonth(), b.getUTCDate()) + 3 * 3600000;
  })();
  for (const u of usuariosSnap.docs) {
    const d = u.data() || {};
    const email = String(d.email || "").trim();
    if (!email) continue;
    const tel = d.clientTelemetry || {};
    const ping = ms(tel.lastPingAt);
    usuarios[u.id] = {
      nome: String(d.name || d.displayName || "").trim(),
      email,
      plano: String(d.plan || ""),
      ultimoAcesso: ping,
      plataforma: String(tel.platform || ""),
    };
    atividade.total += 1;
    if (!ping) {
      atividade.semRegistro += 1;
      continue;
    }
    if (ping >= inicioHoje) atividade.hoje += 1;
    if (ping >= agora - 7 * DIA) atividade.dias7 += 1;
    if (ping >= limite30) {
      atividade.dias30 += 1;
      const p = String(tel.platform || "outro");
      atividade.plataformas[p] = (atividade.plataformas[p] || 0) + 1;
      const v = String(tel.appVersion || "").trim();
      if (v) atividade.versoes[v] = (atividade.versoes[v] || 0) + 1;
    }
  }

  // ── Módulos por subcoleção ────────────────────────────────────────────────
  for (const m of CATALOGO) {
    for (const c of m.colecoes) {
      for (const doc of snapDe[c.nome].docs) {
        const uid = uidPeloCaminho(doc, c.aninhado);
        if (!uid) continue;
        const d = doc.data() || {};
        if (c.filtro && !c.filtro(d)) continue;
        contar(linha(m.id, uid), quandoDoc(d, agora));
      }
    }
  }

  // ── Cursos: course_stats/{curso}/viewers/{uid} ────────────────────────────
  for (const v of viewersSnap.docs) {
    const seg = v.ref.path.split("/");
    if (seg[0] !== "course_stats" || seg.length !== 4) continue;
    const d = v.data() || {};
    const quando = ms(d.lastActivityAt) || ms(d.lastWatchedAt) || ms(d.updatedAt) || ms(d.createdAt);
    contar(linha("cursos", v.id), quando);
  }

  // ── Financeiro: receitas x despesas por usuário ───────────────────────────
  const hoje = new Date(agora - 3 * 3600000);
  const mesAtual = hoje.toISOString().slice(0, 7);
  const zerado = () => ({
    receitas: 0,
    despesas: 0,
    receitasPendentes: 0,
    despesasPendentes: 0,
    receitasFuturas: 0,
    despesasFuturas: 0,
    receitasMes: 0,
    despesasMes: 0,
    qtdReceitas: 0,
    qtdDespesas: 0,
    transferencias: 0,
    reservasMeta: 0,
    ignorados: 0,
  });
  const tot = zerado();
  for (const doc of snapDe.transactions.docs) {
    const uid = uidPeloCaminho(doc);
    if (!uid) continue;
    const d = doc.data() || {};
    const g = linha("financeiro", uid);
    if (g.receitas === undefined) Object.assign(g, zerado());
    contar(g, quandoDoc(d, agora));
    const valor = Math.abs(Number(d.amount) || 0);
    if (valor > VALOR_MAXIMO) {
      g.ignorados += 1;
      tot.ignorados += 1;
      continue;
    }
    // Transferência entre contas do próprio usuário não é receita nem despesa.
    if (d.transferPairId) {
      g.transferencias += 1;
      tot.transferencias += 1;
      continue;
    }
    // Depósito em meta/objetivo (`goalReserve: true`, 02/10/2026): é reserva
    // que sai da conta, não receita nem despesa de consumo — fica fora das
    // somas de Receitas/Despesas (o saldo da conta no app continua descontando).
    if (d.goalReserve === true) {
      g.reservasMeta += 1;
      tot.reservasMeta += 1;
      continue;
    }
    const pago = String(d.status || "paid") !== "pending";
    const dataMs = ms(d.date);
    const futuro = dataMs > agora;
    const doMes =
      dataMs && new Date(dataMs - 3 * 3600000).toISOString().slice(0, 7) === mesAtual;
    const receita = d.type === "income";
    const R = receita ? "receitas" : "despesas";
    for (const alvo of [g, tot]) {
      alvo[receita ? "qtdReceitas" : "qtdDespesas"] += 1;
      if (futuro) alvo[`${R}Futuras`] += valor;
      else if (pago) alvo[R] += valor;
      else alvo[`${R}Pendentes`] += valor;
      if (doMes && !futuro && pago) alvo[`${R}Mes`] += valor;
    }
  }
  for (const g of [...Object.values(porModulo.financeiro || {}), tot]) {
    for (const k of Object.keys(g)) {
      if (/^(receitas|despesas)/.test(k)) g[k] = round2(g[k]);
    }
    g.saldo = round2(g.receitas - g.despesas);
  }
  tot.usuarios = Object.keys(porModulo.financeiro || {}).length;
  tot.mes = mesAtual;

  const meta = {
    financeiro: ["Financeiro", "Lançamentos de receitas e despesas"],
    cursos: ["Cursos em vídeo", "Quem assistiu aos cursos/dicas em vídeo"],
  };
  for (const m of CATALOGO) meta[m.id] = [m.titulo, m.descricao];
  const ordem = [
    "financeiro",
    "contas_fixas",
    "carteiras",
    "objetivos",
    "orcamentos",
    "agenda",
    "escalas",
    "produtividade",
    "cursos",
    "locais",
  ];
  const modulos = ordem.map((id) => {
    const porUid = porModulo[id] || {};
    const linhas = Object.values(porUid);
    return {
      id,
      titulo: meta[id][0],
      descricao: meta[id][1],
      usuarios: linhas.length,
      ativos30: linhas.filter((l) => l.ultimos30 > 0).length,
      registros: linhas.reduce((a, l) => a + l.qtd, 0),
      registros30: linhas.reduce((a, l) => a + l.ultimos30, 0),
      porUid,
    };
  });
  return {
    geradoEm: agora,
    usuarios,
    modulos,
    financeiroTotais: tot,
    atividade,
    parcial,
    limites,
  };
}

exports.ctAdminModulosUso = onCall(
  { region: REGIAO, timeoutSeconds: 300, memory: "1GiB", cors: true },
  async (req) => {
    const uid = req.auth && req.auth.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Entre na sua conta.");
    const db = admin.firestore();
    // Master (e-mail de dono verificado) ou admin/suporte/financeiro/leitura.
    await requireAdminLevel(req, ["admin", "suporte", "financeiro", "leitura"]);
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
        console.warn("[ctAdminModulosUso] cache ilegível, refazendo", e.message);
      }
    }
    const r = await montar(db);
    // Guardado como texto: o mapa por uid tem milhares de campos e passaria
    // do limite de índices por documento se fosse gravado como mapa.
    try {
      await ref.set({ geradoEm: r.geradoEm, json: JSON.stringify(r), geradoPor: uid });
    } catch (e) {
      console.warn("[ctAdminModulosUso] não gravou o cache", e.message);
    }
    return { ...r, doCache: false };
  },
);

exports._montar = montar;
