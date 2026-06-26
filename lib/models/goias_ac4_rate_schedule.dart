import 'scale_rates.dart';
import 'scale_rates_period.dart';
import '../services/scale_rates_period_service.dart';

/// Compatibilidade — delega ao histórico dinâmico em Firestore ([ScaleRatesPeriodService]).
abstract final class GoiasAc4RateSchedule {
  GoiasAc4RateSchedule._();

  static ScaleRatesPeriodService get _svc => ScaleRatesPeriodService();

  static String get scheduleId =>
      ScaleRatesPeriodRegistry.july2026PeriodId;

  static String get label => ScaleRatesPeriodRegistry.july2026.label;

  static DateTime get effectiveFrom =>
      ScaleRatesPeriodRegistry.july2026.effectiveFrom;

  static const ScaleRates legacyRates = ScaleRates();

  static ScaleRates get fromJuly2026Rates =>
      ScaleRatesPeriodRegistry.july2026.rates;

  static bool isOnOrAfterEffectiveDate(DateTime day) {
    final p = ScaleRatesPeriod.resolveAt(
      DateTime(day.year, day.month, day.day),
      _svc.periodsSnapshot,
    );
    return p?.id != ScaleRatesPeriodRegistry.legacyJun2024.id;
  }

  static bool isNowOnOrAfterEffective() {
    final active = _svc.activePeriodNow();
    return active?.id != ScaleRatesPeriodRegistry.legacyJun2024.id;
  }

  static ScaleRates ratesForServiceDay(DateTime serviceDay) =>
      _svc.ratesForServiceDay(serviceDay);

  static ScaleRates ratesForInstant(DateTime instant) =>
      _svc.ratesForInstant(instant);

  static ScaleRates currentDisplayRates() => _svc.currentDisplayRates();

  static Map<String, dynamic> firestoreScheduleMeta() => {
        'scheduleId': scheduleId,
        'label': label,
        'effectiveFrom': effectiveFrom.toIso8601String(),
        'note': 'Histórico completo em ratePeriods (config/scale_rates)',
      };

  static Map<String, double> computeShift({
    required DateTime start,
    required DateTime end,
  }) =>
      _svc.computeShift(start: start, end: end);

  static Map<String, double> computeShiftMainEntryLastDayOfMonth({
    required DateTime start,
    required DateTime end,
    required DateTime entryDate,
  }) =>
      _svc.computeShiftMainEntryLastDayOfMonth(
        start: start,
        end: end,
        entryDate: entryDate,
      );
}
