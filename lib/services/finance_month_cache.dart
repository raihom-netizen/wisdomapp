import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../utils/firestore_user_doc_id.dart';
import 'finance_calendar_bridge.dart';

/// Dados financeiros de um mês civil já processados para o calendário.
class MonthFinanceData {
  final List<CalendarFinanceEntry> entries;
  final Map<DateTime, List<CalendarFinanceEntry>> byDay;
  final Set<DateTime> days;
  final int pendingExpenseCount;
  final double pendingExpenseTotal;
  final int pendingIncomeCount;
  final double pendingIncomeTotal;

  const MonthFinanceData({
    required this.entries,
    required this.byDay,
    required this.days,
    required this.pendingExpenseCount,
    required this.pendingExpenseTotal,
    required this.pendingIncomeCount,
    required this.pendingIncomeTotal,
  });

  factory MonthFinanceData.fromEntries(List<CalendarFinanceEntry> entries) {
    final byDay = FinanceCalendarBridge.groupByDay(entries);
    int expCount = 0;
    double expTotal = 0;
    int incCount = 0;
    double incTotal = 0;
    for (final e in entries) {
      if (e.isExpense) {
        expCount++;
        expTotal += e.amount;
      } else if (e.isIncome) {
        incCount++;
        incTotal += e.amount;
      }
    }
    return MonthFinanceData(
      entries: entries,
      byDay: byDay,
      days: byDay.keys.toSet(),
      pendingExpenseCount: expCount,
      pendingExpenseTotal: expTotal,
      pendingIncomeCount: incCount,
      pendingIncomeTotal: incTotal,
    );
  }
}

/// Cache em memória + cache-first do Firestore para dados financeiros no calendário.
///
/// Garante que a cor dos dias financeiros apareça instantaneamente ao trocar de mês
/// ou voltar para hoje, igual acontece com escala/compromisso/audiência.
class FinanceMonthCache {
  FinanceMonthCache._();

  static final Map<String, MonthFinanceData> _dataByKey = {};

  static String monthKey(DateTime day) =>
      '${day.year}-${day.month.toString().padLeft(2, '0')}';

  static String _cacheKey(String uid, DateTime day) {
    final fsUid = firestoreUserDocIdForAppShell(uid);
    return '$fsUid|${monthKey(day)}';
  }

  static MonthFinanceData? peek(String uid, DateTime focusedDay) {
    return _dataByKey[_cacheKey(uid, focusedDay)];
  }

  static void remember(String uid, DateTime focusedDay, MonthFinanceData data) {
    _dataByKey[_cacheKey(uid, focusedDay)] = data;
  }

  static void invalidateMonth(String uid, DateTime day) {
    _dataByKey.remove(_cacheKey(uid, day));
  }

  static void clearUid(String uid) {
    final fsUid = firestoreUserDocIdForAppShell(uid);
    if (fsUid.isEmpty) return;
    final prefix = '$fsUid|';
    _dataByKey.removeWhere((k, _) => k.startsWith(prefix));
  }

  static (DateTime start, DateTime end) _monthBounds(DateTime day) {
    final monthStart = DateTime(day.year, day.month, 1);
    final monthEnd = DateTime(day.year, day.month + 1, 0, 23, 59, 59);
    return (monthStart, monthEnd);
  }

  /// Retorna dados do mês: primeiro do cache em memória, depois cache Firestore,
  /// depois servidor. Atualiza o cache em memória assim que tiver dados.
  static Future<MonthFinanceData> fetchMonth(
    String uid,
    DateTime ref, {
    bool forceServer = false,
  }) async {
    final key = _cacheKey(uid, ref);

    final mem = _dataByKey[key];
    if (!forceServer && mem != null) return mem;

    final (monthStart, _) = _monthBounds(ref);

    // 1) Tenta cache local do Firestore primeiro — paint instantâneo.
    if (!forceServer) {
      try {
        final cacheEntries = await FinanceCalendarBridge.fetchPendingForMonth(
          uid,
          monthStart,
          source: Source.cache,
        );
        if (cacheEntries.isNotEmpty) {
          final data = MonthFinanceData.fromEntries(cacheEntries);
          remember(uid, ref, data);
          return data;
        }
      } catch (_) {}
    }

    // 2) Servidor — fonte de verdade.
    try {
      final entries = await FinanceCalendarBridge.fetchPendingForMonth(
        uid,
        monthStart,
        source: Source.server,
      );
      final data = MonthFinanceData.fromEntries(entries);
      remember(uid, ref, data);
      return data;
    } catch (e, st) {
      debugPrint('FinanceMonthCache.fetchMonth: $e\n$st');
    }

    // 3) Fallback: retorna o que já tinha em memória, ou vazio.
    return mem ??
        const MonthFinanceData(
          entries: [],
          byDay: {},
          days: {},
          pendingExpenseCount: 0,
          pendingExpenseTotal: 0,
          pendingIncomeCount: 0,
          pendingIncomeTotal: 0,
        );
  }

  /// Pré-carrega mês atual (cache Firestore primeiro — sem bloquear UI).
  static Future<void> prefetchCurrentMonth(String uid, [DateTime? ref]) =>
      prefetchMonth(uid, ref ?? DateTime.now());

  /// Pré-carrega um mês civil específico.
  static Future<void> prefetchMonth(String uid, DateTime ref) async {
    final key = _cacheKey(uid, ref);
    if (_dataByKey.containsKey(key)) return;
    await fetchMonth(uid, ref);
  }

  /// Mês anterior + seguinte — navegação no calendário sem espera.
  static Future<void> prefetchAdjacentMonths(
      String uid, DateTime focused) async {
    final prev = DateTime(focused.year, focused.month - 1, 1);
    final next = DateTime(focused.year, focused.month + 1, 1);
    await Future.wait([
      prefetchMonth(uid, prev),
      prefetchMonth(uid, next),
    ]);
  }
}
