/**
 * Diagnóstico e teste de notificações push do Painel Admin do WISDOMAPP
 * (porte do Controle Total, 02/10/2026 — sem Telegram, sem «aviso com OK»).
 *
 * Onde o WISDOMAPP guarda o push (lib/services/push_notification_service.dart):
 *   users/{uid}/fcmTokens/{tokenId}   (oficial: token, platform, authUid, createdAt, updatedAt)
 *   users/{uid}/deviceTokens/{tokenId} (legado, mesmos campos)
 *   users/{uid}.fcmToken / pushEnabled (campo legado)
 * Preferências: users/{uid}/settings/notifications. Fila de avisos da Agenda:
 * users/{uid}/agendaAlerts (status pending/sent/skipped/cancelled, notifyAt,
 * sentAt, lastDispatchFailReason). Fila de push avulso: users/{uid}/notifications.
 *
 * Callables:
 *  - `ctAdminNotificacoesDiag({uid, validar?})` — admin/suporte. Lê tudo de UM
 *    usuário e devolve um veredito em português. Com `validar` (padrão true) os
 *    tokens são conferidos na Firebase em modo *dry-run* (nada é entregue).
 *  - `ctAdminNotificacoesUsuarios()` — admin/suporte. Lista os usuários com as
 *    plataformas dos aparelhos (2 consultas collectionGroup com limite).
 *  - `ctAdminNotificacoesTeste({uids, confirmar:true, mensagem?})` — SÓ MASTER.
 *    Manda um push de teste DE VERDADE para até `MAX_LOTE` usuários e devolve o
 *    resultado por aparelho. Token que a Firebase declarou morto é apagado
 *    (mesma regra do envio normal). Registra em activity_logs (logAdmin) e em
 *    `admin_notificacao_testes` (coleção sem regra = só servidor).
 */

"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const { requireAdminLevel, requireMaster, logAdmin } = require("./admin_auth");

const REGIAO = "us-central1";
const DIA = 86400000;
const MAX_LOTE = 20;
const LIMITE_USERS = 5000;
const LIMITE_TOKENS = 20000;
const ANDROID_CANAL = "controletotal_compromisso";
const APP_ICON_URL = "https://wisdomapp-b9e98.web.app/icons/Icon-192.png";
const TOKEN_MORTO = new Set([
  "messaging/invalid-registration-token",
  "messaging/registration-token-not-registered",
]);

function paraMs(v) {
  if (!v) return 0;
  if (typeof v.toMillis === "function") return v.toMillis();
  if (v instanceof Date) return v.getTime();
  if (typeof v === "number") return v;
  const t = Date.parse(v);
  return Number.isFinite(t) ? t : 0;
}
function iso(v) {
  const t = paraMs(v);
  return t ? new Date(t).toISOString() : null;
}
function uidValido(v) {
  const s = String(v || "").trim();
  return s && !s.includes("/") && s.length <= 128 ? s : "";
}

/** Junta um doc de fcmTokens/deviceTokens no mapa token → aparelho (puro). */
function acumularToken(porToken, id, d, uidDono) {
  const token = String(d.token || id || "").trim();
  if (token.length < 20) return;
  const atual = porToken.get(token) || { token, origens: [] };
  const visto = paraMs(d.updatedAt) || paraMs(d.lastSeenAt) || paraMs(d.createdAt);
  if (visto > (atual.ultimoRegistro || 0)) atual.ultimoRegistro = visto;
  atual.plataforma = atual.plataforma || String(d.platform || "desconhecida");
  const authUid = String(d.authUid || "").trim();
  if (authUid && authUid !== uidDono) atual.subLogin = authUid;
  porToken.set(token, atual);
}

async function aparelhosDoUsuario(db, uid, userData) {
  const porToken = new Map();
  const ref = db.collection("users").doc(uid);
  const [fcm, dev] = await Promise.all([
    ref.collection("fcmTokens").limit(50).get(),
    ref.collection("deviceTokens").limit(50).get(),
  ]);
  fcm.docs.forEach((doc) => acumularToken(porToken, doc.id, doc.data() || {}, uid));
  dev.docs.forEach((doc) => acumularToken(porToken, doc.id, doc.data() || {}, uid));
  const legado = String((userData && userData.fcmToken) || "").trim();
  if (legado.length >= 20 && !porToken.has(legado)) {
    porToken.set(legado, { token: legado, plataforma: "legado", ultimoRegistro: 0 });
  }
  return [...porToken.values()];
}

function mensagemTeste(token, titulo, corpo) {
  return {
    token,
    notification: { title: titulo, body: corpo },
    data: { type: "teste_admin", title: titulo, body: corpo, click_action: "FLUTTER_NOTIFICATION_CLICK" },
    android: {
      priority: "high",
      notification: { channelId: ANDROID_CANAL, priority: "high", defaultSound: true },
    },
    apns: {
      headers: { "apns-priority": "10", "apns-push-type": "alert" },
      payload: { aps: { alert: { title: titulo, body: corpo }, sound: "default" } },
    },
    webpush: { notification: { icon: APP_ICON_URL, badge: APP_ICON_URL } },
  };
}

/** Envia (ou só valida, com dryRun) para cada token. */
async function enviarPorAparelho(aparelhos, titulo, corpo, dryRun) {
  const messaging = admin.messaging();
  return Promise.all(
    aparelhos.map(async (ap) => {
      try {
        await messaging.send(mensagemTeste(ap.token, titulo, corpo), dryRun);
        return { ...ap, ok: true, erro: null };
      } catch (e) {
        return { ...ap, ok: false, erro: (e && (e.code || e.message)) || "erro" };
      }
    }),
  );
}

async function limparTokensMortos(db, uid, envio) {
  let apagados = 0;
  for (const a of envio) {
    if (a.ok || !TOKEN_MORTO.has(a.erro)) continue;
    for (const sub of ["fcmTokens", "deviceTokens"]) {
      const q = await db.collection("users").doc(uid).collection(sub).where("token", "==", a.token).limit(8).get();
      await Promise.all(q.docs.map((d) => d.ref.delete().catch(() => {})));
      apagados += q.size;
    }
  }
  return apagados;
}

function publicoAparelho(a) {
  return {
    plataforma: a.plataforma || "desconhecida",
    ultimoRegistro: a.ultimoRegistro ? new Date(a.ultimoRegistro).toISOString() : null,
    tokenFim: String(a.token).slice(-8),
    subLogin: a.subLogin || null,
    validado: a.ok !== undefined,
    valido: a.ok !== false,
    erro: a.erro || null,
  };
}

/**
 * Veredito PURO (testável) a partir do que foi lido.
 * @return {{avisos:string[], ok:string[]}}
 */
function veredito({ agora, aparelhos, pushEnabled, prefs, sessao, fila, eventos }) {
  const avisos = [];
  const ok = [];
  if (!aparelhos.length) {
    avisos.push("Nenhum aparelho registrado: o app nunca salvou o token de push desta conta (abrir o app logado e permitir notificações).");
  }
  const validados = aparelhos.filter((a) => a.ok !== undefined);
  const mortos = validados.filter((a) => !a.ok);
  if (mortos.length) {
    avisos.push(`${mortos.length} aparelho(s) com token recusado pela Firebase (${mortos.map((m) => m.erro).join(", ")}).`);
  }
  const validos = validados.filter((a) => a.ok);
  if (validos.length) ok.push(`${validos.length} aparelho(s) com token válido.`);
  if (pushEnabled === false) avisos.push("Push desligado no cadastro (users.pushEnabled = false).");
  if (prefs.push === false) avisos.push("Push desligado em Notificações › Como receber.");
  const off = [
    ["Escalas", prefs.escalas],
    ["Compromissos", prefs.compromissos],
    ["Audiências", prefs.audiencias],
    ["Financeiro", prefs.financeiro],
  ].filter(([, on]) => on === false).map(([n]) => n);
  if (off.length) avisos.push(`Categorias desligadas: ${off.join(", ")}.`);
  const atividade = sessao && sessao.ultimaAtividade ? paraMs(sessao.ultimaAtividade) : 0;
  if (atividade && agora - atividade > 3 * DIA) {
    avisos.push(`A conta não é aberta no app há ${Math.floor((agora - atividade) / DIA)} dia(s): o aparelho pode estar deslogado ou com outra conta.`);
  }
  const recente = Math.max(0, ...aparelhos.map((a) => a.ultimoRegistro || 0));
  if (recente && agora - recente > 7 * DIA) {
    avisos.push(`Token não é renovado desde ${new Date(recente).toLocaleDateString("pt-BR", { timeZone: "America/Sao_Paulo" })}.`);
  }
  const totalEventos = (eventos.escalas || 0) + (eventos.compromissos || 0) + (eventos.contas || 0);
  if (eventos.lidos && totalEventos === 0) {
    avisos.push("Nenhuma escala, compromisso ou conta a partir de ontem: não há o que avisar.");
  }
  if (fila.pendentes === 0) avisos.push("Fila de avisos vazia: nenhum aviso programado para esta conta.");
  else if (fila.pendentes > 0) ok.push(`${fila.pendentes} aviso(s) programado(s).`);
  if (fila.pulados > 0) {
    const m = Object.entries(fila.motivosPulados || {}).map(([k, n]) => `${k}: ${n}`).join(", ");
    avisos.push(`${fila.pulados} aviso(s) não saíram na fila recente (${m}).`);
  }
  if (fila.ultimoEnvio) ok.push(`Último aviso entregue em ${new Date(fila.ultimoEnvio).toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo" })}.`);
  return { avisos, ok };
}

async function contarFuturos(db, uid, colecao, agora) {
  try {
    const agg = await db
      .collection("users").doc(uid).collection(colecao)
      .where("date", ">=", admin.firestore.Timestamp.fromMillis(agora - DIA))
      .count()
      .get();
    return agg.data().count || 0;
  } catch (_) {
    return null;
  }
}

async function diagnosticar(db, uid, validar) {
  const agora = Date.now();
  const userSnap = await db.doc(`users/${uid}`).get();
  if (!userSnap.exists) throw new HttpsError("not-found", "Usuário não encontrado.");
  const u = userSnap.data() || {};
  const ref = db.collection("users").doc(uid);

  const [brutos, notifSnap, alertasSnap, pushSnap, testesSnap] = await Promise.all([
    aparelhosDoUsuario(db, uid, u),
    ref.collection("settings").doc("notifications").get(),
    ref.collection("agendaAlerts")
      .select("status", "notifyAt", "sentAt", "channelKind", "leadMin", "lastDispatchFailReason", "cancelReason")
      .limit(400).get(),
    ref.collection("notifications").orderBy("createdAt", "desc").limit(10).get().catch(() => null),
    db.collection("admin_notificacao_testes").where("uid", "==", uid).limit(20).get().catch(() => null),
  ]);
  const aparelhos = validar
    ? await enviarPorAparelho(brutos, "teste", "teste", true)
    : brutos;

  let sessao = null;
  try {
    const au = await admin.auth().getUser(uid);
    sessao = {
      ultimoLogin: au.metadata.lastSignInTime ? new Date(au.metadata.lastSignInTime).toISOString() : null,
      ultimaAtividade: au.metadata.lastRefreshTime ? new Date(au.metadata.lastRefreshTime).toISOString() : null,
      emailVerificado: au.emailVerified === true,
      desativado: au.disabled === true,
    };
  } catch (_) {
    /* conta sem login (sub-coleção órfã) */
  }

  const n = notifSnap.exists ? notifSnap.data() || {} : {};
  const leads = (Array.isArray(n.scaleReminderLeads) ? n.scaleReminderLeads : [])
    .map((x) => parseInt(x, 10) || 0).filter((x) => x > 0);
  const notifCompromissos = n.notifCompromissos !== undefined
    ? n.notifCompromissos !== false
    : n.notifCompromissosAudiencias !== false;
  const prefs = {
    push: n.scaleReminderEnabled !== false,
    email: n.emailReminderEnabled !== false,
    escalas: n.notifEscalas !== false,
    compromissos: notifCompromissos,
    audiencias: n.notifAudiencias !== false,
    financeiro: n.notifFinanceiro !== false,
    resumoDiario: n.dailyDigestEnabled !== false,
    antecedencias: leads.length ? leads : [1440, 60],
    configurado: notifSnap.exists,
  };

  const alertas = alertasSnap.docs.map((d) => d.data() || {});
  const pendentes = alertas.filter((a) => a.status === "pending");
  const enviados = alertas.filter((a) => a.status === "sent");
  const pulados = alertas.filter((a) => a.status === "skipped");
  const motivosPulados = {};
  for (const a of pulados) {
    const m = String(a.cancelReason || a.lastDispatchFailReason || "sem motivo");
    motivosPulados[m] = (motivosPulados[m] || 0) + 1;
  }
  const ultimoEnvio = Math.max(0, ...enviados.map((a) => paraMs(a.sentAt) || paraMs(a.notifyAt)));
  const proximo = pendentes
    .map((a) => ({ quando: paraMs(a.notifyAt), tipo: a.channelKind || null, antecedencia: a.leadMin || null }))
    .filter((a) => a.quando)
    .sort((a, b) => a.quando - b.quando)[0];
  const falhasRecentes = alertas
    .filter((a) => a.lastDispatchFailReason)
    .map((a) => ({ quando: iso(a.notifyAt), tipo: a.channelKind || null, motivo: String(a.lastDispatchFailReason) }))
    .sort((a, b) => String(b.quando).localeCompare(String(a.quando)))
    .slice(0, 8);
  const fila = {
    pendentes: pendentes.length,
    enviados: enviados.length,
    pulados: pulados.length,
    motivosPulados,
    ultimoEnvio: ultimoEnvio || null,
    proximo: proximo ? { ...proximo, quando: new Date(proximo.quando).toISOString() } : null,
    falhasRecentes,
  };

  const [escalas, compromissos, contas] = await Promise.all([
    contarFuturos(db, uid, "scales", agora),
    contarFuturos(db, uid, "reminders", agora),
    contarFuturos(db, uid, "transactions", agora),
  ]);
  const eventos = { escalas, compromissos, contas, lidos: escalas !== null || compromissos !== null };

  const ultimosPush = pushSnap
    ? pushSnap.docs.map((d) => {
      const x = d.data() || {};
      return { titulo: String(x.title || ""), corpo: String(x.body || "").slice(0, 140), quando: iso(x.createdAt) };
    })
    : [];
  const testes = testesSnap
    ? testesSnap.docs
      .map((d) => d.data() || {})
      .sort((a, b) => (b.criadoEm || 0) - (a.criadoEm || 0))
      .slice(0, 5)
      .map((t) => ({
        quando: t.criadoEm ? new Date(t.criadoEm).toISOString() : null,
        aparelhos: (t.push || []).length,
        entregues: (t.push || []).filter((p) => p.valido).length,
        por: t.porEmail || null,
      }))
    : [];

  const tel = u.clientTelemetry || {};
  return {
    success: true,
    usuario: {
      uid,
      nome: String(u.name || u.displayName || ""),
      email: String(u.email || ""),
      plano: String(u.plan || ""),
      pushEnabled: u.pushEnabled !== false,
      plataforma: String(tel.platform || ""),
      appVersao: String(tel.appVersion || ""),
      ultimoAcessoApp: iso(tel.lastPingAt),
    },
    sessao,
    validado: !!validar,
    aparelhos: aparelhos.map(publicoAparelho),
    preferencias: prefs,
    fila,
    eventosFuturos: { escalas, compromissos, contas },
    ultimosPush,
    testes,
    veredito: veredito({ agora, aparelhos, pushEnabled: u.pushEnabled, prefs, sessao, fila, eventos }),
  };
}

exports.ctAdminNotificacoesDiag = onCall(
  { region: REGIAO, timeoutSeconds: 60, memory: "512MiB", cors: true, maxInstances: 10 },
  async (req) => {
    await requireAdminLevel(req, ["admin", "suporte"]);
    const uid = uidValido(req.data && req.data.uid);
    if (!uid) throw new HttpsError("invalid-argument", "Informe o usuário.");
    const validar = !(req.data && req.data.validar === false);
    try {
      return await diagnosticar(admin.firestore(), uid, validar);
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      console.error("[ctAdminNotificacoesDiag]", uid, e);
      throw new HttpsError("internal", "Não foi possível montar o diagnóstico agora.");
    }
  },
);

/** Lista (pura) de usuários com as plataformas dos aparelhos. */
function montarLista(perfis, tokens) {
  const porUid = new Map();
  for (const p of perfis) {
    const d = p.data || {};
    const email = String(d.email || "").trim();
    const nome = String(d.name || d.displayName || "").trim();
    if (!email && !nome) continue;
    porUid.set(p.id, {
      uid: p.id,
      nome,
      email,
      plano: String(d.plan || ""),
      pushEnabled: d.pushEnabled !== false,
      legado: String(d.fcmToken || "").trim().length >= 20,
      plataformas: new Set(),
      aparelhos: new Set(),
      ultimoRegistro: 0,
    });
  }
  for (const t of tokens) {
    const u = porUid.get(t.uid);
    if (!u) continue;
    u.plataformas.add(String(t.platform || "desconhecida"));
    u.aparelhos.add(t.id);
    const visto = paraMs(t.updatedAt) || paraMs(t.createdAt);
    if (visto > u.ultimoRegistro) u.ultimoRegistro = visto;
  }
  return [...porUid.values()]
    .map((u) => ({
      uid: u.uid,
      nome: u.nome,
      email: u.email,
      plano: u.plano,
      pushEnabled: u.pushEnabled,
      plataformas: [...u.plataformas].sort(),
      aparelhos: u.aparelhos.size || (u.legado ? 1 : 0),
      ultimoRegistro: u.ultimoRegistro ? new Date(u.ultimoRegistro).toISOString() : null,
    }))
    .sort((a, b) => (a.nome || a.email).localeCompare(b.nome || b.email, "pt-BR"));
}

exports.ctAdminNotificacoesUsuarios = onCall(
  { region: REGIAO, timeoutSeconds: 120, memory: "1GiB", cors: true, maxInstances: 5 },
  async (req) => {
    await requireAdminLevel(req, ["admin", "suporte"]);
    const db = admin.firestore();
    const avisos = [];
    const [usersSnap, ...subs] = await Promise.all([
      db.collection("users").select("email", "name", "displayName", "plan", "pushEnabled", "fcmToken")
        .limit(LIMITE_USERS).get(),
      ...["fcmTokens", "deviceTokens"].map((sub) =>
        db.collectionGroup(sub).select("platform", "updatedAt", "createdAt", "token").limit(LIMITE_TOKENS).get()
          .catch((e) => {
            avisos.push(`${sub}: ${e.message}`);
            return null;
          })),
    ]);
    if (usersSnap.size >= LIMITE_USERS) avisos.push(`Lidos só ${LIMITE_USERS} usuários.`);
    const tokens = [];
    for (const snap of subs) {
      if (!snap) continue;
      if (snap.size >= LIMITE_TOKENS) avisos.push(`Lidos só ${LIMITE_TOKENS} aparelhos de uma coleção.`);
      for (const doc of snap.docs) {
        const seg = doc.ref.path.split("/");
        if (seg[0] !== "users" || seg.length !== 4) continue;
        const d = doc.data() || {};
        tokens.push({ uid: seg[1], id: String(d.token || doc.id), ...d });
      }
    }
    const perfis = usersSnap.docs.map((d) => ({ id: d.id, data: d.data() || {} }));
    return { success: true, geradoEm: Date.now(), usuarios: montarLista(perfis, tokens), avisos, maxLote: MAX_LOTE };
  },
);

exports.ctAdminNotificacoesTeste = onCall(
  { region: REGIAO, timeoutSeconds: 120, memory: "512MiB", cors: true, maxInstances: 3 },
  async (req) => {
    await requireMaster(req, "Somente o master pode enviar notificação de teste.");
    const data = req.data || {};
    if (data.confirmar !== true) {
      throw new HttpsError("failed-precondition", "Confirme o envio do teste.");
    }
    const pedidos = Array.isArray(data.uids) ? data.uids : [data.uid];
    const uids = [...new Set(pedidos.map(uidValido).filter(Boolean))];
    if (!uids.length) throw new HttpsError("invalid-argument", "Escolha ao menos um usuário.");
    if (uids.length > MAX_LOTE) {
      throw new HttpsError("invalid-argument", `No máximo ${MAX_LOTE} usuários por teste.`);
    }
    const titulo = "🔔 Teste de notificação";
    const extra = String(data.mensagem || "").trim().slice(0, 140);
    const corpo = extra || "Se você está vendo isto, as notificações do Wisdom APP estão funcionando.";
    const db = admin.firestore();
    const porEmail = String((req.auth.token && req.auth.token.email) || "").toLowerCase();

    const resultados = [];
    for (let i = 0; i < uids.length; i += 5) {
      const fatia = uids.slice(i, i + 5);
      const feitos = await Promise.all(fatia.map(async (uid) => {
        try {
          const s = await db.doc(`users/${uid}`).get();
          if (!s.exists) return { uid, ok: false, aparelhos: 0, entregues: 0, erros: ["Usuário não encontrado."], push: [] };
          const u = s.data() || {};
          const aparelhos = await aparelhosDoUsuario(db, uid, u);
          const envio = await enviarPorAparelho(aparelhos, titulo, corpo, false);
          const apagados = await limparTokensMortos(db, uid, envio);
          const push = envio.map(publicoAparelho);
          await db.collection("admin_notificacao_testes").add({
            uid,
            criadoEm: Date.now(),
            porUid: req.auth.uid,
            porEmail,
            push: push.map((p) => ({ plataforma: p.plataforma, valido: p.valido, erro: p.erro })),
          }).catch(() => {});
          return {
            uid,
            nome: String(u.name || u.displayName || ""),
            email: String(u.email || ""),
            ok: true,
            pushEnabled: u.pushEnabled !== false,
            aparelhos: push.length,
            entregues: push.filter((p) => p.valido).length,
            erros: push.filter((p) => !p.valido).map((p) => `${p.plataforma}: ${p.erro}`),
            tokensApagados: apagados,
            push,
          };
        } catch (e) {
          return { uid, ok: false, aparelhos: 0, entregues: 0, erros: [String((e && e.message) || e)], push: [] };
        }
      }));
      resultados.push(...feitos);
    }
    const resumo = {
      usuarios: resultados.length,
      comEntrega: resultados.filter((r) => r.entregues > 0).length,
      semAparelho: resultados.filter((r) => r.ok && r.aparelhos === 0).length,
      comFalha: resultados.filter((r) => r.erros && r.erros.length).length,
    };
    await logAdmin(
      req,
      "Teste de notificação",
      `Push de teste para ${uids.length} usuário(s): ${resumo.comEntrega} com entrega, ` +
        `${resumo.semAparelho} sem aparelho, ${resumo.comFalha} com falha.`,
      { uids },
    );
    return { success: true, resumo, resultados };
  },
);

exports._veredito = veredito;
exports._montarLista = montarLista;
exports._acumularToken = acumularToken;
