import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/finance_account_balance_utils.dart';
import '../utils/finance_line_opening.dart';
import '../utils/finance_transaction_datetime.dart';
import '../utils/finance_transactions_hub.dart';
import '../utils/finance_transactions_realtime.dart';
import '../utils/firestore_user_doc_id.dart';
import '../utils/fifty_two_weeks_plan.dart';
import '../utils/installment_split.dart';
import 'finance_accounts_service.dart';
import 'finance_opening_balance_service.dart';
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

/// Depósito / resgate em meta + lançamento no Financeiro.
///
/// Desde 02/10/2026 (autorizado pelo dono) guardar dinheiro na meta é uma
/// RESERVA que sai da conta escolhida — não é mais receita:
/// - depósito novo = lançamento `expense` pago, categoria «Meta», com
///   `goalReserve: true` e `goalMovement: 'deposit'` (a conta perde o valor,
///   a meta ganha); [financeForaDosTotais] o tira dos gráficos de categoria;
/// - resgate = `income` com `goalReserve: true` e `goalMovement: 'withdrawal'`
///   (o valor volta para a conta) + contribuição NEGATIVA na meta;
/// - depósitos antigos (`income` sem `goalReserve`) são lidos como estão —
///   nada é migrado à força; editar/excluir continua funcionando nos dois.
/// Lançamento, contribuição e semanas vão num único [WriteBatch].
class GoalDepositService {
  GoalDepositService._();

  static const String kGoalReserve = 'goalReserve';
  static const String kGoalMovement = 'goalMovement';
  static const String kMovementDeposit = 'deposit';
  static const String kMovementWithdrawal = 'withdrawal';

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

  /// Semanas que o usuário ESCOLHEU ao depositar (respeitadas no recálculo).
  /// Depósito antigo sem o campo: as semanas que ele já marcava.
  static List<int> chosenWeeksFromContribData(Map<String, dynamic> data) {
    final raw = data['chosenWeeks'];
    if (raw is List) {
      return raw.whereType<num>().map((e) => e.toInt()).toList();
    }
    return weeksFromContribData(data);
  }

  static bool isWithdrawalContrib(Map<String, dynamic> data) =>
      (data['kind'] ?? '') == kMovementWithdrawal ||
      ((data['amount'] as num?)?.toDouble() ?? 0) < 0;

  /// Depósito antigo: entrou como RECEITA na conta (não saiu dela).
  static bool isLegacyIncomeContrib(Map<String, dynamic> data) =>
      !isWithdrawalContrib(data) &&
      data['reserve'] != true &&
      (data['transactionId'] ?? '').toString().trim().isNotEmpty;

  /// Saldo guardado na meta (depósitos − resgates).
  static double savedAmountFromContribs(
    Iterable<Map<String, dynamic>> contribs,
  ) {
    var s = 0.0;
    for (final d in contribs) {
      s += (d['amount'] as num?)?.toDouble() ?? 0;
    }
    return s;
  }

  /// Saldo atual de uma conta — a MESMA regra do carrossel «Saldos por conta»
  /// do Financeiro no mês corrente: saldo de abertura da conta
  /// ([FinanceOpeningBalanceService], buckets do servidor) + líquido pago do
  /// mês ([FinanceAccountBalanceUtils.netPaidByAccountEffectiveFromMaps]:
  /// data efetiva, cartão de crédito fora, pagamento de fatura debitando a
  /// conta que pagou).
  ///
  /// Correção autorizada pelo dono (02/10/2026): antes somava todos os
  /// lançamentos pagos com `financeAccountId` da conta, de todas as datas
  /// (inclusive futuras), ignorava o pagamento de fatura feito pela conta
  /// (`paidFromFinanceAccountId`) e lia a coleção inteira da conta.
  static Future<double> accountBalanceAllTime({
    required String uid,
    required String financeAccountId,
  }) async {
    final id = financeAccountId.trim();
    if (id.isEmpty) return 0;
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0);
    final accounts = await FinanceAccountsService().listOnce(uid);
    final cards = FinanceAccountBalanceUtils.creditCardAccountIds(accounts);
    final opening = await FinanceOpeningBalanceService.load(
      uid: uid,
      periodStart: monthStart,
      loadAccounts: true,
    );
    final docs = await financePeriodMergedDocumentsCollect(
      uid: firestoreUserDocIdForAppShell(uid),
      from: monthStart,
      to: monthEnd,
      statusFilter: 'paid',
    );
    return accountBalanceFromMaps(
      opening: opening.byAccount[id] ?? 0,
      monthItems: docs.map((d) => d.data()),
      from: monthStart,
      to: monthEnd,
      accountId: id,
      creditCardIds: cards,
    );
  }

  /// Parte pura de [accountBalanceAllTime] (testável).
  static double accountBalanceFromMaps({
    required double opening,
    required Iterable<Map<String, dynamic>> monthItems,
    required DateTime from,
    required DateTime to,
    required String accountId,
    required Set<String> creditCardIds,
  }) {
    final net = FinanceAccountBalanceUtils.netPaidByAccountEffectiveFromMaps(
      items: monthItems,
      from: from,
      to: to,
      creditCardIds: creditCardIds,
    );
    return opening + (net[accountId] ?? 0);
  }

  static Map<String, dynamic> _reserveTxData({
    required bool withdrawal,
    required double amount,
    required String goalId,
    required String goalTitle,
    required List<int> weeks,
    required DateTime effectiveDate,
    required String accountId,
  }) {
    final ts = Timestamp.fromDate(effectiveDate);
    return {
      'type': withdrawal ? 'income' : 'expense',
      'amount': amount,
      'category': 'Meta',
      'description': _txDescription(
        withdrawal: withdrawal,
        reserve: true,
        goalTitle: goalTitle,
        weeks: weeks,
      ),
      'status': 'paid',
      'date': ts,
      'paidAt': ts,
      'effectiveDate':
          FinanceLineOpening.effectiveTimestampForWrite(date: effectiveDate),
      'recurrence': 'none',
      'installmentCount': 1,
      'installmentIndex': 1,
      'goalId': goalId,
      kGoalReserve: true,
      kGoalMovement: withdrawal ? kMovementWithdrawal : kMovementDeposit,
      if (accountId.isNotEmpty) 'financeAccountId': accountId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static String _txDescription({
    required bool withdrawal,
    required bool reserve,
    required String goalTitle,
    required List<int> weeks,
  }) {
    if (withdrawal) return 'Resgate da meta: $goalTitle';
    final label = _weekLabel(weeks);
    return reserve
        ? 'Reserva para meta: $goalTitle$label'
        : 'Depósito meta: $goalTitle$label';
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
  }) =>
      _saveMovement(
        uid: uid,
        goalRef: goalRef,
        goalId: goalId,
        goalTitle: goalTitle,
        amount: amount,
        date: date,
        financeAccountId: financeAccountId,
        weekNumbers: weekNumbers,
        createFinanceTx: createFinanceTx,
        withdrawal: false,
      );

  /// «Resgatar / Retirar da meta»: o valor sai da meta e (com
  /// [createFinanceTx]) volta para a conta como entrada fora dos totais.
  static Future<void> withdraw({
    required String uid,
    required DocumentReference<Map<String, dynamic>> goalRef,
    required String goalId,
    required String goalTitle,
    required double amount,
    required DateTime date,
    String? financeAccountId,
    bool createFinanceTx = true,
  }) =>
      _saveMovement(
        uid: uid,
        goalRef: goalRef,
        goalId: goalId,
        goalTitle: goalTitle,
        amount: amount,
        date: date,
        financeAccountId: financeAccountId,
        weekNumbers: null,
        createFinanceTx: createFinanceTx,
        withdrawal: true,
      );

  static Future<void> _saveMovement({
    required String uid,
    required DocumentReference<Map<String, dynamic>> goalRef,
    required String goalId,
    required String goalTitle,
    required double amount,
    required DateTime date,
    required String? financeAccountId,
    required List<int>? weekNumbers,
    required bool createFinanceTx,
    required bool withdrawal,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('Valor deve ser maior que zero.');
    }
    final accountId = financeAccountId?.trim() ?? '';
    final weeks = weekNumbers?.where((w) => w >= 1 && w <= 52).toList() ?? [];
    weeks.sort();

    final effectiveDate =
        FinanceTransactionDatetime.mergeCalendarDayWithClockNow(date);
    final goalSnap = await goalRef.get();
    final goalData = goalSnap.data() ?? {};
    final is52 = FiftyTwoWeeksPlan.is52WeeksGoal(goalData);
    final contribSnap = await _contribRef(goalRef).get();

    if (withdrawal) {
      final saved =
          savedAmountFromContribs(contribSnap.docs.map((d) => d.data()));
      if (amount > saved + 0.004) {
        throw StateError(
          'A meta tem ${saved.toStringAsFixed(2).replaceAll('.', ',')} '
          'guardado — não dá para resgatar mais que isso.',
        );
      }
    }

    final newContribRef = _contribRef(goalRef).doc();
    final txRef =
        createFinanceTx ? TransactionSaveService.txRef(uid).doc() : null;
    final contribData = <String, dynamic>{
      'amount': withdrawal ? -amount : amount,
      'date': Timestamp.fromDate(effectiveDate),
      'createdAt': FieldValue.serverTimestamp(),
      'kind': withdrawal ? kMovementWithdrawal : kMovementDeposit,
      if (weeks.isNotEmpty) 'chosenWeeks': weeks,
      if (accountId.isNotEmpty) 'financeAccountId': accountId,
      if (txRef != null) 'transactionId': txRef.id,
      if (txRef != null) 'reserve': true,
    };

    var myWeeks = weeks;
    final extra = <void Function(WriteBatch)>[];
    if (is52) {
      final plan = _plan52(
        goalData: goalData,
        existing: contribSnap.docs,
        replaceId: newContribRef.id,
        replaceRef: newContribRef,
        replaceData: contribData,
      );
      myWeeks = plan.weeksFor[newContribRef.id] ?? const [];
      if (myWeeks.length == 1) contribData['weekNumber'] = myWeeks.first;
      if (myWeeks.length > 1) contribData['weekNumbers'] = myWeeks;
      extra.addAll(plan.patches);
      extra.add((b) => b.update(goalRef, {'weeksPaid': plan.paid}));
    } else if (weeks.isNotEmpty) {
      if (weeks.length == 1) contribData['weekNumber'] = weeks.first;
      if (weeks.length > 1) contribData['weekNumbers'] = weeks;
      final paid = FiftyTwoWeeksPlan.paidWeeksFromData(goalData).toList();
      for (final w in weeks) {
        if (!paid.contains(w)) paid.add(w);
      }
      paid.sort();
      extra.add((b) => b.update(goalRef, {'weeksPaid': paid}));
    }

    final ops = <void Function(WriteBatch)>[
      if (txRef != null)
        (b) => b.set(
              txRef,
              _reserveTxData(
                withdrawal: withdrawal,
                amount: amount,
                goalId: goalId,
                goalTitle: goalTitle,
                weeks: myWeeks,
                effectiveDate: effectiveDate,
                accountId: accountId,
              ),
            ),
      (b) => b.set(newContribRef, contribData),
      ...extra,
    ];
    await _commitOps(ops);
    if (txRef != null) {
      FinanceOpeningBalanceService.invalidateIfBefore(uid, effectiveDate);
    }
    FinanceTransactionsHub.notifyMutated(uid: uid);
  }

  /// Grava as operações: as primeiras 450 num ÚNICO lote (lançamento +
  /// contribuição + semanas juntos); o excedente — só patches de rótulo de
  /// semana em metas com centenas de depósitos — em lotes seguintes.
  static Future<void> _commitOps(List<void Function(WriteBatch)> ops) async {
    for (final part in chunked(ops, size: 450)) {
      final batch = FirebaseFirestore.instance.batch();
      for (final op in part) {
        op(batch);
      }
      await batch.commit();
    }
  }

  /// Recalcula as semanas de TODOS os depósitos (ordem cronológica) com
  /// [FiftyTwoWeeksPlan.allocateDeposits]. [replaceId]/[replaceData]: a
  /// contribuição nova ou editada (ainda não gravada); [removeIds]: as que vão
  /// sair. Devolve as semanas de cada contribuição, os patches das que
  /// mudaram e o `weeksPaid` final.
  static ({
    Map<String, List<int>> weeksFor,
    List<void Function(WriteBatch)> patches,
    List<int> paid,
  }) _plan52({
    required Map<String, dynamic> goalData,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> existing,
    String? replaceId,
    DocumentReference<Map<String, dynamic>>? replaceRef,
    Map<String, dynamic>? replaceData,
    Set<String> removeIds = const {},
  }) {
    final entries = <({
      String id,
      DocumentReference<Map<String, dynamic>> ref,
      Map<String, dynamic> data,
      bool replaced,
    })>[];
    for (final d in existing) {
      if (removeIds.contains(d.id)) continue;
      if (d.id == replaceId) continue;
      entries.add((id: d.id, ref: d.reference, data: d.data(), replaced: false));
    }
    if (replaceId != null && replaceRef != null && replaceData != null) {
      entries.add(
          (id: replaceId, ref: replaceRef, data: replaceData, replaced: true));
    }
    entries.sort((a, b) {
      final c = _contribSortKey(a.data).compareTo(_contribSortKey(b.data));
      return c != 0 ? c : a.id.compareTo(b.id);
    });

    final target = (goalData['targetAmount'] as num?)?.toDouble() ?? 0;
    final planStart =
        FiftyTwoWeeksPlan.planStartFromData(goalData) ?? DateTime.now();
    final schedule = FiftyTwoWeeksPlan.buildSchedule(
      target: target,
      planStart: planStart,
    );
    final alloc = FiftyTwoWeeksPlan.allocateDeposits(
      schedule: schedule,
      deposits: [
        for (final e in entries)
          FiftyTwoWeeksDeposit(
            amount: (e.data['amount'] as num?)?.toDouble() ?? 0,
            chosenWeeks: chosenWeeksFromContribData(e.data),
          ),
      ],
    );

    final weeksFor = <String, List<int>>{};
    final patches = <void Function(WriteBatch)>[];
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final w = alloc.weeksByDeposit[i];
      weeksFor[e.id] = w;
      if (e.replaced) continue;
      final old = weeksFromContribData(e.data)..sort();
      if (_sameWeeks(old, w)) continue;
      patches.add((b) => b.update(e.ref, _weekFieldsPatch(w)));
    }
    return (weeksFor: weeksFor, patches: patches, paid: alloc.paidWeeks);
  }

  static bool _sameWeeks(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static DateTime _contribSortKey(Map<String, dynamic> d) {
    final dateTs = d['date'];
    if (dateTs is Timestamp) return dateTs.toDate();
    final createdTs = d['createdAt'];
    if (createdTs is Timestamp) return createdTs.toDate();
    return DateTime.fromMillisecondsSinceEpoch(0);
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
    final withdrawal = isWithdrawalContrib(data);
    final accountId = financeAccountId?.trim() ?? '';
    final txId = (data['transactionId'] ?? '').toString().trim();
    final goalSnap = await goalRef.get();
    final goalData = goalSnap.data() ?? {};
    final title = goalTitle ?? (goalData['title'] ?? 'Meta').toString();
    final is52 = FiftyTwoWeeksPlan.is52WeeksGoal(goalData);

    final effectiveDate =
        FinanceTransactionDatetime.mergeCalendarDayWithClockNow(date);
    final contribUpdate = <String, dynamic>{
      'amount': withdrawal ? -amount : amount,
      'date': Timestamp.fromDate(effectiveDate),
      if (accountId.isNotEmpty) 'financeAccountId': accountId,
    };

    var newWeeks = weeksFromContribData(data);
    final extra = <void Function(WriteBatch)>[];
    if (is52) {
      final contribSnap = await _contribRef(goalRef).get();
      final plan = _plan52(
        goalData: goalData,
        existing: contribSnap.docs,
        replaceId: contribDoc.id,
        replaceRef: contribDoc.reference,
        replaceData: {...data, ...contribUpdate},
      );
      newWeeks = plan.weeksFor[contribDoc.id] ?? const [];
      contribUpdate.addAll(_weekFieldsPatch(newWeeks));
      extra.addAll(plan.patches);
      extra.add((b) => b.update(goalRef, {'weeksPaid': plan.paid}));
    }

    final ops = <void Function(WriteBatch)>[
      (b) => b.update(contribDoc.reference, contribUpdate),
      if (txId.isNotEmpty)
        (b) => b.update(TransactionSaveService.txRef(uid).doc(txId), {
              'amount': amount,
              'date': Timestamp.fromDate(effectiveDate),
              if (data['reserve'] == true)
                'paidAt': Timestamp.fromDate(effectiveDate),
              'effectiveDate': FinanceLineOpening.effectiveTimestampForWrite(
                  date: effectiveDate),
              'description': _txDescription(
                withdrawal: withdrawal,
                reserve: data['reserve'] == true,
                goalTitle: title,
                weeks: newWeeks,
              ),
              if (accountId.isNotEmpty) 'financeAccountId': accountId,
              'updatedAt': FieldValue.serverTimestamp(),
            }),
      ...extra,
    ];
    await _commitOps(ops);
    if (txId.isNotEmpty) {
      FinanceOpeningBalanceService.invalidateIfBefore(uid, effectiveDate);
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
    // Receita (depósito antigo / resgate) ou despesa (reserva nova): todo
    // lançamento com goalId é movimento de meta.
    final goalId = (txData['goalId'] ?? '').toString().trim();
    if (goalId.isEmpty) return null;
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
      final removing = {
        for (final d in contribSnap.docs)
          if ((d.data()['transactionId'] ?? '').toString() == txId) d.id,
      };
      final newPaid = _plan52(
        goalData: goalData,
        existing: contribSnap.docs,
        removeIds: removing,
      ).paid;
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
    if (goalId.isEmpty) return;

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

  /// Apaga a contribuição (e, se pedido, o lançamento ligado) e recalcula as
  /// semanas — tudo no mesmo lote.
  static Future<void> _unlinkContribution({
    required DocumentReference<Map<String, dynamic>> goalRef,
    required QueryDocumentSnapshot<Map<String, dynamic>> contribDoc,
    required bool deleteLinkedTransaction,
    String? uid,
  }) async {
    final data = contribDoc.data();
    final txId = (data['transactionId'] ?? '').toString().trim();

    final goalSnap = await goalRef.get();
    final goalData = goalSnap.data() ?? {};
    final extra = <void Function(WriteBatch)>[];
    if (goalSnap.exists && FiftyTwoWeeksPlan.is52WeeksGoal(goalData)) {
      final contribSnap = await _contribRef(goalRef).get();
      final plan = _plan52(
        goalData: goalData,
        existing: contribSnap.docs,
        removeIds: {contribDoc.id},
      );
      extra.addAll(plan.patches);
      extra.add((b) => b.update(goalRef, {'weeksPaid': plan.paid}));
    }

    final deleteTx = deleteLinkedTransaction && txId.isNotEmpty && uid != null;
    await _commitOps([
      if (deleteTx)
        (b) => b.delete(TransactionSaveService.txRef(uid).doc(txId)),
      (b) => b.delete(contribDoc.reference),
      ...extra,
    ]);

    if (deleteLinkedTransaction && uid != null) {
      FinanceOpeningBalanceService.invalidateForUser(uid);
      FinanceTransactionsHub.notifyMutated(uid: uid);
    }
  }

  /// Recalcula `weeksPaid` e rótulos de semana em cada depósito restante
  /// (ordem cronológica, semanas escolhidas respeitadas, só semanas cobertas
  /// por inteiro). Sem depósitos → semana 0 (lista vazia).
  static Future<void> recalculate52WeeksPaid({
    required DocumentReference<Map<String, dynamic>> goalRef,
  }) async {
    final goalSnap = await goalRef.get();
    if (!goalSnap.exists) return;
    final goalData = goalSnap.data() ?? {};
    if (!FiftyTwoWeeksPlan.is52WeeksGoal(goalData)) return;

    final contribSnap = await _contribRef(goalRef).get();
    final plan = _plan52(goalData: goalData, existing: contribSnap.docs);
    await _commitOps([
      ...plan.patches,
      (b) => b.update(goalRef, {'weeksPaid': plan.paid}),
    ]);
  }

  /// Quantos depósitos e lançamentos do Financeiro estão ligados à meta
  /// (para o diálogo de exclusão).
  static Future<({int contributions, int transactions})> countGoalLinks({
    required String uid,
    required DocumentReference<Map<String, dynamic>> goalRef,
  }) async {
    final contribs = await _contribRef(goalRef).get();
    final txs = await TransactionSaveService.txRef(uid)
        .where('goalId', isEqualTo: goalRef.id)
        .get();
    return (contributions: contribs.docs.length, transactions: txs.docs.length);
  }

  /// Exclui a meta e, se pedido, os depósitos (subcoleção `contributions`) e
  /// os lançamentos do Financeiro com `goalId` desta meta.
  static Future<void> deleteGoal({
    required String uid,
    required DocumentReference<Map<String, dynamic>> goalRef,
    required bool deleteContributions,
    required bool deleteTransactions,
  }) async {
    final ops = <void Function(WriteBatch)>[];
    if (deleteTransactions) {
      final txs = await TransactionSaveService.txRef(uid)
          .where('goalId', isEqualTo: goalRef.id)
          .get();
      for (final d in txs.docs) {
        ops.add((b) => b.delete(d.reference));
      }
    }
    if (deleteContributions) {
      final contribs = await _contribRef(goalRef).get();
      for (final d in contribs.docs) {
        ops.add((b) => b.delete(d.reference));
      }
    }
    ops.add((b) => b.delete(goalRef));
    await _commitOps(ops);
    if (deleteTransactions) {
      FinanceOpeningBalanceService.invalidateForUser(uid);
      FinanceTransactionsHub.notifyMutated(uid: uid);
    }
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
