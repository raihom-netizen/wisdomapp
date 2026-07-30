import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../utils/finance_transaction_status_resolver.dart';
import '../utils/firestore_user_doc_id.dart';

/// Representa um lançamento financeiro pendente exibido no calendário.
class CalendarFinanceEntry {
  final String id;
  final DateTime date;
  final double amount;
  final String type; // 'income' | 'expense'
  final String description;
  final String category;
  final String status;
  final String? financeAccountId;
  final String? calendarColorHex;

  const CalendarFinanceEntry({
    required this.id,
    required this.date,
    required this.amount,
    required this.type,
    required this.description,
    required this.category,
    required this.status,
    this.financeAccountId,
    this.calendarColorHex,
  });

  bool get isIncome => type == 'income';
  bool get isExpense => type == 'expense';
  bool get isPending => status == 'pending';
}

/// Ponte entre o módulo Financeiro (transactions) e o calendário (Escalas).
///
/// Fornece métodos para consultar lançamentos pendentes por dia/mês e
/// renderizar marcadores coloridos no calendário + resumo do dia.
abstract final class FinanceCalendarBridge {
  FinanceCalendarBridge._();

  static CollectionReference<Map<String, dynamic>> _txCol(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(firestoreUserDocIdForAppShell(uid))
          .collection('transactions');

  /// Retorna o DocumentSnapshot completo de uma transação (para edição).
  static Future<DocumentSnapshot<Map<String, dynamic>>> transactionDoc(
    String uid,
    String docId,
  ) async {
    return _txCol(uid).doc(docId).get();
  }

  /// Busca todos os lançamentos **pendentes** do mês informado.
  ///
  /// [month] deve ser o primeiro dia do mês (ex.: DateTime(2026, 7, 1)).
  /// Retorna lista ordenada por data crescente.
  /// Apenas datas de hoje ou futuras são retornadas — lançamentos passados
  /// devem estar como 'paid' e não aparecer como pendentes no calendário.
  static Future<List<CalendarFinanceEntry>> fetchPendingForMonth(
    String uid,
    DateTime month, {
    Source source = Source.server,
  }) async {
    try {
      final start = DateTime(month.year, month.month, 1);
      final end = DateTime(month.year, month.month + 1, 1);
      final snap = await _txCol(uid)
          .where('status', isEqualTo: 'pending')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('date', isLessThan: Timestamp.fromDate(end))
          .orderBy('date')
          .get(GetOptions(source: source));
      return _parseDocs(snap.docs.where(_isFutureOrToday).toList());
    } catch (e) {
      debugPrint('[FinanceCalendarBridge] fetchPendingForMonth error: $e');
      return const [];
    }
  }

  /// `true` se a data do documento for hoje ou futura.
  static bool _isFutureOrToday(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final dateTs = d['date'];
    if (dateTs is! Timestamp) return false;
    final date = dateTs.toDate();
    return FinanceTransactionStatusResolver.resolveByDate(date) != 'paid';
  }

  /// Busca todos os lançamentos (pagos + pendentes) do mês para contadores
  /// de "Receitas Pendentes" e "Contas a Pagar" no resumo mensal.
  static Future<
      ({
        int pendingExpenseCount,
        double pendingExpenseTotal,
        int pendingIncomeCount,
        double pendingIncomeTotal
      })> fetchMonthlyPendingSummary(String uid, DateTime month) async {
    try {
      final start = DateTime(month.year, month.month, 1);
      final end = DateTime(month.year, month.month + 1, 1);
      final snap = await _txCol(uid)
          .where('status', isEqualTo: 'pending')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('date', isLessThan: Timestamp.fromDate(end))
          .get();

      int expCount = 0;
      double expTotal = 0;
      int incCount = 0;
      double incTotal = 0;
      // Deduplicação: mesma despesa/receita fixa no mesmo mês conta apenas 1×.
      final seenFixedKeys = <String>{};
      for (final doc in snap.docs.where(_isFutureOrToday)) {
        final d = doc.data();
        if (d['addToCalendar'] == false) continue;
        // Pula duplicados da mesma despesa/receita fixa + mês.
        final feId = d['fixedExpenseId']?.toString() ?? '';
        final fiId = d['fixedIncomeId']?.toString() ?? '';
        final fixedId = feId.isNotEmpty ? feId : fiId;
        if (fixedId.isNotEmpty) {
          String mk;
          final mkKey =
              feId.isNotEmpty ? 'fixedExpenseMonthKey' : 'fixedIncomeMonthKey';
          final explicitMk = d[mkKey] as String?;
          if (explicitMk != null && explicitMk.isNotEmpty) {
            mk = explicitMk;
          } else {
            final dateTs = d['date'];
            if (dateTs is Timestamp) {
              final dt = dateTs.toDate();
              mk = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
            } else {
              mk = '';
            }
          }
          if (mk.isNotEmpty && !seenFixedKeys.add('$fixedId::$mk')) continue;
        }
        final type = (d['type'] ?? '').toString();
        final amount = (d['amount'] as num?)?.toDouble() ?? 0;
        if (type == 'expense') {
          expCount++;
          expTotal += amount;
        } else if (type == 'income') {
          incCount++;
          incTotal += amount;
        }
      }
      return (
        pendingExpenseCount: expCount,
        pendingExpenseTotal: expTotal,
        pendingIncomeCount: incCount,
        pendingIncomeTotal: incTotal,
      );
    } catch (e) {
      debugPrint(
          '[FinanceCalendarBridge] fetchMonthlyPendingSummary error: $e');
      return (
        pendingExpenseCount: 0,
        pendingExpenseTotal: 0.0,
        pendingIncomeCount: 0,
        pendingIncomeTotal: 0.0,
      );
    }
  }

  /// Busca lançamentos pendentes para um dia específico.
  static Future<List<CalendarFinanceEntry>> fetchPendingForDay(
    String uid,
    DateTime day,
  ) async {
    try {
      final start = DateTime(day.year, day.month, day.day);
      final end = start.add(const Duration(days: 1));
      final snap = await _txCol(uid)
          .where('status', isEqualTo: 'pending')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('date', isLessThan: Timestamp.fromDate(end))
          .get();
      return _parseDocs(snap.docs.where(_isFutureOrToday).toList());
    } catch (e) {
      debugPrint('[FinanceCalendarBridge] fetchPendingForDay error: $e');
      return const [];
    }
  }

  /// Verifica se há lançamentos pendentes para um dia (para marcadores no calendário).
  /// Retorna: ({bool hasExpense, bool hasIncome}) — usado para adicionar cores no marcador.
  static Future<({bool hasExpense, bool hasIncome})> hasPendingForDay(
    String uid,
    DateTime day,
  ) async {
    try {
      final start = DateTime(day.year, day.month, day.day);
      final end = start.add(const Duration(days: 1));
      final snap = await _txCol(uid)
          .where('status', isEqualTo: 'pending')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('date', isLessThan: Timestamp.fromDate(end))
          .get();
      bool hasExp = false;
      bool hasInc = false;
      for (final doc in snap.docs.where(_isFutureOrToday)) {
        if (doc.data()['addToCalendar'] == false) continue;
        final type = (doc.data()['type'] ?? '').toString();
        if (type == 'expense') hasExp = true;
        if (type == 'income') hasInc = true;
        if (hasExp && hasInc) break;
      }
      return (hasExpense: hasExp, hasIncome: hasInc);
    } catch (e) {
      debugPrint('[FinanceCalendarBridge] hasPendingForDay error: $e');
      return (hasExpense: false, hasIncome: false);
    }
  }

  /// Remove todos os lançamentos pendentes de um dia específico.
  /// Usado quando o usuário escolhe "Limpar dia" e opta por limpar também o financeiro.
  /// Se houver despesas/receitas fixas, marca o mês como excluído para não recriar.
  static Future<int> deletePendingForDay(String uid, DateTime day) async {
    try {
      final start = DateTime(day.year, day.month, day.day);
      final end = start.add(const Duration(days: 1));
      final snap = await _txCol(uid)
          .where('status', isEqualTo: 'pending')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('date', isLessThan: Timestamp.fromDate(end))
          .get();
      if (snap.docs.isEmpty) return 0;
      final batch = FirebaseFirestore.instance.batch();
      int count = 0;
      final fixedUpdates = <String, ({String collection, String monthKey})>{};
      for (final doc in snap.docs) {
        final d = doc.data();
        batch.delete(doc.reference);
        count++;
        final feId = (d['fixedExpenseId'] ?? '').toString().trim();
        final fiId = (d['fixedIncomeId'] ?? '').toString().trim();
        final fixedId = feId.isNotEmpty ? feId : fiId;
        if (fixedId.isEmpty) continue;
        final collection = feId.isNotEmpty ? 'fixed_expenses' : 'fixed_incomes';
        String? monthKey =
            (d['fixedExpenseMonthKey'] ?? d['fixedIncomeMonthKey'])?.toString();
        if (monthKey == null || monthKey.isEmpty) {
          final dateTs = d['date'];
          if (dateTs is Timestamp) {
            final dt = dateTs.toDate();
            monthKey = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
          }
        }
        if (monthKey == null || monthKey.isEmpty) continue;
        fixedUpdates[fixedId] = (collection: collection, monthKey: monthKey);
      }
      for (final entry in fixedUpdates.entries) {
        final ref = FirebaseFirestore.instance
            .collection('users')
            .doc(firestoreUserDocIdForAppShell(uid))
            .collection(entry.value.collection)
            .doc(entry.key);
        batch.update(ref, {
          'excludedMonths': FieldValue.arrayUnion([entry.value.monthKey]),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      return count;
    } catch (e) {
      debugPrint('[FinanceCalendarBridge] deletePendingForDay error: $e');
      return 0;
    }
  }

  /// Confirma pagamento/recebimento de um lançamento (status → 'paid').
  static Future<bool> confirmTransaction(String uid, String docId) async {
    try {
      await _txCol(uid).doc(docId).update({
        'status': 'paid',
        'paidAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('[FinanceCalendarBridge] confirmTransaction error: $e');
      return false;
    }
  }

  /// Exclui um único lançamento financeiro pelo ID.
  /// Se a parcela pertencer a uma despesa/receita fixa, marca o mês como
  /// excluído manualmente para que não seja recriado automaticamente.
  static Future<bool> deleteTransaction(String uid, String docId) async {
    try {
      final snap = await _txCol(uid).doc(docId).get();
      final txData = snap.data() ?? {};
      await _txCol(uid).doc(docId).delete();
      await _markFixedMonthExcluded(uid, txData);
      return true;
    } catch (e) {
      debugPrint('[FinanceCalendarBridge] deleteTransaction error: $e');
      return false;
    }
  }

  static Future<void> _markFixedMonthExcluded(
    String uid,
    Map<String, dynamic> txData,
  ) async {
    final feId = (txData['fixedExpenseId'] ?? '').toString().trim();
    final fiId = (txData['fixedIncomeId'] ?? '').toString().trim();
    final fixedId = feId.isNotEmpty ? feId : fiId;
    if (fixedId.isEmpty) return;

    String? monthKey =
        (txData['fixedExpenseMonthKey'] ?? txData['fixedIncomeMonthKey'])
            ?.toString();
    if (monthKey == null || monthKey.isEmpty) {
      final dateTs = txData['date'];
      if (dateTs is Timestamp) {
        final dt = dateTs.toDate();
        monthKey = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
      }
    }
    if (monthKey == null || monthKey.isEmpty) return;

    final fsUid = firestoreUserDocIdForAppShell(uid);
    if (fsUid.isEmpty) return;

    final collection = feId.isNotEmpty ? 'fixed_expenses' : 'fixed_incomes';
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(fsUid)
        .collection(collection)
        .doc(fixedId);

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) return;
        final data = snap.data() ?? {};
        final existing = List<String>.from(data['excludedMonths'] ?? const []);
        if (existing.contains(monthKey)) return;
        existing.add(monthKey!);
        tx.update(ref, {
          'excludedMonths': existing,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    } catch (_) {}
  }

  /// Agrupa entradas por dia (para marcadores no calendário).
  static Map<DateTime, List<CalendarFinanceEntry>> groupByDay(
    List<CalendarFinanceEntry> entries,
  ) {
    final map = <DateTime, List<CalendarFinanceEntry>>{};
    for (final e in entries) {
      final key = DateTime(e.date.year, e.date.month, e.date.day);
      map.putIfAbsent(key, () => []).add(e);
    }
    return map;
  }

  static List<CalendarFinanceEntry> _parseDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final result = <CalendarFinanceEntry>[];
    // Deduplicação: mesma despesa/receita fixa no mesmo mês aparece apenas 1×.
    final seenFixedKeys = <String>{};
    for (final doc in docs) {
      final d = doc.data();
      if (d['addToCalendar'] == false) continue;
      final dateTs = d['date'];
      if (dateTs is! Timestamp) continue;
      final date = dateTs.toDate();
      // Duplicação por fixedExpenseId/fixedIncomeId + mês.
      final feId = d['fixedExpenseId']?.toString() ?? '';
      final fiId = d['fixedIncomeId']?.toString() ?? '';
      final fixedId = feId.isNotEmpty ? feId : fiId;
      if (fixedId.isNotEmpty) {
        final mkKey =
            feId.isNotEmpty ? 'fixedExpenseMonthKey' : 'fixedIncomeMonthKey';
        final mk = (d[mkKey] as String?) ??
            '${date.year}-${date.month.toString().padLeft(2, '0')}';
        final key = '$fixedId::$mk';
        if (!seenFixedKeys.add(key)) continue; // já tem → pula duplicado
      }
      result.add(CalendarFinanceEntry(
        id: doc.id,
        date: DateTime(date.year, date.month, date.day),
        amount: (d['amount'] as num?)?.toDouble() ?? 0,
        type: (d['type'] ?? 'expense').toString(),
        description: (d['description'] ?? '').toString(),
        category: (d['category'] ?? '').toString(),
        status: (d['status'] ?? 'pending').toString(),
        financeAccountId: d['financeAccountId']?.toString(),
        calendarColorHex: d['calendarColorHex']?.toString(),
      ));
    }
    return result;
  }
}
