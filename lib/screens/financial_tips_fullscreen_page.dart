import 'package:flutter/material.dart';

import '../services/financial_tips_catalog_service.dart';
import '../widgets/finance_tip_modern_card.dart';

/// Lista completa de dicas bíblicas — tela cheia com botão voltar.
class FinancialTipsFullscreenPage extends StatelessWidget {
  const FinancialTipsFullscreenPage({
    super.key,
    required this.tips,
    this.highlightTipOfDay = true,
  });

  final List<FinancialTipDisplayItem> tips;
  final bool highlightTipOfDay;

  @override
  Widget build(BuildContext context) {
    final dayIdx = FinancialTipsCatalogService.tipOfDayIndex(tips.length);

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1B4B),
        foregroundColor: Colors.white,
        title: const Text(
          'Dicas Financeiras Bíblicas',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        itemCount: tips.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                '${tips.length} dicas com base na Bíblia para organizar, poupar e decidir com sabedoria.',
                style: TextStyle(
                  color: Colors.grey.shade800,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            );
          }
          final tip = tips[i - 1];
          final isDay = highlightTipOfDay && (i - 1) == dayIdx;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FinanceTipModernCard(
              tip: tip,
              index: i - 1,
              isTipOfDay: isDay,
              showFullText: true,
            ),
          );
        },
      ),
    );
  }
}

Future<void> openFinancialTipsFullscreen(
  BuildContext context,
  List<FinancialTipDisplayItem> tips,
) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => FinancialTipsFullscreenPage(tips: tips),
    ),
  );
}
