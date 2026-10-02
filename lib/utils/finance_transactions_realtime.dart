import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

import 'finance_line_opening.dart';
import 'finance_shared_stream.dart';
import 'finance_transactions_hub.dart';
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

final FinanceSharedStreamCache<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
    _periodDocsShared =
    FinanceSharedStreamCache<List<QueryDocumentSnapshot<Map<String, dynamic>>>>();

/// Lista mesclada (date + effectiveDate no período) — evita perder lançamentos migrados.
///
/// Escuta **compartilhada** por usuário+período ([FinanceSharedStream]): o
/// painel do Início, os cards de fixas e o Financeiro pedem o mesmo período e
/// várias telas montam isto dentro do `build` — antes cada redesenho abria 3
/// escutas novas (Android/iOS) ou 3 leituras pesadas (Web). [renovar] = true
/// descarta a escuta atual (botão «Tentar de novo»).
Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
    financeTransactionsPeriodDocs({
  required String uid,
  required DateTime rangeStart,
  required DateTime rangeEnd,
  bool renovar = false,
}) {
  final rs = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
  final re = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day, 23, 59, 59);
  final key = '$uid|${rs.millisecondsSinceEpoch}|${re.millisecondsSinceEpoch}';
  if (renovar) _periodDocsShared.descartar(key);
  return _periodDocsShared
      .obter(key, () => _financeTransactionsPeriodDocsRaw(uid: uid, rangeStart: rs, rangeEnd: re))
      .stream;
}

Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
    _financeTransactionsPeriodDocsRaw({
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
  final col = FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('transactions');
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

  late final StreamController<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      controller;
  QuerySnapshot<Map<String, dynamic>>? lastA;
  QuerySnapshot<Map<String, dynamic>>? lastB;
  QuerySnapshot<Map<String, dynamic>>? lastC;
  // Consulta que falhou (índice, permissão): conta como «vazia» para as outras
  // poderem emitir — antes uma falha deixava a tela no spinner para sempre.
  final falhou = <int>{};

  void emit() {
    final prontos = [
      (0, lastA),
      (1, lastB),
      (2, lastC),
    ];
    if (prontos.any((p) => p.$2 == null && !falhou.contains(p.$1))) return;
    final snaps = [for (final p in prontos) if (p.$2 != null) p.$2!];
    if (snaps.isEmpty) return;
    controller.add(_mergeTransactionSnapshots(snaps));
  }

  // As 3 escutas eram abertas no onListen e NUNCA fechadas: cada StreamBuilder
  // que trocava de stream (ex.: painel do Início recriando a cada build)
  // deixava 3 listeners do Firestore vivos para sempre. Agora fecham quando o
  // último ouvinte sai e reabrem se alguém voltar a ouvir.
  final subs = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
  // Erro numa das 3 consultas: só registra (como antes, não chega às telas —
  // elas seguem com o último valor emitido).
  void forwardError(int i, Object e, StackTrace st) {
    debugPrint('financeTransactionsPeriodDocs: $e');
    falhou.add(i);
    if (falhou.length == 3) {
      // As 3 falharam: a tela mostra o erro («Tentar de novo»).
      controller.addError(e, st);
    } else {
      emit();
    }
  }

  controller = StreamController<
      List<QueryDocumentSnapshot<Map<String, dynamic>>>>.broadcast(
    onListen: () {
      falhou.clear();
      subs.add(byDate.listen((s) {
        lastA = s;
        emit();
      }, onError: (Object e, StackTrace st) => forwardError(0, e, st)));
      subs.add(byEffective.listen((s) {
        lastB = s;
        emit();
      }, onError: (Object e, StackTrace st) => forwardError(1, e, st)));
      subs.add(byPaidAt.listen((s) {
        lastC = s;
        emit();
      }, onError: (Object e, StackTrace st) => forwardError(2, e, st)));
    },
    onCancel: () {
      for (final s in subs) {
        s.cancel();
      }
      subs.clear();
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
  // Com prazo: sem ele o card ficava com o «pontinho carregando» para sempre
  // (ex.: «Contas fixas do mês» no Início, na Web).
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> loadMerged() =>
      financePeriodMergedDocumentsCollect(
        uid: uid,
        from: rangeStart,
        to: rangeEnd,
      ).timeout(const Duration(seconds: 30));

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> loadWithRetry() async {
    Object? last;
    for (var i = 0; i < 3; i++) {
      try {
        return await loadMerged();
      } catch (e) {
        last = e;
        debugPrint('_financeTransactionsPeriodDocsWeb tentativa ${i + 1}: $e');
        if (i < 2) await Future<void>.delayed(Duration(seconds: 2 << i));
      }
    }
    throw last!;
  }

  try {
    yield await loadWithRetry();
  } catch (e, st) {
    // Erro chega à tela (que mostra «Tentar de novo») em vez de lista vazia,
    // que parecia «não há nada a pagar».
    yield* Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>.error(e, st);
  }

  // Recarrega quando o app grava algo (hub) ou quando a coleção muda no
  // servidor (bot, funções). A 1ª emissão da escuta é a carga inicial (pula).
  final gatilho = StreamController<void>();
  void onRevisao() => gatilho.add(null);
  FinanceTransactionsHub.revision.addListener(onRevisao);
  var primeira = true;
  final sub = FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('transactions')
      .limit(1)
      .snapshots(includeMetadataChanges: false)
      .listen((_) {
    if (primeira) {
      primeira = false;
      return;
    }
    gatilho.add(null);
  }, onError: (Object e) => debugPrint('_financeTransactionsPeriodDocsWeb escuta: $e'));
  try {
    await for (final _ in gatilho.stream) {
      try {
        yield await loadMerged();
      } catch (e) {
        debugPrint('_financeTransactionsPeriodDocsWeb reload: $e');
      }
    }
  } finally {
    FinanceTransactionsHub.revision.removeListener(onRevisao);
    await sub.cancel();
    await gatilho.close();
  }
}

/// Coleta mesclada (date + effectiveDate) — evita perder lançamentos migrados do legado.
Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
    financePeriodMergedDocumentsCollect({
  required String uid,
  required DateTime from,
  required DateTime to,
  String statusFilter = 'all',
  String typeFilter = 'all',
  String? financeAccountId,
  int pageSize = 400,
  int maxDocuments = 8000,

  /// `true`: só o cache local (sem rede, sem novas tentativas) — para pintar
  /// na hora antes da leitura do servidor. Erro/sem cache = lista vazia.
  bool cacheOnly = false,
}) async {
  final id = firestoreUserDocIdForAppShell(uid);
  final f = DateTime(from.year, from.month, from.day);
  final t = DateTime(to.year, to.month, to.day, 23, 59, 59);
  final col = FirebaseFirestore.instance
      .collection('users')
      .doc(id)
      .collection('transactions');

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
    if (cacheOnly) {
      try {
        final snap = await q
            .limit(maxDocuments)
            .get(const GetOptions(source: Source.cache));
        return snap.docs;
      } catch (_) {
        return [];
      }
    }
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

  // As 3 leituras em paralelo (antes uma esperava a outra: 3× o tempo de rede).
  final parts = await Future.wait([
    safeCollect(base('date'), field: 'date'),
    safeCollect(base('effectiveDate'), field: 'effectiveDate'),
    safeCollect(base('paidAt'), field: 'paidAt'),
  ]);
  final byDate = parts[0];
  final byEff = parts[1];
  final byPaidAt = parts[2];

  final merged = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
  for (final d in [...byDate, ...byEff, ...byPaidAt]) {
    merged[d.id] = d;
  }

  final rs = f;
  final re = t;
  final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  for (final doc in merged.values) {
    final d = doc.data();
    if (statusFilter != 'all' &&
        (d['status'] ?? 'paid').toString() != statusFilter) {
      continue;
    }
    if (typeFilter == 'income' &&
        (d['type'] ?? 'expense').toString() != 'income') continue;
    if (typeFilter == 'expense' &&
        (d['type'] ?? 'expense').toString() != 'expense') continue;
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
Stream<QuerySnapshot<Map<String, dynamic>>>
    financeTransactionsOrderedSnapshots({
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
Stream<QuerySnapshot<Map<String, dynamic>>>
    financeTransactionsPendingSnapshots({
  required String uid,
  required String type,
  int limit = kFinancePendingStreamLimit,
}) {
  assert(type == 'income' || type == 'expense');
  // Uma escuta só por (uid, tipo, limite): o painel do Início chama isto
  // dentro do `build` — cada redesenho fechava e reabria a MESMA consulta, o
  // gatilho do assert ca9 do SDK Web (firebase-js-sdk #9842).
  return _pendingStreams
      .obter(
        '$uid|$type|$limit',
        () => FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('transactions')
            .where('type', isEqualTo: type)
            .where('status', isEqualTo: 'pending')
            .orderBy('date', descending: false)
            .limit(limit)
            .snapshots(includeMetadataChanges: !kIsWeb),
      )
      .stream;
}

final FinanceSharedStreamCache<QuerySnapshot<Map<String, dynamic>>>
    _pendingStreams =
    FinanceSharedStreamCache<QuerySnapshot<Map<String, dynamic>>>();

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
