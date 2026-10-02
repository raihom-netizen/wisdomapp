import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../constants/currency_formats.dart';
import '../theme/theme_context.dart';

/// Um ponto da série: [chave] `aaaa-mm` (destaca o mês corrente) e os dois
/// valores lado a lado.
typedef FinanceBarraPonto = ({String chave, String rotulo, double a, double b});

/// Barras duplas mês a mês no padrão do módulo Financeiro — degradê verde ×
/// vermelho, grade discreta, tooltip escuro em R$ e o mês que está correndo
/// em neón. Usado nos gráficos do Financeiro e nos relatórios do Meu banco
/// (Finance Pro), para os dois terem a mesma cara.
class FinanceBarrasDuplas extends StatelessWidget {
  const FinanceBarrasDuplas({
    super.key,
    required this.serie,
    this.rotuloA = 'Receitas',
    this.rotuloB = 'Despesas',
    this.gradienteA = const [Color(0xFF15803D), Color(0xFF22C55E)],
    this.gradienteB = const [Color(0xFFB91C1C), Color(0xFFEF4444)],
    this.textoVazio = 'Sem lançamentos no período.',
  });

  final List<FinanceBarraPonto> serie;
  final String rotuloA;
  final String rotuloB;

  /// Do pé para o topo da barra.
  final List<Color> gradienteA;
  final List<Color> gradienteB;
  final String textoVazio;

  /// `aaaa-mm` → `mm/aa` (rótulo curto do eixo).
  static String rotuloMes(String chave) =>
      chave.length >= 7 ? '${chave.substring(5, 7)}/${chave.substring(2, 4)}' : chave;

  @override
  Widget build(BuildContext context) {
    final maior = serie.map((m) => math.max(m.a, m.b)).fold<double>(0, (x, y) => y > x ? y : x);
    if (serie.isEmpty || maior <= 0) {
      return Center(
        child: Text(textoVazio,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: context.appTextSecondary)),
      );
    }
    final agora = DateTime.now();
    final chaveAtual = '${agora.year}-${agora.month.toString().padLeft(2, '0')}';
    // Muitos meses: barras mais finas para caber no celular.
    final largura = serie.length > 8 ? 10.0 : 16.0;

    return BarChart(
      BarChartData(
        maxY: maior * 1.2,
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(color: context.appBorderSubtle, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF0F172A),
            getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
              '${serie[gi].rotulo}\n${ri == 0 ? rotuloA : rotuloB}\n'
              '${CurrencyFormats.formatBRL(rod.toY)}',
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11),
            ),
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          topTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= serie.length) return const SizedBox.shrink();
                // O mês que está correndo aparece em neón: é o que a pessoa
                // quer comparar com os outros.
                final atual = serie[i].chave == chaveAtual;
                return Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(serie[i].rotulo,
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: atual ? FontWeight.w900 : FontWeight.w700,
                          color: atual ? context.appNeon : context.appTextSecondary)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < serie.length; i++)
            BarChartGroupData(
              x: i,
              barsSpace: 4,
              barRods: [
                BarChartRodData(
                  toY: serie[i].a,
                  gradient: LinearGradient(
                      begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: gradienteA),
                  width: largura,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                ),
                BarChartRodData(
                  toY: serie[i].b,
                  gradient: LinearGradient(
                      begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: gradienteB),
                  width: largura,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
