import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/finance_line_opening.dart';
import '../utils/finance_transaction_datetime.dart';
import '../utils/finance_transactions_hub.dart';
import '../utils/firestore_user_doc_id.dart';
import '../utils/fifty_two_weeks_plan.dart';
import 'transaction_save_service.dart';

/// Dados do vínculo Meta ↔ lançamento financeiro (edição / exclusão).
class GoalLinkedTransactionInfo {
  const GoalLinkedTransactionInfo({
    required this.goalId,
    required this.goalTitle,
    required this.is52,
    required this.weeksToUnmark,
  });

  final String goalId;
  final String goalTitle;
  final bool is52;
  final List<int> weeksToUnmark;

  bool get hasWeeksImpact => is52;

  String deleteImpactMessage() {
    if (is52) {
      if (weeksToUnmark.isEmpty) {
        return 'As semanas do Projeto 52 na meta «$goalTitle» serão recalculadas '
            'conforme os depósitos restantes.';
      }
      final w = weeksToUnmark.join(', ');
      return weeksToUnmark.length == 1
          ? 'Semana $w será desmarcada na meta «$goalTitle» (Projeto 52 semanas). '
              'As demais semanas serão recalculadas.'
          : 'Semanas $w serão desmarcadas na meta «$goalTitle» (Projeto 52 semanas). '
              'As demais semanas serão recalculadas.';
    }
    return 'O depósito na meta «$goalTitle» também será removido.';
  }
}

/// Depósito em meta + lançamento no Financeiro (receita vinculada).
class GoalDepositService {
  GoalDepositService._();

  static CollectionReference<Map<String, dynamic>> _contribRef(
    DocumentReference<Map<String, dynamic>> goalRef,
  ) =>
      goalRef.collection('contributions');

  static List<int> weeksFromContribData(Map<String, dynamic> data) {
    final week = data['weekNumber'] as int?;
    final weeks =
        (data['weekNumbers'] as List?)?.whereType<int>().toList() ?? [];
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

    final effectiveDate =
        FinanceTransactionDatetime.mergeCalendarDayWithClockNow(date);
    String? transactionId;

    if (createFinanceTx) {
      final txRef = TransactionSaveService.txRef(uid).doc();
      transactionId = txRef.id;
      final weekLabel = _weekLabel(weeks);
      await txRef.set({
        'type': 'income',
        'amount': amount,
        'category': 'Meta',
        'description': 'Depósito meta: $goalTitle$weekLabel',
        'status': 'paid',
        'date': Timestamp.fromDate(effectiveDate),
        'effectiveDate':
            FinanceLineOpening.effectiveTimestampForWrite(date: effectiveDate),
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
    final title = goalTitle ?? (goalData['title'] ?? 'Meta').toString();
    final is52 = FiftyTwoWeeksPlan.is52WeeksGoal(goalData);

    List<int> newWeeks = const [];
    if (is52) {
      final target = (goalData['targetAmount'] as num?)?.toDouble() ?? 0;
      final planStart =
          FiftyTwoWeeksPlan.planStartFromData(goalData) ?? DateTime.now();
      final schedule =
          FiftyTwoWeeksPlan.buildSchedule(target: target, planStart: planStart);
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

    final effectiveDate =
        FinanceTransactionDatetime.mergeCalendarDayWithClockNow(date);
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
      final weekLabel =
          is52 ? _weekLabel(newWeeks) : _weekLabel(weeksFromContribData(data));
      await TransactionSaveService.txRef(uid).doc(txId).update({
        'amount': amount,
        'date': Timestamp.fromDate(effectiveDate),
        'effectiveDate':
            FinanceLineOpening.effectiveTimestampForWrite(date: effectiveDate),
        'description': 'Depósito meta: $title$weekLabel',
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
      goalTitle: (goalSnap.data()?['title'] ?? 'Meta').toString(),
    );
  }

  /// Informação para aviso ao excluir lançamento vinculado à Meta no Financeiro.
  static Future<GoalLinkedTransactionInfo?> linkedInfoForTransaction({
    required String uid,
    required String txId,
    required Map<String, dynamic> txData,
  }) async {
    final goalId = (txData['goalId'] ?? '').toString().trim();
    if (goalId.isEmpty || (txData['type'] ?? '').toString() != 'income') {
      return null;
    }
    final fsUid = firestoreUserDocIdForAppShell(uid);
    if (fsUid.isEmpty || txId.trim().isEmpty) return null;

    final goalRef = FirebaseFirestore.instance
        .collection('users')
        .doc(fsUid)
        .collection('goals')
        .doc(goalId);
    final goalSnap = await goalRef.get();
    if (!goalSnap.exists) return null;
    final goalData = goalSnap.data() ?? {};
    final is52 = FiftyTwoWeeksPlan.is52WeeksGoal(goalData);

    var weeks = <int>[];
    if (is52) {
      final oldPaid = FiftyTwoWeeksPlan.paidWeeksFromData(goalData);
      final contribSnap = await _contribRef(goalRef).get();
      final remaining = contribSnap.docs
          .where((d) => (d.data()['transactionId'] ?? '').toString() != txId)
          .toList();
      final newPaid = _paidWeeksFromContributionDocs(
        goalData: goalData,
        contribDocs: remaining,
      );
      weeks = oldPaid.where((w) => !newPaid.contains(w)).toList()..sort();
    } else {
      final contribQ = await goalRef
          .collection('contributions')
          .where('transactionId', isEqualTo: txId)
          .limit(1)
          .get();
      if (contribQ.docs.isNotEmpty) {
        weeks = weeksFromContribData(contribQ.docs.first.data());
      }
    }

    return GoalLinkedTransactionInfo(
      goalId: goalId,
      goalTitle: (goalData['title'] ?? 'Meta').toString(),
      is52: is52,
      weeksToUnmark: weeks,
    );
  }

  /// Remove depósito + desmarca semanas antes de apagar o lançamento no Financeiro.
  static Future<void> unlinkBeforeTransactionDelete({
    required String uid,
    required String txId,
    required Map<String, dynamic> txData,
  }) async {
    final goalId = (txData['goalId'] ?? '').toString().trim();
    if (goalId.isEmpty || (txData['type'] ?? '').toString() != 'income') return;

    final fsUid = firestoreUserDocIdForAppShell(uid);
    if (fsUid.isEmpty || txId.trim().isEmpty) return;

    final goalRef = FirebaseFirestore.instance
        .collection('users')
        .doc(fsUid)
        .collection('goals')
        .doc(goalId);
    final contribQ = await goalRef
        .collection('contributions')
        .where('transactionId', isEqualTo: txId)
        .limit(1)
        .get();
    if (contribQ.docs.isEmpty) return;

    await _unlinkContribution(
      goalRef: goalRef,
      contribDoc: contribQ.docs.first,
      deleteLinkedTransaction: false,
    );
  }

  static Future<void> deleteDeposit({
    required String uid,
    required QueryDocumentSnapshot<Map<String, dynamic>> contribDoc,
    required DocumentReference<Map<String, dynamic>> goalRef,
  }) async {
    await _unlinkContribution(
      goalRef: goalRef,
      contribDoc: contribDoc,
      deleteLinkedTransaction: true,
      uid: uid,
    );
  }

  static Future<void> _unlinkContribution({
    required DocumentReference<Map<String, dynamic>> goalRef,
    required QueryDocumentSnapshot<Map<String, dynamic>> contribDoc,
    required bool deleteLinkedTransaction,
    String? uid,
  }) async {
    final data = contribDoc.data();
    final txId = (data['transactionId'] ?? '').toString().trim();

    if (deleteLinkedTransaction && txId.isNotEmpty && uid != null) {
      await TransactionSaveService.txRef(uid).doc(txId).delete();
    }

    await contribDoc.reference.delete();
    await recalculate52WeeksPaid(goalRef: goalRef);

    if (deleteLinkedTransaction && uid != null) {
      FinanceTransactionsHub.notifyMutated(uid: uid);
    }
  }

  /// Recalcula `weeksPaid` e rótulos de semana em cada depósito restante
  /// (ordem cronológica). Sem depósitos → semana 0 (lista vazia).
  static Future<void> recalculate52WeeksPaid({
    required DocumentReference<Map<String, dynamic>> goalRef,
  }) async {
    final goalSnap = await goalRef.get();
    if (!goalSnap.exists) return;
    final goalData = goalSnap.data() ?? {};
    if (!FiftyTwoWeeksPlan.is52WeeksGoal(goalData)) return;

    final contribSnap = await _contribRef(goalRef).get();
    final sorted = contribSnap.docs.toList()..sort(_compareContributionDocs);

    var batch = FirebaseFirestore.instance.batch();
    var ops = 0;
    var runningPaid = <int>[];
    final target = (goalData['targetAmount'] as num?)?.toDouble() ?? 0;
    final planStart =
        FiftyTwoWeeksPlan.planStartFromData(goalData) ?? DateTime.now();
    final schedule = FiftyTwoWeeksPlan.buildSchedule(
      target: target,
      planStart: planStart,
    );

    for (final doc in sorted) {
      final amount = (doc.data()['amount'] as num?)?.toDouble() ?? 0;
      final weeks = amount <= 0
          ? const <int>[]
          : FiftyTwoWeeksPlan.weeksForDepositAmount(
              amount: amount,
              schedule: schedule,
              paidWeeks: runningPaid,
            );
      runningPaid = [...runningPaid, ...weeks]..sort();

      batch.update(doc.reference, _weekFieldsPatch(weeks));
      ops++;
      if (ops >= 450) {
        await batch.commit();
        batch = FirebaseFirestore.instance.batch();
        ops = 0;
      }
    }

    batch.update(goalRef, {'weeksPaid': runningPaid});
    await batch.commit();
  }

  static List<int> _paidWeeksFromContributionDocs({
    required Map<String, dynamic> goalData,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> contribDocs,
  }) {
    if (!FiftyTwoWeeksPlan.is52WeeksGoal(goalData)) return const [];
    final target = (goalData['targetAmount'] as num?)?.toDouble() ?? 0;
    final planStart =
        FiftyTwoWeeksPlan.planStartFromData(goalData) ?? DateTime.now();
    final schedule = FiftyTwoWeeksPlan.buildSchedule(
      target: target,
      planStart: planStart,
    );

    final sorted = [...contribDocs]..sort(_compareContributionDocs);
    var paid = <int>[];
    for (final doc in sorted) {
      final amount = (doc.data()['amount'] as num?)?.toDouble() ?? 0;
      if (amount <= 0) continue;
      final weeks = FiftyTwoWeeksPlan.weeksForDepositAmount(
        amount: amount,
        schedule: schedule,
        paidWeeks: paid,
      );
      paid = [...paid, ...weeks]..sort();
    }
    return paid;
  }

  static int _compareContributionDocs(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) {
    DateTime key(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
      final d = doc.data();
      final dateTs = d['date'];
      if (dateTs is Timestamp) return dateTs.toDate();
      final createdTs = d['createdAt'];
      if (createdTs is Timestamp) return createdTs.toDate();
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    final cmp = key(a).compareTo(key(b));
    if (cmp != 0) return cmp;
    return a.id.compareTo(b.id);
  }

  static Map<String, dynamic> _weekFieldsPatch(List<int> weeks) {
    if (weeks.isEmpty) {
      return {
        'weekNumber': FieldValue.delete(),
        'weekNumbers': FieldValue.delete(),
      };
    }
    if (weeks.length == 1) {
      return {
        'weekNumber': weeks.first,
        'weekNumbers': FieldValue.delete(),
      };
    }
    return {
      'weekNumbers': weeks,
      'weekNumber': FieldValue.delete(),
    };
  }

  static String _weekLabel(List<int> weeks) {
    if (weeks.isEmpty) return '';
    if (weeks.length == 1) return ' · sem. ${weeks.first}';
    return ' · sem. ${weeks.join(', ')}';
  }
}
