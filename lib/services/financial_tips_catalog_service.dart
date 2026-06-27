import 'dart:math' show min;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:intl/intl.dart';

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

/// Dica resolvida para um dia civil específico.
class FinancialTipDayEntry {
  const FinancialTipDayEntry({
    required this.date,
    required this.label,
    required this.tip,
    this.isToday = false,
  });

  final DateTime date;
  final String label;
  final FinancialTipDisplayItem tip;
  final bool isToday;
}

/// Catálogo resolvido para o Início (após sync do admin ou fallback bíblico).
class HomeTipsCatalogSnapshot {
  const HomeTipsCatalogSnapshot({
    required this.tips,
    this.config,
    this.favoriteIds = const [],
    this.syncedAt,
    this.fromSyncedConfig = false,
  });

  final List<FinancialTipDisplayItem> tips;
  final FinancialTipsHomeConfig? config;
  final List<String> favoriteIds;
  final DateTime? syncedAt;
  final bool fromSyncedConfig;
}

/// Bloco para o Início: apenas a dica do dia.
class HomeTipsPreview {
  const HomeTipsPreview({
    required this.tipOfDay,
    required this.allTips,
    this.dayLabel = 'Hoje',
  });

  final FinancialTipDisplayItem tipOfDay;
  final List<FinancialTipDisplayItem> allTips;
  final String dayLabel;
}

/// Catálogo de dicas bíblicas para o painel Início.
class FinancialTipsCatalogService {
  FinancialTipsCatalogService._();

  /// Histórico visível no módulo Dicas (últimos N dias).
  static const int kModuleHistoryDays = 3;

  static int tipOfDayIndex(int length) {
    if (length <= 0) return 0;
    final now = DateTime.now();
    final start = DateTime(now.year, 1, 1);
    final day = now.difference(start).inDays;
    return day % length;
  }

  static int _daySerial(DateTime d) =>
      DateTime(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 86400000;

  static List<FinancialTipDisplayItem> biblicalCatalog() =>
      List<FinancialTipDisplayItem>.from(kBiblicalFinanceTips);

  static List<FinancialTipDisplayItem> staticFallback() {
    var i = 0;
    return kFinanceTipBankStatic
        .map((e) => FinancialTipDisplayItem.fromBankEntry(e, ordem: (i += 10)))
        .toList();
  }

  static Map<String, FinancialTipDisplayItem> _indexById(
    Iterable<FinancialTipDisplayItem> tips,
  ) {
    return {for (final t in tips) t.id: t};
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
    for (final f in firestoreTips) {
      byId[f.id] = f;
    }
    final out = byId.values.toList()
      ..sort((a, b) => a.ordem.compareTo(b.ordem));
    return out.isNotEmpty ? out : biblicalCatalog();
  }

  static List<String> _rotationIds(
    List<FinancialTipDisplayItem> catalog,
    FinancialTipsHomeConfig? config,
  ) {
    final byId = _indexById(catalog);
    final raw = config?.effectiveRotationOrder ?? [];
    final fromConfig = [
      for (final id in raw)
        if (byId.containsKey(id)) id,
    ];
    if (fromConfig.isNotEmpty) return fromConfig;
    return catalog.map((t) => t.id).toList();
  }

  /// Dica de um dia: prioridade dia da semana (admin) → rotação ordenada → fallback.
  static FinancialTipDisplayItem resolveTipForDate(
    List<FinancialTipDisplayItem> catalog,
    FinancialTipsHomeConfig? config,
    DateTime date,
  ) {
    if (catalog.isEmpty) return biblicalCatalog().first;
    final byId = _indexById(catalog);
    final weekday = date.weekday;

    final overrideId = config?.weekdayTipIds[weekday];
    if (overrideId != null &&
        overrideId.isNotEmpty &&
        byId.containsKey(overrideId)) {
      return byId[overrideId]!;
    }

    final rotation = _rotationIds(catalog, config);
    if (rotation.isEmpty) {
      return catalog[tipOfDayIndex(catalog.length)];
    }
    final idx = _daySerial(date) % rotation.length;
    return byId[rotation[idx]] ?? catalog.first;
  }

  static String dayOffsetLabel(int daysAgo) {
    switch (daysAgo) {
      case 0:
        return 'Hoje';
      case 1:
        return 'Ontem';
      case 2:
        return 'Anteontem';
      default:
        final d = DateTime.now().subtract(Duration(days: daysAgo));
        return DateFormat('EEEE, dd/MM', 'pt_BR').format(d);
    }
  }

  /// Últimos [days] dias (módulo Dicas) — usuário não vê o catálogo inteiro.
  static List<FinancialTipDayEntry> recentTipDays(
    List<FinancialTipDisplayItem> catalog,
    FinancialTipsHomeConfig? config, {
    int days = kModuleHistoryDays,
  }) {
    if (catalog.isEmpty) catalog = biblicalCatalog();
    final today = DateTime.now();
    final base = DateTime(today.year, today.month, today.day);
    final out = <FinancialTipDayEntry>[];
    for (var i = 0; i < days; i++) {
      final date = base.subtract(Duration(days: i));
      out.add(
        FinancialTipDayEntry(
          date: date,
          label: dayOffsetLabel(i),
          tip: resolveTipForDate(catalog, config, date),
          isToday: i == 0,
        ),
      );
    }
    return out;
  }

  static HomeTipsPreview partitionForHome(
    List<FinancialTipDisplayItem> all, {
    FinancialTipsHomeConfig? config,
  }) {
    final catalog = all.isEmpty ? biblicalCatalog() : all;
    final today = DateTime.now();
    final tipOfDay = resolveTipForDate(catalog, config, today);
    return HomeTipsPreview(
      tipOfDay: tipOfDay,
      allTips: catalog,
      dayLabel: 'Hoje',
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

  static Set<String> _idsNeededForConfig(FinancialTipsHomeConfig? config) {
    final ids = <String>{};
    if (config == null) return ids;
    ids.addAll(config.homeTipIds);
    ids.addAll(config.rotationOrder);
    ids.addAll(config.weekdayTipIds.values);
    ids.addAll(config.favoriteTipIds);
    return ids;
  }

  static Future<HomeTipsCatalogSnapshot> _buildFromHomeConfig(
    FinancialTipsHomeConfig? config,
  ) async {
    if (config == null || !config.hasSelection) {
      return HomeTipsCatalogSnapshot(tips: biblicalCatalog());
    }
    final needed = _idsNeededForConfig(config).toList();
    final firestoreTips = needed.isEmpty
        ? <FinancialTipDisplayItem>[]
        : await _fetchTipsByIds(needed);
    final merged = resolveHomeCatalog(firestoreTips);
    return HomeTipsCatalogSnapshot(
      tips: merged,
      config: config,
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
