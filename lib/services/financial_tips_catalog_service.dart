import 'dart:math' show min;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../data/biblical_finance_tips.dart';
import '../data/finance_tip_bank_static.dart';
import '../models/finance_tip_bank_entry.dart';
import '../utils/insights_engine.dart';
import 'financial_tips_home_sync_service.dart';

/// Dica para exibição no Início / módulo Dicas (catálogo completo).
class FinancialTipDisplayItem {
  const FinancialTipDisplayItem({
    required this.id,
    required this.titulo,
    required this.descricao,
    required this.categoriaSlug,
    required this.iconKey,
    required this.colorKey,
    required this.ordem,
    this.referenciaBiblica = '',
    this.textoVersiculo = '',
  });

  final String id;
  final String titulo;
  final String descricao;
  final String categoriaSlug;
  final String iconKey;
  final String colorKey;
  final int ordem;
  final String referenciaBiblica;
  /// Citação literal ou paráfrase do versículo (exibida em destaque no card).
  final String textoVersiculo;

  bool get isBiblical =>
      categoriaSlug == 'biblia' || referenciaBiblica.trim().isNotEmpty;

  factory FinancialTipDisplayItem.fromBankEntry(FinanceTipBankEntry e, {int ordem = 0}) {
    return FinancialTipDisplayItem(
      id: e.id,
      titulo: e.titulo,
      descricao: e.descricao,
      categoriaSlug: e.categoriaSlug,
      iconKey: e.iconKey,
      colorKey: e.colorKey,
      ordem: ordem,
    );
  }

  factory FinancialTipDisplayItem.fromFirestore(String id, Map<String, dynamic> data) {
    final ordemRaw = data['ordem'];
    final ordem = ordemRaw is num ? ordemRaw.toInt() : int.tryParse('$ordemRaw') ?? 999;
    return FinancialTipDisplayItem(
      id: id,
      titulo: (data['titulo'] ?? '').toString().trim(),
      descricao: (data['descricao'] ?? '').toString().trim(),
      categoriaSlug: (data['categoria'] ?? data['categoriaSlug'] ?? '').toString().trim(),
      iconKey: (data['icone'] ?? data['iconKey'] ?? 'lightbulb').toString(),
      colorKey: (data['cor'] ?? data['colorKey'] ?? 'primary').toString(),
      ordem: ordem,
      referenciaBiblica: (data['referenciaBiblica'] ?? data['versiculo'] ?? '').toString().trim(),
      textoVersiculo: (data['textoVersiculo'] ?? data['versiculoTexto'] ?? data['citacao'] ?? '')
          .toString()
          .trim(),
    );
  }
}

/// Catálogo resolvido para o Início (após sync do admin ou fallback bíblico).
class HomeTipsCatalogSnapshot {
  const HomeTipsCatalogSnapshot({
    required this.tips,
    this.favoriteIds = const [],
    this.syncedAt,
    this.fromSyncedConfig = false,
  });

  final List<FinancialTipDisplayItem> tips;
  final List<String> favoriteIds;
  final DateTime? syncedAt;
  final bool fromSyncedConfig;
}

/// Bloco para o Início: dica do dia + até [maxOnHome] no total.
class HomeTipsPreview {
  const HomeTipsPreview({
    required this.tipOfDay,
    required this.previewExtras,
    required this.allTips,
  });

  final FinancialTipDisplayItem tipOfDay;
  final List<FinancialTipDisplayItem> previewExtras;
  final List<FinancialTipDisplayItem> allTips;

  List<FinancialTipDisplayItem> get homeVisibleTips => [
        tipOfDay,
        ...previewExtras,
      ];
}

/// Catálogo de dicas bíblicas para o painel Início.
class FinancialTipsCatalogService {
  FinancialTipsCatalogService._();

  static const int kMaxTipsOnHome = 3;

  static int tipOfDayIndex(int length) {
    if (length <= 0) return 0;
    final now = DateTime.now();
    final start = DateTime(now.year, 1, 1);
    final day = now.difference(start).inDays;
    return day % length;
  }

  static List<FinancialTipDisplayItem> biblicalCatalog() =>
      List<FinancialTipDisplayItem>.from(kBiblicalFinanceTips);

  static List<FinancialTipDisplayItem> staticFallback() {
    var i = 0;
    return kFinanceTipBankStatic
        .map((e) => FinancialTipDisplayItem.fromBankEntry(e, ordem: (i += 10)))
        .toList();
  }

  /// Catálogo do Início: base bíblica local + overrides do Firestore (editáveis no admin).
  static List<FinancialTipDisplayItem> resolveHomeCatalog(
    List<FinancialTipDisplayItem> firestoreTips,
  ) {
    final byId = <String, FinancialTipDisplayItem>{
      for (final b in kBiblicalFinanceTips) b.id: b,
    };
    for (final f in firestoreTips) {
      if (f.isBiblical) byId[f.id] = f;
    }
    final out = byId.values.toList()
      ..sort((a, b) => a.ordem.compareTo(b.ordem));
    return out.isNotEmpty ? out : biblicalCatalog();
  }

  static HomeTipsPreview partitionForHome(
    List<FinancialTipDisplayItem> all, {
    List<String> favoriteIds = const [],
  }) {
    if (all.isEmpty) {
      final fallback = biblicalCatalog();
      return partitionForHome(fallback, favoriteIds: favoriteIds);
    }
    final pool = favoriteIds.isNotEmpty
        ? all.where((t) => favoriteIds.contains(t.id)).toList()
        : all;
    final effective = pool.isNotEmpty ? pool : all;
    final idx = tipOfDayIndex(effective.length);
    final tipOfDay = effective[idx];
    final rest = <FinancialTipDisplayItem>[
      ...effective.sublist(idx + 1),
      ...effective.sublist(0, idx),
    ];
    final extras = rest.take(kMaxTipsOnHome - 1).toList();
    return HomeTipsPreview(
      tipOfDay: tipOfDay,
      previewExtras: extras,
      allTips: all,
    );
  }

  static List<FinancialTipDisplayItem> parseSnapshot(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) {
    final out = <FinancialTipDisplayItem>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['ativo'] == false) continue;
      final item = FinancialTipDisplayItem.fromFirestore(doc.id, data);
      if (item.titulo.isEmpty && item.descricao.isEmpty) continue;
      out.add(item);
    }
    out.sort((a, b) => a.ordem.compareTo(b.ordem));
    return out;
  }

  static Future<List<FinancialTipDisplayItem>> _fetchTipsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final col = FirebaseFirestore.instance
        .collection(InsightsEngine.kFinancialTipsCollection);
    final byId = <String, FinancialTipDisplayItem>{};
    for (var i = 0; i < ids.length; i += 30) {
      final chunk = ids.sublist(i, min(i + 30, ids.length));
      final snap = await col
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['ativo'] == false) continue;
        final item = FinancialTipDisplayItem.fromFirestore(doc.id, data);
        if (item.titulo.isEmpty && item.descricao.isEmpty) continue;
        byId[doc.id] = item;
      }
    }
    return [
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
    ];
  }

  static Future<HomeTipsCatalogSnapshot> _buildFromHomeConfig(
    FinancialTipsHomeConfig? config,
  ) async {
    if (config == null || !config.hasSelection) {
      return HomeTipsCatalogSnapshot(tips: biblicalCatalog());
    }
    final tips = await _fetchTipsByIds(config.homeTipIds);
    if (tips.isEmpty) {
      return HomeTipsCatalogSnapshot(tips: biblicalCatalog());
    }
    return HomeTipsCatalogSnapshot(
      tips: tips,
      favoriteIds: config.favoriteTipIds,
      syncedAt: config.syncedAt,
      fromSyncedConfig: true,
    );
  }

  /// Início dos usuários: escuta `app_config/financial_tips_home` (publicado pelo admin).
  static Stream<HomeTipsCatalogSnapshot> watchHomeTips() async* {
    yield HomeTipsCatalogSnapshot(tips: biblicalCatalog());
    try {
      yield* FirebaseFirestore.instance
          .doc(FinancialTipsHomeSyncService.docPath)
          .snapshots()
          .asyncMap((homeSnap) async {
        final config = FinancialTipsHomeSyncService.parse(homeSnap.data());
        return _buildFromHomeConfig(config);
      });
    } catch (e, st) {
      debugPrint('FinancialTipsCatalogService.watchHomeTips: $e\n$st');
      yield HomeTipsCatalogSnapshot(tips: biblicalCatalog());
    }
  }

  static Future<HomeTipsCatalogSnapshot> fetchHomeTipsOnce() async {
    try {
      final homeSnap = await FirebaseFirestore.instance
          .doc(FinancialTipsHomeSyncService.docPath)
          .get();
      final config = FinancialTipsHomeSyncService.parse(homeSnap.data());
      return _buildFromHomeConfig(config);
    } catch (e) {
      debugPrint('FinancialTipsCatalogService.fetchHomeTipsOnce: $e');
      return HomeTipsCatalogSnapshot(tips: biblicalCatalog());
    }
  }
}
