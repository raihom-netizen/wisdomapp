import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/mp_checkout_pricing_service.dart';

/// Receita prevista (licenças ativas) vs realizada (MP no período).
class AdminRevenueForecastPanel extends StatelessWidget {
  final double revenueRealizedMp;
  final int totalPremiums;
  final int totalUsers;
  final double pixLiquido;
  final double cardLiquido;

  const AdminRevenueForecastPanel({
    super.key,
    required this.revenueRealizedMp,
    required this.totalPremiums,
    required this.totalUsers,
    this.pixLiquido = 0,
    this.cardLiquido = 0,
  });

  @override
  Widget build(BuildContext context) {
    // Lê o preço mensal REAL do checkout (app_config/mp_checkout_prices),
    // com fallback no padrão (R$ 14,99). Antes usava R$ 29,90 fixo, o que
    // inflava o "A receber (est.)" em ~2x.
    return StreamBuilder<MpCheckoutPricingSnapshot>(
      stream: MpCheckoutPricingService.watch(),
      builder: (context, priceSnap) {
        final monthlyTicket = priceSnap.data?.premiumMonthly ??
            MpCheckoutPricingSnapshot.defaults().premiumMonthly;
        return _buildContent(context, monthlyTicket);
      },
    );
  }

  Widget _buildContent(BuildContext context, double monthlyTicket) {
    final forecast = totalPremiums * monthlyTicket;
    final fmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final gap = forecast - revenueRealizedMp;
    final gapLabel = gap >= 0 ? 'A receber (est.)' : 'Acima da meta est.';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_rounded,
                  color: Colors.indigo.shade700, size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Receita prevista vs realizada (MP)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Prevista: $totalPremiums premium(s) × ${fmt.format(monthlyTicket)}/mês · Realizada: pagamentos MP no período.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600, height: 1.3),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, c) {
              final narrow = c.maxWidth < 400;
              final cards = [
                _metricCard(
                  'Prevista (mês ref.)',
                  fmt.format(forecast),
                  Icons.trending_up_rounded,
                  Colors.blue.shade700,
                ),
                _metricCard(
                  'Realizada MP',
                  fmt.format(revenueRealizedMp),
                  Icons.payments_rounded,
                  Colors.green.shade700,
                ),
                _metricCard(
                  gapLabel,
                  fmt.format(gap.abs()),
                  gap >= 0 ? Icons.hourglass_top_rounded : Icons.celebration_rounded,
                  gap >= 0 ? Colors.orange.shade800 : Colors.teal.shade700,
                ),
              ];
              if (narrow) {
                return Column(
                  children: [
                    for (final card in cards) ...[
                      card,
                      const SizedBox(height: 8),
                    ],
                  ],
                );
              }
              return Row(
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(child: cards[i]),
                  ],
                ],
              );
            },
          ),
          if (pixLiquido > 0 || cardLiquido > 0) ...[
            const SizedBox(height: 10),
            Text(
              'PIX líq. ${fmt.format(pixLiquido)} · Cartão líq. ${fmt.format(cardLiquido)}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metricCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 6),
          Text(title,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}
