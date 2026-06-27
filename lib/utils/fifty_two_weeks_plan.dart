import 'package:cloud_firestore/cloud_firestore.dart';

/// Projeto 52 semanas: depósito da semana *n* = incremento × *n* (soma = meta).
class FiftyTwoWeeksPlan {
  FiftyTwoWeeksPlan._();

  static const int weeks = 52;
  static const int triangularSum = 1378; // 52 × 53 / 2

  static double weeklyIncrementForTarget(double target) {
    if (target <= 0) return 0;
    return target / triangularSum;
  }

  static double amountForWeek(double target, int week) {
    if (week < 1 || week > weeks || target <= 0) return 0;
    return weeklyIncrementForTarget(target) * week;
  }

  static DateTime normalizePlanStart(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    // Segunda-feira da semana do início (ISO weekday).
    return d.subtract(Duration(days: d.weekday - DateTime.monday));
  }

  static List<FiftyTwoWeeksWeekEntry> buildSchedule({
    required double target,
    required DateTime planStart,
  }) {
    if (target <= 0) return const [];
    final start = normalizePlanStart(planStart);
    final inc = weeklyIncrementForTarget(target);
    final entries = <FiftyTwoWeeksWeekEntry>[];
    var accumulated = 0.0;
    for (var week = 1; week <= weeks - 1; week++) {
      final amount = double.parse((inc * week).toStringAsFixed(2));
      accumulated += amount;
      entries.add(
        FiftyTwoWeeksWeekEntry(
          week: week,
          amount: amount,
          dueDate: start.add(Duration(days: 7 * (week - 1))),
        ),
      );
    }
    final lastAmount = double.parse((target - accumulated).toStringAsFixed(2));
    entries.add(
      FiftyTwoWeeksWeekEntry(
        week: weeks,
        amount: lastAmount > 0 ? lastAmount : double.parse((inc * weeks).toStringAsFixed(2)),
        dueDate: start.add(Duration(days: 7 * (weeks - 1))),
      ),
    );
    return entries;
  }

  static int currentWeekNumber(DateTime planStart, [DateTime? now]) {
    final start = normalizePlanStart(planStart);
    final today = now ?? DateTime.now();
    final days = DateTime(today.year, today.month, today.day)
        .difference(start)
        .inDays;
    if (days < 0) return 1;
    return (days / 7).floor().clamp(0, weeks - 1) + 1;
  }

  static FiftyTwoWeeksWeekEntry? currentWeekEntry({
    required double target,
    required DateTime planStart,
    DateTime? now,
  }) {
    final n = currentWeekNumber(planStart, now);
    final schedule = buildSchedule(target: target, planStart: planStart);
    if (schedule.isEmpty || n > schedule.length) return null;
    return schedule[n - 1];
  }

  static double expectedDepositedByWeek({
    required double target,
    required int throughWeek,
  }) {
    if (throughWeek <= 0 || target <= 0) return 0;
    final w = throughWeek.clamp(1, weeks);
    final inc = weeklyIncrementForTarget(target);
    return inc * w * (w + 1) / 2;
  }

  static List<int> paidWeeksFromData(Map<String, dynamic> goalData) {
    final raw = goalData['weeksPaid'];
    if (raw is List) {
      return raw.whereType<num>().map((e) => e.toInt()).where((w) => w >= 1 && w <= weeks).toList();
    }
    return const [];
  }

  static bool is52WeeksGoal(Map<String, dynamic> data) =>
      (data['planType'] ?? '').toString() == '52weeks';

  static DateTime? planStartFromData(Map<String, dynamic> data) {
    final ts = data['planStartDate'];
    if (ts is Timestamp) return ts.toDate();
    return null;
  }

  /// Agrupa cronograma por mês (rótulo + entradas).
  static List<({String monthKey, String label, List<FiftyTwoWeeksWeekEntry> weeks})>
      groupScheduleByMonth(List<FiftyTwoWeeksWeekEntry> schedule) {
    if (schedule.isEmpty) return const [];
    final map = <String, List<FiftyTwoWeeksWeekEntry>>{};
    for (final e in schedule) {
      map.putIfAbsent(e.monthKey, () => []).add(e);
    }
    final keys = map.keys.toList()..sort();
    return keys.map((k) {
      final first = map[k]!.first.dueDate;
      final label = _monthLabelPt(first);
      return (monthKey: k, label: label, weeks: map[k]!);
    }).toList();
  }

  static String _monthLabelPt(DateTime d) {
    const months = [
      'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
      'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
    ];
    return '${months[d.month - 1]} ${d.year}';
  }

  /// Semanas não pagas a marcar quando o usuário informa um valor (ordem crescente).
  static List<int> weeksForDepositAmount({
    required double amount,
    required List<FiftyTwoWeeksWeekEntry> schedule,
    required List<int> paidWeeks,
  }) {
    if (amount <= 0 || schedule.isEmpty) return const [];
    final paid = paidWeeks.toSet();
    final unpaid = schedule.where((e) => !paid.contains(e.week)).toList()
      ..sort((a, b) => a.week.compareTo(b.week));
    if (unpaid.isEmpty) return const [];

    final selected = <int>[];
    var sum = 0.0;
    for (final e in unpaid) {
      if (sum >= amount - 0.009) break;
      selected.add(e.week);
      sum += e.amount;
    }
    if (selected.isEmpty) selected.add(unpaid.first.week);
    return selected;
  }

  static double sumWeekAmounts(
    List<FiftyTwoWeeksWeekEntry> schedule,
    Iterable<int> weeks,
  ) {
    final set = weeks.toSet();
    var total = 0.0;
    for (final e in schedule) {
      if (set.contains(e.week)) total += e.amount;
    }
    return total;
  }
}

class FiftyTwoWeeksWeekEntry {
  const FiftyTwoWeeksWeekEntry({
    required this.week,
    required this.amount,
    required this.dueDate,
  });

  final int week;
  final double amount;
  final DateTime dueDate;

  String get monthKey =>
      '${dueDate.year}-${dueDate.month.toString().padLeft(2, '0')}';
}
