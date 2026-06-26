/// Piso para agendar aviso local: agora (fuso do aparelho).
///
/// Antes usava corte fixo às 15h, o que impedia audiências/compromissos da
/// manhã (ex.: 10:30 com aviso 09:30) de entrarem na fila.
DateTime agendaNotificationScheduleFloor([DateTime? reference]) {
  return reference ?? DateTime.now();
}

/// Compatível com chamadas antigas — mesmo que [agendaNotificationScheduleFloor].
DateTime agendaNotificationForwardCutoff([DateTime? reference]) =>
    agendaNotificationScheduleFloor(reference);

/// Meia-noite do dia seguinte (fuso local) — migração em massa e fila futura.
DateTime agendaNotificationStartOfTomorrow([DateTime? reference]) {
  final now = reference ?? DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return today.add(const Duration(days: 1));
}

/// Evento com dia civil >= amanhã (para fila/migração em massa).
bool agendaEventOnOrAfterTomorrow(DateTime eventDay, [DateTime? reference]) {
  final tomorrow = agendaNotificationStartOfTomorrow(reference);
  final day = DateTime(eventDay.year, eventDay.month, eventDay.day);
  return !day.isBefore(tomorrow);
}

/// Evento ainda não começou — pode receber lembrete.
bool agendaEventEligibleForForwardNotify(
  DateTime eventAt, {
  DateTime? now,
}) {
  final n = now ?? DateTime.now();
  return eventAt.isAfter(n);
}
