/**
 * `ctAdminEmailsComProblema` — «E-mails com problema» do Painel Admin do
 * WISDOMAPP (porte do Controle Total, 02/10/2026).
 *
 * No Controle Total a tela lista a supressão (`email_supressao.js`: quem saiu
 * da fila porque a entrega falha). No WISDOMAPP o envio (`sendEmailHtml` em
 * index.js, Gmail SMTP via nodemailer) NÃO registra falha nem bounce em lugar
 * nenhum — só devolve `{ok:false}` e escreve no log. Sem mexer no envio, esta
 * leitura junta tudo o que dá para saber hoje, só lendo:
 *
 *  1. Configuração do envio (`settings/email`): sem usuário/senha de app, TODO
 *     e-mail falha. A senha nunca sai do servidor (só «tem/não tem»).
 *  2. Cadastros (`users`, até 5000, poucos campos): sem e-mail, formato
 *     inválido, domínio com erro de digitação (gmail.con, hotmal.com…),
 *     espaço/maiúscula no endereço, e-mail repetido em mais de um perfil.
 *  3. Login (Firebase Auth, até 5000 contas): e-mail não verificado (só conta
 *     de senha), conta desativada, e-mail do login diferente do cadastro.
 *  4. Avisos da Agenda que não saíram (`users/{uid}/agendaAlerts` com status
 *     `skipped` nos últimos 30 dias, motivo `no_email`/`no_fcm_token`/
 *     `delivery_failed`), pelo índice de grupo (status, notifyAt) que já existe.
 *
 * Permissão: admin/suporte (master sempre). Cache de 10 min em
 * `admin_stats/emails_problema` (`{forcar: true}` refaz). Nada é alterado.
 */

"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const { requireAdminLevel } = require("./admin_auth");

const REGIAO = "us-central1";
const CACHE_DOC = "admin_stats/emails_problema";
const CACHE_MS = 10 * 60 * 1000;
const DIA = 86400000;
const LIMITE_USERS = 5000;
const LIMITE_AUTH_PAGINAS = 5; // 5 × 1000 contas
const LIMITE_ALERTAS = 1000;
const LIMITE_LISTA = 400;
const EMAIL_RX = /^[^@\s]+@[^@\s]+\.[a-z]{2,}$/i;

/** Domínios digitados errado mais comuns → sugestão. */
const DOMINIOS_ERRADOS = {
  "gmail.con": "gmail.com",
  "gmail.co": "gmail.com",
  "gmail.cm": "gmail.com",
  "gmail.om": "gmail.com",
  "gmail.comm": "gmail.com",
  "gmail.com.br": "gmail.com",
  "gmial.com": "gmail.com",
  "gmai.com": "gmail.com",
  "gmal.com": "gmail.com",
  "gamil.com": "gmail.com",
  "gnail.com": "gmail.com",
  "gmaill.com": "gmail.com",
  "hotmail.con": "hotmail.com",
  "hotmal.com": "hotmail.com",
  "hotmial.com": "hotmail.com",
  "hotmai.com": "hotmail.com",
  "hotmail.co": "hotmail.com",
  "hotmil.com": "hotmail.com",
  "outlok.com": "outlook.com",
  "outlook.con": "outlook.com",
  "outloo.com": "outlook.com",
  "yahoo.con": "yahoo.com",
  "yaho.com": "yahoo.com",
  "yahoo.com.b": "yahoo.com.br",
  "icloud.con": "icloud.com",
  "iclod.com": "icloud.com",
  "live.con": "live.com",
  "bol.com": "bol.com.br",
  "uol.com": "uol.com.br",
};

const MOTIVOS_ALERTA = {
  no_email: "Aviso por e-mail sem e-mail no cadastro",
  no_fcm_token: "Aviso por push sem aparelho registrado",
  delivery_failed: "Envio falhou (push e/ou e-mail)",
};

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

/**
 * Problemas de UM endereço (função pura).
 * @return {Array<{codigo:string, texto:string}>}
 */
function problemasDoEmail(bruto) {
  const out = [];
  const s = bruto == null ? "" : String(bruto);
  if (!s.trim()) return [{ codigo: "sem_email", texto: "Sem e-mail no cadastro" }];
  if (s !== s.trim() || /\s/.test(s.trim())) {
    out.push({ codigo: "espaco", texto: "Endereço com espaço" });
  }
  const limpo = s.trim().toLowerCase().replace(/\s+/g, "");
  if (!EMAIL_RX.test(limpo) || limpo.includes("..") || limpo.split("@").length !== 2) {
    out.push({ codigo: "formato", texto: "Formato inválido" });
    return out;
  }
  const dominio = limpo.split("@")[1];
  if (DOMINIOS_ERRADOS[dominio]) {
    out.push({ codigo: "dominio", texto: `Domínio parece errado (${dominio} → ${DOMINIOS_ERRADOS[dominio]}?)` });
  }
  if (s.trim() !== s.trim().toLowerCase()) {
    out.push({ codigo: "maiuscula", texto: "Letra maiúscula no endereço (pode duplicar cadastro)" });
  }
  return out;
}

/**
 * Agregação PURA (testável).
 * @param {object} p
 * @param {Array<{id:string,data:object}>} p.perfis
 * @param {Array<object>|null} p.contasAuth {uid,email,emailVerified,disabled,providers:string[]}
 * @param {Array<object>|null} p.alertas {uid,status,notifyAt,cancelReason,lastDispatchFailReason,sourceType,channelKind}
 * @param {object} p.config {configurado, usuario, temSenha}
 * @param {number} p.agora
 */
function agregar({ perfis, contasAuth, alertas, config, agora }) {
  const itens = new Map(); // uid → item
  const item = (uid, base) => {
    let x = itens.get(uid);
    if (!x) {
      x = { uid, nome: "", email: "", plano: "", problemas: [], codigos: [], criadoEm: 0, ultimoAcesso: 0 };
      itens.set(uid, x);
    }
    if (base) {
      for (const k of Object.keys(base)) if (base[k] && !x[k]) x[k] = base[k];
    }
    return x;
  };
  const marcar = (x, codigo, texto) => {
    if (x.codigos.includes(codigo)) return;
    x.codigos.push(codigo);
    x.problemas.push(texto);
  };

  const porEmail = new Map();
  const perfilPorUid = new Map();
  const contagem = {
    perfis: perfis.length,
    fantasmas: 0,
    sem_email: 0,
    formato: 0,
    dominio: 0,
    espaco: 0,
    maiuscula: 0,
    duplicado: 0,
    nao_verificado: 0,
    desativado: 0,
    diferente_login: 0,
    aviso_nao_saiu: 0,
  };
  for (const p of perfis) {
    const d = p.data || {};
    const base = {
      nome: String(d.name || d.displayName || "").trim(),
      email: String(d.email || "").trim(),
      plano: String(d.plan || ""),
      criadoEm: ms(d.createdAt),
      ultimoAcesso: ms((d.clientTelemetry || {}).lastPingAt),
    };
    perfilPorUid.set(p.id, base);
    // Perfil «fantasma» sem nada (nem nome) é lixo de cadastro — conta à parte.
    const probs = problemasDoEmail(d.email);
    if (probs.length && (base.nome || base.email || d.plan)) {
      const x = item(p.id, base);
      for (const pr of probs) {
        marcar(x, pr.codigo, pr.texto);
        contagem[pr.codigo] = (contagem[pr.codigo] || 0) + 1;
      }
    } else if (probs.length) {
      contagem.fantasmas += 1;
    }
    const chave = base.email.toLowerCase();
    if (chave && EMAIL_RX.test(chave)) {
      if (!porEmail.has(chave)) porEmail.set(chave, []);
      porEmail.get(chave).push(p.id);
    }
  }
  for (const [email, uids] of porEmail) {
    if (uids.length < 2) continue;
    for (const uid of uids) {
      const x = item(uid, perfilPorUid.get(uid));
      marcar(x, "duplicado", `E-mail repetido em ${uids.length} perfis (${email})`);
      contagem.duplicado += 1;
    }
  }

  if (contasAuth) {
    for (const a of contasAuth) {
      const perfil = perfilPorUid.get(a.uid);
      const emailAuth = String(a.email || "").trim().toLowerCase();
      const senha = (a.providers || []).includes("password");
      if (senha && emailAuth && a.emailVerified !== true && perfil) {
        marcar(item(a.uid, perfil), "nao_verificado", "E-mail do login nunca foi verificado");
        contagem.nao_verificado += 1;
      }
      if (a.disabled === true && perfil) {
        marcar(item(a.uid, perfil), "desativado", "Conta de login desativada");
        contagem.desativado += 1;
      }
      const emailPerfil = perfil ? perfil.email.toLowerCase() : "";
      if (perfil && emailAuth && emailPerfil && emailAuth !== emailPerfil) {
        marcar(item(a.uid, perfil), "diferente_login", `Login usa ${emailAuth}; cadastro tem ${emailPerfil}`);
        contagem.diferente_login += 1;
      }
    }
  }

  const avisosAgenda = { total: 0, porMotivo: {} };
  if (alertas) {
    const porUid = new Map();
    for (const al of alertas) {
      const motivo = String(al.lastDispatchFailReason || al.cancelReason || "").trim();
      if (!MOTIVOS_ALERTA[motivo]) continue;
      avisosAgenda.total += 1;
      avisosAgenda.porMotivo[motivo] = (avisosAgenda.porMotivo[motivo] || 0) + 1;
      const g = porUid.get(al.uid) || { qtd: 0, motivos: {}, ultimo: 0 };
      g.qtd += 1;
      g.motivos[motivo] = (g.motivos[motivo] || 0) + 1;
      g.ultimo = Math.max(g.ultimo, ms(al.notifyAt));
      porUid.set(al.uid, g);
    }
    for (const [uid, g] of porUid) {
      const x = item(uid, perfilPorUid.get(uid));
      const partes = Object.entries(g.motivos).map(([m, n]) => `${MOTIVOS_ALERTA[m]}: ${n}`);
      marcar(x, "aviso_nao_saiu", `${g.qtd} aviso(s) da Agenda não saíram em 30 dias — ${partes.join("; ")}`);
      x.ultimaFalha = g.ultimo;
      x.motivosAgenda = g.motivos;
      contagem.aviso_nao_saiu += 1;
    }
  }

  const peso = { formato: 6, dominio: 5, sem_email: 5, aviso_nao_saiu: 4, diferente_login: 3, duplicado: 3,
    desativado: 2, nao_verificado: 1, espaco: 2, maiuscula: 1 };
  const lista = [...itens.values()]
    .map((x) => ({ ...x, gravidade: x.codigos.reduce((a, c) => a + (peso[c] || 1), 0) }))
    .sort((a, b) => b.gravidade - a.gravidade || (b.ultimaFalha || 0) - (a.ultimaFalha || 0));

  const veredito = [];
  if (!config || !config.configurado) {
    veredito.push("O envio de e-mail NÃO está configurado (settings/email sem usuário e senha de app): nenhum e-mail sai.");
  }
  if (contagem.formato + contagem.dominio > 0) {
    veredito.push(`${contagem.formato + contagem.dominio} cadastro(s) com e-mail inválido ou domínio digitado errado.`);
  }
  if (avisosAgenda.porMotivo.delivery_failed) {
    veredito.push(`${avisosAgenda.porMotivo.delivery_failed} aviso(s) da Agenda falharam no envio nos últimos 30 dias.`);
  }

  return {
    geradoEm: agora,
    config: config || { configurado: false },
    contagem,
    avisosAgenda,
    veredito,
    total: lista.length,
    itens: lista.slice(0, LIMITE_LISTA),
    cortado: lista.length > LIMITE_LISTA,
  };
}

async function lerConfig(db) {
  try {
    const s = await db.doc("settings/email").get();
    const d = s.exists ? s.data() || {} : {};
    const user = String(d.user || d.email || "").trim();
    const temSenha = !!String(d.appPassword || d.pass || d.password || "").trim();
    const mascara = user.includes("@") ? `${user.slice(0, 2)}…@${user.split("@")[1]}` : (user ? "…" : "");
    return { configurado: !!user && temSenha, usuario: mascara, temSenha };
  } catch (e) {
    return { configurado: false, usuario: "", temSenha: false, erro: e.message };
  }
}

async function lerAuth(avisos) {
  const out = [];
  let token;
  let voltas = 0;
  try {
    do {
      const r = await admin.auth().listUsers(1000, token);
      for (const u of r.users) {
        out.push({
          uid: u.uid,
          email: u.email || "",
          emailVerified: u.emailVerified === true,
          disabled: u.disabled === true,
          providers: (u.providerData || []).map((p) => p.providerId),
        });
      }
      token = r.pageToken;
      voltas += 1;
    } while (token && voltas < LIMITE_AUTH_PAGINAS);
    if (token) avisos.push(`Login: lidas só ${out.length} contas (limite).`);
    return out;
  } catch (e) {
    avisos.push(`Não deu para ler as contas de login: ${e.message}`);
    return null;
  }
}

async function lerAlertas(db, agora, avisos) {
  try {
    const desde = admin.firestore.Timestamp.fromMillis(agora - 30 * DIA);
    const snap = await db
      .collectionGroup("agendaAlerts")
      .where("status", "==", "skipped")
      .where("notifyAt", ">=", desde)
      .orderBy("notifyAt")
      .select("status", "notifyAt", "cancelReason", "lastDispatchFailReason", "sourceType", "channelKind")
      .limit(LIMITE_ALERTAS)
      .get();
    if (snap.size >= LIMITE_ALERTAS) avisos.push(`Avisos da Agenda: lidos só ${LIMITE_ALERTAS}.`);
    const out = [];
    for (const doc of snap.docs) {
      const seg = doc.ref.path.split("/");
      if (seg[0] !== "users" || seg.length !== 4) continue;
      out.push({ uid: seg[1], ...(doc.data() || {}) });
    }
    return out;
  } catch (e) {
    avisos.push(`Avisos da Agenda não lidos (índice?): ${e.message}`);
    return null;
  }
}

async function montar(db) {
  const agora = Date.now();
  const avisos = [];
  const [config, usersSnap, contasAuth, alertas] = await Promise.all([
    lerConfig(db),
    db
      .collection("users")
      .select("email", "name", "displayName", "plan", "createdAt", "clientTelemetry")
      .limit(LIMITE_USERS)
      .get(),
    lerAuth(avisos),
    lerAlertas(db, agora, avisos),
  ]);
  if (usersSnap.size >= LIMITE_USERS) avisos.push(`Cadastros: lidos só ${LIMITE_USERS}.`);
  const perfis = usersSnap.docs.map((d) => ({ id: d.id, data: d.data() || {} }));
  const r = agregar({ perfis, contasAuth, alertas, config, agora });
  r.avisos = avisos;
  r.semRegistroDeFalhas = true;
  return r;
}

exports.ctAdminEmailsComProblema = onCall(
  { region: REGIAO, timeoutSeconds: 120, memory: "512MiB", cors: true, maxInstances: 5 },
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
        console.warn("[ctAdminEmailsComProblema] cache ilegível", e.message);
      }
    }
    let r;
    try {
      r = await montar(db);
    } catch (e) {
      console.error("[ctAdminEmailsComProblema]", e);
      throw new HttpsError("internal", "Não foi possível montar a lista agora.");
    }
    try {
      const json = JSON.stringify(r);
      if (json.length < 900000) await ref.set({ geradoEm: r.geradoEm, json, geradoPor: req.auth.uid });
    } catch (e) {
      console.warn("[ctAdminEmailsComProblema] não gravou o cache", e.message);
    }
    return { ...r, doCache: false };
  },
);

exports._agregar = agregar;
exports._problemasDoEmail = problemasDoEmail;
