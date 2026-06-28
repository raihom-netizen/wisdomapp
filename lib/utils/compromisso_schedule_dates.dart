/// Gera listas de dias civis para compromissos em lote (Agenda).
class CompromissoScheduleDates {
  CompromissoScheduleDates._();

  static DateTime norm(DateTime d) => DateTime(d.year, d.month, d.day);

  static String dayKey(DateTime d) =>
      '${d.year}-${d.month}-${d.day}';

  static List<DateTime> uniqueSorted(Iterable<DateTime> days) {
    final map = <String, DateTime>{};
    for (final raw in days) {
      final n = norm(raw);
      map[dayKey(n)] = n;
    }
    final list = map.values.toList()..sort((a, b) => a.compareTo(b));
    return list;
  }

  /// Todos os dias entre [start] e [end] (inclusive).
  static List<DateTime> daysInPeriod(DateTime start, DateTime end) {
    final a = norm(start);
    final b = norm(end);
    if (b.isBefore(a)) return [];
    final out = <DateTime>[];
    var cur = a;
    while (!cur.isAfter(b)) {
      out.add(cur);
      cur = cur.add(const Duration(days: 1));
    }
    return out;
  }

  /// [weekdays] usa convenção [DateTime.weekday] (1=seg … 7=dom).
  static List<DateTime> weekdaysInRange({
    required Set<int> weekdays,
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) {
    if (weekdays.isEmpty) return [];
    final start = norm(rangeStart);
    final end = norm(rangeEnd);
    if (end.isBefore(start)) return [];
    final out = <DateTime>[];
    var cur = start;
    while (!cur.isAfter(end)) {
      if (weekdays.contains(cur.weekday)) out.add(cur);
      cur = cur.add(const Duration(days: 1));
    }
    return out;
  }

  static DateTime monthStart(DateTime ref) => DateTime(ref.year, ref.month, 1);

  static DateTime monthEnd(DateTime ref) =>
      DateTime(ref.year, ref.month + 1, 0);

  static DateTime yearStart(DateTime ref) => DateTime(ref.year, 1, 1);

  static DateTime yearEnd(DateTime ref) => DateTime(ref.year, 12, 31);

  /// Restante do ano a partir de [from] (inclusive).
  static DateTime restOfYearStart(DateTime from) {
    final today = norm(from);
    final yStart = yearStart(today);
    return today.isBefore(yStart) ? yStart : today;
  }
}
