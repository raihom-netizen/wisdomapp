/// Como o usuário quer receber lembretes de agenda por tipo.
enum AgendaTypeDeliveryMode {
  /// Push (celular/app) + e-mail quando o e-mail global estiver ligado.
  both,

  /// Apenas notificação no aparelho / push FCM.
  pushOnly,

  /// Apenas e-mail (servidor); sem agendar push local.
  emailOnly,
}

const String kDeliveryFirestoreBoth = 'both';
const String kDeliveryFirestorePushOnly = 'push_only';
const String kDeliveryFirestoreEmailOnly = 'email_only';

AgendaTypeDeliveryMode agendaTypeDeliveryModeFromFirestore(dynamic raw) {
  final s = (raw ?? '').toString().trim().toLowerCase();
  if (s.isEmpty) return AgendaTypeDeliveryMode.both;
  if (s == kDeliveryFirestorePushOnly || s == 'push') {
    return AgendaTypeDeliveryMode.pushOnly;
  }
  if (s == kDeliveryFirestoreEmailOnly || s == 'email') {
    return AgendaTypeDeliveryMode.emailOnly;
  }
  return AgendaTypeDeliveryMode.both;
}

/// Audiências: padrão celular + e-mail (evento sério).
AgendaTypeDeliveryMode defaultAudienciaDeliveryFromFirestore(dynamic raw) {
  if (raw == null) return AgendaTypeDeliveryMode.both;
  return agendaTypeDeliveryModeFromFirestore(raw);
}

String agendaTypeDeliveryModeToFirestore(AgendaTypeDeliveryMode mode) {
  switch (mode) {
    case AgendaTypeDeliveryMode.pushOnly:
      return kDeliveryFirestorePushOnly;
    case AgendaTypeDeliveryMode.emailOnly:
      return kDeliveryFirestoreEmailOnly;
    case AgendaTypeDeliveryMode.both:
      return kDeliveryFirestoreBoth;
  }
}

/// POLÍTICA DE ENTREGA (igual ao Controle Total, 18/09/2026): UMA fonte por
/// aparelho — o SERVIDOR (fila `agendaAlerts` → FCM/APNs/Web Push + e-mail).
///
/// Antes o app agendava a notificação local E o servidor mandava o push do
/// mesmo aviso: com o app fechado nada cancela um quando o outro chega (o id
/// local não é reproduzível fora do Dart), então cada aviso chegava DUAS vezes.
///
/// Com `true`, Android, iPhone e Web não agendam nada localmente; o refresh só
/// cancela os locais antigos que ainda estavam pendentes. O despertador/soneca
/// continua com o app fechado porque também é do servidor: o 1.º aviso e cada
/// repetição são docs da fila (`agenda_soneca.js`), com os botões Adiar/Encerrar
/// (`ctSonecaAcao`); no Android chega como data-only de alta prioridade e o
/// app desenha a notificação em segundo plano.
const bool kAgendaNotificationsServerPushOnly = true;

/// iOS: servidor + backup local — DESLIGADO (era a causa do aviso em dobro).
bool get agendaHybridIosLocalBackupEnabled => false;

/// `true` = o app não agenda lembretes de agenda no aparelho (só o servidor).
bool agendaSkipsLocalSchedulingBecauseServerPushOnly() {
  if (!kAgendaNotificationsServerPushOnly) return false;
  return !agendaHybridIosLocalBackupEnabled;
}

/// Push local / FCM permitido para este tipo.
bool agendaAllowsLocalOrPushDelivery(AgendaTypeDeliveryMode mode) {
  return mode != AgendaTypeDeliveryMode.emailOnly;
}

/// E-mail permitido para este tipo (ainda exige e-mail global ligado).
bool agendaAllowsEmailDelivery(AgendaTypeDeliveryMode mode) {
  return mode != AgendaTypeDeliveryMode.pushOnly;
}

Map<String, dynamic> agendaDeliveryModesToFirestore({
  required AgendaTypeDeliveryMode escala,
  required AgendaTypeDeliveryMode compromisso,
  required AgendaTypeDeliveryMode audiencia,
  AgendaTypeDeliveryMode? financeiro,
}) {
  return {
    'deliveryEscala': agendaTypeDeliveryModeToFirestore(escala),
    'deliveryCompromisso': agendaTypeDeliveryModeToFirestore(compromisso),
    'deliveryAudiencia': agendaTypeDeliveryModeToFirestore(audiencia),
    if (financeiro != null)
      'deliveryFinanceiro': agendaTypeDeliveryModeToFirestore(financeiro),
  };
}
