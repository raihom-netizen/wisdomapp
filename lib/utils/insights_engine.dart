import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/finance_tip_bank_entry.dart';

/// Coleção raiz no Firestore: [InsightsEngine.kFinancialTipsCollection].
///
/// Documento exemplo:
/// ```json
/// {
///   "titulo": "...",
///   "descricao": "...",
///   "categoria": "alimentacao",
///   "icone": "fastfood",
///   "cor": "red",
///   "ativo": true,
///   "ordem": 10,
///   "condicao": {
///     "tipo": "categoria_maior",
///     "categoria": "Alimentação",
///     "valor_min": 500
///   }
/// }
/// ```
///
/// Campos alternativos aceitos: `iconKey` / `colorKey` (compatível com [FinanceTipBankEntry]).
const String kInsightsCacheSubcollection = 'insights_cache';

/// Dica atendida após avaliar [condicao] no Firestore.
class FinancialTipInsight {
  const FinancialTipInsight({
    required this.id,
    required this.titulo,
    required this.descricao,
    required this.icone,
    required this.cor,
  });

  final String id;
  final String titulo;
  final String descricao;
  final IconData icone;
  final Color cor;
}

/// Agrega totais e despesas por categoria a partir dos mesmos documentos usados no Financeiro.
({
  double totalEntrada,
  double totalSaida,
  Map<String, double> categoriasDespesa,
  String? topExpenseCategoryName,
  double? topExpenseCategorySharePct,
}) aggregateFinanceDocsForInsights(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
  var totalEntrada = 0.0;
  var totalSaida = 0.0;
  final categorias = <String, double>{};

  for (final doc in docs) {
    final d = doc.data();
    final type = (d['type'] ?? 'expense').toString();
    final amt = ((d['amount'] ?? 0) as num).toDouble().abs();
    if (type == 'income') {
      totalEntrada += amt;
    } else if (type == 'expense') {
      totalSaida += amt;
      final cat = (d['category'] ?? '').toString().trim();
      final key = cat.isEmpty ? 'Sem categoria' : cat;
      categorias[key] = (categorias[key] ?? 0) + amt;
    }
  }

  String? topName;
  double? topShare;
  if (categorias.isNotEmpty && totalSaida > 0.0001) {
    final sorted = categorias.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    topName = sorted.first.key;
    topShare = (sorted.first.value / totalSaida) * 100.0;
  }

  return (
    totalEntrada: totalEntrada,
    totalSaida: totalSaida,
    categoriasDespesa: categorias,
    topExpenseCategoryName: topName,
    topExpenseCategorySharePct: topShare,
  );
}

/// Motor: lê `financial_tips` e filtra por `condicao` usando os lançamentos do período.
class InsightsEngine {
  InsightsEngine(this._firestore);

  final FirebaseFirestore _firestore;

  static const String kFinancialTipsCollection = 'financial_tips';

  static QuerySnapshot<Map<String, dynamic>>? _cachedTipsSnapshot;
  static DateTime? _cachedTipsAt;
  static const Duration _tipsCacheTtl = Duration(hours: 6);
  static const Duration _tipsFetchTimeout = Duration(seconds: 18);

  /// Limpa cache após import/edição em massa no admin.
  static void clearTipsCache() {
    _cachedTipsSnapshot = null;
    _cachedTipsAt = null;
  }

  /// Lê `financial_tips` com cache em memória (~6h), timeout e 1 retry; em falha usa snapshot em cache (stale).
  Future<QuerySnapshot<Map<String, dynamic>>> _fetchFinancialTipsSnapshot() async {
    final now = DateTime.now();
    if (_cachedTipsSnapshot != null && _cachedTipsAt != null) {
      if (now.difference(_cachedTipsAt!) < _tipsCacheTtl) {
        return _cachedTipsSnapshot!;
      }
    }

    Future<QuerySnapshot<Map<String, dynamic>>> once() => _firestore
        .collection(kFinancialTipsCollection)
        .get()
        .timeout(_tipsFetchTimeout);

    try {
      final snap = await once();
      _cachedTipsSnapshot = snap;
      _cachedTipsAt = now;
      return snap;
    } catch (e1) {
      debugPrint('InsightsEngine: get financial_tips falhou (1ª tentativa): $e1');
      try {
        final snap = await once();
        _cachedTipsSnapshot = snap;
        _cachedTipsAt = now;
        return snap;
      } catch (e2) {
        if (_cachedTipsSnapshot != null) {
          debugPrint('InsightsEngine: usando cache stale de financial_tips após: $e2');
          return _cachedTipsSnapshot!;
        }
        rethrow;
      }
    }
  }

  List<FinancialTipInsight> _montarInsightsApartirDoSnapshot(
    QuerySnapshot<Map<String, dynamic>> snap,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    if (snap.docs.isEmpty) return [];

    final agg = aggregateFinanceDocsForInsights(docs);
    final rows = snap.docs
        .map((d) => (d, d.data()))
        .where((p) {
          final ativo = p.$2['ativo'];
          if (ativo is bool && ativo == false) return false;
          return true;
        })
        .toList()
      ..sort((a, b) {
        final oa = (a.$2['ordem'] is num) ? (a.$2['ordem'] as num).toInt() : 999;
        final ob = (b.$2['ordem'] is num) ? (b.$2['ordem'] as num).toInt() : 999;
        return oa.compareTo(ob);
      });

    final out = <FinancialTipInsight>[];
    for (final item in rows) {
      final doc = item.$1;
      final data = item.$2;
      final cond = data['condicao'];
      if (!_validarCondicao(
        cond,
        entrada: agg.totalEntrada,
        saida: agg.totalSaida,
        categorias: agg.categoriasDespesa,
        topCategoryName: agg.topExpenseCategoryName,
        topCategorySharePct: agg.topExpenseCategorySharePct,
      )) {
        continue;
      }

      final titulo = (data['titulo'] ?? '').toString().trim();
      final descricao = (data['descricao'] ?? '').toString().trim();
      if (titulo.isEmpty && descricao.isEmpty) continue;

      final iconKey = (data['icone'] ?? data['iconKey'] ?? 'lightbulb').toString();
      final colorKey = (data['cor'] ?? data['colorKey'] ?? 'primary').toString();

      out.add(
        FinancialTipInsight(
          id: doc.id,
          titulo: titulo.isEmpty ? 'Dica' : titulo,
          descricao: descricao.isEmpty ? titulo : descricao,
          icone: kFinanceTipIconByKey[iconKey] ?? Icons.lightbulb_outline_rounded,
          cor: kFinanceTipColorByKey[colorKey] ?? const Color(0xFF2D5BFF),
        ),
      );
    }
    return out;
  }

  /// Gera dicas a partir do Firestore + [docs] do período. Falha de rede ou permissão → lista vazia.
  Future<List<FinancialTipInsight>> gerarInsights(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    try {
      final snap = await _fetchFinancialTipsSnapshot();
      return _montarInsightsApartirDoSnapshot(snap, docs);
    } catch (e, st) {
      debugPrint('InsightsEngine.gerarInsights: $e\n$st');
      return [];
    }
  }

  bool _validarCondicao(
    dynamic cond, {
    required double entrada,
    required double saida,
    required Map<String, double> categorias,
    required String? topCategoryName,
    required double? topCategorySharePct,
  }) {
    if (cond == null) return false;
    if (cond is! Map) return false;
    final m = cond.map((k, v) => MapEntry(k.toString(), v));
    final tipo = (m['tipo'] ?? '').toString().trim();

    switch (tipo) {
      case 'sempre':
        return true;
      case 'gasto_maior_receita':
        return saida > entrada + 0.01;
      case 'categoria_maior':
        final cat = (m['categoria'] ?? '').toString();
        final min = (m['valor_min'] is num) ? (m['valor_min'] as num).toDouble() : 0.0;
        return _valorCategoria(categorias, cat) > min;
      case 'concentracao_categoria':
        /// Mesma categoria no topo E participação mínima nas despesas (%).
        final cat = (m['categoria'] ?? '').toString();
        final minPct = (m['pct_min'] is num) ? (m['pct_min'] as num).toDouble() : 0.0;
        if (topCategoryName == null || topCategorySharePct == null) return false;
        if (!_sameCategoryName(topCategoryName, cat)) return false;
        return topCategorySharePct >= minPct;
      default:
        return false;
    }
  }

  /// Grava cache opcional em `users/{uid}/insights_cache/{cacheDocId}` (ex.: período ou `latest`).
  Future<void> gravarCacheInsights({
    required String uid,
    required String cacheDocId,
    required DateTime periodFrom,
    required DateTime periodTo,
    required List<String> matchedFinancialTipIds,
  }) async {
    await _firestore
        .collection('users')
        .doc(uid)
        .collection(kInsightsCacheSubcollection)
        .doc(cacheDocId)
        .set(
          {
            'periodFrom': Timestamp.fromDate(periodFrom),
            'periodTo': Timestamp.fromDate(periodTo),
            'matchedFinancialTipIds': matchedFinancialTipIds,
            'updatedAt': FieldValue.serverTimestamp(),
            'sourceCollection': kFinancialTipsCollection,
          },
          SetOptions(merge: true),
        );
  }
}

double _valorCategoria(Map<String, double> categorias, String wantedRaw) {
  final wanted = wantedRaw.trim();
  if (wanted.isEmpty) return 0;
  for (final e in categorias.entries) {
    if (_sameCategoryName(e.key, wanted)) return e.value;
  }
  return 0;
}

bool _sameCategoryName(String stored, String wanted) {
  final a = stored.trim().toLowerCase();
  final b = wanted.trim().toLowerCase();
  return a == b;
}
