import 'agenda_reminder_end_of_day.dart';

(int, int) _parseScaleHHmm(String hhmm) {
  final parts = hhmm.trim().split(':');
  final h = int.tryParse(parts.first.trim()) ?? 0;
  final m = parts.length > 1 ? (int.tryParse(parts[1].trim()) ?? 0) : 0;
  return (h.clamp(0, 23), m.clamp(0, 59));
}

DateTime _clockOnDay(String hhmm, DateTime day) {
  final (h, m) = _parseScaleHHmm(hhmm);
  return DateTime(day.year, day.month, day.day, h, m);
}

/// Fim do turno. 00:00 no fim = fim do dia civil (exceto 00:00–00:00 = 24h).
DateTime scaleEntryEndDateTime({
  required String startHHmm,
  required String endHHmm,
  required DateTime day,
}) {
  final startDt = _clockOnDay(startHHmm, day);
  final (eh, em) = _parseScaleHHmm(endHHmm);
  if (eh == 0 && em == 0) {
    final (sh, sm) = _parseScaleHHmm(startHHmm);
    if (sh == 0 && sm == 0) {
      return startDt.add(const Duration(days: 1));
    }
    return DateTime(day.year, day.month, day.day, 23, 59, 59);
  }
  var endDt = _clockOnDay(endHHmm, day);
  if (!endDt.isAfter(startDt)) {
    endDt = endDt.add(const Duration(days: 1));
  }
  return endDt;
}

/// Até quando o plantão/compromisso aparece no widget nativo (fim + carência).
DateTime scaleEntryWidgetVisibleUntil({
  required String startHHmm,
  required String endHHmm,
  required DateTime day,
  required bool isCompromissoOrMirror,
}) {
  final end = scaleEntryEndDateTime(
    startHHmm: startHHmm,
    endHHmm: endHHmm,
    day: day,
  );
  final grace = isCompromissoOrMirror
      ? kWidgetCompromissoGraceAfterEnd
      : kWidgetPlantaoGraceAfterEnd;
  return end.add(grace);
}

/// Plantão/compromisso ainda visível no widget.
bool scaleEntryVisibleOnWidget({
  required String startHHmm,
  required String endHHmm,
  required DateTime day,
  required DateTime now,
  required bool isCompromissoOrMirror,
}) {
  return now.isBefore(
    scaleEntryWidgetVisibleUntil(
      startHHmm: startHHmm,
      endHHmm: endHHmm,
      day: day,
      isCompromissoOrMirror: isCompromissoOrMirror,
    ),
  );
}
