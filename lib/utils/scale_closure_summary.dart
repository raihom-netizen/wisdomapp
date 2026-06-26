import '../models/scale_entry.dart';
import '../models/shift_location.dart';

/// Mesma regra de [ScalesScreen._entryInResumoFinanceiro].
bool scaleEntryInResumoFinanceiro(ScaleEntry e, List<ShiftLocation> locations) {
  if (e.isCompromisso) return false;
  if (e.temFinanceiroHabilitadoNoPainel) return true;
  final loc = matchShiftLocationForScaleEntry(e, locations);
  return loc != null && loc.financialEnabled;
}

/// Igual ao totalizador de Escalas: resolve vínculo por campo salvo ou match com pré-cadastros.
String scaleEmployerTypeForEntry(ScaleEntry e, List<ShiftLocation> locations) {
  if (e.employerType != null && e.employerType!.isNotEmpty) return e.employerType!;
  final labelBase = (e.label ?? '').trim().toUpperCase();
  final abbr = (e.abbreviation ?? '').trim().toUpperCase();
  if (labelBase.isEmpty && abbr.isEmpty) return 'private';
  for (final loc in locations) {
    final nameBase = ShiftLocation.baseNameFromFull(loc.name).toUpperCase();
    final locAbbr = loc.abbreviation.trim().toUpperCase();
    if (nameBase.isNotEmpty &&
        (labelBase.contains(nameBase) || nameBase.contains(labelBase))) {
      return loc.employerType.name;
    }
    if (locAbbr.isNotEmpty && (abbr == locAbbr || labelBase.contains(locAbbr))) {
      return loc.employerType.name;
    }
  }
  return 'private';
}

DateTime scaleDateOnlyLocal(DateTime d) => DateTime(d.year, d.month, d.day);

bool scaleEntryDateInRangeInclusive(ScaleEntry e, DateTime periodStart, DateTime periodEnd) {
  final d = scaleDateOnlyLocal(e.date);
  final s = scaleDateOnlyLocal(periodStart);
  final ed = scaleDateOnlyLocal(periodEnd);
  return !d.isBefore(s) && !d.isAfter(ed);
}

/// Agrupa no bucket Estado / Município / Particular como o card "financeiro ativo" em Escalas.
String? scaleFinancialBucketKey(ScaleEntry e, List<ShiftLocation> locations) {
  if (e.employerType != null && e.employerType! == 'private') return 'private';
  final t = scaleEmployerTypeForEntry(e, locations);
  if (t == 'state' || t == 'municipality') return t;
  return null;
}

String scaleFormatHours(double h) {
  if (h.isNaN || h.isInfinite || h <= 0) return '0';
  if ((h - h.round()).abs() < 0.001) return '${h.round()}';
  return h.toStringAsFixed(1);
}

/// Uma linha do fechamento (banco de horas por vínculo).
class ScaleClosureLine {
  final String typeKey;
  final String label;
  final List<ScaleEntry> realizados;
  final List<ScaleEntry> pendentes;

  const ScaleClosureLine({
    required this.typeKey,
    required this.label,
    required this.realizados,
    required this.pendentes,
  });

  int get countReal => realizados.length;
  int get countPend => pendentes.length;

  double get hoursDayReal =>
      realizados.fold<double>(0, (s, e) => s + e.hoursDay);
  double get hoursNightReal =>
      realizados.fold<double>(0, (s, e) => s + e.hoursNight);

  double get valueReal =>
      realizados.fold<double>(0, (s, e) => s + e.totalValue);
  double get valuePend =>
      pendentes.fold<double>(0, (s, e) => s + e.totalValue);

  /// Linha pode entrar no fechamento (realizado ou pendente com valor).
  bool get isSelectableForClosure => valueReal > 0.001 || valuePend > 0.001;

  String historyDescription(String periodHuman) {
    final hd = scaleFormatHours(hoursDayReal);
    final hn = scaleFormatHours(hoursNightReal);
    final tag = typeKey == 'state'
        ? 'Banco de horas Estado'
        : typeKey == 'municipality'
            ? 'Banco de horas Município'
            : 'Banco de horas Particular';
    return '$tag • $periodHuman • $countReal plantão(ões) • ${hd}h diurnas / ${hn}h noturnas';
  }

  /// Histórico quando o lançamento usa valor **pendente** (ainda a receber).
  String historyDescriptionPending(String periodHuman) {
    final hp = scaleFormatHours(
      pendentes.fold<double>(0, (s, e) => s + e.hoursDay),
    );
    final hnp = scaleFormatHours(
      pendentes.fold<double>(0, (s, e) => s + e.hoursNight),
    );
    final tag = typeKey == 'state'
        ? 'Banco de horas Estado (pendente)'
        : typeKey == 'municipality'
            ? 'Banco de horas Município (pendente)'
            : 'Banco de horas Particular (pendente)';
    return '$tag • $periodHuman • $countPend plantão(ões) pendente(s) • ${hp}h diurnas / ${hnp}h noturnas';
  }
}

class ScaleClosureSummary {
  final List<ScaleClosureLine> lines;
  final int totalPendentes;
  final int totalRealizados;

  const ScaleClosureSummary({
    required this.lines,
    required this.totalPendentes,
    required this.totalRealizados,
  });

  bool get allDoneNoPending => totalPendentes == 0 && totalRealizados > 0;
}

/// [referenciaJaTirado] = último dia do período (ou fim do fechamento): define "realizado" vs pendente.
ScaleClosureSummary computeScaleClosureSummary({
  required List<ScaleEntry> entries,
  required List<ShiftLocation> locations,
  required DateTime periodStart,
  required DateTime periodEnd,
  required DateTime referenciaJaTirado,
}) {
  const types = ['state', 'municipality', 'private'];
  const labels = {
    'state': 'Estado',
    'municipality': 'Município',
    'private': 'Particular',
  };
  final byType = <String, List<ScaleEntry>>{
    for (final t in types) t: [],
  };

  for (final e in entries) {
    if (!scaleEntryDateInRangeInclusive(e, periodStart, periodEnd)) continue;
    if (!scaleEntryInResumoFinanceiro(e, locations)) continue;
    final bucket = scaleFinancialBucketKey(e, locations);
    if (bucket == null) continue;
    byType[bucket]!.add(e);
  }

  var totPend = 0;
  var totReal = 0;
  final lines = <ScaleClosureLine>[];
  for (final t in types) {
    final list = byType[t]!;
    final realizados = <ScaleEntry>[];
    final pendentes = <ScaleEntry>[];
    for (final e in list) {
      if (e.effectiveJaTiradoParaExibicaoComLocais(referenciaJaTirado, locations)) {
        realizados.add(e);
      } else {
        pendentes.add(e);
      }
    }
    totPend += pendentes.length;
    totReal += realizados.length;
    lines.add(ScaleClosureLine(
      typeKey: t,
      label: labels[t]!,
      realizados: realizados,
      pendentes: pendentes,
    ));
  }

  return ScaleClosureSummary(
    lines: lines,
    totalPendentes: totPend,
    totalRealizados: totReal,
  );
}

/// Primeiro dia civil após [lastDayInclusive] (ex.: após 30/04 → 01/05).
DateTime scaleDefaultPaymentDateAfterPeriod(DateTime lastDayInclusive) {
  final d = scaleDateOnlyLocal(lastDayInclusive);
  return DateTime(d.year, d.month, d.day).add(const Duration(days: 1));
}

String _ymdCompact(DateTime d) {
  final x = scaleDateOnlyLocal(d);
  final y = x.year.toString().padLeft(4, '0');
  final m = x.month.toString().padLeft(2, '0');
  final day = x.day.toString().padLeft(2, '0');
  return '$y$m$day';
}

/// Chave estável para evitar duplicar o mesmo fechamento (mesmo utilizador, período e vínculo).
/// Gravar em `transactions.scaleClosureDedupKey`.
/// Fechamento **realizado** mantém o formato histórico (sem sufixo), para continuar a reconhecer
/// lançamentos já gravados. Fechamento **pendente** usa sufixo `|pending`, permitindo um segundo
/// lançamento no mesmo vínculo e período (ex.: Estado recebido + Município a receber).
String scaleClosureDedupKey({
  required String userFirestoreDocId,
  required DateTime periodStart,
  required DateTime periodEnd,
  required String employerTypeKey,
  String ledger = 'realized',
}) {
  final a = _ymdCompact(periodStart);
  final b = _ymdCompact(periodEnd);
  final leg = ledger.trim().isEmpty ? 'realized' : ledger.trim();
  final base = 'scale_closure|$userFirestoreDocId|$a|$b|$employerTypeKey';
  if (leg == 'realized') {
    return base;
  }
  return '$base|pending';
}
