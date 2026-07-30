/**
 * Preferência por tipo: push, e-mail ou ambos (settings/notifications).
 */

const DELIVERY_BOTH = "both";
const DELIVERY_PUSH_ONLY = "push_only";
const DELIVERY_EMAIL_ONLY = "email_only";

function parseDeliveryMode(raw) {
  const s = (raw || "").toString().trim().toLowerCase();
  if (s === DELIVERY_PUSH_ONLY || s === "push") return DELIVERY_PUSH_ONLY;
  if (s === DELIVERY_EMAIL_ONLY || s === "email") return DELIVERY_EMAIL_ONLY;
  return DELIVERY_BOTH;
}

function deliveryModeForChannelKind(config, channelKind) {
  const k = (channelKind || "").toString().toLowerCase();
  if (k === "audiencia") return parseDeliveryMode(config.deliveryAudiencia);
  if (k === "compromisso") return parseDeliveryMode(config.deliveryCompromisso);
  if (k === "escala") return parseDeliveryMode(config.deliveryEscala);
  if (k === "financeiro") return parseDeliveryMode(config.deliveryFinanceiro);
  return DELIVERY_BOTH;
}

function allowsPushForChannel(config, channelKind) {
  if (config.scaleReminderEnabled === false) return false;
  const mode = deliveryModeForChannelKind(config, channelKind);
  return mode !== DELIVERY_EMAIL_ONLY;
}

function allowsEmailForChannel(config, channelKind) {
  if (config.emailReminderEnabled === false) return false;
  const mode = deliveryModeForChannelKind(config, channelKind);
  return mode !== DELIVERY_PUSH_ONLY;
}

/** Lead já entregue nos canais que o usuário ativou (push e/ou e-mail). */
function isAgendaLeadDeliveryComplete(sourceData, leadMin, config, channelKind) {
  const d = sourceData || {};
  const pushDone = Array.isArray(d.notificadoLeads) && d.notificadoLeads.includes(leadMin);
  const emailDone =
    Array.isArray(d.emailNotificadoLeads) && d.emailNotificadoLeads.includes(leadMin);
  const needPush = allowsPushForChannel(config, channelKind);
  const needEmail = allowsEmailForChannel(config, channelKind);
  if (needPush && !pushDone) return false;
  if (needEmail && !emailDone) return false;
  return true;
}

function parseDeliveryFieldsFromNotifData(notifData) {
  const d = notifData || {};
  return {
    deliveryEscala: parseDeliveryMode(d.deliveryEscala),
    deliveryCompromisso: parseDeliveryMode(d.deliveryCompromisso),
    deliveryAudiencia: parseDeliveryMode(d.deliveryAudiencia),
    deliveryFinanceiro: parseDeliveryMode(d.deliveryFinanceiro),
  };
}

module.exports = {
  DELIVERY_BOTH,
  DELIVERY_PUSH_ONLY,
  DELIVERY_EMAIL_ONLY,
  parseDeliveryMode,
  deliveryModeForChannelKind,
  allowsPushForChannel,
  allowsEmailForChannel,
  isAgendaLeadDeliveryComplete,
  parseDeliveryFieldsFromNotifData,
};
