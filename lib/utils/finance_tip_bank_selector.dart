import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/finance_tip_bank_static.dart';
import '../models/finance_tip_bank_entry.dart';
import 'finance_smart_tips_composer.dart';

/// Seleciona entradas do [kFinanceTipBankStatic] conforme padrões dos lançamentos e totais do período.
///
/// Combina com dicas **dinâmicas** (motor + composer); não duplica lógica de métricas — usa [FinanceSmartTipsStats].
List<FinanceTipBankEntry> selectFinanceTipBankEntries({
  required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  required FinanceSmartTipsStats stats,
  int maxItems = 10,
}) {
  final out = <FinanceTipBankEntry>[];
  final seen = <String>{};

  void push(FinanceTipBankEntry? e) {
    if (e == null || seen.contains(e.id) || out.length >= maxItems) return;
    seen.add(e.id);
    out.add(e);
  }

  void pushFromSlug(String slug, int maxFromSlug) {
    var n = 0;
    for (final e in kFinanceTipBankStatic) {
      if (out.length >= maxItems) return;
      if (e.categoriaSlug != slug) continue;
      if (seen.contains(e.id)) continue;
      seen.add(e.id);
      out.add(e);
      n++;
      if (n >= maxFromSlug) return;
    }
  }

  var foodTotal = 0.0;
  var transportTotal = 0.0;
  var smallExpenseCount = 0;
  for (final doc in docs) {
    final d = doc.data();
    if ((d['type'] ?? 'expense').toString() != 'expense') continue;
    final cat = (d['category'] ?? '').toString();
    final amt = ((d['amount'] ?? 0) as num).toDouble().abs();
    if (_isFoodCategory(cat)) foodTotal += amt;
    if (_isTransportCategory(cat)) transportTotal += amt;
    if (amt > 0 && amt <= 80) smallExpenseCount++;
  }

  final deficit = stats.totalExpense > stats.totalIncome + 0.01;
  final strongFood = foodTotal >= 400;
  final strongTransport = transportTotal >= 200;
  final manySmall = smallExpenseCount >= 14 && stats.totalExpense > 100;
  final topHeavy = stats.topExpenseCategorySharePct != null && stats.topExpenseCategorySharePct! >= 32;

  if (deficit) {
    pushFromSlug('comportamento', 2);
    pushFromSlug('cartao', 2);
  }

  if (strongFood) {
    pushFromSlug('alimentacao', 2);
  }

  if (strongTransport) {
    pushFromSlug('transporte', 1);
  }

  if (manySmall) {
    pushFromSlug('gastos', 1);
  }

  if (topHeavy) {
    pushFromSlug('controle', 1);
  }

  if (stats.balancePeriod >= 0 && stats.totalIncome > 100) {
    pushFromSlug('investimento', 1);
  }

  // Rodízio diário: sempre trazer 1 educação diferente sem saturar
  final edu = kFinanceTipBankStatic.where((e) => e.categoriaSlug == 'educacao').toList();
  if (edu.isNotEmpty) {
    final idx = DateTime.now().toUtc().day % edu.length;
    push(edu[idx]);
  }

  // Baseline: controle + cartão (um de cada) se ainda houver espaço
  if (out.length < maxItems) pushFromSlug('controle', 2);
  if (out.length < maxItems) pushFromSlug('cartao', 1);

  // Completar com educação / investimento
  if (out.length < maxItems) pushFromSlug('educacao', 2);
  if (out.length < maxItems) pushFromSlug('investimento', 1);

  return out.take(maxItems).toList();
}

bool _isFoodCategory(String raw) {
  final l = raw.toLowerCase().trim();
  if (l.isEmpty) return false;
  return l.contains('aliment') ||
      l.contains('mercado') ||
      l.contains('super') ||
      l.contains('restaur') ||
      l.contains('lanch') ||
      l.contains('ifood') ||
      l.contains('delivery');
}

bool _isTransportCategory(String raw) {
  final l = raw.toLowerCase().trim();
  if (l.isEmpty) return false;
  return l.contains('transport') ||
      l.contains('uber') ||
      l.contains('combust') ||
      l.contains('gasolina') ||
      l.contains('estacion') ||
      l.contains('pedágio') ||
      l.contains('pedagio');
}
