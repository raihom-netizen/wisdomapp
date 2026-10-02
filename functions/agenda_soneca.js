/**
 * Soneca dos avisos de agenda + som escolhido pelo usuário.
 *
 * SONECA — o aviso repete 3 ou 5 vezes (a cada 3 ou 5 min) até a pessoa
 * tocar em «Encerrar» ou «Adiar 3/5 min» na própria notificação.
 *   - Configuração em `users/{uid}/settings/notifications`:
 *       sonecaAtiva (bool), sonecaVezes (3|5), sonecaIntervaloMin (3|5),
 *       sonecaEscalas / sonecaCompromissos / sonecaAudiencias / sonecaFinanceiro
 *       (padrão ligado quando a soneca está ativa).
 *   - Cada repetição é um doc a mais na fila `agendaAlerts` com `snoozeOf`
 *     (id do aviso original), `snoozeIndex` e `snoozeTotal`. Só push: e-mail e
 *     Telegram não repetem.
 *   - Os botões chamam `ctSonecaAcao` (HTTP) com um token HMAC do par
 *     uid + aviso — funciona com o app fechado (Android em segundo plano e
 *     extensão nativa do iOS), sem login.
 *
 * SOM — `somNotificacao: { all, escala, compromisso, audiencia, financeiro }`
 * guarda o id do tom do catálogo do app. O servidor manda o canal Android
 * `ct_som_<id>` (som no pacote nativo) e `aps.sound = <id>.wav` no iOS.
 */

const admin = require("firebase-admin");
const crypto = require("crypto");
const despertador = require("./agenda_despertador");

const VEZES_VALIDAS = [3, 5];
const INTERVALOS_VALIDOS = [3, 5];
const MAX_REPETICOES_POR_AVISO = 30;
const RE_SOM_ID = /^[a-z0-9_]{2,40}$/;

function categoriaDoCanal(channelKind) {
  const k = (channelKind || "").toString().toLowerCase();
  if (k === "audiencia" || k === "compromisso" || k === "financeiro") return k;
  return "escala"; // escala e folga
}

/**
 * `sonecaModulos: { escala: {ativa, vezes, intervaloMin}, compromisso: …,
 * audiencia: …, financeiro: … }` — cada módulo tem o seu despertador.
 */
function parseSonecaConfig(notifData) {
  const mods = (notifData && notifData.sonecaModulos) || {};
  // Despertador é OPCIONAL e nasce desligado: sem o interruptor geral
  // `sonecaAtiva: true`, nenhum módulo repete — mesmo com o módulo marcado.
  const geral = !!(notifData && notifData.sonecaAtiva === true);
  const out = {};
  for (const k of ["escala", "compromisso", "audiencia", "financeiro"]) {
    const m = mods[k] || {};
    const vezes = Number(m.vezes);
    const intervalo = Number(m.intervaloMin);
    out[k] = {
      ativa: geral && m.ativa === true,
      vezes: VEZES_VALIDAS.includes(vezes) ? vezes : 3,
      intervaloMin: INTERVALOS_VALIDOS.includes(intervalo) ? intervalo : 5,
      // O usuário escolheu vezes/intervalo neste módulo? Sem escolha, o
      // «Despertar» do item usa 3 × 3 min (agenda_despertar_item.js).
      definido: VEZES_VALIDAS.includes(vezes) || INTERVALOS_VALIDOS.includes(intervalo),
    };
  }
  return out;
}

function sonecaDoModulo(config, channelKind) {
  const s = config && config.soneca;
  return (s && s[categoriaDoCanal(channelKind)]) || null;
}

function parseSons(notifData) {
  const raw = (notifData && notifData.somNotificacao) || {};
  const out = {};
  for (const k of ["all", "escala", "compromisso", "audiencia", "financeiro"]) {
    const v = (raw[k] || "").toString().trim();
    out[k] = RE_SOM_ID.test(v) ? v : "";
  }
  return out;
}

const RE_CANAL_PROPRIO = /^ct_som_user_[a-z]+_[a-z0-9]+$/;
const RE_ARQUIVO_PROPRIO = /^ct_user_[a-z]+_[a-z0-9]+\.wav$/;

/** `somProprio: { <cat>: { android: <canal>, ios: <arquivo.wav> } }` (MP3/voz). */
function parseSomProprio(notifData) {
  const raw = (notifData && notifData.somProprio) || {};
  const out = {};
  for (const k of ["all", "escala", "compromisso", "audiencia", "financeiro"]) {
    const v = raw[k] || {};
    out[k] = {
      android: RE_CANAL_PROPRIO.test(String(v.android || "")) ? String(v.android) : "",
      ios: RE_ARQUIVO_PROPRIO.test(String(v.ios || "")) ? String(v.ios) : "",
    };
  }
  return out;
}

/**
 * Onde tocar o `soundId` em cada plataforma:
 * catálogo → canal `ct_som_<id>` / `<id>.wav`; «proprio» → o canal/arquivo
 * gravado pelo aparelho da pessoa (da categoria, senão de «todas»).
 */
function destinoDoSom(config, channelKind, soundId) {
  if (!soundId) return { android: "", ios: "", catalogo: "" };
  if (soundId !== "proprio") {
    return { android: `ct_som_${soundId}`, ios: `${soundId}.wav`, catalogo: soundId };
  }
  const cat = categoriaDoCanal(channelKind);
  const sons = (config && config.sons) || {};
  const proprios = (config && config.somProprio) || {};
  const chave = sons[cat] === "proprio" ? cat : "all";
  const p = proprios[chave] || {};
  return { android: p.android || "", ios: p.ios || "", catalogo: "" };
}

function sonecaAtivaPara(config, channelKind) {
  const m = sonecaDoModulo(config, channelKind);
  return !!(m && m.ativa);
}

const MODOS_VALIDOS = ["som", "vibrar", "silencio"];

/** `modoNotificacao: { all, escala, … }` = "som" | "vibrar" | "silencio". */
function parseModos(notifData) {
  const raw = (notifData && notifData.modoNotificacao) || {};
  const out = {};
  for (const k of ["all", "escala", "compromisso", "audiencia", "financeiro"]) {
    const v = (raw[k] || "").toString();
    out[k] = MODOS_VALIDOS.includes(v) ? v : "";
  }
  return out;
}

/**
 * Como o aviso chega: o do próprio evento («só vibrar/só push» no formulário)
 * manda; senão o do módulo; senão o de «todas»; padrão = com som.
 */
function modoPara(config, channelKind, srcData) {
  const d = srcData || {};
  const doEvento = (d.notificationDeliveryMode || "").toString();
  if (doEvento === "vibrate") return "vibrar";
  if (doEvento === "push") return "silencio";
  if (doEvento === "audio") return "som";
  const modos = (config && config.modos) || {};
  return modos[categoriaDoCanal(channelKind)] || modos.all || "som";
}

/**
 * Tom do aviso: o do próprio evento (quando a pessoa escolheu no formulário e
 * não pediu «só vibrar/só push»), senão o da categoria, senão o de «todas».
 */
function somPara(config, channelKind, srcData) {
  const d = srcData || {};
  if (modoPara(config, channelKind, d) !== "som") return "";
  const doEvento = (d.notificationSoundId || "").toString().trim();
  if (RE_SOM_ID.test(doEvento)) return doEvento;
  const sons = (config && config.sons) || {};
  return sons[categoriaDoCanal(channelKind)] || sons.all || "";
}

// ── Token dos botões ────────────────────────────────────────────────────────

let chaveCache = null;

async function chaveHmac(db) {
  if (chaveCache) return chaveCache;
  const ref = db.collection("private_config").doc("agenda_soneca");
  const snap = await ref.get();
  let chave = snap.exists ? (snap.data().hmacKey || "").toString() : "";
  if (chave.length < 32) {
    chave = crypto.randomBytes(32).toString("hex");
    // create() falha se outra instância gravou antes — aí relê a dela.
    try {
      await ref.create({ hmacKey: chave, createdAt: admin.firestore.FieldValue.serverTimestamp() });
    } catch (_) {
      const again = await ref.get();
      chave = (again.data() || {}).hmacKey || chave;
    }
  }
  chaveCache = chave;
  return chave;
}

async function tokenPara(db, uid, avisoId) {
  const chave = await chaveHmac(db);
  return crypto.createHmac("sha256", chave).update(`${uid}|${avisoId}`).digest("hex").slice(0, 40);
}

async function tokenValido(db, uid, avisoId, token) {
  if (!uid || !avisoId || !token) return false;
  const esperado = await tokenPara(db, uid, avisoId);
  const a = Buffer.from(esperado);
  const b = Buffer.from(String(token));
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function urlDaAcao() {
  const projeto = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || "wisdomapp-b9e98";
  return `https://us-central1-${projeto}.cloudfunctions.net/ctSonecaAcao`;
}

// ── Repetições ──────────────────────────────────────────────────────────────

const CAMPOS_COPIADOS = [
  "sourceType", "sourceId", "leadMin", "eventAt", "channelKind", "title", "body",
  "eventTitle", "timeStr", "startStr", "linkLocalizacao", "contatoWhatsApp", "planVersion",
  // «Despertar no horário» (agenda_despertador.js): a repetição também é alarme.
  "despertador", "despertadorAte",
];

/** Aviso de alarme por item («Despertar no horário»), não o despertador do módulo. */
function ehAlarmeDoItem(alertData) {
  return !!alertData && alertData.despertador === true;
}

function dataDe(v) {
  if (!v) return null;
  if (typeof v.toDate === "function") return v.toDate();
  if (v instanceof Date) return v;
  return null;
}

/**
 * Agenda `quantas` repetições do aviso `avisoId`, a partir de `inicio`,
 * espaçadas por `intervaloMin`. Nenhuma passa do início do evento — ou, no
 * alarme por item (que toca NO horário), do `limite` dele.
 */
async function agendarRepeticoes(
  db, uid, avisoId, base, { inicio, quantas, intervaloMin, prefixo, total, limite, extra },
) {
  const coll = db.collection("users").doc(uid).collection("agendaAlerts");
  const eventAt = dataDe(base.eventAt);
  const teto = limite || eventAt;
  let criadas = 0;
  for (let k = 1; k <= quantas; k++) {
    const quando = new Date(inicio.getTime() + (k - 1) * intervaloMin * 60 * 1000);
    if (teto && quando >= teto) break;
    const doc = {
      status: "pending",
      notifyAt: admin.firestore.Timestamp.fromDate(quando),
      pushEnabled: true,
      emailEnabled: false,
      snoozeOf: avisoId,
      snoozeIndex: k,
      snoozeTotal: total || quantas,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    for (const c of CAMPOS_COPIADOS) {
      if (base[c] !== undefined) doc[c] = base[c];
    }
    if (extra) Object.assign(doc, extra);
    try {
      // create(): o mesmo aviso despachado duas vezes não duplica a série.
      await coll.doc(`${avisoId}_${prefixo}${k}`).create(doc);
      criadas++;
    } catch (_) {}
  }
  return criadas;
}

/** Depois do 1º envio de um aviso com soneca: agenda as N repetições. */
async function criarRepeticoesAposEnvio(db, uid, alertRef, alertData, config, agora) {
  if (!alertRef || !alertData || alertData.snoozeOf) return 0;
  // Alarme por item: repete MESMO com o despertador geral/do módulo desligado,
  // e as repetições começam no horário (não antes do evento) e param no limite.
  if (ehAlarmeDoItem(alertData)) {
    const r = despertador.repeticoes(config);
    const eventAt = dataDe(alertData.eventAt) || agora;
    return agendarRepeticoes(db, uid, alertRef.id, alertData, {
      inicio: new Date(agora.getTime() + r.intervaloMin * 60 * 1000),
      quantas: r.vezes,
      intervaloMin: r.intervaloMin,
      prefixo: "s",
      total: r.vezes,
      limite: dataDe(alertData.despertadorAte) || despertador.limiteDoAlarme(eventAt, config),
    });
  }
  if (!sonecaAtivaPara(config, alertData.channelKind)) return 0;
  const s = sonecaDoModulo(config, alertData.channelKind);
  return agendarRepeticoes(db, uid, alertRef.id, alertData, {
    inicio: new Date(agora.getTime() + s.intervaloMin * 60 * 1000),
    quantas: s.vezes,
    intervaloMin: s.intervaloMin,
    prefixo: "s",
    total: s.vezes,
  });
}

async function pendentesDaSerie(db, uid, avisoId) {
  const snap = await db
    .collection("users").doc(uid).collection("agendaAlerts")
    .where("snoozeOf", "==", avisoId)
    .get();
  return snap;
}

async function encerrarSerie(db, uid, avisoId, motivo) {
  const snap = await pendentesDaSerie(db, uid, avisoId);
  const batch = db.batch();
  let n = 0;
  snap.forEach((doc) => {
    if ((doc.data().status || "") !== "pending") return;
    batch.update(doc.ref, {
      status: "cancelled",
      cancelReason: motivo,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    n++;
  });
  if (n) await batch.commit();
  await db.collection("users").doc(uid).collection("agendaAlerts").doc(avisoId)
    .set({ sonecaEncerradaEm: admin.firestore.FieldValue.serverTimestamp() }, { merge: true })
    .catch(() => {});
  return n;
}

/**
 * «Adiar X min»: as repetições que faltavam recomeçam daqui a X minutos (no
 * mínimo uma). Mesma ideia do despertador.
 */
async function adiarSerie(db, uid, avisoId, minutos, config) {
  const coll = db.collection("users").doc(uid).collection("agendaAlerts");
  // Titular e sub-login recebem o mesmo push: se os dois tocarem «Adiar»
  // quase juntos, nasciam duas séries de repetição. Só o primeiro toque em
  // 20 s vale; o segundo responde ok sem criar nada.
  const liberado = await db.runTransaction(async (tx) => {
    const s = await tx.get(coll.doc(avisoId));
    if (!s.exists) return "inexistente";
    const ultimo = Number((s.data() || {}).sonecaAdiadaMs) || 0;
    if (Date.now() - ultimo < 20000) return "repetido";
    tx.update(coll.doc(avisoId), { sonecaAdiadaMs: Date.now() });
    return "ok";
  });
  if (liberado === "inexistente") return { ok: false, motivo: "aviso_inexistente" };
  if (liberado === "repetido") return { ok: true, criadas: 0, jaAdiado: true };
  const original = await coll.doc(avisoId).get();
  if (!original.exists) return { ok: false, motivo: "aviso_inexistente" };
  const base = original.data() || {};
  const snap = await pendentesDaSerie(db, uid, avisoId);
  if (snap.size >= MAX_REPETICOES_POR_AVISO) return { ok: false, motivo: "limite" };
  const pendentes = snap.docs.filter((d) => (d.data().status || "") === "pending").length;
  await encerrarSerie(db, uid, avisoId, "soneca_adiada");
  const agora = new Date();
  const eventAt = dataDe(base.eventAt);
  const inicio = new Date(agora.getTime() + minutos * 60 * 1000);
  if (ehAlarmeDoItem(base)) {
    // Alarme por item toca NO horário: «Adiar» empurra para depois dele, como
    // um despertador. O limite novo acompanha as repetições adiadas.
    const r = despertador.repeticoes(config);
    const quantas = Math.max(1, pendentes);
    const limite = new Date(inicio.getTime() + quantas * r.intervaloMin * 60 * 1000 + 60 * 1000);
    const criadas = await agendarRepeticoes(db, uid, avisoId, base, {
      inicio,
      quantas,
      intervaloMin: r.intervaloMin,
      prefixo: `a${agora.getTime()}_`,
      total: quantas,
      limite,
      extra: { despertadorAte: admin.firestore.Timestamp.fromDate(limite) },
    });
    return { ok: criadas > 0, criadas };
  }
  if (eventAt && inicio >= eventAt) return { ok: false, motivo: "evento_vai_comecar" };
  const mod = sonecaDoModulo(config, base.channelKind);
  const intervalo = (mod && mod.intervaloMin) || minutos;
  const criadas = await agendarRepeticoes(db, uid, avisoId, base, {
    inicio,
    quantas: Math.max(1, pendentes),
    intervaloMin: intervalo,
    prefixo: `a${agora.getTime()}_`,
    total: Math.max(1, pendentes),
  });
  return { ok: criadas > 0, criadas };
}

/** Campos extras do push quando a soneca vale para este aviso. */
async function dadosDoPush(db, uid, alertData, alertId, config) {
  if (!alertId) return {};
  const ehRepeticao = !!(alertData && alertData.snoozeOf);
  const avisoId = ehRepeticao ? alertData.snoozeOf : alertId;
  const alarme = ehAlarmeDoItem(alertData);
  if (!ehRepeticao && !alarme && !sonecaAtivaPara(config, alertData && alertData.channelKind)) return {};
  const totalOriginal = alarme
    ? despertador.repeticoes(config).vezes
    : (sonecaDoModulo(config, alertData && alertData.channelKind) || {}).vezes || 0;
  return {
    ...(alarme ? { despertador: "1" } : {}),
    soneca: "1",
    sonecaAvisoId: String(avisoId),
    sonecaUid: String(uid),
    sonecaToken: await tokenPara(db, uid, avisoId),
    sonecaUrl: urlDaAcao(),
    sonecaIndice: String(ehRepeticao ? alertData.snoozeIndex || 1 : 0),
    sonecaTotal: String(ehRepeticao ? alertData.snoozeTotal || 0 : totalOriginal),
  };
}

/**
 * «Encerrar» no alarme por item = o lembrete foi atendido: marca o
 * compromisso como concluído (mesmos campos do fechamento automático do app:
 * done + REALIZADO), sem apagar nada. Aviso comum não é tocado.
 * Devolve true quando concluiu.
 */
async function concluirAlarmeAoEncerrar(db, uid, avisoId) {
  const snap = await db.collection("users").doc(uid).collection("agendaAlerts").doc(avisoId).get();
  if (!snap.exists) return false;
  const a = snap.data() || {};
  if (!ehAlarmeDoItem(a) || a.sourceType !== "reminder" || !a.sourceId) return false;
  const ref = db.collection("users").doc(uid).collection("reminders").doc(String(a.sourceId));
  const rem = await ref.get();
  if (!rem.exists) return false;
  const d = rem.data() || {};
  if (d.done === true) return false;
  await ref.set(
    {
      done: true,
      status: "REALIZADO",
      despertadorEncerradoEm: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return true;
}

module.exports = {
  VEZES_VALIDAS,
  INTERVALOS_VALIDOS,
  categoriaDoCanal,
  parseSonecaConfig,
  parseSons,
  parseModos,
  parseSomProprio,
  destinoDoSom,
  modoPara,
  sonecaAtivaPara,
  somPara,
  tokenPara,
  tokenValido,
  urlDaAcao,
  criarRepeticoesAposEnvio,
  encerrarSerie,
  adiarSerie,
  dadosDoPush,
  concluirAlarmeAoEncerrar,
  ehAlarmeDoItem,
};
