import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/app_business_rules.dart';
import '../utils/finance_line_opening.dart';
import '../utils/firestore_user_doc_id.dart';

/// Despesas fixas: todo mês o sistema cria um lançamento automaticamente no período definido pelo usuário.
class FixedExpenseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Limite do Firestore por WriteBatch (não alterar sem conferir documentação).
  static const int batchLimit = 500;
  /// Tetos para [monthsAhead]: geração de parcelas até este número de meses à frente (evita explosão de lançamentos).
  static const int maxMonthsAhead = 24;

  CollectionReference<Map<String, dynamic>> _fixedRef(String uid) => _db
      .collection('users')
      .doc(firestoreUserDocIdForAppShell(uid))
      .collection('fixed_expenses');

  CollectionReference<Map<String, dynamic>> _txRef(String uid) => _db
      .collection('users')
      .doc(firestoreUserDocIdForAppShell(uid))
      .collection('transactions');

  /// Lista todas as despesas fixas ativas do usuário.
  Future<List<Map<String, dynamic>>> list(String uid) async {
    final snap = await _fixedRef(uid).orderBy('createdAt', descending: true).get();
    return snap.docs.map((d) {
      final m = Map<String, dynamic>.from(d.data());
      m['id'] = d.id;
      return m;
    }).toList();
  }

  /// Modo da despesa fixa: por período (datas) ou por parcelas (financiamento/empréstimo).
  static const String modePeriod = 'period';
  static const String modeInstallments = 'installments';

  /// Cria uma despesa fixa.
  /// [dayOfMonth] 1–31 (dia do mês em que o lançamento será criado).
  /// [endDate] null = sem data fim (por período) ou calculado (por parcelas).
  /// [mode] 'period' = por período (start/end); 'installments' = por parcelas (totalParcelas, parcelaInicial).
  /// [parcelaInicial] quando por parcelas: a partir de qual parcela está (ex.: 4 em 10 = começou a controlar na 4ª).
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

  /// Atualiza uma despesa fixa.
  /// Se [dayOfMonth] for alterado, as parcelas futuras (pendentes) são atualizadas para o novo dia.
  /// Retorna o número de parcelas futuras que foram ajustadas (0 se não alterou o dia).
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

  /// Atualiza a data (dia do mês) das parcelas futuras pendentes desta despesa fixa.
  /// Ex.: usuário editou de dia 16 para 08 — as contas pendentes dos próximos meses passam a vencer no dia 08.
  /// Usa WriteBatch (até [batchLimit] por commit) para menos round-trips.
  Future<int> updateFuturePendingEntries(String uid, String fixedExpenseId, int newDayOfMonth) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final snap = await _txRef(uid)
        .where('fixedExpenseId', isEqualTo: fixedExpenseId)
        .where('status', isEqualTo: 'pending')
        .get();
    final toUpdate = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final doc in snap.docs) {
      final d = doc.data();
      final dateTs = d['date'];
      if (dateTs is! Timestamp) continue;
      final date = (dateTs as Timestamp).toDate();
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
        final date = (dateTs as Timestamp).toDate();
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

  /// Remove uma despesa fixa (não remove lançamentos já criados).
  Future<void> delete(String uid, String id) async {
    await _fixedRef(uid).doc(id).delete();
  }

  /// Remove todas as parcelas (lançamentos) criadas por esta despesa fixa no Financeiro.
  /// Retorna a quantidade de lançamentos excluídos. Usa WriteBatch ([batchLimit] por vez) — sem await por doc.
  Future<int> deleteAllParcelas(String uid, String fixedExpenseId) async {
    try {
      final snap = await _txRef(uid)
          .where('fixedExpenseId', isEqualTo: fixedExpenseId)
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
      throw Exception('Erro ao remover parcelas da despesa fixa: $e');
    }
  }

  /// Garante que, para cada despesa fixa ativa, exista um lançamento em cada mês do período (startDate..endDate).
  /// Respeita a data final (endDate) cadastrada na despesa — gera parcelas até o último mês do período.
  /// [monthsAhead] não limita mais a geração; é usado apenas em preferências de exibição (painel pendentes).
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

    // Queries em paralelo: uma por despesa fixa (monthKeys já existentes)
    final existingSnaps = await Future.wait([
      for (final fe in activeItems)
        _txRef(uid).where('fixedExpenseId', isEqualTo: fe['id'].toString()).get(),
    ]);

    final List<Map<String, dynamic>> toCreate = [];
    for (var i = 0; i < activeItems.length; i++) {
      final fe = activeItems[i];
      final existingSnap = existingSnaps[i];
      final start = (fe['startDate'] as Timestamp).toDate();
      final end = (fe['endDate'] as Timestamp).toDate();
      final dayOfMonth = (fe['dayOfMonth'] as num?)?.toInt() ?? 1;
      final category = (fe['category'] ?? 'Despesa').toString();
      final description = (fe['description'] ?? 'Despesa fixa').toString();
      final feId = fe['id'].toString();
      final amount = (fe['amount'] as num?)?.toDouble() ?? 0;

      // Inclui monthKey explícito OU deriva do campo date (pagas/legado sem fixedExpenseMonthKey),
      // senão o sistema recriava parcela "Pendente" do mesmo mês ao rodar ensure de novo.
      final existingMonthKeys = <String>{};
      for (final d in existingSnap.docs) {
        final data = d.data();
        final mk = data['fixedExpenseMonthKey'] as String?;
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
      // Respeitar a data final da despesa fixa: gerar parcelas até o mês de end (inclusive).
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
        // Índice da parcela: primeiro mês = parcelaInicial, segundo = parcelaInicial+1, etc.
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
          'type': 'expense',
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
          'fixedExpenseId': feId,
          'fixedExpenseMonthKey': monthKey,
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
      throw Exception('Erro ao gerar parcelas de despesas fixas: $e');
    }
  }
}
