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

  static List<int> weeksFromContribData(Map<String, dynamic> data) {
    final week = data['weekNumber'] as int?;
    final weeks = (data['weekNumbers'] as List?)?.whereType<int>().toList() ?? [];
    if (week != null) return [week];
    return weeks;
  }

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
      final weekLabel = _weekLabel(weeks);
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
    required DocumentReference<Map<String, dynamic>> goalRef,
    required QueryDocumentSnapshot<Map<String, dynamic>> contribDoc,
    required double amount,
    required DateTime date,
    String? financeAccountId,
    String? goalTitle,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('Valor deve ser maior que zero.');
    }
    final data = contribDoc.data();
    final accountId = financeAccountId?.trim() ?? '';
    final txId = (data['transactionId'] ?? '').toString().trim();
    final goalSnap = await goalRef.get();
    final goalData = goalSnap.data() ?? {};
    final title = goalTitle ?? (goalData['title'] ?? 'Objetivo').toString();
    final is52 = FiftyTwoWeeksPlan.is52WeeksGoal(goalData);

    List<int> newWeeks = const [];
    if (is52) {
      final target = (goalData['targetAmount'] as num?)?.toDouble() ?? 0;
      final planStart = FiftyTwoWeeksPlan.planStartFromData(goalData) ?? DateTime.now();
      final schedule = FiftyTwoWeeksPlan.buildSchedule(target: target, planStart: planStart);
      final oldWeeks = weeksFromContribData(data);
      var paid = FiftyTwoWeeksPlan.paidWeeksFromData(goalData);
      paid.removeWhere(oldWeeks.contains);
      newWeeks = FiftyTwoWeeksPlan.weeksForDepositAmount(
        amount: amount,
        schedule: schedule,
        paidWeeks: paid,
      );
      paid.addAll(newWeeks);
      paid.sort();
      await goalRef.update({'weeksPaid': paid});
    }

    final effectiveDate = FinanceTransactionDatetime.mergeCalendarDayWithClockNow(date);
    final contribUpdate = <String, dynamic>{
      'amount': amount,
      'date': Timestamp.fromDate(effectiveDate),
      if (accountId.isNotEmpty) 'financeAccountId': accountId,
    };
    if (is52) {
      if (newWeeks.length == 1) {
        contribUpdate['weekNumber'] = newWeeks.first;
        contribUpdate['weekNumbers'] = FieldValue.delete();
      } else if (newWeeks.length > 1) {
        contribUpdate['weekNumbers'] = newWeeks;
        contribUpdate['weekNumber'] = FieldValue.delete();
      } else {
        contribUpdate['weekNumber'] = FieldValue.delete();
        contribUpdate['weekNumbers'] = FieldValue.delete();
      }
    }
    await contribDoc.reference.update(contribUpdate);

    if (txId.isNotEmpty) {
      final weekLabel = is52 ? _weekLabel(newWeeks) : _weekLabel(weeksFromContribData(data));
      await TransactionSaveService.txRef(uid).doc(txId).update({
        'amount': amount,
        'date': Timestamp.fromDate(effectiveDate),
        'effectiveDate': FinanceLineOpening.effectiveTimestampForWrite(date: effectiveDate),
        'description': 'Depósito objetivo: $title$weekLabel',
        if (accountId.isNotEmpty) 'financeAccountId': accountId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      FinanceTransactionsHub.notifyMutated(uid: uid);
    }
  }

  /// Sincroniza depósito vinculado quando o lançamento é editado no Financeiro.
  static Future<void> syncFromTransaction({
    required String uid,
    required String goalId,
    required String txId,
    required double amount,
    required DateTime date,
    String? financeAccountId,
  }) async {
    final fsUid = firestoreUserDocIdForAppShell(uid);
    if (fsUid.isEmpty || goalId.trim().isEmpty || txId.trim().isEmpty) return;

    final goalRef = FirebaseFirestore.instance
        .collection('users')
        .doc(fsUid)
        .collection('goals')
        .doc(goalId);
    final goalSnap = await goalRef.get();
    if (!goalSnap.exists) return;

    final contribQuery = await goalRef
        .collection('contributions')
        .where('transactionId', isEqualTo: txId)
        .limit(1)
        .get();
    if (contribQuery.docs.isEmpty) return;

    await updateDeposit(
      uid: uid,
      goalRef: goalRef,
      contribDoc: contribQuery.docs.first,
      amount: amount,
      date: date,
      financeAccountId: financeAccountId,
      goalTitle: (goalSnap.data()?['title'] ?? 'Objetivo').toString(),
    );
  }

  static Future<void> deleteDeposit({
    required String uid,
    required QueryDocumentSnapshot<Map<String, dynamic>> contribDoc,
    required DocumentReference<Map<String, dynamic>> goalRef,
  }) async {
    final data = contribDoc.data();
    final txId = (data['transactionId'] ?? '').toString().trim();
    final weeksToRemove = weeksFromContribData(data).toSet();

    if (txId.isNotEmpty) {
      await TransactionSaveService.txRef(uid).doc(txId).delete();
      FinanceTransactionsHub.notifyMutated(uid: uid);
    }

    await contribDoc.reference.delete();

    if (weeksToRemove.isNotEmpty) {
      final goalSnap = await goalRef.get();
      final paid = FiftyTwoWeeksPlan.paidWeeksFromData(goalSnap.data() ?? {});
      paid.removeWhere(weeksToRemove.contains);
      await goalRef.update({'weeksPaid': paid});
    }
  }

  static String _weekLabel(List<int> weeks) {
    if (weeks.isEmpty) return '';
    if (weeks.length == 1) return ' · sem. ${weeks.first}';
    return ' · sem. ${weeks.join(', ')}';
  }
}
