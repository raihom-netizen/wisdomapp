import 'package:flutter/material.dart';

import '../models/weekly_summary_ui_data.dart';
import '../theme/app_colors.dart';
import '../theme/theme_context.dart';

/// Corpo do resumo semanal — financeiro (WISDOMAPP).
class WeeklySummaryPremiumBody extends StatelessWidget {
  final WeeklySummaryUiData data;

  const WeeklySummaryPremiumBody({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Semana ${data.weekRangeLabel}',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: context.isDarkMode
                ? context.appTextPrimary
                : const Color(0xFF0F172A),
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 14),
        _sectionTitle(context, 'Financeiro'),
        const SizedBox(height: 8),
        _twoCol(
          _miniCard(context, 'Contas a pagar', '${data.despesasPendentesCount} · ${data.despesasPendentesValor}', const Color(0xFFEA580C)),
          _miniCard(context, 'Pago (desp.)', data.despesasPagasValor, AppColors.financeDespesa),
        ),
        const SizedBox(height: 8),
        _twoCol(
          _miniCard(context, 'A receber', '${data.receitasPendentesCount} · ${data.receitasPendentesValor}', const Color(0xFFCA8A04)),
          _miniCard(context, 'Recebido', data.receitasRecebidasValor, AppColors.financeReceita),
        ),
        const SizedBox(height: 8),
        _twoCol(
          _miniCard(context, 'Saldo acumulado', data.saldoAcumulado, AppColors.deepBlue),
          _miniCard(context, 'Saldo período', data.saldoPeriodo, AppColors.primary),
        ),
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String t) {
    return Text(
      t.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.9,
        color: context.appTextMuted,
      ),
    );
  }

  Widget _twoCol(Widget a, Widget b) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: a),
        const SizedBox(width: 8),
        Expanded(child: b),
      ],
    );
  }

  Widget _miniCard(
    BuildContext context,
    String title,
    String value,
    Color accent, {
    bool fullWidth = false,
  }) {
    final w = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: context.isDarkMode ? 0.20 : 0.12),
            context.isDarkMode ? context.appSurface : Colors.white,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: accent.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: accent,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
    if (fullWidth) return w;
    return w;
  }
}
