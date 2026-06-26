import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

import 'finance_line_opening.dart';
import 'firestore_query_batched_collect.dart';
import 'firestore_user_doc_id.dart';

/// Limite padrão para streams de pendentes (índice `type`+`status`+`date`).
const int kFinancePendingStreamLimit = 500;

bool _docEffectiveInPeriod(
  Map<String, dynamic> d,
  DateTime rangeStart,
  DateTime rangeEnd,
) {
  final effective = FinanceLineOpening.effectiveDateTimeFromMap(d);
  if (effective == null) return false;
  return !effective.isBefore(rangeStart) && !effective.isAfter(rangeEnd);
}

List<QueryDocumentSnapshot<Map<String, dynamic>>> _mergeTransactionSnapshots(
  List<QuerySnapshot<Map<String, dynamic>>> snaps,
) {
  final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
  for (final snap in snaps) {
    for (final doc in snap.docs) {
      byId[doc.id] = doc;
    }
  }
  final out = byId.values.toList()
    ..sort((a, b) {
      final ta = FinanceLineOpening.effectiveDateTimeFromMap(a.data()) ??
          (a.data()['date'] as Timestamp?)?.toDate();
      final tb = FinanceLineOpening.effectiveDateTimeFromMap(b.data()) ??
          (b.data()['date'] as Timestamp?)?.toDate();
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return ta.compareTo(tb);
    });
  return out;
}

/// Lista mesclada (date + effectiveDate no período) — evita perder lançamentos migrados.
Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> financeTransactionsPeriodDocs({
  required String uid,
  required DateTime rangeStart,
  required DateTime rangeEnd,
}) {
  if (kIsWeb) {
    return _financeTransactionsPeriodDocsWeb(
      uid: uid,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
    );
  }
  final rs = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
  final re = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day, 23, 59, 59);
  final col = FirebaseFirestore.instance.collection('users').doc(uid).collection('transactions');
  final metadataChanges = !kIsWeb;
  final byDate = col
      .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(rs))
      .where('date', isLessThanOrEqualTo: Timestamp.fromDate(re))
      .orderBy('date', descending: false)
      .snapshots(includeMetadataChanges: metadataChanges);
  final byEffective = col
      .where('effectiveDate', isGreaterThanOrEqualTo: Timestamp.fromDate(rs))
      .where('effectiveDate', isLessThanOrEqualTo: Timestamp.fromDate(re))
      .orderBy('effectiveDate', descending: false)
      .snapshots(includeMetadataChanges: metadataChanges);
  final byPaidAt = col
      .where('paidAt', isGreaterThanOrEqualTo: Timestamp.fromDate(rs))
      .where('paidAt', isLessThanOrEqualTo: Timestamp.fromDate(re))
      .orderBy('paidAt', descending: false)
      .snapshots(includeMetadataChanges: metadataChanges);

  late final StreamController<List<QueryDocumentSnapshot<Map<String, dynamic>>>> controller;
  QuerySnapshot<Map<String, dynamic>>? lastA;
  QuerySnapshot<Map<String, dynamic>>? lastB;
  QuerySnapshot<Map<String, dynamic>>? lastC;

  void emit() {
    if (lastA == null || lastB == null || lastC == null) return;
    controller.add(_mergeTransactionSnapshots([lastA!, lastB!, lastC!]));
  }

  controller = StreamController<List<QueryDocumentSnapshot<Map<String, dynamic>>>>.broadcast(
    onListen: () {
      byDate.listen((s) {
        lastA = s;
        emit();
      });
      byEffective.listen((s) {
        lastB = s;
        emit();
      });
      byPaidAt.listen((s) {
        lastC = s;
        emit();
      });
    },
  );
  return controller.stream;
}

/// Web: evita 3 listeners `snapshots()` simultâneos (assert INTERNAL no SDK 11.x).
Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
    _financeTransactionsPeriodDocsWeb({
  required String uid,
  required DateTime rangeStart,
  required DateTime rangeEnd,
}) async* {
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> loadMerged() =>
      financePeriodMergedDocumentsCollect(
        uid: uid,
        from: rangeStart,
        to: rangeEnd,
      );

  try {
    yield await loadMerged();
  } catch (e) {
    debugPrint('_financeTransactionsPeriodDocsWeb initial: $e');
    yield const [];
  }

  final col = FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('transactions');
  await for (final _ in col.limit(1).snapshots(includeMetadataChanges: false)) {
    try {
      yield await loadMerged();
    } catch (e) {
      debugPrint('_financeTransactionsPeriodDocsWeb reload: $e');
    }
  }
}

/// Coleta mesclada (date + effectiveDate) — evita perder lançamentos migrados do legado.
Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> financePeriodMergedDocumentsCollect({
  required String uid,
  required DateTime from,
  required DateTime to,
  String statusFilter = 'all',
  String typeFilter = 'all',
  String? financeAccountId,
  int pageSize = 400,
  int maxDocuments = 8000,
}) async {
  final id = firestoreUserDocIdForAppShell(uid);
  final f = DateTime(from.year, from.month, from.day);
  final t = DateTime(to.year, to.month, to.day, 23, 59, 59);
  final col = FirebaseFirestore.instance.collection('users').doc(id).collection('transactions');

  Query<Map<String, dynamic>> base(String field) {
    var q = col
        .where(field, isGreaterThanOrEqualTo: Timestamp.fromDate(f))
        .where(field, isLessThanOrEqualTo: Timestamp.fromDate(t))
        .orderBy(field, descending: false);
    if (statusFilter == 'pending') {
      q = q.where('status', isEqualTo: 'pending');
    } else if (statusFilter == 'paid') {
      q = q.where('status', isEqualTo: 'paid');
    }
    if (typeFilter == 'income') {
      q = q.where('type', isEqualTo: 'income');
    } else if (typeFilter == 'expense') {
      q = q.where('type', isEqualTo: 'expense');
    }
    final acc = financeAccountId?.trim();
    if (acc != null && acc.isNotEmpty) {
      q = q.where('financeAccountId', isEqualTo: acc);
    }
    return q;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> safeCollect(
    Query<Map<String, dynamic>> q, {
    required String field,
  }) async {
    try {
      return await firestoreQueryCollectDocumentsBatched(
        q,
        pageSize: pageSize,
        maxDocuments: maxDocuments,
      );
    } catch (e) {
      debugPrint('financePeriodMergedDocumentsCollect($field): $e');
      if (field == 'date') return [];
      try {
        var simple = col
            .where(field, isGreaterThanOrEqualTo: Timestamp.fromDate(f))
            .where(field, isLessThanOrEqualTo: Timestamp.fromDate(t))
            .orderBy(field, descending: false);
        return await firestoreQueryCollectDocumentsBatched(
          simple,
          pageSize: pageSize,
          maxDocuments: maxDocuments,
        );
      } catch (e2) {
        debugPrint('financePeriodMergedDocumentsCollect($field) fallback: $e2');
        return [];
      }
    }
  }

  final byDate = await safeCollect(base('date'), field: 'date');
  final byEff = await safeCollect(base('effectiveDate'), field: 'effectiveDate');
  final byPaidAt = await safeCollect(base('paidAt'), field: 'paidAt');

  final merged = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
  for (final d in [...byDate, ...byEff, ...byPaidAt]) {
    merged[d.id] = d;
  }

  final rs = f;
  final re = t;
  final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  for (final doc in merged.values) {
    final d = doc.data();
    if (statusFilter != 'all' && (d['status'] ?? 'paid').toString() != statusFilter) {
      continue;
    }
    if (typeFilter == 'income' && (d['type'] ?? 'expense').toString() != 'income') continue;
    if (typeFilter == 'expense' && (d['type'] ?? 'expense').toString() != 'expense') continue;
    if (!_docEffectiveInPeriod(d, rs, re)) continue;
    out.add(doc);
  }
  out.sort((a, b) {
    final da = FinanceLineOpening.effectiveDateTimeFromMap(a.data()) ??
        (a.data()['date'] as Timestamp?)?.toDate();
    final db = FinanceLineOpening.effectiveDateTimeFromMap(b.data()) ??
        (b.data()['date'] as Timestamp?)?.toDate();
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return da.compareTo(db);
  });
  return out;
}

/// Streams de transações com [includeMetadataChanges] para refletir gravações
/// locais (offline/cache) na hora nos saldos do painel e gráficos.

/// **Evitar** em produção: carrega a coleção inteira. Preferir
/// [financeTransactionsRangedSnapshots], [financeTransactionsPeriodDocs] ou
/// [financeTransactionsPendingSnapshots].
Stream<QuerySnapshot<Map<String, dynamic>>> financeTransactionsOrderedSnapshots({
  required String uid,
}) {
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('transactions')
      .orderBy('date', descending: false)
      .snapshots(includeMetadataChanges: !kIsWeb);
}

/// Pendentes indexados (receita ou despesa) — até [limit] docs, sem varrer histórico.
Stream<QuerySnapshot<Map<String, dynamic>>> financeTransactionsPendingSnapshots({
  required String uid,
  required String type,
  int limit = kFinancePendingStreamLimit,
}) {
  assert(type == 'income' || type == 'expense');
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('transactions')
      .where('type', isEqualTo: type)
      .where('status', isEqualTo: 'pending')
      .orderBy('date', descending: false)
      .limit(limit)
      .snapshots(includeMetadataChanges: !kIsWeb);
}

Stream<QuerySnapshot<Map<String, dynamic>>> financeTransactionsRangedSnapshots({
  required String uid,
  required DateTime rangeStart,
  required DateTime rangeEnd,
}) {
  final rs = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
  final re = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day, 23, 59, 59);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('transactions')
      .where(
        'date',
        isGreaterThanOrEqualTo: Timestamp.fromDate(rs),
      )
      .where(
        'date',
        isLessThanOrEqualTo: Timestamp.fromDate(re),
      )
      .orderBy('date', descending: false)
      .snapshots(includeMetadataChanges: !kIsWeb);
}
