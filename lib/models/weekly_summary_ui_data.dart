import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/currency_formats.dart';
import '../services/finance_opening_balance_service.dart';
import 'scale_entry.dart';

DateTime _mondayOfWeekLocal(DateTime d) {
  final local = DateTime(d.year, d.month, d.day);
  return local.subtract(Duration(days: local.weekday - DateTime.monday));
}

String _weekKeyFromDateLocal(DateTime d) {
  final m = _mondayOfWeekLocal(d);
  return '${m.year}-${m.month.toString().padLeft(2, '0')}-${m.day.toString().padLeft(2, '0')}';
}

/// Dados para o cartão / diálogo «Resumo semanal» super premium (financeiro + escalas).
class WeeklySummaryUiData {
  const WeeklySummaryUiData({
    required this.weekKey,
    required this.weekRangeLabel,
    required this.despesasPendentesCount,
    required this.despesasPendentesValor,
    required this.despesasPagasValor,
    required this.receitasRecebidasValor,
    required this.receitasPendentesCount,
    required this.receitasPendentesValor,
    required this.saldoPeriodo,
    required this.saldoAcumulado,
    required this.escalasTiradasCount,
    required this.horasDiurnasTiradas,
    required this.horasNoturnasTiradas,
    required this.horasEstadoTiradas,
    required this.horasMunicipioTiradas,
    required this.horasParticularTiradas,
    required this.horasOutrasTiradas,
    required this.valorTotalPlantoesTirados,
    required this.metaLines,
  });

  final String weekKey;
  final String weekRangeLabel;
  final int despesasPendentesCount;
  final String despesasPendentesValor;
  final String despesasPagasValor;
  final String receitasRecebidasValor;
  final int receitasPendentesCount;
  final String receitasPendentesValor;
  final String saldoPeriodo;
  final String saldoAcumulado;
  final int escalasTiradasCount;
  final double horasDiurnasTiradas;
  final double horasNoturnasTiradas;
  final double horasEstadoTiradas;
  final double horasMunicipioTiradas;
  final double horasParticularTiradas;
  /// Vínculo não definido ou legado.
  final double horasOutrasTiradas;
  final String valorTotalPlantoesTirados;
  final List<String> metaLines;

  /// Texto curto para o cartão flutuante (banner).
  String get bannerTeaser => 'Semana $weekRangeLabel · toque em OK para ver o resumo completo.';

  static String _weekRangeLabelStatic(DateTime monday) {
    final sun = monday.add(const Duration(days: 6));
    if (monday.month == sun.month) {
      return '${monday.day}–${sun.day}/${monday.month.toString().padLeft(2, '0')}';
    }
    return '${monday.day}/${monday.month}–${sun.day}/${sun.month}';
  }

  /// Dados fictícios para pré-visualizar o layout (definições, semana sem lançamentos).
  /// Usa o intervalo da semana civil atual em [referenceDay] só para o rótulo de datas.
  static WeeklySummaryUiData previewSample([DateTime? referenceDay]) {
    final d = referenceDay ?? DateTime.now();
    final start = _mondayOfWeekLocal(d);
    final range = _weekRangeLabelStatic(start);
    final wk = _weekKeyFromDateLocal(d);
    return WeeklySummaryUiData(
      weekKey: wk,
      weekRangeLabel: range,
      despesasPendentesCount: 4,
      despesasPendentesValor: CurrencyFormats.formatBRL(1250.40),
      despesasPagasValor: CurrencyFormats.formatBRL(890.00),
      receitasRecebidasValor: CurrencyFormats.formatBRL(2100.00),
      receitasPendentesCount: 2,
      receitasPendentesValor: CurrencyFormats.formatBRL(450.75),
      saldoPeriodo: CurrencyFormats.formatBRL(459.35),
      saldoAcumulado: CurrencyFormats.formatBRL(12800.00),
      escalasTiradasCount: 5,
      horasDiurnasTiradas: 42.5,
      horasNoturnasTiradas: 18.0,
      horasEstadoTiradas: 32.0,
      horasMunicipioTiradas: 20.5,
      horasParticularTiradas: 8.0,
      horasOutrasTiradas: 0,
      valorTotalPlantoesTirados: CurrencyFormats.formatBRL(3176.64),
      metaLines: const ['Reserva emergência 68%', 'Meta férias 42%'],
    );
  }

  static Future<WeeklySummaryUiData> build(String uid) async {
    final now = DateTime.now();
    final start = _mondayOfWeekLocal(now);
    final end = DateTime(start.year, start.month, start.day + 6, 23, 59, 59);
    final wk = _weekKeyFromDateLocal(now);
    final range = _weekRangeLabelStatic(start);

    final txSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('transactions')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .orderBy('date', descending: false)
        .get();

    double receitas = 0, despesasPagas = 0, despesasPendentesValor = 0;
    int pendentesCount = 0;
    double receitasPendentesValor = 0;
    int receitasPendentesCount = 0;

    for (final doc in txSnap.docs) {
      final d = doc.data();
      final ts = d['date'];
      if (ts is! Timestamp) continue;
      final date = ts.toDate();
      final amount = (d['amount'] ?? 0).toDouble();
      final type = (d['type'] ?? 'expense').toString();
      final isPending = (d['status'] ?? 'paid').toString() != 'paid';
      final paidAtTs = d['paidAt'];
      final paidAt = paidAtTs is Timestamp ? paidAtTs.toDate() : null;
      final effectiveDate = paidAt ?? date;

      if (type == 'income') {
        if (isPending) {
          if (!date.isBefore(start) && !date.isAfter(end)) {
            receitasPendentesValor += amount.abs();
            receitasPendentesCount++;
          }
        } else {
          if (!effectiveDate.isBefore(start) && !effectiveDate.isAfter(end)) {
            receitas += amount;
          }
        }
      } else {
        final absAmount = amount.abs();
        if (isPending) {
          if (!date.isBefore(start) && !date.isAfter(end)) {
            despesasPendentesValor += absAmount;
            pendentesCount++;
          }
        } else {
          if (!effectiveDate.isBefore(start) && !effectiveDate.isAfter(end)) {
            despesasPagas += absAmount;
          }
        }
      }
    }

    final saldoAnterior = await FinanceOpeningBalanceService.loadTotalFast(
      uid: uid,
      periodStart: start,
    );
    final saldoPeriodo = receitas - despesasPagas;
    final saldoAcumulado = saldoAnterior + saldoPeriodo;

    final scaleSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('scales')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .get();

    final refDay = DateTime(now.year, now.month, now.day);
    var escalasTiradas = 0;
    var hd = 0.0, hn = 0.0;
    var hState = 0.0, hMun = 0.0, hPriv = 0.0, hOut = 0.0;
    var valorTirados = 0.0;

    for (final doc in scaleSnap.docs) {
      final e = ScaleEntry.fromDoc(doc);
      if (e.isCompromisso) continue;
      if (!e.effectiveJaTiradoParaExibicao(refDay)) continue;
      escalasTiradas++;
      hd += e.hoursDay;
      hn += e.hoursNight;
      final hLinha = e.hoursDay + e.hoursNight;
      switch (e.employerType) {
        case 'state':
          hState += hLinha;
          break;
        case 'municipality':
          hMun += hLinha;
          break;
        case 'private':
          hPriv += hLinha;
          break;
        default:
          hOut += hLinha;
      }
      valorTirados += e.totalValue;
    }

    final goalsSnap =
        await FirebaseFirestore.instance.collection('users').doc(uid).collection('goals').where('status', isEqualTo: 'active').get();

    final metaParts = <String>[];
    for (final g in goalsSnap.docs) {
      final title = (g.data()['title'] ?? '').toString().toLowerCase();
      if (title.contains('banco de horas')) continue;
      final target = (g.data()['targetAmount'] ?? 0).toDouble();
      if (target <= 0) continue;
      final cSnap = await g.reference.collection('contributions').get();
      var current = 0.0;
      for (final c in cSnap.docs) {
        current += (c.data()['amount'] ?? 0).toDouble();
      }
      final pct = ((current / target) * 100).clamp(0, 100).round();
      final shortTitle = (g.data()['title'] ?? 'Meta').toString();
      final label = shortTitle.length > 22 ? '${shortTitle.substring(0, 20)}…' : shortTitle;
      metaParts.add('$label $pct%');
      if (metaParts.length >= 3) break;
    }

    return WeeklySummaryUiData(
      weekKey: wk,
      weekRangeLabel: range,
      despesasPendentesCount: pendentesCount,
      despesasPendentesValor: CurrencyFormats.formatBRL(despesasPendentesValor),
      despesasPagasValor: CurrencyFormats.formatBRL(despesasPagas),
      receitasRecebidasValor: CurrencyFormats.formatBRL(receitas),
      receitasPendentesCount: receitasPendentesCount,
      receitasPendentesValor: CurrencyFormats.formatBRL(receitasPendentesValor),
      saldoPeriodo: CurrencyFormats.formatBRL(saldoPeriodo),
      saldoAcumulado: CurrencyFormats.formatBRL(saldoAcumulado),
      escalasTiradasCount: escalasTiradas,
      horasDiurnasTiradas: hd,
      horasNoturnasTiradas: hn,
      horasEstadoTiradas: hState,
      horasMunicipioTiradas: hMun,
      horasParticularTiradas: hPriv,
      horasOutrasTiradas: hOut,
      valorTotalPlantoesTirados: CurrencyFormats.formatBRL(valorTirados),
      metaLines: metaParts,
    );
  }
}
