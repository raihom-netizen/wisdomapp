import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/app_business_rules.dart';
import '../utils/finance_line_opening.dart';
import '../utils/firestore_user_doc_id.dart';

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
    final snap = await _fixedRef(uid).orderBy('createdAt', descending: true).get();
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
  }) async {
    final day = dayOfMonth.clamp(1, 31);
    DateTime end;
    int? effTotalParcelas;
    if (mode == modeInstallments && totalParcelas != null && totalParcelas >= 1) {
      effTotalParcelas = totalParcelas.clamp(1, AppBusinessRules.maxFixedFlowInstallments);
      final start = DateTime(startDate.year, startDate.month, startDate.day);
      final ini = (parcelaInicial ?? 1).clamp(1, effTotalParcelas);
      final meses = effTotalParcelas - ini + 1;
      end = DateTime(start.year, start.month + meses - 1, start.day);
    } else {
      effTotalParcelas = null;
      end = endDate ?? DateTime(startDate.year + 10, startDate.month, startDate.day);
    }
    final data = <String, dynamic>{
      'description': description,
      'category': category,
      'amount': amount,
      'dayOfMonth': day,
      'startDate': Timestamp.fromDate(DateTime(startDate.year, startDate.month, startDate.day)),
      'endDate': Timestamp.fromDate(DateTime(end.year, end.month, end.day)),
      'active': true,
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
  }) async {
    final data = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (description != null) data['description'] = description;
    if (category != null) data['category'] = category;
    if (amount != null) data['amount'] = amount;
    if (dayOfMonth != null) data['dayOfMonth'] = dayOfMonth.clamp(1, 31);
    if (startDate != null) data['startDate'] = Timestamp.fromDate(DateTime(startDate.year, startDate.month, startDate.day));
    if (endDate != null) data['endDate'] = Timestamp.fromDate(DateTime(endDate.year, endDate.month, endDate.day));
    if (active != null) data['active'] = active;
    if (mode != null) {
      data['mode'] = mode;
      if (mode == modePeriod) {
        data['totalParcelas'] = FieldValue.delete();
        data['parcelaInicial'] = FieldValue.delete();
      }
    }
    if (totalParcelas != null) {
      data['totalParcelas'] = totalParcelas.clamp(1, AppBusinessRules.maxFixedFlowInstallments);
    }
    if (parcelaInicial != null && totalParcelas != null) {
      final cap = totalParcelas.clamp(1, AppBusinessRules.maxFixedFlowInstallments);
      data['parcelaInicial'] = parcelaInicial.clamp(1, cap);
    }
    await _fixedRef(uid).doc(id).update(data);
    if (dayOfMonth != null) return updateFuturePendingEntries(uid, id, dayOfMonth.clamp(1, 31));
    return 0;
  }

  Future<int> updateFuturePendingEntries(String uid, String fixedIncomeId, int newDayOfMonth) async {
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

  Future<void> delete(String uid, String id) async {
    await _fixedRef(uid).doc(id).delete();
  }

  Future<int> deleteAllParcelas(String uid, String fixedIncomeId) async {
    try {
      final snap = await _txRef(uid).where('fixedIncomeId', isEqualTo: fixedIncomeId).get();
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

  Future<int> ensureMonthlyEntries(String uid, {int monthsAhead = 4}) async {
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
      for (final fe in activeItems) _txRef(uid).where('fixedIncomeId', isEqualTo: fe['id'].toString()).get(),
    ]);

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

      final existingMonthKeys = <String>{};
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
          existingMonthKeys.add('${dt.year}-${dt.month.toString().padLeft(2, '0')}');
        }
      }

      final isByInstallments = (fe['mode'] ?? modePeriod) == modeInstallments;
      final totalParcelas = (fe['totalParcelas'] as num?)?.toInt();
      final parcelaInicial = (fe['parcelaInicial'] as num?)?.toInt() ?? 1;
      final installmentCount = isByInstallments && totalParcelas != null ? totalParcelas : 1;
      final startMonth = DateTime(start.year, start.month, 1);

      DateTime month = DateTime(start.year, start.month, 1);
      final limitEnd = DateTime(end.year, end.month, 1);

      while (!month.isAfter(limitEnd)) {
        if (month.isBefore(startMonth)) {
          month = DateTime(month.year, month.month + 1, 1);
          continue;
        }
        final monthKey = '${month.year}-${month.month.toString().padLeft(2, '0')}';
        if (existingMonthKeys.contains(monthKey)) {
          month = DateTime(month.year, month.month + 1, 1);
          continue;
        }
        int parcelIndex = 1;
        if (isByInstallments && totalParcelas != null) {
          final monthsFromStart = (month.year - start.year) * 12 + (month.month - start.month);
          parcelIndex = (parcelaInicial + monthsFromStart).clamp(1, totalParcelas);
          if (parcelIndex > totalParcelas) {
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
        final descOut = isByInstallments && totalParcelas != null && totalParcelas > 1
            ? '$description · $parcelIndex/$totalParcelas'
            : description;
        final dateTs = Timestamp.fromDate(date);
        toCreate.add({
          'type': 'income',
          'amount': amount,
          'category': category,
          'description': descOut,
          'status': 'pending',
          'date': dateTs,
          'effectiveDate':
              FinanceLineOpening.effectiveTimestampForWrite(date: date),
          'recurrence': 'fixed',
          'installmentCount': installmentCount,
          'installmentIndex': parcelIndex,
          'fixedIncomeId': feId,
          'fixedIncomeMonthKey': monthKey,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        month = DateTime(month.year, month.month + 1, 1);
      }
    }

    int created = 0;
    try {
      for (var j = 0; j < toCreate.length; j += batchLimit) {
        final batch = _db.batch();
        for (final data in toCreate.skip(j).take(batchLimit)) {
          batch.set(_txRef(uid).doc(), data);
          created++;
        }
        await batch.commit();
      }
      return created;
    } catch (e) {
      throw Exception('Erro ao gerar parcelas de receitas fixas: $e');
    }
  }
}
