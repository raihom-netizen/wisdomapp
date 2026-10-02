/**
 * «Despertar no horário» — modo POR ITEM de compromisso particular.
 *
 * Pedido do dono (23/09/2026): «me lembra às 15h de tomar remédio» tem de
 * TOCAR como despertador no celular NA HORA, e depois do horário parar
 * sozinho. Os outros compromissos continuam seguindo à risca «Quando avisar»
 * (1 dia / 1 h / 30 min) — nada aqui muda o plano deles.
 *
 * Campos no `reminders/{id}` (e no espelho `scales/agenda_{id}`, só para a
 * tela mostrar o ⏰):
 *   despertador: true       → o item é um alarme (som de despertador + soneca
 *                             própria, mesmo com o despertador geral desligado)
 *   avisarNoHorario: true   → cria o aviso de lead 0 (no horário exato)
 *   apenasNoHorario: true   → NÃO cria os avisos antecipados de «Quando avisar»
 *                             (lembrete rápido do bot: só toca na hora)
 *
 * Na fila `agendaAlerts` o aviso de lead 0 (e as repetições dele) levam
 * `despertador: true` e `despertadorAte` (último instante em que ainda pode
 * tocar). Passou disso, nada mais sai — «passou, já desativa».
 */

const despertarItem = require("./agenda_despertar_item");

const LEAD_NO_HORARIO = 0;

const CAMPO_DESPERTADOR = "despertador";
const CAMPO_NO_HORARIO = "avisarNoHorario";
const CAMPO_SO_NO_HORARIO = "apenasNoHorario";

/** Toque longo de despertador (catálogo do app: res/raw e Library/Sounds). */
const SOM_PADRAO = "extra_despertar_crescente";
const RE_SOM_LONGO = /^(longo|extra)_[a-z0-9_]+$/;
const RE_SOM_ID = /^[a-z0-9_]{2,40}$/;

/** Repetições padrão do alarme: 3 vezes, a cada 3 minutos. */
const VEZES_PADRAO = 3;
const INTERVALO_PADRAO = 3;

/** Folga para o aviso «no horário» gravado com o horário já em cima. */
const TOLERANCIA_SLOT_MS = 60 * 1000;
/** Quanto depois do horário o 1º toque ainda pode sair (cron atrasado). */
const JANELA_PRIMEIRO_TOQUE_MS = 15 * 60 * 1000;
/** Margem depois da última repetição planejada. */
const MARGEM_FIM_MS = 2 * 60 * 1000;

function ativo(d) {
  return !!d && d[CAMPO_DESPERTADOR] === true;
}

/** O item quer o aviso no horário exato (lead 0)? */
function tocaNoHorario(d) {
  return ativo(d) && d[CAMPO_NO_HORARIO] !== false;
}

/**
 * Antecedências do item: as de «Quando avisar» (a menos que o item peça só
 * no horário) + o lead 0 quando é despertador. Item comum = exatamente as
 * globais, na mesma ordem de antes (maior → menor).
 */
function leadsDoItem(d, leadsGlobais) {
  const globais = (Array.isArray(leadsGlobais) ? leadsGlobais : [])
    .map((x) => parseInt(x, 10) || 0)
    .filter((x) => x > 0);
  if (!ativo(d)) return globais.sort((a, b) => b - a);
  const base = d[CAMPO_SO_NO_HORARIO] === true ? [] : globais;
  const out = [...new Set(base)];
  if (tocaNoHorario(d)) out.push(LEAD_NO_HORARIO);
  return out.sort((a, b) => b - a);
}

/** Lead aceito no envio: o da configuração atual, ou o 0 do despertador. */
function leadPermitido(leadMin, alerta, leadsGlobais) {
  if (leadMin === LEAD_NO_HORARIO) return !!alerta && alerta.despertador === true;
  return (Array.isArray(leadsGlobais) ? leadsGlobais : []).includes(leadMin);
}

/**
 * Vezes/intervalo do alarme: o do despertador do módulo Compromissos quando o
 * usuário ligou (ele escolheu 3/5 × 3/5 min); senão 3 × 3 min.
 */
function repeticoes(config) {
  const m = config && config.soneca && config.soneca.compromisso;
  if (m && m.ativa) {
    return { vezes: Number(m.vezes) || VEZES_PADRAO, intervaloMin: Number(m.intervaloMin) || INTERVALO_PADRAO };
  }
  return { vezes: VEZES_PADRAO, intervaloMin: INTERVALO_PADRAO };
}

/** Último instante em que o alarme (e as repetições) ainda podem tocar. */
function limiteDoAlarme(eventAt, config) {
  const r = repeticoes(config);
  return new Date(eventAt.getTime() + r.vezes * r.intervaloMin * 60 * 1000 + MARGEM_FIM_MS);
}

/** O aviso «no horário» ainda cabe na fila? (horário não passou além da folga) */
function slotNoHorarioAgendavel(eventAt, now) {
  return eventAt.getTime() >= now.getTime() - TOLERANCIA_SLOT_MS;
}

function dataDe(v) {
  if (!v) return null;
  if (typeof v.toDate === "function") return v.toDate();
  if (v instanceof Date) return v;
  return null;
}

/**
 * Decide, no ENVIO, se um aviso vencido da fila sai. Devolve:
 *   { ok: true }                          → segue para o disparo
 *   { ok: false, motivo, marcar: bool }   → não sai (marcar = grava skipped)
 * Para aviso comum o resultado é o MESMO da regra de antes (event_started,
 * lead 0 ignorado, lead fora da configuração, atraso > 15 min / 60 min).
 */
function avaliarEnvio(a, now, leadsGlobais) {
  const alarme = !!a && a.despertador === true;
  const notifyAt = dataDe(a.notifyAt) || new Date(a.notifyAt);
  const eventAt = dataDe(a.eventAt);
  const leadMin = parseInt(a.leadMin, 10) || 0;

  if (eventAt && eventAt <= now) {
    if (!alarme) return { ok: false, motivo: "event_started", marcar: true };
    const ate = dataDe(a.despertadorAte) || new Date(eventAt.getTime() + JANELA_PRIMEIRO_TOQUE_MS);
    if (now > ate) return { ok: false, motivo: "despertador_passou", marcar: true };
  }
  if (!alarme && leadMin <= 0) return { ok: false, motivo: "lead_invalido", marcar: false };
  if (!leadPermitido(leadMin, a, leadsGlobais)) {
    return { ok: false, motivo: "lead_fora_da_configuracao", marcar: true };
  }
  const atrasoMaxMs = leadMin >= 1440 ? 60 * 60 * 1000 : 15 * 60 * 1000;
  if (!a.lastDispatchFailAt && now.getTime() - notifyAt.getTime() > atrasoMaxMs) {
    return { ok: false, motivo: "horario_do_aviso_ja_passou", marcar: true };
  }
  return { ok: true };
}

/**
 * Som e modo do alarme. O que foi escolhido NO PRÓPRIO item manda («só
 * vibrar», tom do formulário); senão um toque longo: o do módulo Compromissos
 * (ou de «todas») quando for longo/extra/próprio; senão o padrão de despertar.
 */
function somDoAlarme(config, srcData) {
  const d = srcData || {};
  // «Despertar» do item (agenda_despertar_item.js) ligado: o toque/«só
  // vibrar» escolhido nele manda também no alarme do horário.
  const despertar = despertarItem.despertarDoItem(d);
  const doDespertar = despertarItem.somDoDespertar(config, "compromisso", despertar);
  if (doDespertar) return doDespertar;
  const doEvento = (d.notificationDeliveryMode || "").toString();
  if (doEvento === "vibrate") return { modo: "vibrar", soundId: "" };
  if (doEvento === "push") return { modo: "silencio", soundId: "" };
  const escolhido = (d.notificationSoundId || "").toString().trim();
  if (RE_SOM_ID.test(escolhido)) return { modo: "som", soundId: escolhido };
  const sons = (config && config.sons) || {};
  for (const s of [sons.compromisso, sons.all]) {
    if (s === "proprio" || RE_SOM_LONGO.test(s || "")) return { modo: "som", soundId: s };
  }
  return { modo: "som", soundId: SOM_PADRAO };
}

/** «14:05» a partir do horário de Brasília do instante. */
function horaBR(dt) {
  const w = new Date(dt.getTime() - 3 * 60 * 60 * 1000);
  return `${String(w.getUTCHours()).padStart(2, "0")}:${String(w.getUTCMinutes()).padStart(2, "0")}`;
}

/** Emoji gravado em `commitmentSymbol` (`emoji:💊`), ou ⏰. */
function emojiDoItem(d) {
  const s = String((d && d.commitmentSymbol) || "");
  return s.startsWith("emoji:") && s.length > 6 ? s.slice(6) : "⏰";
}

/** Título/corpo do push do alarme (no lugar de «Lembrete — Compromisso: X»). */
function textoDoAlarme(d, eventAt) {
  const titulo = ((d && d.title) || "Lembrete").toString().trim();
  const emoji = emojiDoItem(d);
  return {
    title: `⏰ Agora: ${emoji === "⏰" ? "" : `${emoji} `}${titulo}`,
    body: `Está na hora (${horaBR(eventAt)}). Toque em Encerrar quando fizer, ou Adiar.`,
  };
}

module.exports = {
  LEAD_NO_HORARIO,
  CAMPO_DESPERTADOR,
  CAMPO_NO_HORARIO,
  CAMPO_SO_NO_HORARIO,
  SOM_PADRAO,
  VEZES_PADRAO,
  INTERVALO_PADRAO,
  ativo,
  tocaNoHorario,
  leadsDoItem,
  leadPermitido,
  repeticoes,
  limiteDoAlarme,
  slotNoHorarioAgendavel,
  avaliarEnvio,
  somDoAlarme,
  textoDoAlarme,
  emojiDoItem,
};
