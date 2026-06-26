import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/finance_line_opening.dart';
import '../utils/finance_transaction_datetime.dart';
import '../utils/finance_transactions_hub.dart';
import '../utils/firestore_user_doc_id.dart';
import '../utils/fifty_two_weeks_plan.dart';
import 'transaction_save_service.dart';

/// Depósito em meta + lançamento no Financeiro (receita vinculada).
class GoalDepositService {
  GoalDepositService._();

  static CollectionReference<Map<String, dynamic>> _contribRef(
    DocumentReference<Map<String, dynamic>> goalRef,
  ) =>
      goalRef.collection('contributions');

  /// Saldo líquido acumulado de uma conta (todos os lançamentos pagos).
  static Future<double> accountBalanceAllTime({
    required String uid,
    required String financeAccountId,
  }) async {
    final id = financeAccountId.trim();
    if (id.isEmpty) return 0;
    final snap = await TransactionSaveService.txRef(uid)
        .where('financeAccountId', isEqualTo: id)
        .where('status', isEqualTo: 'paid')
        .get();
    var total = 0.0;
    for (final d in snap.docs) {
      final data = d.data();
      final amount = (data['amount'] as num?)?.toDouble() ?? 0;
      if (amount <= 0) continue;
      final type = (data['type'] ?? 'expense').toString();
      total += type == 'income' ? amount : -amount;
    }
    return total;
  }

  static Future<void> saveDeposit({
    required String uid,
    required DocumentReference<Map<String, dynamic>> goalRef,
    required String goalId,
    required String goalTitle,
    required double amount,
    required DateTime date,
    String? financeAccountId,
    List<int>? weekNumbers,
    bool createFinanceTx = true,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('Valor deve ser maior que zero.');
    }
    final accountId = financeAccountId?.trim() ?? '';
    final weeks = weekNumbers?.where((w) => w >= 1 && w <= 52).toList() ?? [];
    weeks.sort();

    final effectiveDate = FinanceTransactionDatetime.mergeCalendarDayWithClockNow(date);
    String? transactionId;

    if (createFinanceTx) {
      final txRef = TransactionSaveService.txRef(uid).doc();
      transactionId = txRef.id;
      final weekLabel = weeks.isEmpty
          ? ''
          : weeks.length == 1
              ? ' · sem. ${weeks.first}'
              : ' · sem. ${weeks.join(', ')}';
      await txRef.set({
        'type': 'income',
        'amount': amount,
        'category': 'Meta',
        'description': 'Depósito objetivo: $goalTitle$weekLabel',
        'status': 'paid',
        'date': Timestamp.fromDate(effectiveDate),
        'effectiveDate': FinanceLineOpening.effectiveTimestampForWrite(date: effectiveDate),
        'recurrence': 'none',
        'installmentCount': 1,
        'installmentIndex': 1,
        'goalId': goalId,
        if (accountId.isNotEmpty) 'financeAccountId': accountId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await _contribRef(goalRef).add({
      'amount': amount,
      'date': Timestamp.fromDate(effectiveDate),
      'createdAt': FieldValue.serverTimestamp(),
      if (weeks.length == 1) 'weekNumber': weeks.first,
      if (weeks.length > 1) 'weekNumbers': weeks,
      if (accountId.isNotEmpty) 'financeAccountId': accountId,
      if (transactionId != null) 'transactionId': transactionId,
    });

    if (weeks.isNotEmpty) {
      final goalSnap = await goalRef.get();
      final paid = FiftyTwoWeeksPlan.paidWeeksFromData(goalSnap.data() ?? {});
      for (final w in weeks) {
        if (!paid.contains(w)) paid.add(w);
      }
      paid.sort();
      await goalRef.update({'weeksPaid': paid});
    }

    FinanceTransactionsHub.notifyMutated(uid: uid);
  }

  static Future<void> updateDeposit({
    required String uid,
    required QueryDocumentSnapshot<Map<String, dynamic>> contribDoc,
    required double amount,
    required DateTime date,
    String? financeAccountId,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('Valor deve ser maior que zero.');
    }
    final data = contribDoc.data();
    final accountId = financeAccountId?.trim() ?? '';
    final txId = (data['transactionId'] ?? '').toString().trim();

    await contribDoc.reference.update({
      'amount': amount,
      'date': Timestamp.fromDate(date),
      if (accountId.isNotEmpty) 'financeAccountId': accountId,
    });

    if (txId.isNotEmpty) {
      final effectiveDate = FinanceTransactionDatetime.mergeCalendarDayWithClockNow(date);
      await TransactionSaveService.txRef(uid).doc(txId).update({
        'amount': amount,
        'date': Timestamp.fromDate(effectiveDate),
        'effectiveDate': FinanceLineOpening.effectiveTimestampForWrite(date: effectiveDate),
        if (accountId.isNotEmpty) 'financeAccountId': accountId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      FinanceTransactionsHub.notifyMutated(uid: uid);
    }
  }

  static Future<void> deleteDeposit({
    required String uid,
    required QueryDocumentSnapshot<Map<String, dynamic>> contribDoc,
    required DocumentReference<Map<String, dynamic>> goalRef,
  }) async {
    final data = contribDoc.data();
    final txId = (data['transactionId'] ?? '').toString().trim();
    final week = data['weekNumber'] as int?;
    final weeks = (data['weekNumbers'] as List?)?.whereType<int>().toList() ?? [];

    if (txId.isNotEmpty) {
      await TransactionSaveService.txRef(uid).doc(txId).delete();
      FinanceTransactionsHub.notifyMutated(uid: uid);
    }

    await contribDoc.reference.delete();

    final weeksToRemove = <int>{};
    if (week != null) weeksToRemove.add(week);
    weeksToRemove.addAll(weeks);
    if (weeksToRemove.isNotEmpty) {
      final goalSnap = await goalRef.get();
      final paid = FiftyTwoWeeksPlan.paidWeeksFromData(goalSnap.data() ?? {});
      paid.removeWhere(weeksToRemove.contains);
      await goalRef.update({'weeksPaid': paid});
    }
  }
}
