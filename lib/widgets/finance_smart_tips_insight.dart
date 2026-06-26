import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/fixed_expense_service.dart';
import '../services/fixed_income_service.dart';
import '../theme/app_colors.dart';
import '../utils/finance_smart_tips_composer.dart';
import 'finance_premium_ui.dart';

/// Monta [FinanceSmartTipsStats] a partir dos lançamentos do período (bloco de dicas + painel assistente).
FinanceSmartTipsStats buildFinanceSmartTipsStats({
  required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  required double totalIncome,
  required double totalExpense,
  required double balancePeriod,
  double? fixedMonthlySum,
  double? fixedIncomeMonthlySum,
}) {
  var expCount = 0;
  var incCount = 0;
  var pendExp = 0;
  var pendInc = 0;
  var pendExpAmt = 0.0;
  for (final doc in docs) {
    final d = doc.data();
    final type = (d['type'] ?? 'expense').toString();
    final status = (d['status'] ?? 'paid').toString();
    if (type == 'expense') {
      expCount++;
      if (status == 'pending') {
        pendExp++;
        pendExpAmt += ((d['amount'] ?? 0) as num).toDouble().abs();
      }
    } else if (type == 'income') {
      incCount++;
      if (status == 'pending') pendInc++;
    }
  }
  final m = <String, double>{};
  for (final doc in docs) {
    final d = doc.data();
    if ((d['type'] ?? 'expense').toString() != 'expense') continue;
    final cat = (d['category'] ?? '').toString().trim();
    final key = cat.isEmpty ? 'Sem categoria' : cat;
    m[key] = (m[key] ?? 0) + ((d['amount'] ?? 0) as num).toDouble().abs();
  }
  final sorted = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  String? topName;
  double? topShare;
  if (sorted.isNotEmpty && totalExpense > 0.0001) {
    topName = sorted.first.key;
    topShare = (sorted.first.value / totalExpense) * 100.0;
  }
  final fixedPct = fixedMonthlySum != null && totalIncome > 0.0001
      ? (fixedMonthlySum / totalIncome) * 100.0
      : null;
  final fixedIncomePct = fixedIncomeMonthlySum != null && totalIncome > 0.0001
      ? (fixedIncomeMonthlySum / totalIncome) * 100.0
      : null;

  var foodExpenseApprox = 0.0;
  for (final doc in docs) {
    final d = doc.data();
    if ((d['type'] ?? 'expense').toString() != 'expense') continue;
    final cat = (d['category'] ?? '').toString();
    if (!_categoryLooksLikeFood(cat)) continue;
    foodExpenseApprox += ((d['amount'] ?? 0) as num).toDouble().abs();
  }

  return FinanceSmartTipsStats(
    totalIncome: totalIncome,
    totalExpense: totalExpense,
    balancePeriod: balancePeriod,
    expenseTransactionCount: expCount,
    incomeTransactionCount: incCount,
    pendingExpenseCount: pendExp,
    pendingExpenseAmount: pendExpAmt,
    pendingIncomeCount: pendInc,
    topExpenseCategoryName: topName,
    topExpenseCategorySharePct: topShare,
    fixedMonthlySum: fixedMonthlySum,
    fixedPctOfPeriodIncome: fixedPct,
    fixedIncomeMonthlySum: fixedIncomeMonthlySum,
    fixedIncomePctOfPeriodIncome: fixedIncomePct,
    foodExpenseTotalApprox: foodExpenseApprox,
  );
}

bool _categoryLooksLikeFood(String raw) {
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

/// Secção de dicas: **personalizadas ao período** + **educação / mercado** (rotação diária).
class FinanceSmartTipsInsightBlock extends StatelessWidget {
  const FinanceSmartTipsInsightBlock({
    super.key,
    required this.uid,
    required this.docs,
    required this.totalIncome,
    required this.totalExpense,
    required this.balancePeriod,
    this.onOpenAssistantPanel,
    this.previewMode = false,
  });

  final String uid;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final double totalIncome;
  final double totalExpense;
  final double balancePeriod;
  /// Abre o painel completo do assistente financeiro (opcional).
  final VoidCallback? onOpenAssistantPanel;
  /// Dentro do sheet de preview: omite cabeçalho duplicado da tela principal.
  final bool previewMode;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<List<Map<String, dynamic>>>>(
      future: Future.wait([
        FixedExpenseService().list(uid),
        FixedIncomeService().list(uid),
      ]),
      builder: (context, snap) {
        double? fixedMonthly;
        double? fixedIncomeMonthly;
        if (snap.hasData) {
          var monthlyExp = 0.0;
          for (final e in snap.data![0]) {
            if (e['active'] == false) continue;
            monthlyExp += ((e['amount'] ?? 0) as num).toDouble().abs();
          }
          if (monthlyExp > 0) fixedMonthly = monthlyExp;
          var monthlyInc = 0.0;
          for (final e in snap.data![1]) {
            if (e['active'] == false) continue;
            monthlyInc += ((e['amount'] ?? 0) as num).toDouble().abs();
          }
          if (monthlyInc > 0) fixedIncomeMonthly = monthlyInc;
        }
        final stats = buildFinanceSmartTipsStats(
          docs: docs,
          totalIncome: totalIncome,
          totalExpense: totalExpense,
          balancePeriod: balancePeriod,
          fixedMonthlySum: fixedMonthly,
          fixedIncomeMonthlySum: fixedIncomeMonthly,
        );
        final tips = FinanceSmartTipsComposer.compose(stats, maxTips: 5);
        if (tips.isEmpty && onOpenAssistantPanel == null) return const SizedBox.shrink();

        final now = DateTime.now();
        final freshness =
            'Conteúdo de mercado e educação: combinação do dia ${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} · suas dicas mudam com o período e os lançamentos.';

        return Padding(
          padding: EdgeInsets.only(top: previewMode ? 0 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (previewMode && onOpenAssistantPanel != null) ...[
                _SuperPremiumAssistantCta(
                  onTap: onOpenAssistantPanel!,
                  fullWidth: true,
                ),
                const SizedBox(height: 14),
              ],
              if (!previewMode) ...[
              LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 380;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.amber.withValues(alpha: 0.35),
                              AppColors.accent.withValues(alpha: 0.22),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.lightbulb_rounded, color: Colors.amber.shade900, size: 22),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Dicas inteligentes para você',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                                letterSpacing: -0.2,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              'Economia, dívidas, metas e contexto de mercado',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textMuted,
                              ),
                            ),
                            if (narrow && onOpenAssistantPanel != null) ...[
                              const SizedBox(height: 10),
                              _SuperPremiumAssistantCta(
                                onTap: onOpenAssistantPanel!,
                                fullWidth: true,
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (!narrow && onOpenAssistantPanel != null)
                        _SuperPremiumAssistantCta(
                          onTap: onOpenAssistantPanel!,
                          fullWidth: false,
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              ],
              if (tips.isEmpty && onOpenAssistantPanel != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Resumo rápido neste painel; abra o painel completo para alertas e todas as dicas.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                )
              else
                ...tips.map((t) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _SmartTipTile(tip: t),
                    )),
              if (!previewMode) ...[
                const SizedBox(height: 8),
                Text(
                  freshness,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMuted.withValues(alpha: 0.95),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

List<Widget> _premiumCtaTexts(bool fullWidth) {
  return [
    Text(
      'SUPER PREMIUM',
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w900,
        fontSize: fullWidth ? 13.5 : 12,
        letterSpacing: fullWidth ? 1.15 : 0.9,
        height: 1.1,
        shadows: [
          Shadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    ),
    Text(
      'Painel completo do assistente',
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.9),
        fontWeight: FontWeight.w700,
        fontSize: fullWidth ? 11 : 10,
        height: 1.2,
      ),
    ),
  ];
}

/// CTA legível (gradiente + texto branco) — evita azul sobre azul do `FilledButton.tonal`.
class _SuperPremiumAssistantCta extends StatelessWidget {
  const _SuperPremiumAssistantCta({
    required this.onTap,
    required this.fullWidth,
  });

  final VoidCallback onTap;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final textColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: _premiumCtaTexts(fullWidth),
    );

    final inner = Material(
      color: Colors.transparent,
      elevation: 0,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AppColors.logoGradient,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.deepBlueDark.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.22),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: fullWidth ? 14 : 10,
              horizontal: fullWidth ? 18 : 14,
            ),
            child: Row(
              mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment:
                  fullWidth ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                Icon(Icons.auto_awesome_rounded,
                    color: Colors.white.withValues(alpha: 0.96), size: fullWidth ? 22 : 19),
                SizedBox(width: fullWidth ? 10 : 8),
                if (fullWidth)
                  Expanded(child: textColumn)
                else
                  textColumn,
              ],
            ),
          ),
        ),
      ),
    );
    if (fullWidth) {
      return SizedBox(width: double.infinity, child: inner);
    }
    return inner;
  }
}

class _SmartTipTile extends StatelessWidget {
  const _SmartTipTile({required this.tip});

  final FinanceSmartTip tip;

  @override
  Widget build(BuildContext context) {
    final personalized = tip.personalized;
    final accent = personalized ? AppColors.primary : AppColors.accent;
    final badgeBg = personalized ? AppColors.primary.withValues(alpha: 0.12) : AppColors.accent.withValues(alpha: 0.12);
    final badgeFg = personalized ? AppColors.primary : const Color(0xFF0F766E);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            accent.withValues(alpha: 0.04),
          ],
        ),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: accent.withValues(alpha: 0.28)),
                  ),
                  child: Text(
                    personalized ? 'Para você' : 'Mercado & educação',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: badgeFg,
                    ),
                  ),
                ),
                const Spacer(),
                Icon(
                  personalized ? Icons.person_pin_rounded : Icons.public_rounded,
                  size: 18,
                  color: accent.withValues(alpha: 0.75),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              tip.title,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w900,
                height: 1.25,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              tip.body,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.42,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Uma linha compacta na tela principal — abre o preview completo ao tocar em Veja mais.
class FinanceSmartTipsCompactBar extends StatelessWidget {
  const FinanceSmartTipsCompactBar({
    super.key,
    required this.onVejaMais,
  });

  final VoidCallback onVejaMais;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onVejaMais,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  AppColors.amber.withValues(alpha: 0.1),
                  Colors.white,
                ],
              ),
              border: Border.all(color: AppColors.amber.withValues(alpha: 0.24)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.amber.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.amber.withValues(alpha: 0.45),
                          AppColors.accent.withValues(alpha: 0.28),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.lightbulb_rounded, color: Colors.amber.shade900, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Dicas inteligentes para você',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  FilledButton.tonal(
                    onPressed: onVejaMais,
                    style: FilledButton.styleFrom(
                      foregroundColor: Colors.amber.shade900,
                      backgroundColor: AppColors.amber.withValues(alpha: 0.16),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      minimumSize: const Size(48, 40),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Veja mais', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Preview premium das dicas (sheet deslizante).
Future<void> showFinanceSmartTipsPreviewSheet({
  required BuildContext context,
  required String uid,
  required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  required double totalIncome,
  required double totalExpense,
  required double balancePeriod,
  VoidCallback? onOpenAssistantPanel,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.84,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: financePremiumSheetDecoration(surfaceTint: AppColors.amber),
        child: Column(
          children: [
            FinancePremiumSheetHeader(
              title: 'Dicas inteligentes',
              subtitle: 'Economia, dívidas, metas e contexto de mercado',
              icon: Icons.lightbulb_rounded,
              iconGradient: [
                Colors.amber.shade700,
                AppColors.accent,
              ],
              titleColor: AppColors.textPrimary,
              onBack: () => Navigator.pop(ctx),
            ),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                children: [
                  FinanceSmartTipsInsightBlock(
                    uid: uid,
                    docs: docs,
                    totalIncome: totalIncome,
                    totalExpense: totalExpense,
                    balancePeriod: balancePeriod,
                    onOpenAssistantPanel: onOpenAssistantPanel,
                    previewMode: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
