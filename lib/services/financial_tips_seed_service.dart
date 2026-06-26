import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/biblical_finance_tips.dart';
import '../data/financial_tips_firestore_seed_bank.dart';
import '../utils/insights_engine.dart';

/// Importa o banco diversificado de dicas para `financial_tips` (admin).
class FinancialTipsSeedService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Grava dicas com ID fixo. Se [skipExisting], ignora documentos que já existem;
  /// se false, sobrescreve os IDs do banco (modo «Substituir existentes»).
  Future<FinancialTipsSeedResult> seedDiversifiedBank({
    bool skipExisting = true,
  }) async {
    final col = _db.collection(InsightsEngine.kFinancialTipsCollection);
    var created = 0;
    var skipped = 0;
    var updated = 0;

    WriteBatch? batch;
    var opsInBatch = 0;

    Future<void> flush() async {
      if (batch != null && opsInBatch > 0) {
        await batch!.commit();
        batch = null;
        opsInBatch = 0;
      }
    }

    final existingIds = skipExisting
        ? (await col.get()).docs.map((d) => d.id).toSet()
        : <String>{};

    for (final seed in kFinancialTipsFirestoreSeedBank) {
      final ref = col.doc(seed.docId);
      if (skipExisting && existingIds.contains(seed.docId)) {
        skipped++;
        continue;
      }
      if (!skipExisting && existingIds.contains(seed.docId)) {
        updated++;
      } else {
        created++;
      }

      batch ??= _db.batch();
      batch!.set(
        ref,
        {
          ...seed.toFirestorePayload(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: false),
      );
      opsInBatch++;

      if (opsInBatch >= 400) {
        await flush();
      }
    }

    await flush();

    InsightsEngine.clearTipsCache();

    return FinancialTipsSeedResult(
      created: created,
      skipped: skipped,
      updated: updated,
      totalInBank: kFinancialTipsFirestoreSeedBank.length,
    );
  }

  /// Importa bíblicas + gerais de uma vez (primeira configuração do painel).
  Future<FinancialTipsFullSeedResult> seedFullCatalog({
    bool skipExisting = true,
    bool markHomeDefaults = true,
  }) async {
    final biblical = await seedBiblicalCatalog(skipExisting: skipExisting);
    final general = await seedDiversifiedBank(skipExisting: skipExisting);
    var homeMarked = 0;
    if (markHomeDefaults) {
      homeMarked = await _markDefaultHomeTips();
    }
    return FinancialTipsFullSeedResult(
      biblical: biblical,
      general: general,
      homeTipsMarked: homeMarked,
    );
  }

  Future<int> _markDefaultHomeTips() async {
    final col = _db.collection(InsightsEngine.kFinancialTipsCollection);
    final homeIds = kBiblicalFinanceTips.take(3).map((t) => t.id).toList();
    if (homeIds.isEmpty) return 0;
    final batch = _db.batch();
    for (var i = 0; i < homeIds.length; i++) {
      batch.set(
        col.doc(homeIds[i]),
        {
          'exibirNoInicio': true,
          if (i == 0) 'favorita': true,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
    InsightsEngine.clearTipsCache();
    return homeIds.length;
  }

  /// Grava dicas bíblicas do Início (`kBiblicalFinanceTips`) para edição no admin.
  Future<FinancialTipsSeedResult> seedBiblicalCatalog({
    bool skipExisting = true,
  }) async {
    final col = _db.collection(InsightsEngine.kFinancialTipsCollection);
    var created = 0;
    var skipped = 0;
    var updated = 0;

    WriteBatch? batch;
    var opsInBatch = 0;

    Future<void> flush() async {
      if (batch != null && opsInBatch > 0) {
        await batch!.commit();
        batch = null;
        opsInBatch = 0;
      }
    }

    final existingIds = skipExisting
        ? (await col.get()).docs.map((d) => d.id).toSet()
        : <String>{};

    for (final tip in kBiblicalFinanceTips) {
      final ref = col.doc(tip.id);
      if (skipExisting && existingIds.contains(tip.id)) {
        skipped++;
        continue;
      }
      if (!skipExisting && existingIds.contains(tip.id)) {
        updated++;
      } else {
        created++;
      }

      batch ??= _db.batch();
      batch!.set(
        ref,
        {
          'titulo': tip.titulo,
          'descricao': tip.descricao,
          'categoria': tip.categoriaSlug,
          'referenciaBiblica': tip.referenciaBiblica,
          'textoVersiculo': tip.textoVersiculo,
          'icone': tip.iconKey,
          'cor': tip.colorKey,
          'iconKey': tip.iconKey,
          'colorKey': tip.colorKey,
          'ordem': tip.ordem,
          'ativo': true,
          'condicao': const {'tipo': 'sempre'},
          'seedTag': 'biblical_v1',
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: false),
      );
      opsInBatch++;

      if (opsInBatch >= 400) {
        await flush();
      }
    }

    await flush();
    InsightsEngine.clearTipsCache();

    return FinancialTipsSeedResult(
      created: created,
      skipped: skipped,
      updated: updated,
      totalInBank: kBiblicalFinanceTips.length,
    );
  }
}

class FinancialTipsSeedResult {
  final int created;
  final int skipped;
  final int updated;
  final int totalInBank;

  const FinancialTipsSeedResult({
    required this.created,
    required this.skipped,
    required this.updated,
    required this.totalInBank,
  });
}

class FinancialTipsFullSeedResult {
  const FinancialTipsFullSeedResult({
    required this.biblical,
    required this.general,
    required this.homeTipsMarked,
  });

  final FinancialTipsSeedResult biblical;
  final FinancialTipsSeedResult general;
  final int homeTipsMarked;

  int get totalCreated => biblical.created + general.created;
}
