import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/app_business_rules.dart';
import '../utils/finance_line_opening.dart';
import '../utils/finance_transaction_status_resolver.dart';
import '../utils/finance_transactions_hub.dart';
import '../utils/firestore_user_doc_id.dart';
import '../utils/fixed_flow_schedule.dart';
import 'finance_month_cache.dart';

/// Receitas fixas (aluguéis, comissões, juros, etc.): o sistema gera lançamentos **pendentes** por mês no período.
/// Mesma lógica de [FixedExpenseService], com `type: income` e coleção `fixed_incomes`.
class FixedIncomeService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const int batchLimit = 500;
  static const int maxMonthsAhead = 24;

  CollectionReference<Map<String, dynamic>> _fixedRef(String uid) => _db
      .collection('users')
      .doc(firestoreUserDocIdForAppShell(uid))
      .collection('fixed_incomes');

  CollectionReference<Map<String, dynamic>> _txRef(String uid) => _db
      .collection('users')
      .doc(firestoreUserDocIdForAppShell(uid))
      .collection('transactions');

  Future<List<Map<String, dynamic>>> list(String uid) async {
    final snap =
        await _fixedRef(uid).orderBy('createdAt', descending: true).get();
    return snap.docs.map((d) {
      final m = Map<String, dynamic>.from(d.data());
      m['id'] = d.id;
      return m;
    }).toList();
  }

  static const String modePeriod = 'period';
  static const String modeInstallments = 'installments';

  Future<String> add({
    required String uid,
    required String description,
    required String category,
    required double amount,
    required int dayOfMonth,
    required DateTime startDate,
    DateTime? endDate,
    String mode = modePeriod,
    int? totalParcelas,
    int? parcelaInicial,
    bool addToCalendar = false,
    String? calendarColorHex,
    String? financeAccountId,
    String? parceiroId,
    String? parceiroNome,
    String? parceiroTipo,
  }) async {
    final day = dayOfMonth.clamp(1, 31);
    DateTime end;
    int? effTotalParcelas;
    if (mode == modeInstallments &&
        totalParcelas != null &&
        totalParcelas >= 1) {
      effTotalParcelas =
          totalParcelas.clamp(1, AppBusinessRules.maxFixedFlowInstallments);
      final start = DateTime(startDate.year, startDate.month, startDate.day);
      final ini = (parcelaInicial ?? 1).clamp(1, effTotalParcelas);
      // Último dia do mês final (31/01 + 2 parcelas = 28/02, não 03/03).
      end = FixedFlowSchedule.installmentsEndDate(
        start: start,
        totalParcelas: effTotalParcelas,
        parcelaInicial: ini,
      );
    } else {
      effTotalParcelas = null;
      end = endDate ??
          DateTime(startDate.year + 10, startDate.month, startDate.day);
    }
    final accId = (financeAccountId ?? '').trim();
    // Cliente/fornecedor do cadastro de Vendas (opcional) — vai junto para
    // cada lançamento gerado no mês já nascer com o vínculo.
    final pid = (parceiroId ?? '').trim();
    final data = <String, dynamic>{
      if (pid.isNotEmpty) ...{
        'parceiroId': pid,
        'parceiroNome': (parceiroNome ?? '').trim(),
        'parceiroTipo': (parceiroTipo ?? '').trim(),
      },
      'description': description,
      'category': category,
      'amount': amount,
      'dayOfMonth': day,
      'startDate': Timestamp.fromDate(
          DateTime(startDate.year, startDate.month, startDate.day)),
      'endDate': Timestamp.fromDate(DateTime(end.year, end.month, end.day)),
      'active': true,
      'addToCalendar': addToCalendar,
      if (accId.isNotEmpty) 'financeAccountId': accId,
      if (addToCalendar &&
          calendarColorHex != null &&
          calendarColorHex.trim().isNotEmpty)
        'calendarColorHex': calendarColorHex.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (mode == modeInstallments && effTotalParcelas != null) {
      data['mode'] = modeInstallments;
      data['totalParcelas'] = effTotalParcelas;
      data['parcelaInicial'] = (parcelaInicial ?? 1).clamp(1, effTotalParcelas);
    } else {
      data['mode'] = modePeriod;
    }
    final ref = await _fixedRef(uid).add(data);
    return ref.id;
  }

  Future<int> update({
    required String uid,
    required String id,
    String? description,
    String? category,
    double? amount,
    int? dayOfMonth,
    DateTime? startDate,
    DateTime? endDate,
    bool? active,
    String? mode,
    int? totalParcelas,
    int? parcelaInicial,
    bool? addToCalendar,
    String? calendarColorHex,
    String? financeAccountId,
    bool clearFinanceAccount = false,
    String? parceiroId,
    String? parceiroNome,
    String? parceiroTipo,
  }) async {
    final data = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (description != null) data['description'] = description;
    if (category != null) data['category'] = category;
    if (amount != null) data['amount'] = amount;
    if (dayOfMonth != null) data['dayOfMonth'] = dayOfMonth.clamp(1, 31);
    if (startDate != null) {
      data['startDate'] = Timestamp.fromDate(
          DateTime(startDate.year, startDate.month, startDate.day));
    }
    if (endDate != null) {
      data['endDate'] = Timestamp.fromDate(
          DateTime(endDate.year, endDate.month, endDate.day));
    }
    if (active != null) data['active'] = active;
    if (mode != null) {
      data['mode'] = mode;
      if (mode == modePeriod) {
        data['totalParcelas'] = FieldValue.delete();
        data['parcelaInicial'] = FieldValue.delete();
      }
    }
    if (totalParcelas != null) {
      data['totalParcelas'] =
          totalParcelas.clamp(1, AppBusinessRules.maxFixedFlowInstallments);
    }
    if (parcelaInicial != null && totalParcelas != null) {
      final cap =
          totalParcelas.clamp(1, AppBusinessRules.maxFixedFlowInstallments);
      data['parcelaInicial'] = parcelaInicial.clamp(1, cap);
    }
    if (clearFinanceAccount) {
      data['financeAccountId'] = FieldValue.delete();
    } else if (financeAccountId != null) {
      final accId = financeAccountId.trim();
      if (accId.isEmpty) {
        data['financeAccountId'] = FieldValue.delete();
      } else {
        data['financeAccountId'] = accId;
      }
    }
    if (addToCalendar != null) {
      data['addToCalendar'] = addToCalendar;
      if (addToCalendar &&
          calendarColorHex != null &&
          calendarColorHex.trim().isNotEmpty) {
        data['calendarColorHex'] = calendarColorHex.trim();
      } else {
        data['calendarColorHex'] = FieldValue.delete();
      }
    } else if (calendarColorHex != null) {
      if (calendarColorHex.trim().isNotEmpty) {
        data['calendarColorHex'] = calendarColorHex.trim();
      } else {
        data['calendarColorHex'] = FieldValue.delete();
      }
    }
    // Cliente/fornecedor: `''` limpa o vínculo, `null` não mexe.
    if (parceiroId != null) {
      final pid = parceiroId.trim();
      if (pid.isEmpty) {
        data['parceiroId'] = FieldValue.delete();
        data['parceiroNome'] = FieldValue.delete();
        data['parceiroTipo'] = FieldValue.delete();
      } else {
        data['parceiroId'] = pid;
        data['parceiroNome'] = (parceiroNome ?? '').trim();
        data['parceiroTipo'] = (parceiroTipo ?? '').trim();
      }
    }
    final beforeSnap = await _fixedRef(uid).doc(id).get();
    final before = beforeSnap.data() ?? const <String, dynamic>{};
    await _fixedRef(uid).doc(id).update(data);
    // Meses PENDENTES já gerados acompanham a edição (valor, descrição,
    // categoria, nº da parcela) e os que sobraram ao encurtar a data final /
    // nº de parcelas são apagados. Pagos nunca são tocados.
    await _syncPendingWithFixed(uid, id, before);
    if (parceiroId != null) {
      await _updatePendingParceiro(
        uid,
        id,
        parceiroId.trim(),
        (parceiroNome ?? '').trim(),
        (parceiroTipo ?? '').trim(),
      );
    }
    if (addToCalendar != null || calendarColorHex != null) {
      // Só a cor mudou: respeita o opt-in gravado na fixa (ausente =
      // desligado; regra do dono 01/10/2026) — não liga sozinho.
      final ligado = addToCalendar ??
          ((await _fixedRef(uid).doc(id).get()).data()?['addToCalendar'] ==
              true);
      await _updateFuturePendingCalendarFlags(
        uid,
        id,
        ligado,
        calendarColorHex,
      );
    }
    if (clearFinanceAccount || financeAccountId != null) {
      await _updatePendingAccount(
        uid,
        id,
        clearFinanceAccount ? null : financeAccountId,
      );
    }
    if (dayOfMonth != null) {
      return updateFuturePendingEntries(uid, id, dayOfMonth.clamp(1, 31));
    }
    return 0;
  }

  /// Propaga banco/caixa para **todos** os lançamentos pendentes desta receita fixa.
  /// Não altera pagos/recebidos (`status != pending`).
  Future<int> _updatePendingAccount(
    String uid,
    String fixedIncomeId,
    String? financeAccountId,
  ) async {
    try {
      final snap = await _txRef(uid)
          .where('fixedIncomeId', isEqualTo: fixedIncomeId)
          .where('status', isEqualTo: 'pending')
          .get();
      if (snap.docs.isEmpty) return 0;
      final accId = (financeAccountId ?? '').trim();
      var updated = 0;
      for (var i = 0; i < snap.docs.length; i += batchLimit) {
        final batch = _db.batch();
        for (final doc in snap.docs.skip(i).take(batchLimit)) {
          batch.update(doc.reference, {
            if (accId.isNotEmpty)
              'financeAccountId': accId
            else
              'financeAccountId': FieldValue.delete(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          updated++;
        }
        await batch.commit();
      }
      return updated;
    } catch (_) {
      return 0;
    }
  }

  /// Propaga o cliente/fornecedor para os lançamentos ainda **pendentes**
  /// desta receita fixa. Recebidos ficam como estão.
  Future<int> _updatePendingParceiro(
    String uid,
    String fixedIncomeId,
    String parceiroId,
    String parceiroNome,
    String parceiroTipo,
  ) async {
    try {
      final snap = await _txRef(uid)
          .where('fixedIncomeId', isEqualTo: fixedIncomeId)
          .where('status', isEqualTo: 'pending')
          .get();
      if (snap.docs.isEmpty) return 0;
      var updated = 0;
      for (var i = 0; i < snap.docs.length; i += batchLimit) {
        final batch = _db.batch();
        for (final doc in snap.docs.skip(i).take(batchLimit)) {
          batch.update(doc.reference, {
            if (parceiroId.isNotEmpty) ...{
              'parceiroId': parceiroId,
              'parceiroNome': parceiroNome,
              'parceiroTipo': parceiroTipo,
            } else ...{
              'parceiroId': FieldValue.delete(),
              'parceiroNome': FieldValue.delete(),
              'parceiroTipo': FieldValue.delete(),
            },
            'updatedAt': FieldValue.serverTimestamp(),
          });
          updated++;
        }
        await batch.commit();
      }
      return updated;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _updateFuturePendingCalendarFlags(
    String uid,
    String fixedIncomeId,
    bool addToCalendar,
    String? calendarColorHex,
  ) async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final snap = await _txRef(uid)
          .where('fixedIncomeId', isEqualTo: fixedIncomeId)
          .where('status', isEqualTo: 'pending')
          .get();
      final toUpdate = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final doc in snap.docs) {
        final d = doc.data();
        final dateTs = d['date'];
        if (dateTs is! Timestamp) continue;
        final date = dateTs.toDate();
        if (date.isBefore(today)) continue;
        toUpdate.add(doc);
      }
      if (toUpdate.isEmpty) return;
      for (var i = 0; i < toUpdate.length; i += batchLimit) {
        final batch = _db.batch();
        for (final doc in toUpdate.skip(i).take(batchLimit)) {
          batch.update(doc.reference, {
            'addToCalendar': addToCalendar,
            if (addToCalendar)
              'hideFromCalendar': FieldValue.delete()
            else
              'hideFromCalendar': true,
            if (addToCalendar &&
                calendarColorHex != null &&
                calendarColorHex.trim().isNotEmpty)
              'calendarColorHex': calendarColorHex.trim()
            else
              'calendarColorHex': FieldValue.delete(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }
    } catch (_) {}
  }

  Future<int> updateFuturePendingEntries(
      String uid, String fixedIncomeId, int newDayOfMonth) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final snap = await _txRef(uid)
        .where('fixedIncomeId', isEqualTo: fixedIncomeId)
        .where('status', isEqualTo: 'pending')
        .get();
    final toUpdate = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final doc in snap.docs) {
      final d = doc.data();
      final dateTs = d['date'];
      if (dateTs is! Timestamp) continue;
      final date = dateTs.toDate();
      if (date.isBefore(today)) continue;
      int lastDay = 28;
      try {
        lastDay = DateTime(date.year, date.month + 1, 0).day;
      } catch (_) {}
      final day = newDayOfMonth.clamp(1, lastDay);
      final newDate = DateTime(date.year, date.month, day);
      if (newDate == date) continue;
      toUpdate.add(doc);
    }
    int updated = 0;
    for (var i = 0; i < toUpdate.length; i += batchLimit) {
      final batch = _db.batch();
      for (final doc in toUpdate.skip(i).take(batchLimit)) {
        final d = doc.data();
        final dateTs = d['date'];
        if (dateTs is! Timestamp) continue;
        final date = dateTs.toDate();
        int lastDay = 28;
        try {
          lastDay = DateTime(date.year, date.month + 1, 0).day;
        } catch (_) {}
        final day = newDayOfMonth.clamp(1, lastDay);
        final newDate = DateTime(date.year, date.month, day);
        batch.update(doc.reference, {
          'date': Timestamp.fromDate(newDate),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        updated++;
      }
      await batch.commit();
    }
    return updated;
  }

  /// Remove uma receita fixa e os lançamentos pendentes ligados a ela
  /// (Agenda/calendário + Financeiro). Recebidos permanecem.
  Future<int> delete(String uid, String id) async {
    final removed = await _deletePendingEntriesForFixed(uid, id);
    await _fixedRef(uid).doc(id).delete();
    FinanceMonthCache.clearUid(uid);
    FinanceTransactionsHub.notifyMutated(uid: uid);
    return removed;
  }

  /// Remove todos os lançamentos **pending** desta receita fixa (qualquer mês).
  Future<int> _deletePendingEntriesForFixed(
      String uid, String fixedIncomeId) async {
    final snap = await _txRef(uid)
        .where('fixedIncomeId', isEqualTo: fixedIncomeId)
        .get();
    final toDelete = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final doc in snap.docs) {
      final status = (doc.data()['status'] ?? '').toString().toLowerCase();
      if (status != 'pending') continue;
      toDelete.add(doc);
    }
    if (toDelete.isEmpty) return 0;
    for (var i = 0; i < toDelete.length; i += batchLimit) {
      final batch = _db.batch();
      for (final doc in toDelete.skip(i).take(batchLimit)) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
    return toDelete.length;
  }

  /// Migra lançamentos pendentes com data anterior a hoje para "paid".
  /// Limpa dados legados e garante que parcelas passadas de receitas fixas
  /// não fiquem eternamente como pendentes.
  Future<void> _migratePastPendingEntries(
    String uid,
    List<QuerySnapshot<Map<String, dynamic>>> snaps,
  ) async {
    // Antes esta rotina marcava como PAGO todo pendente com data anterior a
    // hoje. Dar baixa é decisão do usuário: uma conta vencida continua
    // vencida até ele confirmar que pagou (ou receber, no caso da receita).
    // Mantida como no-op para não mexer nas chamadas existentes.
    return;
    // ignore: dead_code
    try {
      final startOfToday = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      );
      final toUpdate = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final snap in snaps) {
        for (final doc in snap.docs) {
          final d = doc.data();
          if ((d['status'] ?? '').toString() != 'pending') continue;
          final dateTs = d['date'];
          if (dateTs is! Timestamp) continue;
          final date = dateTs.toDate();
          if (!date.isBefore(startOfToday)) continue;
          toUpdate.add(doc);
        }
      }
      if (toUpdate.isEmpty) return;
      for (var i = 0; i < toUpdate.length; i += batchLimit) {
        final batch = _db.batch();
        for (final doc in toUpdate.skip(i).take(batchLimit)) {
          final dateTs = doc.data()['date'];
          final date = dateTs is Timestamp ? dateTs.toDate() : DateTime.now();
          final paidAt =
              FinanceTransactionStatusResolver.paidAtForAutoPaid(date);
          batch.update(doc.reference, {
            'status': 'paid',
            'paidAt': paidAt,
            'effectiveDate': FinanceLineOpening.effectiveTimestampForWrite(
              date: date,
              paidAt: paidAt,
            ),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }
    } catch (_) {
      // Falha silenciosa: não impede a geração das parcelas futuras.
    }
  }

  Future<int> deleteAllParcelas(String uid, String fixedIncomeId) async {
    try {
      final snap = await _txRef(uid)
          .where('fixedIncomeId', isEqualTo: fixedIncomeId)
          .get();
      if (snap.docs.isEmpty) return 0;
      int deleted = 0;
      for (var i = 0; i < snap.docs.length; i += batchLimit) {
        final batch = _db.batch();
        for (final doc in snap.docs.skip(i).take(batchLimit)) {
          batch.delete(doc.reference);
          deleted++;
        }
        await batch.commit();
      }
      return deleted;
    } catch (e) {
      throw Exception('Erro ao remover parcelas da receita fixa: $e');
    }
  }

  /// Guarda contra chamadas concorrentes de [ensureMonthlyEntries] no mesmo
  /// aparelho (igual à despesa fixa) — duas gerações juntas duplicavam o mês.
  static Future<int>? _ensureRunning;

  Future<int> ensureMonthlyEntries(String uid, {int monthsAhead = 4}) async {
    if (_ensureRunning != null) return _ensureRunning!;
    _ensureRunning = _ensureMonthlyEntriesImpl(uid, monthsAhead: monthsAhead);
    try {
      return await _ensureRunning!;
    } finally {
      _ensureRunning = null;
    }
  }

  Future<int> _ensureMonthlyEntriesImpl(String uid,
      {int monthsAhead = 4}) async {
    final items = await list(uid);
    final activeItems = <Map<String, dynamic>>[];
    for (final fe in items) {
      if (fe['active'] != true) continue;
      final startTs = fe['startDate'];
      final endTs = fe['endDate'];
      if (startTs is! Timestamp || endTs is! Timestamp) continue;
      final feId = (fe['id'] ?? '').toString();
      if (feId.isEmpty) continue;
      final amount = (fe['amount'] as num?)?.toDouble() ?? 0;
      if (amount <= 0) continue;
      activeItems.add(fe);
    }
    if (activeItems.isEmpty) return 0;

    final existingSnaps = await Future.wait([
      for (final fe in activeItems)
        _txRef(uid)
            .where('fixedIncomeId', isEqualTo: fe['id'].toString())
            .get(),
    ]);

    // Migra lançamentos pendentes com data no passado para "paid". Isso limpa
    // dados antigos que não deveriam estar como pendentes e evita que voltem
    // ao painel de pendentes após serem excluídos.
    await _migratePastPendingEntries(uid, existingSnaps);

    final List<Map<String, dynamic>> toCreate = [];
    for (var i = 0; i < activeItems.length; i++) {
      final fe = activeItems[i];
      final existingSnap = existingSnaps[i];
      final start = (fe['startDate'] as Timestamp).toDate();
      final end = (fe['endDate'] as Timestamp).toDate();
      final dayOfMonth = (fe['dayOfMonth'] as num?)?.toInt() ?? 1;
      final category = (fe['category'] ?? 'Receita').toString();
      final description = (fe['description'] ?? 'Receita fixa').toString();
      final feId = fe['id'].toString();
      final amount = (fe['amount'] as num?)?.toDouble() ?? 0;
      // Só aparece na Agenda com opt-in explícito; legado sem campo =
      // DESLIGADO (regra do dono 01/10/2026).
      final addToCalendar = fe['addToCalendar'] == true;
      final calHex = (fe['calendarColorHex'] ?? '').toString().trim();
      final financeAccountId =
          (fe['financeAccountId'] ?? '').toString().trim();
      final parceiroId = (fe['parceiroId'] ?? '').toString().trim();
      final parceiroNome = (fe['parceiroNome'] ?? '').toString().trim();
      final parceiroTipo = (fe['parceiroTipo'] ?? '').toString().trim();

      // Meses explicitamente excluídos pelo usuário são tratados como "existentes"
      // para não recriar parcelas removidas manualmente.
      final existingMonthKeys = <String>{
        ...List<String>.from(fe['excludedMonths'] ?? const []),
      };
      for (final d in existingSnap.docs) {
        final data = d.data();
        final mk = data['fixedIncomeMonthKey'] as String?;
        if (mk != null && mk.isNotEmpty) {
          existingMonthKeys.add(mk);
          continue;
        }
        final dateTs = data['date'];
        if (dateTs is Timestamp) {
          final dt = dateTs.toDate();
          existingMonthKeys
              .add('${dt.year}-${dt.month.toString().padLeft(2, '0')}');
        }
      }

      final isByInstallments = (fe['mode'] ?? modePeriod) == modeInstallments;
      final totalParcelas = (fe['totalParcelas'] as num?)?.toInt();
      final parcelaInicial = (fe['parcelaInicial'] as num?)?.toInt() ?? 1;
      final installmentCount =
          isByInstallments && totalParcelas != null ? totalParcelas : 1;
      final startMonth = DateTime(start.year, start.month, 1);

      DateTime month = DateTime(start.year, start.month, 1);
      final limitEnd = DateTime(end.year, end.month, 1);

      while (!month.isAfter(limitEnd)) {
        if (month.isBefore(startMonth)) {
          month = DateTime(month.year, month.month + 1, 1);
          continue;
        }
        final monthKey =
            '${month.year}-${month.month.toString().padLeft(2, '0')}';
        if (existingMonthKeys.contains(monthKey)) {
          month = DateTime(month.year, month.month + 1, 1);
          continue;
        }
        int parcelIndex = 1;
        if (isByInstallments && totalParcelas != null) {
          final monthsFromStart =
              (month.year - start.year) * 12 + (month.month - start.month);
          // Sem clamp: mês fora das parcelas NÃO gera (antes repetia N/N).
          parcelIndex = parcelaInicial + monthsFromStart;
          if (parcelIndex < 1 || parcelIndex > totalParcelas) {
            month = DateTime(month.year, month.month + 1, 1);
            continue;
          }
        }
        existingMonthKeys.add(monthKey);
        int lastDay = 31;
        try {
          lastDay = DateTime(month.year, month.month + 1, 0).day;
        } catch (_) {}
        final dayClamped = dayOfMonth.clamp(1, lastDay);
        final date = DateTime(month.year, month.month, dayClamped);
        final descOut =
            isByInstallments && totalParcelas != null && totalParcelas > 1
                ? '$description · $parcelIndex/$totalParcelas'
                : description;
        final dateTs = Timestamp.fromDate(date);
        // WISDOMAPP: o mês gerado nasce PENDENTE, mesmo com data passada —
        // dar baixa é decisão do usuário (regra anterior ao port, mantida).
        const status = 'pending';
        const Timestamp? paidAt = null;
        toCreate.add({
          '__id': FixedFlowSchedule.generatedTxId(
            prefix: 'fi',
            fixedId: feId,
            month: month,
          ),
          'type': 'income',
          'amount': amount,
          'category': category,
          'description': descOut,
          'status': status,
          'date': dateTs,
          if (paidAt != null) 'paidAt': paidAt,
          'effectiveDate': FinanceLineOpening.effectiveTimestampForWrite(
            date: date,
            paidAt: paidAt,
          ),
          'recurrence': 'fixed',
          'installmentCount': installmentCount,
          'installmentIndex': parcelIndex,
          'fixedIncomeId': feId,
          'fixedIncomeMonthKey': monthKey,
          'addToCalendar': addToCalendar,
          if (!addToCalendar) 'hideFromCalendar': true,
          if (financeAccountId.isNotEmpty) 'financeAccountId': financeAccountId,
          if (parceiroId.isNotEmpty) ...{
            'parceiroId': parceiroId,
            'parceiroNome': parceiroNome,
            'parceiroTipo': parceiroTipo,
          },
          if (addToCalendar && calHex.isNotEmpty) 'calendarColorHex': calHex,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        month = DateTime(month.year, month.month + 1, 1);
      }
    }

    try {
      return await _createGeneratedMonths(uid, toCreate);
    } catch (e) {
      throw Exception('Erro ao gerar parcelas de receitas fixas: $e');
    }
  }

  /// Grava os meses gerados com ID determinístico (`fi_{fixa}_{yyyyMM}`):
  /// numa transação, só cria o documento que ainda NÃO existe — dois aparelhos
  /// gerando juntos não duplicam o mês nem sobrescrevem um mês já pago.
  /// Meses antigos com ID aleatório continuam valendo: já entraram em
  /// `existingMonthKeys` pela consulta por `fixedIncomeId` e não chegam aqui.
  /// Sem rede (transação indisponível) cai num lote comum com os mesmos IDs.
  Future<int> _createGeneratedMonths(
    String uid,
    List<Map<String, dynamic>> toCreate,
  ) async {
    var created = 0;
    const chunk = 200;
    for (var j = 0; j < toCreate.length; j += chunk) {
      final part = toCreate.skip(j).take(chunk).toList();
      final refs = [
        for (final d in part) _txRef(uid).doc(d['__id'] as String),
      ];
      final payloads = [
        for (final d in part) Map<String, dynamic>.from(d)..remove('__id'),
      ];
      try {
        final n = await _db.runTransaction<int>((t) async {
          final snaps = <DocumentSnapshot<Map<String, dynamic>>>[];
          for (final r in refs) {
            snaps.add(await t.get(r));
          }
          var made = 0;
          for (var k = 0; k < refs.length; k++) {
            if (snaps[k].exists) continue;
            t.set(refs[k], payloads[k]);
            made++;
          }
          return made;
        });
        created += n;
      } catch (_) {
        final batch = _db.batch();
        for (var k = 0; k < refs.length; k++) {
          batch.set(refs[k], payloads[k]);
        }
        await batch.commit();
        created += refs.length;
      }
    }
    return created;
  }

  /// Ver [FixedFlowSchedule.planPendingSync].
  Future<void> _syncPendingWithFixed(
    String uid,
    String fixedId,
    Map<String, dynamic> before,
  ) async {
    try {
      final after = (await _fixedRef(uid).doc(fixedId).get()).data();
      if (after == null) return;
      final snap = await _txRef(uid)
          .where('fixedIncomeId', isEqualTo: fixedId)
          .where('status', isEqualTo: 'pending')
          .get();
      if (snap.docs.isEmpty) return;
      final plan = FixedFlowSchedule.planPendingSync(
        before: before,
        after: after,
        pending: [for (final d in snap.docs) (id: d.id, data: d.data())],
        monthKeyField: 'fixedIncomeMonthKey',
        modeInstallments: modeInstallments,
      );
      if (plan.isEmpty) return;
      final ops = <void Function(WriteBatch)>[
        for (final e in plan.updates.entries)
          (b) => b.update(_txRef(uid).doc(e.key), {
                ...e.value,
                'updatedAt': FieldValue.serverTimestamp(),
              }),
        for (final id in plan.deletes) (b) => b.delete(_txRef(uid).doc(id)),
      ];
      for (var i = 0; i < ops.length; i += 450) {
        final batch = _db.batch();
        for (final op in ops.skip(i).take(450)) {
          op(batch);
        }
        await batch.commit();
      }
      FinanceMonthCache.clearUid(uid);
      FinanceTransactionsHub.notifyMutated(uid: uid);
    } catch (_) {
      // A fixa já foi salva; os pendentes ficam como estavam (comportamento antigo).
    }
  }
}
