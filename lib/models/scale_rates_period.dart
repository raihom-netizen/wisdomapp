import 'package:cloud_firestore/cloud_firestore.dart';

import 'scale_rates.dart';

/// Um período de vigência da tabela AC4 GO (início em data/hora local).
class ScaleRatesPeriod {
  const ScaleRatesPeriod({
    required this.id,
    required this.label,
    required this.effectiveFrom,
    required this.rates,
    this.notes,
  });

  final String id;
  final String label;
  /// Início da vigência (horário local do dispositivo / Brasil).
  final DateTime effectiveFrom;
  final ScaleRates rates;
  final String? notes;

  /// Vigente agora (último período cujo início já passou).
  bool isActiveAt(DateTime instant, List<ScaleRatesPeriod> allSorted) {
    if (allSorted.isEmpty) return false;
    final active = ScaleRatesPeriod.resolveAt(instant, allSorted);
    return active?.id == id;
  }

  bool isScheduled(DateTime now) => effectiveFrom.isAfter(now);

  DateTime? effectiveUntil(List<ScaleRatesPeriod> allSorted) {
    final idx = allSorted.indexWhere((p) => p.id == id);
    if (idx < 0 || idx >= allSorted.length - 1) return null;
    return allSorted[idx + 1].effectiveFrom.subtract(const Duration(seconds: 1));
  }

  static ScaleRatesPeriod? resolveAt(
    DateTime instant,
    List<ScaleRatesPeriod> sortedAsc,
  ) {
    if (sortedAsc.isEmpty) return null;
    ScaleRatesPeriod? hit;
    for (final p in sortedAsc) {
      if (!p.effectiveFrom.isAfter(instant)) {
        hit = p;
      } else {
        break;
      }
    }
    return hit ?? sortedAsc.first;
  }

  static List<ScaleRatesPeriod> sortAsc(List<ScaleRatesPeriod> list) {
    final copy = List<ScaleRatesPeriod>.from(list);
    copy.sort((a, b) => a.effectiveFrom.compareTo(b.effectiveFrom));
    return copy;
  }

  static DateTime parseEffectiveFrom(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    final s = raw?.toString() ?? '';
    if (s.isEmpty) return DateTime(2024, 6, 1);
    final parsed = DateTime.tryParse(s);
    if (parsed != null) return parsed;
    final parts = s.split('T').first.split('-');
    if (parts.length == 3) {
      final y = int.tryParse(parts[0]) ?? 2024;
      final m = int.tryParse(parts[1]) ?? 6;
      final d = int.tryParse(parts[2]) ?? 1;
      if (s.contains('T')) {
        final time = s.split('T').last.split(':');
        final h = time.isNotEmpty ? int.tryParse(time[0]) ?? 0 : 0;
        final min = time.length > 1 ? int.tryParse(time[1]) ?? 0 : 0;
        return DateTime(y, m, d, h, min);
      }
      return DateTime(y, m, d);
    }
    return DateTime(2024, 6, 1);
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'effectiveFrom': Timestamp.fromDate(effectiveFrom),
        'effectiveFromIso': effectiveFrom.toIso8601String(),
        'rates': rates.toMap(),
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
      };

  factory ScaleRatesPeriod.fromMap(Map<String, dynamic> map) {
    final ratesRaw = map['rates'];
    return ScaleRatesPeriod(
      id: (map['id'] ?? map['scheduleId'] ?? '').toString().isNotEmpty
          ? (map['id'] ?? map['scheduleId']).toString()
          : 'period_${map['effectiveFrom']}',
      label: (map['label'] ?? 'Período AC4').toString(),
      effectiveFrom: parseEffectiveFrom(
        map['effectiveFrom'] ?? map['effectiveFromIso'],
      ),
      rates: ratesRaw is Map<String, dynamic>
          ? ScaleRates.fromMap(ratesRaw)
          : ScaleRates.defaultRates,
      notes: map['notes']?.toString(),
    );
  }

  ScaleRatesPeriod copyWith({
    String? id,
    String? label,
    DateTime? effectiveFrom,
    ScaleRates? rates,
    String? notes,
  }) =>
      ScaleRatesPeriod(
        id: id ?? this.id,
        label: label ?? this.label,
        effectiveFrom: effectiveFrom ?? this.effectiveFrom,
        rates: rates ?? this.rates,
        notes: notes ?? this.notes,
      );
}

/// Períodos embutidos no app (fallback offline + seed inicial no Firestore).
abstract final class ScaleRatesPeriodRegistry {
  ScaleRatesPeriodRegistry._();

  static const String july2026PeriodId = 'goias_ac4_july2026';

  static final ScaleRatesPeriod legacyJun2024 = ScaleRatesPeriod(
    id: 'ac4_jun2024',
    label: 'ANEXO I — jun/2024',
    effectiveFrom: DateTime(2024, 6, 1),
    rates: ScaleRates(),
  );

  static final ScaleRatesPeriod july2026 = ScaleRatesPeriod(
    id: july2026PeriodId,
    label: 'ANEXO I — jul/2026',
    effectiveFrom: DateTime(2026, 7, 1, 0, 0),
    rates: const ScaleRates(
      valueDiurno: [40, 30, 30, 30, 30, 40, 40],
      valueNoturno: [45, 33, 33, 33, 33, 45, 45],
    ),
    notes: 'Reajuste programado — vigência 01/07/2026 00:00',
  );

  static List<ScaleRatesPeriod> bootstrapPeriods() =>
      ScaleRatesPeriod.sortAsc([legacyJun2024, july2026]);

  static List<ScaleRatesPeriod> parsePeriodsList(dynamic raw) {
    if (raw is! List) return bootstrapPeriods();
    final out = <ScaleRatesPeriod>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        out.add(ScaleRatesPeriod.fromMap(item));
      } else if (item is Map) {
        out.add(ScaleRatesPeriod.fromMap(Map<String, dynamic>.from(item)));
      }
    }
    if (out.isEmpty) return bootstrapPeriods();
    return ScaleRatesPeriod.sortAsc(out);
  }
}
