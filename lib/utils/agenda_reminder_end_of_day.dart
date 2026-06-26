import 'package:cloud_firestore/cloud_firestore.dart';

/// Dia civil local do campo `date` do lembrete (Agenda).
DateTime? _agendaReminderCalendarDay(Map<String, dynamic> d) {
  final ts = d['date'];
  if (ts is! Timestamp) return null;
  final date = ts.toDate();
  return DateTime(date.year, date.month, date.day);
}

/// Início do evento (date + time HH:mm). Sem hora = 00:00 do dia civil.
DateTime? agendaReminderEventStartDateTime(Map<String, dynamic> d) {
  final day = _agendaReminderCalendarDay(d);
  if (day == null) return null;
  final timeStr = (d['time'] ?? '').toString().trim();
  if (timeStr.isEmpty) return day;
  final parts = timeStr.split(':');
  if (parts.length < 2) return day;
  final h = int.tryParse(parts[0]) ?? 0;
  final m = int.tryParse(parts[1]) ?? 0;
  return DateTime(day.year, day.month, day.day, h, m);
}

/// Audiência e compromisso permanecem no painel até 24h após o horário marcado
/// (ex.: hoje 09:00 → sai amanhã às 09:00).
DateTime? agendaReminderPanelOpenUntil(Map<String, dynamic> d) {
  final start = agendaReminderEventStartDateTime(d);
  if (start == null) return null;
  return start.add(const Duration(hours: 24));
}

bool agendaReminderOpenStatus(Map<String, dynamic> d) {
  final type = (d['type'] ?? 'compromisso').toString();
  if (type == 'audiencia') {
    return (d['status'] ?? 'EM_ABERTO').toString() == 'EM_ABERTO';
  }
  return (d['done'] ?? false) != true;
}

/// Gravar REALIZADO/done: audiência/compromisso após 24h do horário; outros tipos na hora do evento.
bool agendaShouldAutoCloseNow(Map<String, dynamic> d, DateTime now) {
  if (!agendaReminderOpenStatus(d)) return false;
  final type = (d['type'] ?? 'compromisso').toString();
  if (type == 'audiencia' || type == 'compromisso') {
    final end = agendaReminderPanelOpenUntil(d);
    if (end == null) return false;
    return !now.isBefore(end);
  }
  final dt = agendaReminderEventStartDateTime(d);
  return dt != null && dt.isBefore(now);
}

/// Audiência ou compromisso na Agenda (ignora outros tipos legados).
bool agendaReminderIsAudienciaOrCompromisso(Map<String, dynamic> d) {
  final type = (d['type'] ?? 'compromisso').toString().toLowerCase();
  return type == 'audiencia' || type == 'compromisso';
}

/// Evento ainda não começou — padronização fila v2/v3 (push/e-mail futuros).
bool agendaReminderFutureEventForNotify(
  Map<String, dynamic> d,
  DateTime now,
) {
  if (!agendaReminderIsAudienciaOrCompromisso(d)) return false;
  if (!agendaReminderOpenStatus(d)) return false;
  final start = agendaReminderEventStartDateTime(d);
  return start != null && start.isAfter(now);
}

/// Horário de início do plantão/compromisso na escala.
DateTime? agendaScaleEventStartDateTime(Map<String, dynamic> d) {
  final ts = d['date'];
  if (ts is! Timestamp) return null;
  final date = ts.toDate();
  final startStr = (d['start'] ?? '').toString().trim();
  if (startStr.isEmpty) {
    return DateTime(date.year, date.month, date.day);
  }
  final parts = startStr.split(':');
  final h = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
  final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
  return DateTime(date.year, date.month, date.day, h, m);
}

/// Plantão/compromisso na escala com data/hora ainda no futuro.
bool agendaScaleFutureEventForNotify(
  Map<String, dynamic> d,
  DateTime now,
) {
  if (d['isAgendaMirror'] == true) return false;
  if (d['isProdutividadeFolgaMirror'] == true) return false;
  final start = agendaScaleEventStartDateTime(d);
  return start != null && start.isAfter(now);
}

/// Ainda pode receber lembrete local/push (evento futuro ou janela 24h no painel).
bool agendaReminderEligibleForNotifySchedule(
  Map<String, dynamic> d,
  DateTime now,
) {
  if (!agendaReminderOpenStatus(d)) return false;
  final type = (d['type'] ?? 'compromisso').toString();
  if (type == 'audiencia' || type == 'compromisso') {
    return agendaStillCountedAsOpenOnPanel(d, now);
  }
  final dt = agendaReminderEventStartDateTime(d);
  return dt != null && dt.isAfter(now);
}

/// Contadores e listas «em aberto» no painel: visível até 24h após o horário marcado.
bool agendaStillCountedAsOpenOnPanel(Map<String, dynamic> d, DateTime now) {
  if (!agendaReminderOpenStatus(d)) return false;
  final type = (d['type'] ?? 'compromisso').toString();
  if (type == 'audiencia' || type == 'compromisso') {
    final end = agendaReminderPanelOpenUntil(d);
    if (end == null) return true;
    return now.isBefore(end);
  }
  final dt = agendaReminderEventStartDateTime(d);
  if (dt == null) return true;
  return !dt.isBefore(now);
}
