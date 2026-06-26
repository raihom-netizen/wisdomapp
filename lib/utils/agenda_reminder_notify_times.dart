/// Margem (s) para notificação «quase na hora» no SO vs. fila iminente local.
const int kAgendaImminentGraceSeconds = 90;

/// Antecedências efetivas = **somente** as marcadas em Configurações (sem
/// injetar 10/5/2/1 min extras).
List<int> agendaConfiguredLeadMinutes(
  DateTime eventAt,
  DateTime now,
  List<int> baseLeads,
) {
  return baseLeads.where((m) => m > 0).toSet().toList()..sort();
}

/// @deprecated Use [agendaConfiguredLeadMinutes].
List<int> agendaImminentLeadMinutes(
  DateTime eventAt,
  DateTime now,
  List<int> baseLeads, {
  int maxMinutes = 180,
}) =>
    agendaConfiguredLeadMinutes(eventAt, now, baseLeads);

DateTime _startOfCalendarDay(DateTime d) =>
    DateTime(d.year, d.month, d.day);

/// Horários exatos de notificação — **sem catch-up** antes do lead configurado.
///
/// - Só gera aviso se `eventAt - lead` ainda está **no futuro**.
/// - Evento **hoje**: ignora «1 dia antes» que cairia antes de hoje 00:00.
/// - Lead já vencido = **não reenvia** (evita spam «toda hora»).
List<DateTime> agendaEffectiveNotifyAtList({
  required DateTime eventAt,
  required List<int> leadMinutes,
  required DateTime now,
}) {
  if (!eventAt.isAfter(now)) return [];

  final leads = leadMinutes.where((m) => m > 0).toSet().toList()..sort();
  if (leads.isEmpty) return [];

  final eventDayStart = _startOfCalendarDay(eventAt);
  final todayStart = _startOfCalendarDay(now);
  final isEventToday = eventDayStart == todayStart;

  final result = <DateTime>[];
  final usedMinuteBuckets = <int>{};

  for (final lead in leads) {
    final notifyAt = eventAt.subtract(Duration(minutes: lead));
    if (isEventToday && notifyAt.isBefore(todayStart)) continue;
    if (!notifyAt.isAfter(now)) continue;
    if (!notifyAt.isBefore(eventAt)) continue;
    final bucket = notifyAt.millisecondsSinceEpoch ~/ 60000;
    if (usedMinuteBuckets.contains(bucket)) continue;
    usedMinuteBuckets.add(bucket);
    result.add(notifyAt);
  }

  result.sort();
  return result;
}
