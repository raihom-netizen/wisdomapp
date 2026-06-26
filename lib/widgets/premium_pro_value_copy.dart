import 'package:flutter/material.dart';

import '../constants/premium_pro_limits.dart';
import '../services/mp_checkout_pricing_service.dart';
import '../theme/app_colors.dart';

/// Textos de posicionamento Premium PRO (Open Finance + automação).
class PremiumProCopy {
  PremiumProCopy._();
  static const String diferencialBancos =
      'Compatível com os principais bancos do Brasil.';
  static const String diferencialMeios =
      'Funciona automaticamente com cartão, Pix e débito.';
  static const String visaoProduto =
      'O app deixa de ser só um lançador: passa a reduzir o esforço do dia a dia — é isso que faz valer a assinatura.';
  static const String resumoFluxo =
      'Ative a integração com o banco (quando disponível), autorize o acesso e o sistema pode registar movimentações por si.';
  static const String multiContas =
      'Conecte mais de um banco no mesmo plano (ex.: Nubank + Itaú) e mantenha tudo em um só lugar.';
  static String get limiteConexoes =>
      'Até ${PremiumProLimits.maxBankConnections} instituições simultâneas — equilíbrio entre automação e custo de API por conta.';
  static const String trialAnualDica =
      'No anual, vale combinar alguns dias de teste da automação: o usuário vê o extrato “mágico” e reduz o medo de voltar ao manual (ative no checkout quando fizer sentido comercial).';
}

/// Dois destaques em chips (diferencial comercial).
class PremiumProDiferencialChips extends StatelessWidget {
  const PremiumProDiferencialChips({super.key});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _chip(Icons.account_balance_rounded, PremiumProCopy.diferencialBancos),
        _chip(Icons.credit_card_rounded, PremiumProCopy.diferencialMeios),
      ],
    );
  }

  Widget _chip(IconData icon, String text) {
    return Material(
      color: AppColors.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Checklist “depois da conexão”.
class PremiumProDepoisChecklist extends StatelessWidget {
  const PremiumProDepoisChecklist({super.key});

  @override
  Widget build(BuildContext context) {
    const items = [
      'Compra → já aparece no app',
      'Já categorizado automaticamente',
      'Controle total sem esforço',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Depois da conexão',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: AppColors.textMuted,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 8),
        ...items.map(
          (t) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_rounded, size: 20, color: AppColors.success),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      t,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Resumo do fluxo + visão de produto (bloco discreto).
class PremiumProResumoVisaoCard extends StatelessWidget {
  const PremiumProResumoVisaoCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: AppColors.accent, size: 22),
                const SizedBox(width: 8),
                const Text(
                  'Resumo do fluxo',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              PremiumProCopy.resumoFluxo,
              style: TextStyle(fontSize: 13, height: 1.45, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),
            Text(
              'Por que isso importa',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              PremiumProCopy.visaoProduto,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                fontStyle: FontStyle.italic,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Selo de economia do PRO anual + multi-contas + limite + dica de trial (preços em `mp_checkout_prices`).
class PremiumProMarketingHighlights extends StatelessWidget {
  final bool compact;

  const PremiumProMarketingHighlights({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MpCheckoutPricingSnapshot>(
      stream: MpCheckoutPricingService.watch(),
      builder: (context, snap) {
        final p = snap.data ?? MpCheckoutPricingSnapshot.defaults();
        final save = p.premiumProAnnualSavingsVsTwelveMonthly;
        final pct = p.premiumProAnnualApproxDiscountPercent;
        final pad = compact ? const EdgeInsets.all(12.0) : const EdgeInsets.all(16.0);
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: AppColors.logoOrange.withValues(alpha: 0.45)),
          ),
          color: const Color(0xFFFFF7ED),
          child: Padding(
            padding: pad,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.sell_rounded, color: Colors.orange.shade800, size: compact ? 22 : 26),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Integração automática — referência',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: compact ? 14 : 15,
                          color: const Color(0xFF9A3412),
                        ),
                      ),
                    ),
                  ],
                ),
                if (save != null && save > 0 && pct != null) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(
                        avatar: Icon(Icons.percent_rounded, size: 18, color: Colors.deepOrange.shade800),
                        label: Text(
                          '~$pct% vs 12× mensal',
                          style: TextStyle(fontWeight: FontWeight.w800, color: Colors.deepOrange.shade900, fontSize: 12),
                        ),
                        backgroundColor: Colors.orange.shade100,
                        side: BorderSide(color: Colors.orange.shade300),
                      ),
                      Chip(
                        avatar: Icon(Icons.savings_outlined, size: 18, color: Colors.green.shade800),
                        label: Text(
                          'Economize ${MpCheckoutPricingSnapshot.formatBrl(save)} no anual',
                          style: TextStyle(fontWeight: FontWeight.w800, color: Colors.green.shade900, fontSize: 12),
                        ),
                        backgroundColor: Colors.green.shade50,
                        side: BorderSide(color: Colors.green.shade200),
                      ),
                    ],
                  ),
                  Text(
                    '${p.premiumProAnnualLine} (${p.premiumProAnnualEquivPerMonthLine} em média) · referência: ${p.premiumProMonthlyLine}',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.35),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  Text(
                    '${p.premiumProAnnualLine} ou ${p.premiumProMonthlyLine} — valores em tempo real no checkout.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35),
                  ),
                ],
                SizedBox(height: compact ? 10 : 12),
                _ProMarketingLine(Icons.hub_outlined, PremiumProCopy.multiContas, compact),
                _ProMarketingLine(Icons.shield_outlined, PremiumProCopy.limiteConexoes, compact),
                _ProMarketingLine(Icons.timer_outlined, PremiumProCopy.trialAnualDica, compact),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProMarketingLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool compact;

  const _ProMarketingLine(this.icon, this.text, this.compact);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 6 : 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: compact ? 17 : 19, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: compact ? 11.5 : 12.5,
                height: 1.4,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
