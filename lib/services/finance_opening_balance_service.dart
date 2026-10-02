import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'finance_accounts_service.dart';
import '../utils/finance_account_balance_utils.dart';
import '../utils/finance_transactions_realtime.dart';
import '../utils/finance_line_opening.dart';
import '../utils/finance_server_totals.dart';
import '../utils/firestore_query_batched_collect.dart';
import '../utils/firestore_user_doc_id.dart';

/// Saldo de abertura: total via [finance_month_buckets]; por conta via
/// [finance_account_month_buckets] (servidor) + só o mês parcial em transactions.
class FinanceOpeningBalanceService {
  FinanceOpeningBalanceService._();

  static const int _openingBucketsVersionExpected = 3;

  static final Map<String, ({double total, Map<String, double> byAccount, DateTime at})>
      _cache = {};

  /// Muda sempre que o cache de abertura muda (mutação otimista aplicada,
  /// invalidação, recálculo depois dos buckets do servidor). O Financeiro
  /// escuta para trocar o número na hora, sem recarregar a tela
  /// (port Controle Total, 30/09/2026).
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static bool _revisionBumpQueued = false;

  static void _bumpRevision() {
    if (_revisionBumpQueued) return;
    _revisionBumpQueued = true;
    // Microtask: nunca notifica no meio de um build/setState de quem chamou.
    scheduleMicrotask(() {
      _revisionBumpQueued = false;
      revision.value++;
    });
  }

  /// Contador de mutações locais por usuário: carga que começou antes de uma
  /// mutação não sobrescreve o valor otimista mais novo.
  static final Map<String, int> _mutationGen = {};

  /// Mutações cujo efeito nos buckets do servidor ainda não foi confirmado.
  /// Enquanto > 0, [load] devolve o valor em cache (otimista) mesmo vencido,
  /// em vez de ler buckets que ainda não receberam a gravação.
  static final Map<String, int> _awaitingBuckets = {};

  static final Map<String, Future<({double total, Map<String, double> byAccount})>>
      _inflight = {};

  static String _cacheKey(String uid, DateTime periodStart, bool withAccounts) {
    final id = firestoreUserDocIdForAppShell(uid);
    final d = DateTime(periodStart.year, periodStart.month, periodStart.day);
    return '$id|${d.toIso8601String().substring(0, 10)}|acc:$withAccounts';
  }

  static void invalidateForUser(String uid) {
    final id = firestoreUserDocIdForAppShell(uid);
    _cache.removeWhere((k, _) => k.startsWith('$id|'));
    FinanceServerTotals.invalidateForUser(id);
    _bumpRevision();
  }

  /// Leitura síncrona do cache em memória — evita FutureBuilder piscar no painel/Financeiro.
  static ({double total, Map<String, double> byAccount})? peekCached({
    required String uid,
    required DateTime periodStart,
    bool loadAccounts = false,
    Duration maxAge = const Duration(minutes: 30),
  }) {
    if (uid.isEmpty) return null;
    final start = DateTime(periodStart.year, periodStart.month, periodStart.day);
    final key = _cacheKey(uid, start, loadAccounts);
    final hit = _cache[key];
    if (hit == null || DateTime.now().difference(hit.at) > maxAge) return null;
    return (
      total: hit.total,
      byAccount: Map<String, double>.from(hit.byAccount),
    );
  }

  static void invalidateIfBefore(String uid, DateTime effectiveDate) {
    final id = firestoreUserDocIdForAppShell(uid);
    var removed = false;
    for (final k in _cache.keys.toList()) {
      if (!k.startsWith('$id|')) continue;
      final datePart = k.split('|');
      if (datePart.length < 2) continue;
      final start = DateTime.tryParse(datePart[1]);
      if (start != null && effectiveDate.isBefore(start)) {
        _cache.remove(k);
        removed = true;
      }
    }
    if (removed) {
      _bumpRevision();
      // A carga que vem agora pode ler o bucket ANTES do gatilho do servidor
      // somar esta gravação (corrida): refaz de novo quando o bucket do mês
      // confirmar, para não deixar um saldo defasado em cache.
      _scheduleAuthoritativeRefresh(
        id,
        monthKeys: {FinanceLineOpening.monthKeySaoPaulo(effectiveDate)},
        watchAccountBuckets: false,
        mutationAt: DateTime.now(),
        holdCache: false,
      );
    }
  }

  /// Mutação local já gravada (ou sendo gravada) — atualiza NA HORA o saldo de
  /// abertura em cache com a diferença exata desse lançamento ([before] →
  /// [after]; criar: [before] nulo; excluir: [after] nulo). O total segue a
  /// regra dos buckets ([FinanceLineOpening.openingContribution]); o mapa por
  /// conta, a regra de [FinanceAccountBalanceUtils.applyMutationToOpening].
  /// Depois, quando os buckets do servidor confirmam a gravação, o cache é
  /// descartado e a carga normal substitui o número em silêncio.
  ///
  /// Retorna true se algum saldo em cache mudou.
  static bool applyOptimisticMutation({
    required String uid,
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
    Set<String> creditCardIds = const <String>{},
  }) {
    if (uid.isEmpty || (before == null && after == null)) return false;
    final id = firestoreUserDocIdForAppShell(uid);

    // Sem efeito em saldo pago nenhum (ex.: só descrição, pendente → pendente).
    final noEffect =
        FinanceLineOpening.openingContribution(before ?? const {}) == 0 &&
            FinanceLineOpening.openingContribution(after ?? const {}) == 0;
    if (noEffect) return false;

    _mutationGen[id] = (_mutationGen[id] ?? 0) + 1;

    double rawContribution(Map<String, dynamic>? d, DateTime start) {
      if (d == null) return 0;
      final eff = FinanceLineOpening.effectiveDateTimeFromMap(d);
      if (eff == null || !eff.isBefore(start)) return 0;
      return FinanceLineOpening.openingContribution(d);
    }

    var changed = false;
    for (final k in _cache.keys.toList()) {
      if (!k.startsWith('$id|')) continue;
      final parts = k.split('|');
      if (parts.length < 3) continue;
      final start = DateTime.tryParse(parts[1]);
      if (start == null) continue;
      final withAccounts = parts[2] == 'acc:true';
      final hit = _cache[k]!;
      final total = hit.total +
          rawContribution(after, start) -
          rawContribution(before, start);
      var byAcc = hit.byAccount;
      if (withAccounts) {
        byAcc = FinanceAccountBalanceUtils.applyMutationToOpening(
          base: hit.byAccount,
          before: before,
          after: after,
          periodStart: start,
          creditCardIds: creditCardIds,
        );
      }
      if ((total - hit.total).abs() < 1e-9 && mapEquals(byAcc, hit.byAccount)) {
        continue;
      }
      changed = true;
      _cache[k] = (
        total: total,
        byAccount: Map.unmodifiable(byAcc),
        at: hit.at,
      );
    }

    // Buckets que o gatilho do servidor vai tocar (mês antes/depois).
    final months = <String>{};
    var touchesAccount = false;
    for (final d in [before, after]) {
      if (d == null) continue;
      final eff = FinanceLineOpening.effectiveDateTimeFromMap(d);
      if (eff != null) months.add(FinanceLineOpening.monthKeySaoPaulo(eff));
      final aid = (d['financeAccountId'] ?? '').toString().trim();
      final paidFrom = (d['paidFromFinanceAccountId'] ?? '').toString().trim();
      if (aid.isNotEmpty || paidFrom.isNotEmpty) touchesAccount = true;
    }
    _scheduleAuthoritativeRefresh(
      id,
      monthKeys: months,
      watchAccountBuckets: touchesAccount,
      mutationAt: DateTime.now(),
      holdCache: true,
    );
    if (changed) _bumpRevision();
    return changed;
  }

  /// Espera o gatilho dos buckets gravar os meses afetados (ou no máx.
  /// [_bucketWaitTimeout]) e então descarta o cache do usuário (e o dos totais
  /// do servidor): a próxima carga lê os buckets já atualizados.
  static const Duration _bucketWaitTimeout = Duration(seconds: 12);

  static void _scheduleAuthoritativeRefresh(
    String fsId, {
    required Set<String> monthKeys,
    required bool watchAccountBuckets,
    required DateTime mutationAt,
    required bool holdCache,
  }) {
    if (fsId.isEmpty) return;
    if (holdCache) {
      _awaitingBuckets[fsId] = (_awaitingBuckets[fsId] ?? 0) + 1;
    }
    final gen = _mutationGen[fsId] ?? 0;
    final colecao = watchAccountBuckets
        ? 'finance_account_month_buckets'
        : 'finance_month_buckets';
    unawaited(() async {
      try {
        await Future.wait(monthKeys.map((mk) => _waitBucketTouched(
              FirebaseFirestore.instance.doc('users/$fsId/$colecao/$mk'),
              mutationAt,
            ))).timeout(_bucketWaitTimeout);
      } catch (_) {
        // Timeout / offline: segue para o recálculo mesmo assim.
      }
      if (holdCache) {
        final n = (_awaitingBuckets[fsId] ?? 1) - 1;
        if (n <= 0) {
          _awaitingBuckets.remove(fsId);
        } else {
          _awaitingBuckets[fsId] = n;
        }
      }
      // Uma mutação mais nova tem o próprio recálculo agendado — deixa para ela.
      if (holdCache && (_mutationGen[fsId] ?? 0) != gen) return;
      if ((_awaitingBuckets[fsId] ?? 0) > 0) return;
      _cache.removeWhere((k, _) => k.startsWith('$fsId|'));
      FinanceServerTotals.invalidateForUser(fsId);
      _bumpRevision();
    }());
  }

  static Future<void> _waitBucketTouched(
    DocumentReference<Map<String, dynamic>> ref,
    DateTime mutationAt,
  ) {
    final done = Completer<void>();
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? sub;
    Object? firstServerStamp;
    var sawServer = false;
    // Tolerância para relógio do aparelho levemente adiantado.
    final threshold = mutationAt.subtract(const Duration(seconds: 5));
    sub = ref.snapshots(includeMetadataChanges: true).listen((snap) {
      if (snap.metadata.isFromCache || snap.metadata.hasPendingWrites) return;
      final stamp = snap.data()?['updatedAt'];
      if (stamp is Timestamp && stamp.toDate().isAfter(threshold)) {
        if (!done.isCompleted) done.complete();
        return;
      }
      if (!sawServer) {
        sawServer = true;
        firstServerStamp = stamp;
        return;
      }
      if (stamp != firstServerStamp && !done.isCompleted) done.complete();
    }, onError: (_) {
      if (!done.isCompleted) done.complete();
    });
    return done.future
        .timeout(_bucketWaitTimeout, onTimeout: () {})
        .whenComplete(() => sub?.cancel());
  }

  /// Restaura accountId a partir da chave sanitizada gravada pelo servidor.
  static String _restoreAccountFieldKey(String fieldKey) {
    return fieldKey.replaceAll('\uFF0E', '.');
  }

  static void _mergeNetByAccountMap(Map<String, double> target, Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return;
    raw.forEach((fieldKey, value) {
      if (value is! num) return;
      final aid = _restoreAccountFieldKey(fieldKey);
      if (aid.isEmpty) return;
      target[aid] = (target[aid] ?? 0) + value.toDouble();
    });
  }

  /// Só o total (buckets) — exibe saldos/KPI na hora.
  static Future<double> loadTotalFast({
    required String uid,
    required DateTime periodStart,
    Duration cacheTtl = const Duration(minutes: 5),
  }) async {
    final r = await load(
      uid: uid,
      periodStart: periodStart,
      loadAccounts: false,
      cacheTtl: cacheTtl,
    );
    return r.total;
  }

  /// Total (buckets + mês parcial). [loadAccounts]: mapa por conta via buckets servidor.
  static Future<({double total, Map<String, double> byAccount})> load({
    required String uid,
    required DateTime periodStart,
    bool loadAccounts = true,
    Duration cacheTtl = const Duration(minutes: 5),
  }) async {
    if (uid.isEmpty) {
      return (total: 0.0, byAccount: const <String, double>{});
    }
    final start = DateTime(periodStart.year, periodStart.month, periodStart.day);
    final key = _cacheKey(uid, start, loadAccounts);
    final hit = _cache[key];
    final fsId = firestoreUserDocIdForAppShell(uid);
    final age = hit == null ? null : DateTime.now().difference(hit.at);
    // Enquanto uma mutação local espera o bucket do servidor, o valor em cache
    // (já com a mutação aplicada) é mais correto que reler buckets defasados.
    final holding = (_awaitingBuckets[fsId] ?? 0) > 0 &&
        age != null &&
        age < const Duration(minutes: 30);
    if (hit != null && (age! < cacheTtl || holding)) {
      return (total: hit.total, byAccount: Map<String, double>.from(hit.byAccount));
    }

    // Mesma carga já em andamento (Financeiro + painel juntos): reaproveita.
    final running = _inflight[key];
    if (running != null) return running;
    final fut = _loadUncached(
      fsId: fsId,
      start: start,
      key: key,
      loadAccounts: loadAccounts,
      cacheTtl: cacheTtl,
    );
    _inflight[key] = fut;
    try {
      return await fut;
    } finally {
      if (identical(_inflight[key], fut)) _inflight.remove(key);
    }
  }

  /// Uma mutação local aconteceu durante a carga: o que foi lido pode não ter
  /// a gravação — devolve o valor otimista (mais novo) que já está em cache.
  static ({double total, Map<String, double> byAccount})? _newerThanLoad(
      String fsId, String key, int genAtStart) {
    if ((_mutationGen[fsId] ?? 0) == genAtStart) return null;
    final newer = _cache[key];
    if (newer == null) return null;
    return (
      total: newer.total,
      byAccount: Map<String, double>.from(newer.byAccount),
    );
  }

  static Future<({double total, Map<String, double> byAccount})> _loadUncached({
    required String fsId,
    required DateTime start,
    required String key,
    required bool loadAccounts,
    required Duration cacheTtl,
  }) async {
    final genAtStart = _mutationGen[fsId] ?? 0;
    try {
      final server = await FinanceServerTotals.load(
        uid: fsId,
        from: start,
        to: start,
        statusFilter: 'paid',
        cacheTtl: cacheTtl,
      );
      final total = server.openingTotal;
      final byAcc = loadAccounts
          ? await _reconcileByAccount(
              fsId: fsId,
              start: start,
              total: total,
              byAcc: Map<String, double>.from(server.openingByAccount),
            )
          : const <String, double>{};
      final newer = _newerThanLoad(fsId, key, genAtStart);
      if (newer != null) return newer;
      _cache[key] = (
        total: total,
        byAccount: Map.unmodifiable(Map<String, double>.from(byAcc)),
        at: DateTime.now(),
      );
      return (total: total, byAccount: byAcc);
    } catch (_) {
      // Fallback local abaixo.
    }

    final partialKey = FinanceLineOpening.monthKeySaoPaulo(start);
    final monthStart = FinanceLineOpening.startOfMonthWallLocal(start);

    var prefix = 0.0;
    try {
      final buckets = await FirebaseFirestore.instance
          .collection('users')
          .doc(fsId)
          .collection('finance_month_buckets')
          .orderBy(FieldPath.documentId)
          .where(FieldPath.documentId, isLessThan: partialKey)
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 6));
      for (final doc in buckets.docs) {
        prefix += (doc.data()['netPaid'] as num?)?.toDouble() ?? 0;
      }
    } catch (_) {}

    final seen = <String>{};
    var partial = 0.0;
    final byAcc = <String, double>{};

    void absorb(Map<String, dynamic> d, String docId) {
      if (seen.contains(docId)) return;
      seen.add(docId);
      final c = FinanceLineOpening.openingContribution(d);
      if (c == 0) return;
      partial += c;
      if (loadAccounts) {
        final aid = (d['financeAccountId'] ?? '').toString().trim();
        if (aid.isNotEmpty) {
          byAcc[aid] = (byAcc[aid] ?? 0) + c;
        }
      }
    }

    if (loadAccounts) {
      try {
        final accBuckets = await FirebaseFirestore.instance
            .collection('users')
            .doc(fsId)
            .collection('finance_account_month_buckets')
            .orderBy(FieldPath.documentId)
            .where(FieldPath.documentId, isLessThan: partialKey)
            .get(const GetOptions(source: Source.serverAndCache))
            .timeout(const Duration(seconds: 6));
        for (final doc in accBuckets.docs) {
          final data = doc.data();
          _mergeNetByAccountMap(byAcc, data['netByAccount'] as Map<String, dynamic>?);
        }
      } catch (_) {}
    }

    try {
      final partialDocs = await financePeriodMergedDocumentsCollect(
        uid: fsId,
        from: monthStart,
        to: start.subtract(const Duration(seconds: 1)),
        statusFilter: 'paid',
        maxDocuments: 12000,
      ).timeout(const Duration(seconds: 20));
      for (final doc in partialDocs) {
        absorb(doc.data(), doc.id);
      }
    } catch (_) {}

    if (loadAccounts) {
      try {
        final monthDocs = await firestoreQueryCollectDocumentsBatched(
          FirebaseFirestore.instance
              .collection('users')
              .doc(fsId)
              .collection('transactions')
              .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
              .where('date', isLessThan: Timestamp.fromDate(start))
              .orderBy('date', descending: false),
          pageSize: 400,
          maxDocuments: 2500,
        ).timeout(const Duration(seconds: 12));
        for (final doc in monthDocs) {
          final d = doc.data();
          if (d['effectiveDate'] != null) continue;
          final ts = d['date'];
          if (ts is! Timestamp) continue;
          final date = ts.toDate();
          if (!date.isBefore(start)) continue;
          absorb(d, doc.id);
        }
      } catch (_) {}
    }

    final total = prefix + partial;
    if (loadAccounts) {
      final fixed = await _reconcileByAccount(
          fsId: fsId, start: start, total: total, byAcc: byAcc);
      if (!identical(fixed, byAcc)) {
        byAcc
          ..clear()
          ..addAll(fixed);
      }
    }
    final newer = _newerThanLoad(fsId, key, genAtStart);
    if (newer != null) return newer;
    final result = (total: total, byAccount: byAcc);
    _cache[key] = (
      total: total,
      byAccount: Map.unmodifiable(Map<String, double>.from(byAcc)),
      at: DateTime.now(),
    );
    return result;
  }

  /// Reconciliação por conta (port Controle Total, `_loadUncached`): quando a
  /// soma das contas não bate com o total dos buckets, recalcula o saldo de
  /// abertura de cada conta a partir dos lançamentos pagos reais (fonte da
  /// verdade). Sem isso, com os buckets por conta vazios/defasados, o total
  /// saía certo (ex.: R$ 996,50) e cada card de conta ficava R$ 0,00.
  /// Regra por conta = [FinanceAccountBalanceUtils.openingPaidByAccountFromDocMaps]
  /// (cartão fora; pagamento de fatura debita a conta que pagou).
  static Future<Map<String, double>> _reconcileByAccount({
    required String fsId,
    required DateTime start,
    required double total,
    required Map<String, double> byAcc,
  }) async {
    final sumAssigned = byAcc.values.fold<double>(0, (a, b) => a + b);
    if ((total - sumAssigned).abs() <= 0.05) return byAcc;
    try {
      final accounts = FinanceAccountsService.peekLastKnown(fsId) ??
          await FinanceAccountsService()
              .listOnce(fsId)
              .timeout(const Duration(seconds: 6));
      final cardIds = FinanceAccountBalanceUtils.creditCardAccountIds(accounts);
      final beforeDocs = await financePeriodMergedDocumentsCollect(
        uid: fsId,
        from: DateTime(2000, 1, 1),
        to: start.subtract(const Duration(seconds: 1)),
        statusFilter: 'paid',
        maxDocuments: 20000,
      ).timeout(const Duration(seconds: 25));
      return FinanceAccountBalanceUtils.openingPaidByAccountFromDocMaps(
        items: beforeDocs.map((d) => d.data()),
        periodStart: start,
        creditCardIds: cardIds,
      );
    } catch (e) {
      debugPrint('FinanceOpeningBalanceService._reconcileByAccount: $e');
      return byAcc;
    }
  }

  /// Versão esperada dos agregados (contas por mês no servidor).
  static int get openingBucketsVersionExpected => _openingBucketsVersionExpected;

  /// Uma vez por sessão: reconstrói buckets mensais + por conta no servidor (migração v2).
  static bool _rebuildAsked = false;

  static Future<void> ensureServerBucketsRebuildIfNeeded(String uid) async {
    if (_rebuildAsked || uid.isEmpty) return;
    _rebuildAsked = true;
    try {
      final fsId = firestoreUserDocIdForAppShell(uid);
      final meta = await FirebaseFirestore.instance
          .doc('users/$fsId/finance_stats/meta')
          .get();
      if (meta.exists &&
          (meta.data()?['openingBucketsVersion'] as num? ?? 0) >= _openingBucketsVersionExpected) {
        return;
      }
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('ctFinanceRebuildOpeningBuckets')
          .call()
          .timeout(const Duration(seconds: 180));
      invalidateForUser(uid);
    } catch (_) {}
  }
}
