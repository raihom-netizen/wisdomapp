import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../utils/finance_main_period_server.dart';
import '../utils/firestore_user_doc_id.dart';
import 'finance_accounts_service.dart';
import 'finance_month_cache.dart';
import 'finance_opening_balance_service.dart';

/// Aquecimento instantâneo do Financeiro (cache Firestore + memória).
///
/// Espelha o padrão de Escalas/Agenda: ao abrir o app ou a Agenda, os
/// pendentes/contas/mês já estão no cache local — a UI pinta sem esperar rede.
class FinanceInstantPrefetchService {
  FinanceInstantPrefetchService._();

  static String? _lastUid;
  static DateTime? _lastWarmAt;
  static Future<void>? _inFlight;
  static const Duration _kMinInterval = Duration(seconds: 45);

  /// Boot / troca de conta: aquece contas, pendentes e mês atual.
  static Future<void> warmUpOnLogin(String uid) {
    final fsUid = firestoreUserDocIdForAppShell(uid);
    if (fsUid.isEmpty) return Future<void>.value();
    return _warm(fsUid, force: false, includeMainPeriod: true);
  }

  /// Ao abrir o módulo Agenda: garante mês focado + adjacentes prontos.
  static Future<void> warmUpForAgenda(String uid, [DateTime? focusedDay]) {
    final fsUid = firestoreUserDocIdForAppShell(uid);
    if (fsUid.isEmpty) return Future<void>.value();
    final day = focusedDay ?? DateTime.now();
    return _warm(
      fsUid,
      force: false,
      includeMainPeriod: false,
      focusedDay: day,
    );
  }

  /// Ao abrir o módulo Financeiro: reforça período + contas.
  static Future<void> warmUpForFinanceModule(String uid) {
    final fsUid = firestoreUserDocIdForAppShell(uid);
    if (fsUid.isEmpty) return Future<void>.value();
    return _warm(fsUid, force: true, includeMainPeriod: true);
  }

  static Future<void> _warm(
    String fsUid, {
    required bool force,
    required bool includeMainPeriod,
    DateTime? focusedDay,
  }) {
    final now = DateTime.now();
    if (!force &&
        _lastUid == fsUid &&
        _lastWarmAt != null &&
        now.difference(_lastWarmAt!) < _kMinInterval &&
        _inFlight == null) {
      return Future<void>.value();
    }
    if (_inFlight != null && _lastUid == fsUid) return _inFlight!;

    _inFlight = _run(
      fsUid,
      includeMainPeriod: includeMainPeriod,
      focusedDay: focusedDay ?? now,
    ).whenComplete(() {
      _inFlight = null;
      _lastUid = fsUid;
      _lastWarmAt = DateTime.now();
    });
    return _inFlight!;
  }

  static Future<void> _run(
    String fsUid, {
    required bool includeMainPeriod,
    required DateTime focusedDay,
  }) async {
    try {
      await Future.wait<void>([
        _warmAccounts(fsUid),
        _warmPendingType(fsUid, 'income'),
        _warmPendingType(fsUid, 'expense'),
        FinanceMonthCache.prefetchCurrentMonth(fsUid, focusedDay),
      ]);
      unawaited(FinanceMonthCache.prefetchAdjacentMonths(fsUid, focusedDay));
      if (includeMainPeriod) {
        unawaited(_warmMainPeriodFirstPage(fsUid));
        unawaited(
          FinanceOpeningBalanceService.loadTotalFast(
            uid: fsUid,
            periodStart: DateTime(focusedDay.year, focusedDay.month, 1),
          ).catchError((_) => 0.0),
        );
      }
    } catch (e, st) {
      debugPrint('FinanceInstantPrefetchService: $e\n$st');
    }
  }

  static Future<void> _warmAccounts(String fsUid) async {
    try {
      await FinanceAccountsService().listOnce(fsUid);
    } catch (_) {}
  }

  /// Preenche o persistence do Firestore para o stream da Agenda/Financeiro.
  static Future<void> _warmPendingType(String fsUid, String type) async {
    final q = FirebaseFirestore.instance
        .collection('users')
        .doc(fsUid)
        .collection('transactions')
        .where('type', isEqualTo: type)
        .where('status', isEqualTo: 'pending')
        .orderBy('date', descending: false)
        .limit(500);
    try {
      final cached = await q.get(const GetOptions(source: Source.cache));
      if (cached.docs.isNotEmpty) {
        // Já há cache — atualiza em background sem bloquear.
        unawaited(q.get(const GetOptions(source: Source.serverAndCache)));
        return;
      }
    } catch (_) {}
    try {
      await q
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  static Future<void> _warmMainPeriodFirstPage(String fsUid) async {
    try {
      final now = DateTime.now();
      final from = DateTime(now.year, now.month, 1);
      final to = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
      final q = financeMainPeriodFirestoreQuery(
        sessionUid: fsUid,
        from: from,
        to: to,
        statusFilter: 'all',
        typeFilter: 'all',
      ).limit(200);
      try {
        final cached = await q.get(const GetOptions(source: Source.cache));
        if (cached.docs.isNotEmpty) {
          unawaited(q.get(const GetOptions(source: Source.serverAndCache)));
          return;
        }
      } catch (_) {}
      await q
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }
}
