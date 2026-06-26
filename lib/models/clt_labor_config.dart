import 'scale_rates.dart';

/// Parâmetros CLT para cálculo de hora normal, extras e adicional noturno.
class CltLaborConfig {
  const CltLaborConfig({
    this.monthlySalary = 2200,
    this.monthlyHours = 220,
    this.overtimeWeekdayPercent = 50,
    this.overtimeSundayHolidayPercent = 100,
    this.nightAdditionalPercent = 20,
    this.insalubrityGradePercent = 0,
    this.dangerPercent = 0,
    this.nightHourReduced = true,
    this.extendNightAfter5am = true,
    this.maxDailyOvertimeHours = 2,
    this.fixedHourOverride = 0,
  });

  final double monthlySalary;
  /// Jornada mensal (ex.: 220h = 44h/semana, 180h = 36h/semana).
  final int monthlyHours;
  final double overtimeWeekdayPercent;
  final double overtimeSundayHolidayPercent;
  final double nightAdditionalPercent;
  /// 0, 10, 20 ou 40 (insalubridade sobre salário-mínimo — simplificado % aqui).
  final double insalubrityGradePercent;
  final double dangerPercent;
  final bool nightHourReduced;
  final bool extendNightAfter5am;
  final int maxDailyOvertimeHours;
  /// Se > 0, ignora salário/jornada e usa valor fixo informado pelo usuário.
  final double fixedHourOverride;

  double get hourNormal {
    if (fixedHourOverride > 0) return fixedHourOverride;
    if (monthlyHours <= 0) return 0;
    return monthlySalary / monthlyHours;
  }

  double get hourWithNightAdditional =>
      hourNormal * (1 + nightAdditionalPercent / 100);

  double get hourOvertimeWeekday =>
      hourNormal * (1 + overtimeWeekdayPercent / 100);

  double get hourOvertimeSundayHoliday =>
      hourNormal * (1 + overtimeSundayHolidayPercent / 100);

  double get hourOvertimeNight =>
      hourWithNightAdditional * (1 + overtimeWeekdayPercent / 100);

  /// Converte para tabela uniforme usada pela Calculadora / Escalas.
  ScaleRates toScaleRates() {
    final hn = hourNormal;
    final hnight = hourWithNightAdditional;
    return ScaleRates(
      nightStart: '22:00',
      nightEnd: '05:00',
      valueDiurno: List<double>.filled(7, hn),
      valueNoturno: List<double>.filled(7, hnight),
      ac4NightAnchorPreviousDay: false,
    );
  }

  Map<String, dynamic> toMap() => {
        'monthlySalary': monthlySalary,
        'monthlyHours': monthlyHours,
        'overtimeWeekdayPercent': overtimeWeekdayPercent,
        'overtimeSundayHolidayPercent': overtimeSundayHolidayPercent,
        'nightAdditionalPercent': nightAdditionalPercent,
        'insalubrityGradePercent': insalubrityGradePercent,
        'dangerPercent': dangerPercent,
        'nightHourReduced': nightHourReduced,
        'extendNightAfter5am': extendNightAfter5am,
        'maxDailyOvertimeHours': maxDailyOvertimeHours,
        'fixedHourOverride': fixedHourOverride,
      };

  factory CltLaborConfig.fromMap(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return CltLaborConfig.defaults();
    double d(dynamic v, double def) {
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '') ?? def;
    }

    int i(dynamic v, int def) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? def;
    }

    return CltLaborConfig(
      monthlySalary: d(data['monthlySalary'], 2200),
      monthlyHours: i(data['monthlyHours'], 220),
      overtimeWeekdayPercent: d(data['overtimeWeekdayPercent'], 50),
      overtimeSundayHolidayPercent: d(data['overtimeSundayHolidayPercent'], 100),
      nightAdditionalPercent: d(data['nightAdditionalPercent'], 20),
      insalubrityGradePercent: d(data['insalubrityGradePercent'], 0),
      dangerPercent: d(data['dangerPercent'], 0),
      nightHourReduced: data['nightHourReduced'] != false,
      extendNightAfter5am: data['extendNightAfter5am'] != false,
      maxDailyOvertimeHours: i(data['maxDailyOvertimeHours'], 2),
      fixedHourOverride: d(data['fixedHourOverride'], 0),
    );
  }

  /// Padrão legal CLT (Constituição + CLT + Súmula 60 TST) — usuário só clica em Ativar.
  factory CltLaborConfig.defaults() => const CltLaborConfig();

  CltLaborConfig copyWith({
    double? monthlySalary,
    int? monthlyHours,
    double? overtimeWeekdayPercent,
    double? overtimeSundayHolidayPercent,
    double? nightAdditionalPercent,
    double? insalubrityGradePercent,
    double? dangerPercent,
    bool? nightHourReduced,
    bool? extendNightAfter5am,
    int? maxDailyOvertimeHours,
    double? fixedHourOverride,
  }) =>
      CltLaborConfig(
        monthlySalary: monthlySalary ?? this.monthlySalary,
        monthlyHours: monthlyHours ?? this.monthlyHours,
        overtimeWeekdayPercent:
            overtimeWeekdayPercent ?? this.overtimeWeekdayPercent,
        overtimeSundayHolidayPercent: overtimeSundayHolidayPercent ??
            this.overtimeSundayHolidayPercent,
        nightAdditionalPercent:
            nightAdditionalPercent ?? this.nightAdditionalPercent,
        insalubrityGradePercent:
            insalubrityGradePercent ?? this.insalubrityGradePercent,
        dangerPercent: dangerPercent ?? this.dangerPercent,
        nightHourReduced: nightHourReduced ?? this.nightHourReduced,
        extendNightAfter5am: extendNightAfter5am ?? this.extendNightAfter5am,
        maxDailyOvertimeHours:
            maxDailyOvertimeHours ?? this.maxDailyOvertimeHours,
        fixedHourOverride: fixedHourOverride ?? this.fixedHourOverride,
      );
}
