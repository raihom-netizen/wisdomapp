/**
 * «Despertar» POR ITEM — compromisso, audiência, escala/plantão e plantão
 * recorrente (pré-cadastro em `users/{uid}/locations`).
 *
 * Pedido do dono (26/09/2026): em cada item um botão «Despertar» (liga/desliga)
 * com o SOM escolhido ou «Só vibrar». PADRÃO DESLIGADO — o ITEM decide SE
 * desperta; o módulo (Notificações › Despertador e sons) decide só COMO toca:
 *
 *   despertar: { ativo: bool, modo: "som" | "vibrar", som: "<id do catálogo>" | "" }
 *
 *   - ativo = true  → o aviso chega como despertador (Adiar/Encerrar +
 *                     repetições), com o toque escolhido (vazio = toque longo
 *                     do módulo ou o padrão de despertar) ou só vibrando.
 *                     Vezes/intervalo = os escolhidos no módulo (mesmo com o
 *                     despertador do módulo desligado); sem escolha, 3 × 3 min;
 *   - ativo = false ou campo AUSENTE → aviso normal, sem despertador, MESMO com
 *                     o despertador do módulo ligado (itens antigos e os do
 *                     bot também: sem o campo = desligado).
 *
 * Vale também para Contas: lançamento PENDENTE em `transactions` (o aviso de
 * vencimento só existe enquanto está pendente; pago = aviso cancelado). Isso
 * cobre as parcelas a receber de Vendas e os lançamentos da Frota, que são
 * documentos em `transactions`. O «⏰ Despertar no horário»
 * (`despertador: true`, agenda_despertador.js — bot e compromisso) é outro
 * recurso e segue como era.
 *
 * Plantão lançado a partir de um pré-cadastro recorrente sem `despertar`
 * próprio herda o do pré-cadastro (casamento FORTE: nome base igual ou sigla
 * exata) — assim a série inteira segue o que foi escolhido no pré-cadastro.
 *
 * Módulo puro (sem Firestore): testado em `teste_despertar_item.js`.
 */

const CAMPO = "despertar";
const MODOS = ["som", "vibrar"];
const RE_SOM_ID = /^[a-z0-9_]{2,40}$/;
const RE_SOM_LONGO = /^(longo|extra)_[a-z0-9_]+$/;
/** Mesmo toque padrão do «Despertar no horário» (agenda_despertador.js). */
const SOM_PADRAO = "extra_despertar_crescente";

/** Repetições do despertar quando o módulo não tem vezes/intervalo escolhidos. */
const VEZES_PADRAO = 3;
const INTERVALO_PADRAO = 3;

/** Normaliza o campo do item; `null` quando ausente/inválido (= desligado). */
function despertarDoItem(d) {
  const raw = d && d[CAMPO];
  if (!raw || typeof raw !== "object" || typeof raw.ativo !== "boolean") return null;
  const modo = MODOS.includes(raw.modo) ? raw.modo : "som";
  const som = String(raw.som || "").trim();
  return { ativo: raw.ativo, modo, som: RE_SOM_ID.test(som) ? som : "" };
}

function categoria(channelKind) {
  const k = (channelKind || "").toString().toLowerCase();
  if (k === "audiencia" || k === "compromisso" || k === "financeiro") return k;
  return "escala";
}

/**
 * Config com o despertador do módulo do aviso decidido pelo ITEM: ligado só
 * quando `despertar.ativo === true`; ausente/desligado = sem despertador,
 * mesmo com o módulo ligado. Vezes/intervalo: os escolhidos no módulo, senão
 * 3 × 3 min. Vale também para Contas (lançamento pendente em `transactions`).
 * Nunca altera a config recebida.
 */
function configComDespertar(config, channelKind, despertar) {
  if (!config) return config;
  const cat = categoria(channelKind);
  const ligado = !!despertar && despertar.ativo === true;
  const soneca = { ...(config.soneca || {}) };
  const base = soneca[cat] || {};
  const definido =
    base.definido === true || (base.definido === undefined && Number(base.vezes) > 0 && Number(base.intervaloMin) > 0);
  soneca[cat] = {
    ...base,
    ativa: ligado,
    vezes: definido ? Number(base.vezes) : VEZES_PADRAO,
    intervaloMin: definido ? Number(base.intervaloMin) : INTERVALO_PADRAO,
  };
  return { ...config, soneca };
}

/**
 * Modo e toque do push quando o despertar do item está LIGADO; `null` quando
 * desligado/ausente (vale o modo/som de sempre). Toque vazio = o toque longo
 * (ou próprio) do módulo/«todas», senão o padrão de despertar.
 */
function somDoDespertar(config, channelKind, despertar) {
  if (!despertar || despertar.ativo !== true) return null;
  if (despertar.modo === "vibrar") return { modo: "vibrar", soundId: "" };
  if (despertar.som) return { modo: "som", soundId: despertar.som };
  const sons = (config && config.sons) || {};
  for (const s of [sons[categoria(channelKind)], sons.all]) {
    if (s === "proprio" || RE_SOM_LONGO.test(s || "")) return { modo: "som", soundId: s };
  }
  return { modo: "som", soundId: SOM_PADRAO };
}

function normalizaRotulo(s) {
  return String(s || "")
    .trim()
    .toUpperCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/\s+/g, " ");
}

/** «NOME 08:00 ÀS 20:00 12 HORAS» → «NOME» (mesma regra do app). */
function nomeBase(label) {
  let n = String(label || "").trim();
  n = n.replace(/\s+\d+([,.]\d+)?\s+HORAS\s*$/i, "").trim();
  const m = n.match(/\s+\d{1,2}:\d{2}\s*[àa]s\s*\d{1,2}:\d{2}\s*$/i);
  if (m) n = n.slice(0, m.index).trim();
  return n;
}

/**
 * Pré-cadastro recorrente do plantão (só casamento forte e só entre os que
 * têm `despertar`): nome base igual vale mais que sigla exata.
 */
function localDoPlantao(scaleData, locations) {
  const d = scaleData || {};
  if (d.isCompromisso === true || d.isAgendaMirror === true) return null;
  const label = normalizaRotulo(nomeBase(d.label));
  const abbr = normalizaRotulo(d.abbreviation);
  if (!label && !abbr) return null;
  let melhor = null;
  let melhorNota = 0;
  for (const loc of Array.isArray(locations) ? locations : []) {
    if (!despertarDoItem(loc)) continue;
    const nome = normalizaRotulo(nomeBase(loc.name));
    const sigla = normalizaRotulo(loc.abbreviation);
    let nota = 0;
    if (nome && label && nome === label) nota += 100;
    if (sigla && abbr && sigla === abbr) nota += 50;
    if (nota > melhorNota) {
      melhorNota = nota;
      melhor = loc;
    }
  }
  return melhor;
}

/**
 * Despertar que vale para o aviso: o do próprio item; no plantão sem o campo,
 * o do pré-cadastro recorrente; senão `null` (= desligado).
 */
function despertarEfetivo(srcData, { sourceType, locations } = {}) {
  // Conta paga não desperta (defesa: o aviso já é cancelado ao pagar).
  if (sourceType === "transaction" && srcData && srcData.status !== "pending") return null;
  const doItem = despertarDoItem(srcData);
  if (doItem) return doItem;
  if (sourceType === "scale" && Array.isArray(locations) && locations.length) {
    const loc = localDoPlantao(srcData, locations);
    if (loc) return despertarDoItem(loc);
  }
  return null;
}

module.exports = {
  CAMPO,
  SOM_PADRAO,
  VEZES_PADRAO,
  INTERVALO_PADRAO,
  despertarDoItem,
  configComDespertar,
  somDoDespertar,
  localDoPlantao,
  despertarEfetivo,
  nomeBase,
};
