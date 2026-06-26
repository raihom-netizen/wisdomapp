/// Valores padrão de escala (hora diurna/noturna por dia da semana).
/// Base: Portaria AC4 (Goiás) — novo valor junho 2024, segurança pública GO.
/// Diurno: 05h01–21h59 | Noturno: 22h–05h
///
/// **Lógica de cálculo** (`computeShift`) vai no **código do app** — usuários não “ativam” isso
/// na tela. Novos ajustes de regra exigem **nova versão** (ou deploy web). Opcionalmente,
/// `ac4NightAnchorPreviousDay` em `config/scale_rates` (Firestore) permite desligar o modo
/// AC4 correto sem republicar app (caso raro de rollback).
class ScaleRates {
  /// Nome do padrão (AC4 GO) para exibição no admin.
  static const String defaultLabel = 'AC4 (GO)';
  /// Início do período noturno (ex: "22:00")
  final String nightStart;
  /// Fim do período noturno (ex: "05:00")
  final String nightEnd;
  /// Valor hora diurna por dia da semana (0 = domingo .. 6 = sábado)
  final List<double> valueDiurno;
  /// Valor hora noturna por dia da semana (0 = domingo .. 6 = sábado)
  final List<double> valueNoturno;
  /// Se true (padrão): madrugada 00h–05h usa noturno do dia em que começou às 22h (AC4).
  /// Se false: comportamento antigo (noturno pelo dia civil — incorreto para AC4).
  final bool ac4NightAnchorPreviousDay;

  const ScaleRates({
    this.nightStart = '22:00',
    this.nightEnd = '05:00',
    List<double>? valueDiurno,
    List<double>? valueNoturno,
    this.ac4NightAnchorPreviousDay = true,
  })  : valueDiurno = valueDiurno ?? _defaultDiurno,
        valueNoturno = valueNoturno ?? _defaultNoturno;

  /// Valores padrão AC4 GO — ANEXO I da Portaria (junho 2024), segurança pública GO.
  /// Diurno 05h01–21h59 | Noturno 22h00–05h00.
  static const List<double> _defaultDiurno = [
    36.41, // Dom
    26.47, 26.47, 26.47, 26.47, // Seg–Qui
    36.41, 36.41, // Sex–Sáb
  ];
  /// Noturno conforme ANEXO I: Dom 41,38; Seg–Qui 29,80; Sex–Sáb 41,38.
  static const List<double> _defaultNoturno = [
    41.38, // Dom
    29.80, 29.80, 29.80, 29.80, // Seg–Qui
    41.38, 41.38, // Sex–Sáb
  ];

  /// Padrão AC4 (GO) — você pode usar como base e alterar os valores no admin se quiser
  static ScaleRates get defaultRates => const ScaleRates();

  double diurnoForWeekday(int weekday) =>
      valueDiurno[weekday.clamp(0, 6)];

  double noturnoForWeekday(int weekday) =>
      valueNoturno[weekday.clamp(0, 6)];

  ScaleRates copyWith({
    String? nightStart,
    String? nightEnd,
    List<double>? valueDiurno,
    List<double>? valueNoturno,
    bool? ac4NightAnchorPreviousDay,
  }) =>
      ScaleRates(
        nightStart: nightStart ?? this.nightStart,
        nightEnd: nightEnd ?? this.nightEnd,
        valueDiurno: valueDiurno ?? List<double>.from(this.valueDiurno),
        valueNoturno: valueNoturno ?? List<double>.from(this.valueNoturno),
        ac4NightAnchorPreviousDay:
            ac4NightAnchorPreviousDay ?? this.ac4NightAnchorPreviousDay,
      );

  /// DateTime.weekday em Dart: 1=Seg .. 7=Dom. Converte para 0=Dom .. 6=Sab.
  static int weekdayToIndex(int dartWeekday) => dartWeekday % 7;

  /// Último dia civil do mês (28/29/30/31).
  static bool isLastDayOfMonth(DateTime d) {
    final last = DateTime(d.year, d.month + 1, 0);
    return d.day == last.day;
  }

  /// Valor/horas do **registro principal** quando [entryDate] é o último dia do mês e o
  /// turno atravessa meia-noite: só o trecho até 23:59:59 desse dia. O restante (a partir de
  /// 00:00 do 1º do mês seguinte) deve ser lançado automaticamente em [entryDate+1].
  Map<String, double> computeShiftMainEntryLastDayOfMonth({
    required DateTime start,
    required DateTime end,
    required DateTime entryDate,
  }) {
    if (!isLastDayOfMonth(entryDate)) {
      return computeShift(start: start, end: end);
    }
    final startDay = DateTime(entryDate.year, entryDate.month, entryDate.day);
    final endDay = DateTime(end.year, end.month, end.day);
    if (startDay == endDay) {
      return computeShift(start: start, end: end);
    }
    final dayEnd =
        DateTime(entryDate.year, entryDate.month, entryDate.day, 23, 59, 59);
    return computeShift(start: start, end: dayEnd);
  }

  /// Converte "HH:mm" para minutos desde 00:00.
  static int _parseMinutes(String hhmm) {
    final parts = hhmm.split(':');
    final h = int.tryParse(parts.first) ?? 0;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return h * 60 + m;
  }

  /// Índice 0–6 para tabela de **noturno** neste minuto (só chamar se já for noturno).
  ///
  /// AC4: o bloco 22h–05h é um só turno noturno. Entre 00h e [fim noturno), o valor
  /// noturno é o do **dia em que começou às 22h** (dia anterior), não o do dia civil
  /// atual — ex.: domingo 22h → segunda 04h59 segue domingo noturno (41,38), não
  /// segunda noturno (29,80). O diurno continua usando o dia civil.
  static int _noturnoRateIndexForMinute(
    DateTime cur,
    int nightStartMin,
    int nightEndMin,
  ) {
    final minuteOfDay = cur.hour * 60 + cur.minute;
    if (minuteOfDay >= nightStartMin) {
      return weekdayToIndex(cur.weekday);
    }
    final prev = cur.subtract(const Duration(days: 1));
    return weekdayToIndex(prev.weekday);
  }

  /// Calcula horas diurnas, noturnas e valor total para um plantão (considera mudança de dia).
  Map<String, double> computeShift({
    required DateTime start,
    required DateTime end,
  }) =>
      computeShiftWithRatesForMinute(
        start: start,
        end: end,
        ratesForMinute: (_) => this,
      );

  /// Permite trocar a tabela AC4 minuto a minuto (ex.: reajuste GO 01/07/2026).
  static Map<String, double> computeShiftWithRatesForMinute({
    required DateTime start,
    required DateTime end,
    required ScaleRates Function(DateTime minute) ratesForMinute,
  }) {
    double dayMin = 0, nightMin = 0, totalValue = 0, dayValue = 0, nightValue = 0;
    var cur = start;
    final endDt = end.isBefore(start) ? end.add(const Duration(days: 1)) : end;

    while (cur.isBefore(endDt)) {
      final rates = ratesForMinute(cur);
      final nightStartMin = _parseMinutes(rates.nightStart);
      final nightEndMin = _parseMinutes(rates.nightEnd);
      final minuteOfDay = cur.hour * 60 + cur.minute;
      final isNight =
          minuteOfDay >= nightStartMin || minuteOfDay < nightEndMin;
      final wd = weekdayToIndex(cur.weekday);
      final noturnoIdx = rates.ac4NightAnchorPreviousDay
          ? _noturnoRateIndexForMinute(cur, nightStartMin, nightEndMin)
          : wd;
      final rate =
          isNight ? rates.valueNoturno[noturnoIdx] : rates.valueDiurno[wd];
      final inc = rate / 60.0;

      if (isNight) {
        nightMin += 1;
        nightValue += inc;
      } else {
        dayMin += 1;
        dayValue += inc;
      }
      totalValue += inc;
      cur = cur.add(const Duration(minutes: 1));
    }

    if (!totalValue.isFinite) totalValue = 0;

    return {
      'hoursDay': dayMin / 60.0,
      'hoursNight': nightMin / 60.0,
      'dayValue': dayValue,
      'nightValue': nightValue,
      'total': totalValue,
    };
  }

  Map<String, dynamic> toMap() => {
        'nightStart': nightStart,
        'nightEnd': nightEnd,
        'valueDiurno': valueDiurno,
        'valueNoturno': valueNoturno,
        'ac4NightAnchorPreviousDay': ac4NightAnchorPreviousDay,
      };

  static ScaleRates fromMap(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return defaultRates;
    List<double> parseRateList(dynamic v) {
      if (v is List) return v.map((e) => (e is num ? e.toDouble() : double.tryParse(e.toString()) ?? 0.0)).toList();
      return List<double>.from(_defaultDiurno);
    }
    final parsed = ScaleRates(
      nightStart: (data['nightStart'] ?? '22:00').toString(),
      nightEnd: (data['nightEnd'] ?? '05:00').toString(),
      valueDiurno: parseRateList(data['valueDiurno']).length == 7 ? parseRateList(data['valueDiurno']) : _defaultDiurno,
      valueNoturno: parseRateList(data['valueNoturno']).length == 7 ? parseRateList(data['valueNoturno']) : _defaultNoturno,
      // Ausente no Firestore = AC4 correto (sem exigir migração manual do utilizador).
      ac4NightAnchorPreviousDay: data['ac4NightAnchorPreviousDay'] != false,
    );
    return coerceNonZeroOrDefault(parsed);
  }

  /// Se as tabelas vierem todas a zero (dados corrompidos / migração), usa AC4 padrão para a calculadora e escala não ficarem a R\$ 0,00.
  static ScaleRates coerceNonZeroOrDefault(ScaleRates r) {
    var s = 0.0;
    for (final x in r.valueDiurno) {
      s += x.abs();
    }
    for (final x in r.valueNoturno) {
      s += x.abs();
    }
    if (s < 1e-9) return defaultRates;
    return r;
  }
}
