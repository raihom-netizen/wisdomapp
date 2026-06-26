import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../constants/currency_formats.dart';
import '../constants/date_time_formats.dart';
import '../models/finance_assistant_insight.dart';
import '../models/user_profile.dart';
import '../services/fixed_expense_service.dart';
import '../services/fixed_income_service.dart';
import '../theme/app_colors.dart';
import '../utils/finance_assistant_insights_engine.dart';
import '../utils/finance_period_summary.dart';
import '../utils/finance_smart_tips_composer.dart';
import '../utils/finance_tip_bank_selector.dart';
import '../utils/finance_health_score.dart';
import '../utils/insights_engine.dart';
import '../models/finance_tip_bank_entry.dart';
import '../utils/firestore_user_doc_id.dart';
import '../widgets/finance_smart_tips_insight.dart';
import '../widgets/skeleton_loader.dart';

/// Painel completo: alertas automáticos + dicas personalizadas + educação (mesmas regras do bloco na tela).
class FinanceAssistantInsightsPage extends StatefulWidget {
  const FinanceAssistantInsightsPage({
    super.key,
    required this.uid,
    required this.profile,
    required this.from,
    required this.to,
    required this.statusFilter,
    required this.typeFilter,
    required this.docs,
    required this.totalIncome,
    required this.totalExpense,
    required this.balancePeriod,
  });

  final String uid;
  final UserProfile profile;
  final DateTime from;
  final DateTime to;
  final String statusFilter;
  final String typeFilter;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final double totalIncome;
  final double totalExpense;
  final double balancePeriod;

  @override
  State<FinanceAssistantInsightsPage> createState() => _FinanceAssistantInsightsPageState();

  static (DateTime, DateTime) _previousPeriodSameLength(DateTime from, DateTime to) {
    final f = DateTime(from.year, from.month, from.day);
    final t = DateTime(to.year, to.month, to.day, 23, 59, 59);
    final prevEnd = f.subtract(const Duration(days: 1));
    final days = t.difference(f).inDays + 1;
    final prevStart = DateTime(prevEnd.year, prevEnd.month, prevEnd.day).subtract(Duration(days: days - 1));
    return (prevStart, DateTime(prevEnd.year, prevEnd.month, prevEnd.day, 23, 59, 59));
  }

  static Widget _chipResumo(String label, double value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            CurrencyFormats.formatBRL(value),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

}

class _FinanceAssistantInsightsPageState extends State<FinanceAssistantInsightsPage> {
  late Future<List<dynamic>> _panelFuture;

  @override
  void initState() {
    super.initState();
    _panelFuture = _loadPanel();
  }

  Future<List<dynamic>> _loadPanel() {
    final sid = firestoreUserDocIdForAppShell(widget.uid);
    final (pf, pt) = FinanceAssistantInsightsPage._previousPeriodSameLength(widget.from, widget.to);
    return Future.wait<dynamic>([
      FixedExpenseService().list(sid),
      FixedIncomeService().list(sid),
      FinancePeriodSummary.load(
        uid: sid,
        from: pf,
        to: pt,
        statusFilter: widget.statusFilter,
        typeFilter: widget.typeFilter,
      ),
      InsightsEngine(FirebaseFirestore.instance).gerarInsights(widget.docs),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final periodo =
        '${DateTimeFormats.dateBR.format(widget.from)} a ${DateTimeFormats.dateBR.format(widget.to)}';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Assistente financeiro'),
        backgroundColor: AppColors.deepBlueDark,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          final next = _loadPanel();
          setState(() => _panelFuture = next);
          await next;
        },
        child: FutureBuilder<List<dynamic>>(
          future: _panelFuture,
          builder: (context, snap) {
          if (snap.hasError) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(24, 48, 24, 24 + MediaQuery.paddingOf(context).bottom),
              children: [
                Icon(Icons.error_outline_rounded, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text('Erro ao carregar: ${snap.error}', textAlign: TextAlign.center),
              ],
            );
          }
          if (!snap.hasData) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(24, 48, 24, 24 + MediaQuery.paddingOf(context).bottom),
              children: [
                Text(
                  'A carregar assistente…',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Colors.grey.shade800),
                ),
                const SizedBox(height: 20),
                const SkeletonListLoader(itemCount: 6, itemHeight: 72),
              ],
            );
          }
          final data = snap.data!;
          final expList = data[0] as List<Map<String, dynamic>>;
          final incList = data[1] as List<Map<String, dynamic>>;
          final prev = data[2] as ({double income, double expense, int docCount});
          final fireTips = data[3] as List<FinancialTipInsight>;

          double? fixedMonthly;
          for (final e in expList) {
            if (e['active'] == false) continue;
            fixedMonthly = (fixedMonthly ?? 0) + ((e['amount'] ?? 0) as num).toDouble().abs();
          }
          if (fixedMonthly == 0) fixedMonthly = null;

          double? fixedIncomeMonthly;
          for (final e in incList) {
            if (e['active'] == false) continue;
            fixedIncomeMonthly = (fixedIncomeMonthly ?? 0) + ((e['amount'] ?? 0) as num).toDouble().abs();
          }
          if (fixedIncomeMonthly == 0) fixedIncomeMonthly = null;

          final stats = buildFinanceSmartTipsStats(
            docs: widget.docs,
            totalIncome: widget.totalIncome,
            totalExpense: widget.totalExpense,
            balancePeriod: widget.balancePeriod,
            fixedMonthlySum: fixedMonthly,
            fixedIncomeMonthlySum: fixedIncomeMonthly,
          );

          final alerts = FinanceAssistantInsightsEngine.buildAlerts(
            stats,
            prevIncome: prev.income,
            prevExpense: prev.expense,
          );
          final tips = FinanceSmartTipsComposer.compose(stats, maxTips: 14);
          final bankTips = selectFinanceTipBankEntries(docs: widget.docs, stats: stats, maxItems: 10);
          final scorePeriodo = calcularScoreFinanceiro(widget.totalIncome, widget.totalExpense);
          final tierPeriodo = tierFromScore(scorePeriodo);

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.paddingOf(context).bottom),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.deepBlueDark, AppColors.primary, AppColors.accent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Análise do período',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      periodo,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FinanceAssistantInsightsPage._chipResumo('Receitas', widget.totalIncome),
                        FinanceAssistantInsightsPage._chipResumo('Despesas', widget.totalExpense),
                        FinanceAssistantInsightsPage._chipResumo('Saldo período', widget.balancePeriod),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        children: [
                          Text(
                            '$scorePeriodo',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 28,
                              height: 1,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            width: 4,
                            height: 36,
                            decoration: BoxDecoration(
                              color: colorFinanceHealthTier(tierPeriodo),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Score do período · ${labelFinanceHealthTier(tierPeriodo)}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  hintFinanceHealthTier(tierPeriodo),
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontSize: 11.5,
                                    height: 1.3,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Alertas e padrões',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: Colors.grey.shade900,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 8),
              if (alerts.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Text(
                    'Nenhum alerta automático para este período — ótimo sinal ou poucos dados.',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.35),
                  ),
                )
              else
                ...alerts.map((a) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _AssistantAlertCard(insight: a),
                    )),
              const SizedBox(height: 22),
              Text(
                'Dicas inteligentes',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: Colors.grey.shade900,
                  letterSpacing: -0.2,
                ),
              ),
              Text(
                'Personalizadas aos seus lançamentos + educação financeira',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 10),
              if (tips.isEmpty)
                Text('Sem dicas neste momento.', style: TextStyle(color: Colors.grey.shade600))
              else
                ...tips.map((t) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ComposerTipTile(tip: t),
                    )),
              const SizedBox(height: 22),
              Text(
                'Regras remotas (Firestore)',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: Colors.grey.shade900,
                  letterSpacing: -0.2,
                ),
              ),
              Text(
                'Coleção ${InsightsEngine.kFinancialTipsCollection}: dicas e condições editáveis no painel (sem novo release do app).',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 10),
              if (fireTips.isEmpty)
                Text(
                  'Nenhuma dica remota aplicável — cadastre documentos em financial_tips ou ajuste condições.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.35),
                )
              else
                ...fireTips.map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _FirestoreTipInsightTile(insight: f),
                    )),
              const SizedBox(height: 22),
              Text(
                'Biblioteca de dicas',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: Colors.grey.shade900,
                  letterSpacing: -0.2,
                ),
              ),
              Text(
                'Conteúdo local priorizado pelo seu comportamento no período (complementa as regras remotas).',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 10),
              if (bankTips.isEmpty)
                Text('Nenhuma dica do banco para exibir.', style: TextStyle(color: Colors.grey.shade600))
              else
                ...bankTips.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _BankTipTile(entry: e),
                    )),
            ],
          );
        },
        ),
      ),
    );
  }
}

class _AssistantAlertCard extends StatelessWidget {
  const _AssistantAlertCard({required this.insight});

  final FinanceAssistantInsight insight;

  @override
  Widget build(BuildContext context) {
    final c = insight.accentColor;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: c.withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(insight.icon, color: c, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    insight.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      height: 1.25,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    insight.body,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.42,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mesmo estilo de badge que o bloco na tela Financeiro (`_SmartTipTile`).
class _FirestoreTipInsightTile extends StatelessWidget {
  const _FirestoreTipInsightTile({required this.insight});

  final FinancialTipInsight insight;

  @override
  Widget build(BuildContext context) {
    final c = insight.cor;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: c.withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(insight.icone, color: c, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Servidor · ${insight.id}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary.withValues(alpha: 0.95),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    insight.titulo,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      height: 1.25,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    insight.descricao,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.42,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BankTipTile extends StatelessWidget {
  const _BankTipTile({required this.entry});

  final FinanceTipBankEntry entry;

  static String _labelCategoria(String slug) {
    switch (slug) {
      case 'educacao':
        return 'Educação';
      case 'comportamento':
        return 'Comportamento';
      case 'alimentacao':
        return 'Alimentação';
      case 'gastos':
        return 'Gastos';
      case 'transporte':
        return 'Transporte';
      case 'cartao':
        return 'Cartão';
      case 'investimento':
        return 'Investimento';
      case 'controle':
        return 'Controle';
      default:
        return slug;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = entry.color;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: c.withValues(alpha: 0.1), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(entry.icon, color: c, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: c.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _labelCategoria(entry.categoriaSlug),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: c.withValues(alpha: 0.95),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    entry.titulo,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      height: 1.25,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    entry.descricao,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.42,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComposerTipTile extends StatelessWidget {
  const _ComposerTipTile({required this.tip});

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
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w900,
                height: 1.25,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              tip.body,
              style: const TextStyle(
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
