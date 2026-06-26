import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/date_time_formats.dart';
import '../services/user_categories_service.dart';
import 'finance_line_opening.dart';

/// Modos de ordenação da grid de lançamentos da fatura do cartão.
enum FinanceFaturaTxSortMode {
  dateDesc,
  dateAsc,
  amountDesc,
  amountAsc,
  category,
}

extension FinanceFaturaTxSortModeUi on FinanceFaturaTxSortMode {
  String get storageKey => switch (this) {
        FinanceFaturaTxSortMode.dateDesc => 'date_desc',
        FinanceFaturaTxSortMode.dateAsc => 'date_asc',
        FinanceFaturaTxSortMode.amountDesc => 'amount_desc',
        FinanceFaturaTxSortMode.amountAsc => 'amount_asc',
        FinanceFaturaTxSortMode.category => 'category',
      };

  String get label => switch (this) {
        FinanceFaturaTxSortMode.dateDesc => 'Data (mais recente)',
        FinanceFaturaTxSortMode.dateAsc => 'Data (mais antiga)',
        FinanceFaturaTxSortMode.amountDesc => 'Valor (maior → menor)',
        FinanceFaturaTxSortMode.amountAsc => 'Valor (menor → maior)',
        FinanceFaturaTxSortMode.category => 'Categoria (A → Z)',
      };

  static FinanceFaturaTxSortMode fromKey(String key) {
    for (final m in FinanceFaturaTxSortMode.values) {
      if (m.storageKey == key) return m;
    }
    return FinanceFaturaTxSortMode.dateDesc;
  }
}

/// Grupo visual na lista (cabeçalho de dia ou categoria + documentos).
class FinanceFaturaTxGroup {
  final String headerLabel;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  const FinanceFaturaTxGroup({
    required this.headerLabel,
    required this.docs,
  });
}

/// Ordenação e agrupamento compartilhados (Financeiro + Painel).
class FinanceFaturaTransactionSort {
  FinanceFaturaTransactionSort._();

  static DateTime? calendarDay(Map<String, dynamic> d) {
    final instant = effectiveInstant(d);
    if (instant == null) return null;
    return DateTime(instant.year, instant.month, instant.day);
  }

  /// Data/hora efetiva do lançamento (paidAt → effectiveDate → date), com hora para ordenação intra-dia.
  static DateTime? effectiveInstant(Map<String, dynamic> d) {
    final eff = FinanceLineOpening.effectiveDateTimeFromMap(d);
    if (eff != null) return eff;
    final ts = d['date'];
    if (ts is Timestamp) return ts.toDate();
    if (ts is DateTime) return ts;
    return null;
  }

  static double amountAbs(Map<String, dynamic> d) =>
      (d['amount'] as num?)?.toDouble().abs() ?? 0;

  static String categoryLabel(Map<String, dynamic> d) {
    final c = (d['category'] ?? '').toString().trim();
    return c.isEmpty ? 'Sem categoria' : c;
  }

  static int _compareInstantDesc(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.compareTo(a);
  }

  static int _compareInstantAsc(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return a.compareTo(b);
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> sortedDocs(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    FinanceFaturaTxSortMode mode,
  ) {
    final list = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
    list.sort((a, b) {
      final da = a.data();
      final db = b.data();
      final aAmt = amountAbs(da);
      final bAmt = amountAbs(db);
      final aInstant = effectiveInstant(da);
      final bInstant = effectiveInstant(db);
      final aCat = categoryLabel(da);
      final bCat = categoryLabel(db);
      switch (mode) {
        case FinanceFaturaTxSortMode.amountAsc:
          final c = aAmt.compareTo(bAmt);
          return c != 0 ? c : _compareInstantDesc(aInstant, bInstant);
        case FinanceFaturaTxSortMode.amountDesc:
          final c = bAmt.compareTo(aAmt);
          return c != 0 ? c : _compareInstantDesc(aInstant, bInstant);
        case FinanceFaturaTxSortMode.dateAsc:
          final c = _compareInstantAsc(aInstant, bInstant);
          return c != 0 ? c : bAmt.compareTo(aAmt);
        case FinanceFaturaTxSortMode.category:
          final c = UserCategoriesService.compareNamesPt(aCat, bCat);
          if (c != 0) return c;
          final d = _compareInstantDesc(aInstant, bInstant);
          return d != 0 ? d : bAmt.compareTo(aAmt);
        case FinanceFaturaTxSortMode.dateDesc:
          final c = _compareInstantDesc(aInstant, bInstant);
          return c != 0 ? c : bAmt.compareTo(aAmt);
      }
    });
    return list;
  }

  /// Ordenação de mapas (Painel — receitas/despesas pendentes).
  static List<Map<String, dynamic>> sortedMaps(
    Iterable<Map<String, dynamic>> items,
    FinanceFaturaTxSortMode mode,
  ) {
    final list = List<Map<String, dynamic>>.from(items);
    list.sort((a, b) {
      final aAmt = amountAbs(a);
      final bAmt = amountAbs(b);
      final aInstant = effectiveInstant(a);
      final bInstant = effectiveInstant(b);
      final aCat = categoryLabel(a);
      final bCat = categoryLabel(b);
      switch (mode) {
        case FinanceFaturaTxSortMode.amountAsc:
          final c = aAmt.compareTo(bAmt);
          return c != 0 ? c : _compareInstantDesc(aInstant, bInstant);
        case FinanceFaturaTxSortMode.amountDesc:
          final c = bAmt.compareTo(aAmt);
          return c != 0 ? c : _compareInstantDesc(aInstant, bInstant);
        case FinanceFaturaTxSortMode.dateAsc:
          final c = _compareInstantAsc(aInstant, bInstant);
          return c != 0 ? c : bAmt.compareTo(aAmt);
        case FinanceFaturaTxSortMode.category:
          final c = UserCategoriesService.compareNamesPt(aCat, bCat);
          if (c != 0) return c;
          final d = _compareInstantDesc(aInstant, bInstant);
          return d != 0 ? d : bAmt.compareTo(aAmt);
        case FinanceFaturaTxSortMode.dateDesc:
          final c = _compareInstantDesc(aInstant, bInstant);
          return c != 0 ? c : bAmt.compareTo(aAmt);
      }
    });
    return list;
  }

  static List<FinanceFaturaTxGroup> groupedForUi(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    FinanceFaturaTxSortMode mode,
  ) {
    final sorted = sortedDocs(docs, mode);
    if (sorted.isEmpty) return const [];

    switch (mode) {
      case FinanceFaturaTxSortMode.dateDesc:
      case FinanceFaturaTxSortMode.dateAsc:
        final byDay = <DateTime?, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
        for (final doc in sorted) {
          final day = calendarDay(doc.data());
          byDay.putIfAbsent(day, () => []).add(doc);
        }
        final days = byDay.keys.toList()
          ..sort((a, b) => mode == FinanceFaturaTxSortMode.dateDesc
              ? _compareInstantDesc(a, b)
              : _compareInstantAsc(a, b));
        final withinDayMode = mode == FinanceFaturaTxSortMode.dateAsc
            ? FinanceFaturaTxSortMode.dateAsc
            : FinanceFaturaTxSortMode.dateDesc;
        return [
          for (final day in days)
            FinanceFaturaTxGroup(
              headerLabel: day == null ? 'Sem data' : DateTimeFormats.formatDate(day),
              docs: sortedDocs(byDay[day]!, withinDayMode),
            ),
        ];
      case FinanceFaturaTxSortMode.category:
        final byCat = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
        for (final doc in sorted) {
          final cat = categoryLabel(doc.data());
          byCat.putIfAbsent(cat, () => []).add(doc);
        }
        final cats = byCat.keys.toList()
          ..sort(UserCategoriesService.compareNamesPt);
        return [
          for (final cat in cats)
            FinanceFaturaTxGroup(
              headerLabel: cat,
              docs: sortedDocs(byCat[cat]!, FinanceFaturaTxSortMode.dateDesc),
            ),
        ];
      case FinanceFaturaTxSortMode.amountAsc:
      case FinanceFaturaTxSortMode.amountDesc:
        return [
          FinanceFaturaTxGroup(headerLabel: 'Todos os lançamentos', docs: sorted),
        ];
    }
  }
}
