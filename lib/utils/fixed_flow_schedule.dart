import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

/// Regras puras das despesas/receitas fixas (datas, nº da parcela, IDs dos
/// meses gerados e sincronização dos pendentes ao editar a fixa).
///
/// Correções autorizadas pelo dono (02/10/2026):
/// - fixa por parcelas que começa dia 29–31: a data final era montada com
///   `DateTime(ano, mês + n − 1, dia)`, que «transborda» para o mês seguinte
///   (31/01 + 1 mês = 03/03) e gerava um mês a mais; e o
///   `.clamp(1, totalParcelas)` repetia a última parcela nesse mês extra
///   (2/2 duas vezes). Agora a data final fica no último dia do mês final e
///   parcela fora do intervalo não é gerada;
/// - IDs determinísticos por fixa + mês: dois aparelhos gerando ao mesmo
///   tempo gravam no MESMO documento (sem duplicar o mês).
class FixedFlowSchedule {
  FixedFlowSchedule._();

  /// Data final da fixa por parcelas: mês da última parcela, com o dia de
  /// início limitado ao último dia daquele mês.
  ///
  /// Ex.: início 31/01/2026, 2 parcelas → 28/02/2026 (antes: 03/03/2026).
  static DateTime installmentsEndDate({
    required DateTime start,
    required int totalParcelas,
    int parcelaInicial = 1,
  }) {
    final total = math.max(1, totalParcelas);
    final ini = parcelaInicial.clamp(1, total);
    final meses = total - ini + 1;
    final lastDay = DateTime(start.year, start.month + meses, 0).day;
    return DateTime(
      start.year,
      start.month + meses - 1,
      math.min(start.day, lastDay),
    );
  }

  /// Nº da parcela do mês [month] (1º mês = [parcelaInicial]); `null` quando o
  /// mês cai fora das parcelas (antes do início ou depois da última).
  static int? installmentIndexForMonth({
    required DateTime start,
    required DateTime month,
    required int parcelaInicial,
    required int totalParcelas,
  }) {
    final monthsFromStart =
        (month.year - start.year) * 12 + (month.month - start.month);
    final idx = parcelaInicial + monthsFromStart;
    if (idx < 1 || idx > totalParcelas) return null;
    return idx;
  }

  static String monthKey(DateTime month) =>
      '${month.year}-${month.month.toString().padLeft(2, '0')}';

  /// ID do lançamento gerado: `fx_{idDaFixa}_{yyyyMM}` (despesa) ou
  /// `fi_{idDaFixa}_{yyyyMM}` (receita).
  static String generatedTxId({
    required String prefix,
    required String fixedId,
    required DateTime month,
  }) =>
      '${prefix}_${fixedId}_${month.year}${month.month.toString().padLeft(2, '0')}';

  static String descriptionFor({
    required String description,
    required bool byInstallments,
    int? parcelIndex,
    int? totalParcelas,
  }) {
    if (byInstallments &&
        parcelIndex != null &&
        totalParcelas != null &&
        totalParcelas > 1) {
      return '$description · $parcelIndex/$totalParcelas';
    }
    return description;
  }

  /// Mês (dia 1) de um lançamento gerado: chave explícita do mês ou a data.
  static DateTime? monthOfGenerated(
    Map<String, dynamic> tx, {
    required String monthKeyField,
  }) {
    final mk = (tx[monthKeyField] ?? '').toString().trim();
    final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(mk);
    if (m != null) {
      return DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), 1);
    }
    final ts = tx['date'];
    DateTime? d;
    if (ts is Timestamp) d = ts.toDate();
    if (ts is DateTime) d = ts;
    return d == null ? null : DateTime(d.year, d.month, 1);
  }

  /// O que fazer com os lançamentos **pendentes** já gerados quando a fixa é
  /// editada. Pagos nunca entram aqui (o chamador só passa pendentes).
  ///
  /// - mês depois da nova data final, ou parcela acima do novo total → apagar;
  /// - valor / categoria / descrição só são regravados se MUDARAM na fixa
  ///   ([before] × [after]) — o ajuste manual de um mês não é apagado à toa;
  /// - nº da parcela e o sufixo «n/N» acompanham a nova configuração.
  static FixedFlowPendingPlan planPendingSync({
    required Map<String, dynamic> before,
    required Map<String, dynamic> after,
    required List<({String id, Map<String, dynamic> data})> pending,
    required String monthKeyField,
    required String modeInstallments,
  }) {
    final updates = <String, Map<String, dynamic>>{};
    final deletes = <String>[];

    DateTime? asDate(Object? v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return null;
    }

    final start = asDate(after['startDate']);
    final end = asDate(after['endDate']);
    if (start == null) {
      return FixedFlowPendingPlan(updates: updates, deletes: deletes);
    }
    final endMonth = end == null ? null : DateTime(end.year, end.month, 1);
    final byInst = (after['mode'] ?? '') == modeInstallments;
    final total = (after['totalParcelas'] as num?)?.toInt();
    final ini = (after['parcelaInicial'] as num?)?.toInt() ?? 1;

    final amountChanged = before['amount'] != after['amount'];
    final categoryChanged = before['category'] != after['category'];
    final descChanged = before['description'] != after['description'];
    final instChanged = before['mode'] != after['mode'] ||
        before['totalParcelas'] != after['totalParcelas'] ||
        before['parcelaInicial'] != after['parcelaInicial'] ||
        asDate(before['startDate']) != start;

    for (final p in pending) {
      final month = monthOfGenerated(p.data, monthKeyField: monthKeyField);
      if (month == null) continue;
      if (endMonth != null && month.isAfter(endMonth)) {
        deletes.add(p.id);
        continue;
      }
      int? idx;
      if (byInst && total != null) {
        idx = installmentIndexForMonth(
          start: start,
          month: month,
          parcelaInicial: ini,
          totalParcelas: total,
        );
        // Depois da última parcela: sobrou. Antes do início: não mexe.
        if (idx == null && !month.isBefore(DateTime(start.year, start.month, 1))) {
          deletes.add(p.id);
          continue;
        }
      }

      final patch = <String, dynamic>{};
      if (amountChanged && after['amount'] is num) {
        patch['amount'] = (after['amount'] as num).toDouble();
      }
      if (categoryChanged && after['category'] != null) {
        patch['category'] = after['category'];
      }
      if ((descChanged || instChanged) && after['description'] != null) {
        final desc = descriptionFor(
          description: after['description'].toString(),
          byInstallments: byInst,
          parcelIndex: idx,
          totalParcelas: total,
        );
        if (desc != p.data['description']) patch['description'] = desc;
      }
      if (instChanged) {
        final count = byInst && total != null ? total : 1;
        final index = idx ?? 1;
        if (p.data['installmentCount'] != count) {
          patch['installmentCount'] = count;
        }
        if (p.data['installmentIndex'] != index) {
          patch['installmentIndex'] = index;
        }
      }
      if (patch.isNotEmpty) updates[p.id] = patch;
    }
    return FixedFlowPendingPlan(updates: updates, deletes: deletes);
  }
}

class FixedFlowPendingPlan {
  const FixedFlowPendingPlan({required this.updates, required this.deletes});

  /// id do lançamento → campos a regravar.
  final Map<String, Map<String, dynamic>> updates;
  final List<String> deletes;

  bool get isEmpty => updates.isEmpty && deletes.isEmpty;
}
