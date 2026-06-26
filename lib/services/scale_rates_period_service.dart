import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/scale_rates.dart';
import '../models/scale_rates_period.dart';
import 'scale_rates_cache_notifier.dart';

/// Histórico de períodos AC4 GO no Firestore (`config/scale_rates.ratePeriods`).
/// Cálculos usam a tabela vigente na **data e hora** do serviço (retroativo ok).
class ScaleRatesPeriodService {
  ScaleRatesPeriodService._();
  factory ScaleRatesPeriodService() => _instance;
  static final ScaleRatesPeriodService _instance = ScaleRatesPeriodService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  List<ScaleRatesPeriod> _periods =
      ScaleRatesPeriodRegistry.bootstrapPeriods();
  bool _loaded = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _watchSub;

  DocumentReference<Map<String, dynamic>> get _globalRatesDoc =>
      _db.collection('config').doc('scale_rates');

  List<ScaleRatesPeriod> get periodsSnapshot =>
      List<ScaleRatesPeriod>.unmodifiable(_periods);

  String get recalcVersionKey => _periods
      .map((p) => '${p.id}@${p.effectiveFrom.millisecondsSinceEpoch}')
      .join('|');

  /// Chave estável para recálculo após reajustes já em vigor.
  String get recalcVersionForPastPeriods {
    final now = DateTime.now();
    final past = _periods
        .where((p) => !p.effectiveFrom.isAfter(now))
        .map((p) => '${p.id}@${p.effectiveFrom.millisecondsSinceEpoch}');
    return past.join('|');
  }

  /// Data a partir da qual plantões devem ser recalculados (1º reajuste após o legado).
  DateTime? get recalcFromDate {
    final sorted = ScaleRatesPeriod.sortAsc(_periods);
    if (sorted.length < 2) return null;
    return sorted[1].effectiveFrom;
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      final snap = await _globalRatesDoc.get();
      _applyFromDoc(snap.data());
      _loaded = true;
      _startWatch();
    } catch (_) {
      _periods = ScaleRatesPeriodRegistry.bootstrapPeriods();
      _loaded = true;
    }
  }

  void _startWatch() {
    _watchSub?.cancel();
    _watchSub = _globalRatesDoc.snapshots().listen((snap) {
      final before = recalcVersionKey;
      _applyFromDoc(snap.data());
      if (recalcVersionKey != before) {
        ScaleRatesCacheNotifier.instance.notifyRatesChanged(null);
      }
    });
  }

  void _applyFromDoc(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) {
      _periods = ScaleRatesPeriodRegistry.bootstrapPeriods();
      return;
    }
    final parsed = ScaleRatesPeriodRegistry.parsePeriodsList(data['ratePeriods']);
    _periods = parsed.isNotEmpty ? parsed : ScaleRatesPeriodRegistry.bootstrapPeriods();
  }

  /// Tabela vigente num instante (minuto a minuto nos cálculos).
  ScaleRates ratesForInstant(DateTime instant) {
    final p = ScaleRatesPeriod.resolveAt(instant, _periods);
    return p?.rates ?? ScaleRates.defaultRates;
  }

  /// Tabela para a data civil do plantão (exibição dayRate/nightRate no cadastro).
  ScaleRates ratesForServiceDay(DateTime serviceDay) =>
      ratesForInstant(
        DateTime(serviceDay.year, serviceDay.month, serviceDay.day),
      );

  ScaleRates currentDisplayRates() => ratesForInstant(DateTime.now());

  ScaleRatesPeriod? activePeriodNow() =>
      ScaleRatesPeriod.resolveAt(DateTime.now(), _periods);

  List<ScaleRatesPeriod> scheduledPeriods() {
    final now = DateTime.now();
    return _periods.where((p) => p.effectiveFrom.isAfter(now)).toList();
  }

  bool hasScheduledFutureChanges() => scheduledPeriods().isNotEmpty;

  Map<String, double> computeShift({
    required DateTime start,
    required DateTime end,
  }) =>
      ScaleRates.computeShiftWithRatesForMinute(
        start: start,
        end: end,
        ratesForMinute: ratesForInstant,
      );

  Map<String, double> computeShiftMainEntryLastDayOfMonth({
    required DateTime start,
    required DateTime end,
    required DateTime entryDate,
  }) {
    if (!ScaleRates.isLastDayOfMonth(entryDate)) {
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

  Stream<List<ScaleRatesPeriod>> watchPeriods() {
    return _globalRatesDoc.snapshots().map((snap) {
      _applyFromDoc(snap.data());
      return List<ScaleRatesPeriod>.from(_periods);
    });
  }

  /// Grava histórico completo + espelha tabela vigente no doc global (compatibilidade).
  Future<void> savePeriods(List<ScaleRatesPeriod> periods) async {
    final sorted = ScaleRatesPeriod.sortAsc(periods);
    if (sorted.isEmpty) return;
    final active = ScaleRatesPeriod.resolveAt(DateTime.now(), sorted) ?? sorted.first;
    final map = active.rates.toMap()
      ..['ratePeriods'] = sorted.map((p) => p.toMap()).toList()
      ..['ratePeriodsVersion'] = recalcVersionKeyFor(sorted)
      ..['ratePeriodsSyncedAt'] = FieldValue.serverTimestamp()
      ..['updatedAt'] = FieldValue.serverTimestamp();
    await _globalRatesDoc.set(map, SetOptions(merge: true));
    _periods = sorted;
    _loaded = true;
    ScaleRatesCacheNotifier.instance.notifyRatesChanged(null);
  }

  static String recalcVersionKeyFor(List<ScaleRatesPeriod> periods) =>
      periods
          .map((p) => '${p.id}@${p.effectiveFrom.millisecondsSinceEpoch}')
          .join('|');

  /// Valida vigência antes de gravar (evita sobreposição de início e tabela zerada).
  String? validatePeriod(ScaleRatesPeriod period, List<ScaleRatesPeriod> all) {
    final others = all.where((p) => p.id != period.id).toList();
    for (final o in others) {
      if (o.effectiveFrom.millisecondsSinceEpoch ==
          period.effectiveFrom.millisecondsSinceEpoch) {
        return 'Já existe período com o mesmo início de vigência '
            '(${period.effectiveFrom}).';
      }
    }
    var sum = 0.0;
    for (final v in period.rates.valueDiurno) {
      sum += v.abs();
    }
    for (final v in period.rates.valueNoturno) {
      sum += v.abs();
    }
    if (sum <= 0) {
      return 'Informe valores diurno/noturno maiores que zero.';
    }
    return null;
  }

  Future<void> addOrUpdatePeriod(ScaleRatesPeriod period) async {
    await ensureLoaded();
    final list = List<ScaleRatesPeriod>.from(_periods);
    final err = validatePeriod(period, list);
    if (err != null) throw StateError(err);
    final idx = list.indexWhere((p) => p.id == period.id);
    if (idx >= 0) {
      list[idx] = period;
    } else {
      list.add(period);
    }
    await savePeriods(list);
  }

  Future<void> removePeriod(String id) async {
    await ensureLoaded();
    final list = _periods.where((p) => p.id != id).toList();
    if (list.isEmpty) return;
    await savePeriods(list);
  }

  /// Cria períodos padrão no Firestore se ainda não existir histórico.
  Future<void> seedBootstrapIfEmpty() async {
    final snap = await _globalRatesDoc.get();
    final data = snap.data() ?? {};
    if (data['ratePeriods'] is List && (data['ratePeriods'] as List).isNotEmpty) {
      _applyFromDoc(data);
      await _ensureJuly2026ScheduledIfMissing();
      _loaded = true;
      _startWatch();
      return;
    }
    await savePeriods(ScaleRatesPeriodRegistry.bootstrapPeriods());
    _loaded = true;
    _startWatch();
  }

  /// Garante o 2º período (reajuste jul/2026) se só existir o legado.
  Future<void> _ensureJuly2026ScheduledIfMissing() async {
    final hasJuly = _periods.any(
      (p) => p.id == ScaleRatesPeriodRegistry.july2026PeriodId,
    );
    if (hasJuly || _periods.isEmpty) return;
    final list = [..._periods, ScaleRatesPeriodRegistry.july2026];
    await savePeriods(list);
  }

  void dispose() {
    _watchSub?.cancel();
    _watchSub = null;
  }
}
