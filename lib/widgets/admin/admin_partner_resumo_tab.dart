import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../constants/app_brand.dart';
import '../../services/admin_partner_stats_service.dart';
import '../../services/mp_checkout_pricing_service.dart';
import '../../widgets/admin_menu_lateral.dart';
import '../../widgets/skeleton_loader.dart';
import 'admin_alert_center.dart';

typedef AdminPartnerNavigate = void Function(AdminMenuItem item);
typedef AdminPartnerAlertNavigate = void Function(String alertId);
typedef AdminPartnerStatsLoaded = void Function(int licensesExpired, int licensesExpiring7d);

/// Resumo read-only do sócio — usuários, licenças, recebimentos da própria parte.
class AdminPartnerResumoTab extends StatefulWidget {
  final Color brandBlue;
  final Color brandTeal;
  final AdminPartnerNavigate onNavigate;
  final AdminPartnerAlertNavigate onAlertNavigate;
  final AdminPartnerStatsLoaded? onStatsLoaded;

  const AdminPartnerResumoTab({
    super.key,
    required this.brandBlue,
    required this.brandTeal,
    required this.onNavigate,
    required this.onAlertNavigate,
    this.onStatsLoaded,
  });

  @override
  State<AdminPartnerResumoTab> createState() => _AdminPartnerResumoTabState();
}

class _AdminPartnerResumoTabState extends State<AdminPartnerResumoTab> {
  static const _periodOptions = [7, 30, 90, 365];
  int _periodDays = 30;
  Future<AdminPartnerStats>? _statsFuture;
  DateTime? _lastUpdate;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _statsFuture =
          const AdminPartnerStatsService().load(periodDays: _periodDays);
    });
  }

  Future<void> _refresh() async {
    _reload();
    final f = _statsFuture;
    if (f != null) await f;
    if (mounted) setState(() => _lastUpdate = DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final horizontalPad = MediaQuery.sizeOf(context).width < 380 ? 12.0 : 16.0;
    final fmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
            horizontalPad, 16, horizontalPad, 16 + bottomPad),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _PartnerHeader(
            brandBlue: widget.brandBlue,
            brandTeal: widget.brandTeal,
          ),
          const SizedBox(height: 12),
          if (_lastUpdate != null)
            Text(
              'Atualizado às ${DateFormat('HH:mm').format(_lastUpdate!)}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          const SizedBox(height: 12),
          _buildPeriodFilter(),
          const SizedBox(height: 20),
          FutureBuilder<AdminPartnerStats>(
            future: _statsFuture,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: SkeletonListLoader(itemCount: 5, itemHeight: 88),
                );
              }
              if (snap.hasError) {
                return _errorCard(snap.error.toString());
              }
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: SkeletonListLoader(itemCount: 5, itemHeight: 88),
                );
              }
              final stats = snap.data!;
              widget.onStatsLoaded?.call(
                stats.licensesExpired,
                stats.licensesExpiring7d,
              );
              if (_lastUpdate == null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _lastUpdate = DateTime.now());
                });
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (stats.licensesExpired > 0 ||
                      stats.licensesExpiring7d > 0) ...[
                    AdminAlertCenterPanel(
                      items: [
                        AdminAlertItem(
                          id: 'licencas_vencidas',
                          title: 'Licenças vencidas',
                          subtitle: 'Toque para ver usuários',
                          icon: Icons.event_busy_rounded,
                          color: const Color(0xFFEF4444),
                          count: stats.licensesExpired,
                        ),
                        AdminAlertItem(
                          id: 'licencas_vencendo_7',
                          title: 'Vencem em 7 dias',
                          subtitle: 'Toque para ver usuários',
                          icon: Icons.schedule_rounded,
                          color: const Color(0xFFF97316),
                          count: stats.licensesExpiring7d,
                        ),
                      ],
                      onNavigate: widget.onAlertNavigate,
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text(
                    'Sua parte · ${AppBrand.idealizerName}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: widget.brandTeal,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _PartnerMetricCard(
                        label: 'Recebido bruto',
                        value: fmt.format(stats.partnerGross),
                        color: const Color(0xFF10B981),
                        icon: Icons.payments_rounded,
                        onTap: () =>
                            widget.onNavigate(AdminMenuItem.mercadopago),
                      ),
                      _PartnerMetricCard(
                        label: 'Recebido líquido',
                        value: fmt.format(stats.partnerNet),
                        subValue:
                            'PIX ${fmt.format(stats.partnerPixNet)} · Cartão ${fmt.format(stats.partnerCardNet)}',
                        color: const Color(0xFF059669),
                        icon: Icons.account_balance_wallet_rounded,
                        onTap: () =>
                            widget.onNavigate(AdminMenuItem.mercadopago),
                      ),
                      _PartnerMetricCard(
                        label: 'Usuários',
                        value: '${stats.totalUsers}',
                        color: widget.brandBlue,
                        icon: Icons.people_rounded,
                        onTap: () => widget.onNavigate(AdminMenuItem.usuarios),
                      ),
                      _PartnerMetricCard(
                        label: 'Premium',
                        value: '${stats.totalPremiums}',
                        color: widget.brandTeal,
                        icon: Icons.star_rounded,
                        onTap: () => widget.onNavigate(AdminMenuItem.usuarios),
                      ),
                      _PartnerMetricCard(
                        label: 'Lic. vencidas',
                        value: '${stats.licensesExpired}',
                        color: const Color(0xFFEA580C),
                        icon: Icons.event_busy_rounded,
                        onTap: () => widget.onNavigate(AdminMenuItem.usuarios),
                      ),
                      _PartnerMetricCard(
                        label: 'Vencem em 7d',
                        value: '${stats.licensesExpiring7d}',
                        color: const Color(0xFFF59E0B),
                        icon: Icons.timer_rounded,
                        onTap: () => widget.onNavigate(AdminMenuItem.usuarios),
                      ),
                      _PartnerMetricCard(
                        label: 'Acessos: domínio',
                        value: 'Ver gráficos',
                        color: const Color(0xFF8B5CF6),
                        icon: Icons.analytics_rounded,
                        onTap: () =>
                            widget.onNavigate(AdminMenuItem.acessosDominio),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _PartnerForecastPanel(
                    totalPremiums: stats.totalPremiums,
                    partnerGrossRealized: stats.partnerGross,
                    partnerSharePercent: stats.partnerSharePercent,
                  ),
                  if (stats.partnerGrossByBucket.any((v) => v > 0)) ...[
                    const SizedBox(height: 20),
                    _PartnerRevenueChart(
                      values: stats.partnerGrossByBucket,
                      labels: stats.bucketLabels,
                      color: widget.brandTeal,
                      onTap: () =>
                          widget.onNavigate(AdminMenuItem.mercadopago),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _errorCard(String message) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Column(
        children: [
          Icon(Icons.error_outline_rounded,
              size: 48, color: Colors.orange.shade700),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodFilter() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Período:',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: Colors.grey.shade700)),
        ..._periodOptions.map((d) {
          final selected = _periodDays == d;
          final label = d == 365 ? '12 meses' : '$d dias';
          return FilterChip(
            label: Text(label),
            selected: selected,
            onSelected: (_) {
              setState(() => _periodDays = d);
              _reload();
            },
            selectedColor: widget.brandBlue.withValues(alpha: 0.2),
            checkmarkColor: widget.brandBlue,
          );
        }),
      ],
    );
  }
}

class _PartnerHeader extends StatelessWidget {
  final Color brandBlue;
  final Color brandTeal;

  const _PartnerHeader({required this.brandBlue, required this.brandTeal});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [brandBlue, brandTeal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: brandBlue.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.handshake_rounded,
                color: Colors.white, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Painel ${AppBrand.idealizerName}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Visualização · usuários · recebimentos · domínio',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PartnerMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String? subValue;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  const _PartnerMetricCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    required this.onTap,
  this.subValue,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final cardW = w < 380 ? (w - 36) / 2 : 168.0;
    return SizedBox(
      width: cardW,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                colors: [
                  color.withValues(alpha: 0.14),
                  color.withValues(alpha: 0.06),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(height: 8),
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color)),
                const SizedBox(height: 4),
                Text(value,
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: Colors.grey.shade900)),
                if (subValue != null) ...[
                  const SizedBox(height: 4),
                  Text(subValue!,
                      style: TextStyle(
                          fontSize: 10, color: Colors.grey.shade600)),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.touch_app_rounded, size: 13, color: color),
                    const SizedBox(width: 4),
                    Text('Abrir',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: color)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PartnerForecastPanel extends StatelessWidget {
  final int totalPremiums;
  final double partnerGrossRealized;
  final double partnerSharePercent;

  const _PartnerForecastPanel({
    required this.totalPremiums,
    required this.partnerGrossRealized,
    required this.partnerSharePercent,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MpCheckoutPricingSnapshot>(
      stream: MpCheckoutPricingService.watch(),
      builder: (context, priceSnap) {
        final monthly = priceSnap.data?.premiumMonthly ??
            MpCheckoutPricingSnapshot.defaults().premiumMonthly;
        final partnerShare = partnerSharePercent / 100;
        final forecast = totalPremiums * monthly * partnerShare;
        final gap = forecast - partnerGrossRealized;
        final fmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.25)),
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
                      'Previsão vs recebido (sua parte)',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '$totalPremiums premium(s) × ${fmt.format(monthly)} × ${partnerSharePercent.toStringAsFixed(0)}%',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _miniMetric(
                      'Previsto',
                      fmt.format(forecast),
                      Colors.blue.shade700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _miniMetric(
                      'Realizado',
                      fmt.format(partnerGrossRealized),
                      Colors.green.shade700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _miniMetric(
                      gap >= 0 ? 'A receber' : 'Acima',
                      fmt.format(gap.abs()),
                      gap >= 0 ? Colors.orange.shade800 : Colors.teal.shade700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _miniMetric(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade700)),
          Text(value,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

class _PartnerRevenueChart extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final Color color;
  final VoidCallback onTap;

  const _PartnerRevenueChart({
    required this.values,
    required this.labels,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final maxY = values.fold<double>(0, (a, b) => a > b ? a : b);
    final spots = values
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.show_chart_rounded, color: color),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Recebimentos no período (bruto · sua parte)',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                  ),
                  Icon(Icons.touch_app_rounded, size: 16, color: color),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 160,
                child: LineChart(
                  LineChartData(
                    minY: 0,
                    maxY: maxY <= 0 ? 1 : maxY * 1.15,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: maxY > 0 ? maxY / 4 : 1,
                    ),
                    titlesData: FlTitlesData(
                      leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: (values.length / 4).ceilToDouble().clamp(1, 999),
                          getTitlesWidget: (v, meta) {
                            final i = v.toInt();
                            if (i < 0 || i >= labels.length) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(labels[i],
                                  style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.grey.shade600)),
                            );
                          },
                        ),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        color: color,
                        barWidth: 3,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          color: color.withValues(alpha: 0.12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
