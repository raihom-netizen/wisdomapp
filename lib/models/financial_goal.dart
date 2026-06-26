import 'dart:math' as math;

/// Tipos de metas financeiras (categorias).
enum GoalCategory {
  reservaEmergencia('💰 Reserva de Emergência', 'reserva_emergencia'),
  casa('🏠 Compra (Casa/Lote)', 'casa'),
  veiculo('🚗 Veículo', 'veiculo'),
  viagem('✈️ Viagem', 'viagem'),
  estudo('🎓 Estudo', 'estudo'),
  investimento('📈 Investimento', 'investimento'),
  personalizada('📦 Meta Personalizada', 'personalizada');

  final String label;
  final String id;
  const GoalCategory(this.label, this.id);
  static GoalCategory fromId(String? id) =>
      GoalCategory.values.firstWhere((e) => e.id == id, orElse: () => GoalCategory.personalizada);
}

enum GoalPriority { alta, media, baixa }

extension GoalPriorityExt on GoalPriority {
  String get label => switch (this) {
    GoalPriority.alta => 'Alta',
    GoalPriority.media => 'Média',
    GoalPriority.baixa => 'Baixa',
  };
}

enum GoalStatus { emAndamento, concluida, atrasada }

extension GoalStatusExt on GoalStatus {
  String get label => switch (this) {
    GoalStatus.emAndamento => 'Em andamento',
    GoalStatus.concluida => 'Concluída',
    GoalStatus.atrasada => 'Atrasada',
  };
}

/// Projeção inteligente: quanto guardar/mês, prazo estimado, se está no ritmo.
class GoalProjection {
  final double monthlyNeeded;
  final int daysRemaining;
  final double? currentMonthlyPace;
  final bool isOnTrack;
  final int? monthsAheadOrBehind; // positivo = atrasado, negativo = adiantado
  final DateTime? projectedCompletion;

  const GoalProjection({
    required this.monthlyNeeded,
    required this.daysRemaining,
    this.currentMonthlyPace,
    required this.isOnTrack,
    this.monthsAheadOrBehind,
    this.projectedCompletion,
  });

  String get statusMessage {
    if (daysRemaining <= 0 && !isOnTrack) return 'Prazo vencido';
    if (isOnTrack) return 'No ritmo certo para bater a meta no prazo.';
    if (monthsAheadOrBehind != null && monthsAheadOrBehind! > 0) {
      return 'No ritmo atual você atingirá $monthsAheadOrBehind ${monthsAheadOrBehind == 1 ? 'mês' : 'meses'} depois do prazo.';
    }
    if (monthsAheadOrBehind != null && monthsAheadOrBehind! < 0) {
      return 'No ritmo atual você atingirá ${(-monthsAheadOrBehind!)} ${-monthsAheadOrBehind! == 1 ? 'mês' : 'meses'} antes do prazo!';
    }
    return 'Guarde R\$ ${monthlyNeeded.toStringAsFixed(0)}/mês para atingir no prazo.';
  }
}

/// Calcula projeção inteligente: quanto guardar/mês, ritmo, prazo estimado.
/// Com juros: FV = PV(1+i)^n → n = ln(FV/PV)/ln(1+i)
GoalProjection computeGoalProjection({
  required double target,
  required double current,
  required DateTime? dueDate,
  required Map<String, double> contribByMonth,
  double monthlyInterestRate = 0,
}) {
  final faltam = (target - current).clamp(0.0, double.infinity);
  final now = DateTime.now();

  if (faltam <= 0) {
    return GoalProjection(
      monthlyNeeded: 0,
      daysRemaining: 0,
      isOnTrack: true,
    );
  }

  int daysRemaining = 0;
  int monthsLeft = 0;
  if (dueDate != null) {
    daysRemaining = dueDate.difference(now).inDays.clamp(0, 9999);
    monthsLeft = (dueDate.year - now.year) * 12 + (dueDate.month - now.month);
    if (dueDate.day < now.day) monthsLeft = (monthsLeft - 1).clamp(1, 999);
    if (monthsLeft < 1) monthsLeft = 1;
  } else {
    monthsLeft = 12; // padrão 1 ano se sem prazo
  }

  double monthlyNeeded;
  if (monthlyInterestRate > 0) {
    // FV = PMT * (((1+i)^n - 1) / i)  →  PMT = FV * i / ((1+i)^n - 1)
    final i = monthlyInterestRate / 100;
    if (i <= 0 || monthsLeft <= 0) {
      monthlyNeeded = faltam / monthsLeft;
    } else {
      final denom = math.pow(1 + i, monthsLeft).toDouble() - 1;
      if (denom <= 0) {
        monthlyNeeded = faltam / monthsLeft;
      } else {
        monthlyNeeded = faltam * i / denom;
      }
    }
  } else {
    monthlyNeeded = faltam / monthsLeft;
  }

  // Ritmo atual (média dos últimos 3 meses com aportes)
  final sortedMonths = contribByMonth.keys.toList()..sort();
  double currentMonthlyPace = 0;
  if (sortedMonths.isNotEmpty) {
    final recent = sortedMonths.reversed.take(3).toList();
    double sum = 0;
    for (final m in recent) {
      sum += contribByMonth[m] ?? 0;
    }
    currentMonthlyPace = recent.isNotEmpty ? sum / recent.length : 0;
  }

  bool isOnTrack = true;
  int? monthsAheadOrBehind;
  DateTime? projectedCompletion;

  if (currentMonthlyPace > 0 && dueDate != null) {
    // Quantos meses para atingir no ritmo atual (sem juros simplificado)?
    final monthsToReach = (faltam / currentMonthlyPace).ceil();
    monthsAheadOrBehind = monthsToReach - monthsLeft;
    isOnTrack = monthsAheadOrBehind <= 0;
    projectedCompletion = DateTime(now.year, now.month + monthsToReach, 1);
  } else if (currentMonthlyPace == 0 && dueDate != null && monthsLeft > 0) {
    isOnTrack = monthlyNeeded <= 0; // impossível sem aportes
  }

  return GoalProjection(
    monthlyNeeded: monthlyNeeded,
    daysRemaining: daysRemaining,
    currentMonthlyPace: currentMonthlyPace > 0 ? currentMonthlyPace : null,
    isOnTrack: isOnTrack,
    monthsAheadOrBehind: monthsAheadOrBehind,
    projectedCompletion: projectedCompletion,
  );
}

/// Valor futuro com juros compostos: FV = PV(1+i)^n
double futureValueCompound(double pv, double monthlyRatePercent, int months) {
  if (months <= 0) return pv;
  final i = monthlyRatePercent / 100;
  return pv * math.pow(1 + i, months).toDouble();
}
