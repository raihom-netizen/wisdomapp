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

  static int _cents(double v) => (v * 100).round();

  /// Semanas não pagas que o valor cobre **por inteiro** (ordem crescente).
  ///
  /// Correção autorizada pelo dono (02/10/2026): antes a semana entrava assim
  /// que «começava» a ser paga (R$ 50 com semanas de R$ 10/20/30 marcava 1, 2
  /// e 3 = R$ 60) e, com valor menor que a 1ª semana, marcava a semana mesmo
  /// assim. Agora só entra semana cuja soma cabe no valor (+ [carry], a sobra
  /// acumulada de depósitos anteriores); o que sobra fica guardado para a
  /// próxima semana.
  static List<int> weeksForDepositAmount({
    required double amount,
    required List<FiftyTwoWeeksWeekEntry> schedule,
    required List<int> paidWeeks,
    double carry = 0,
  }) {
    if (schedule.isEmpty) return const [];
    var pool = _cents(amount) + _cents(carry);
    if (pool <= 0) return const [];
    final paid = paidWeeks.toSet();
    final unpaid = schedule.where((e) => !paid.contains(e.week)).toList()
      ..sort((a, b) => a.week.compareTo(b.week));

    final selected = <int>[];
    for (final e in unpaid) {
      final c = _cents(e.amount);
      if (c > pool) break;
      selected.add(e.week);
      pool -= c;
    }
    return selected;
  }

  /// Prévia de UM depósito sobre semanas já pagas por outros depósitos — a
  /// mesma regra de [allocateDeposits] (escolhidas primeiro, só semana
  /// inteira). Usada ao editar o valor de um depósito.
  static List<int> weeksForSingleDeposit({
    required double amount,
    required List<FiftyTwoWeeksWeekEntry> schedule,
    required List<int> paidWeeks,
    List<int> chosenWeeks = const [],
  }) {
    final others = paidWeeks.toSet();
    final alloc = allocateDeposits(
      schedule: schedule,
      deposits: [
        FiftyTwoWeeksDeposit(
          amount: sumWeekAmounts(schedule, others),
          chosenWeeks: others.toList(),
        ),
        FiftyTwoWeeksDeposit(amount: amount, chosenWeeks: chosenWeeks),
      ],
    );
    return alloc.weeksByDeposit[1];
  }

  /// Distribui os depósitos (ordem cronológica) pelas semanas — usado no
  /// recálculo da meta. Regras:
  /// - só marca semana coberta por inteiro; a sobra acumula para a próxima;
  /// - semanas escolhidas pelo usuário no depósito ([FiftyTwoWeeksDeposit.chosenWeeks])
  ///   são atendidas primeiro; se alguma escolhida não coube, o dinheiro fica
  ///   guardado (não vai para outra semana sem o usuário pedir);
  /// - sem escolha, preenche as semanas não pagas em ordem crescente;
  /// - depósito negativo (resgate) tira o dinheiro: se faltar, desmarca as
  ///   últimas semanas marcadas até o saldo fechar.
  static FiftyTwoWeeksAllocation allocateDeposits({
    required List<FiftyTwoWeeksWeekEntry> schedule,
    required List<FiftyTwoWeeksDeposit> deposits,
  }) {
    final byWeek = <int, int>{
      for (final e in schedule) e.week: _cents(e.amount),
    };
    final ordered = [...schedule]..sort((a, b) => a.week.compareTo(b.week));
    final paid = <int>{};
    final weeksByDeposit = <List<int>>[];
    final marked = <({int dep, int week})>[];
    var pool = 0;

    void mark(int dep, int week) {
      paid.add(week);
      weeksByDeposit[dep].add(week);
      marked.add((dep: dep, week: week));
      pool -= byWeek[week]!;
    }

    for (var i = 0; i < deposits.length; i++) {
      final dep = deposits[i];
      weeksByDeposit.add(<int>[]);
      pool += _cents(dep.amount);
      while (pool < 0 && marked.isNotEmpty) {
        final last = marked.removeLast();
        paid.remove(last.week);
        weeksByDeposit[last.dep].remove(last.week);
        pool += byWeek[last.week]!;
      }
      if (pool <= 0) continue;

      var chosenMissing = false;
      final chosen = dep.chosenWeeks.toSet().toList()..sort();
      for (final w in chosen) {
        final c = byWeek[w];
        if (c == null || paid.contains(w)) continue;
        if (c <= pool) {
          mark(i, w);
        } else {
          chosenMissing = true;
        }
      }
      if (chosenMissing) continue;
      for (final e in ordered) {
        if (paid.contains(e.week)) continue;
        if (byWeek[e.week]! > pool) break;
        mark(i, e.week);
      }
    }
    for (final l in weeksByDeposit) {
      l.sort();
    }
    return FiftyTwoWeeksAllocation(
      weeksByDeposit: weeksByDeposit,
      paidWeeks: paid.toList()..sort(),
      leftover: pool / 100.0,
    );
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

/// Um depósito (ou resgate, valor negativo) para [FiftyTwoWeeksPlan.allocateDeposits].
class FiftyTwoWeeksDeposit {
  const FiftyTwoWeeksDeposit({
    required this.amount,
    this.chosenWeeks = const [],
  });

  final double amount;
  final List<int> chosenWeeks;
}

class FiftyTwoWeeksAllocation {
  const FiftyTwoWeeksAllocation({
    required this.weeksByDeposit,
    required this.paidWeeks,
    required this.leftover,
  });

  /// Mesma ordem dos depósitos informados.
  final List<List<int>> weeksByDeposit;
  final List<int> paidWeeks;

  /// Dinheiro guardado que ainda não fechou uma semana inteira.
  final double leftover;
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
