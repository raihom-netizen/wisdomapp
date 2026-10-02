import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/currency_formats.dart';
import '../theme/theme_context.dart';
import '../utils/finance_line_opening.dart';
import 'categorias_painel.dart';
import 'categorias_rosca_moderna.dart';
import '../utils/finance_fora_dos_totais.dart';
import 'finance_barras_duplas.dart';

/// Painel de gráficos do Financeiro.
///
/// Três perguntas, três desenhos — e nada além disso. Gráfico que não responde
/// pergunta é enfeite que atrasa a rolagem:
///
///   1. **Como foi o mês?** barras de receita × despesa, mês a mês.
///   2. **Para onde foi o dinheiro?** rosca das categorias de despesa.
///   3. **O saldo está subindo ou caindo?** linha do acumulado.
///
/// No escuro, o destaque é o verde fluorescente do tema: o mês que está
/// correndo, a maior categoria e a linha do saldo. Num fundo grafite é o que
/// puxa o olho para o que importa sem precisar de legenda gritada.
class FinanceGraficosModernos extends StatefulWidget {
  const FinanceGraficosModernos({
    super.key,
    required this.docs,
    this.saldoAbertura = 0,
    this.meses = 6,
    this.onAbrirCategoria,
    this.uid,
    this.onAbrirPeriodo,
  });

  /// Toque numa categoria: abre os lançamentos dela (categoria gravada + período).
  final void Function(String categoria, DateTime de, DateTime ate)? onAbrirCategoria;

  /// Com o uid, a aba Categorias vira o painel completo (período próprio,
  /// Ícones · Pizza · Barras · Comparativo). Sem ele, usa os lançamentos da tela.
  final String? uid;

  /// Toque numa barra do comparativo (dia/semana/mês).
  final void Function(DateTime de, DateTime ate)? onAbrirPeriodo;

  /// Lançamentos do período já carregados pela tela — nada é relido daqui.
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  /// Saldo de onde a linha do acumulado começa.
  final double saldoAbertura;

  final int meses;

  @override
  State<FinanceGraficosModernos> createState() => _FinanceGraficosModernosState();
}

enum _Aba { fluxo, categorias, saldo }

class _FinanceGraficosModernosState extends State<FinanceGraficosModernos> {
  // Padrão: Categorias (pedido de 21/09/2026). A escolha do usuário fica
  // gravada no aparelho e volta na próxima abertura.
  _Aba _aba = _Aba.categorias;
  static const _kChaveAba = 'financeiro_graficos_aba';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final salvo = p.getString(_kChaveAba);
      if (!mounted || salvo == null) return;
      for (final a in _Aba.values) {
        if (a.name == salvo) setState(() => _aba = a);
      }
    }).catchError((_) {});
  }

  void _escolherAba(_Aba a) {
    setState(() => _aba = a);
    SharedPreferences.getInstance().then((p) => p.setString(_kChaveAba, a.name)).catchError((_) => false);
  }

  static const _kVerde = Color(0xFF22C55E);
  static const _kVermelho = Color(0xFFEF4444);

  static const _mesesCurtos = [
    'jan', 'fev', 'mar', 'abr', 'mai', 'jun',
    'jul', 'ago', 'set', 'out', 'nov', 'dez',
  ];

  // ── Leitura dos lançamentos ───────────────────────────────────────────────

  DateTime? _data(Map<String, dynamic> d) {
    final v = d['effectiveDate'] ?? d['paidAt'] ?? d['date'];
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  double _valor(Map<String, dynamic> d) => (d['amount'] as num?)?.toDouble() ?? 0;
  bool _receita(Map<String, dynamic> d) => '${d['type']}' == 'income';

  /// Mês a mês, do mais antigo para o mais novo.
  List<({String chave, String rotulo, double receita, double despesa})> get _porMes {
    final mapa = <String, ({double r, double d})>{};
    for (final doc in widget.docs) {
      final d = doc.data();
      final tipo = '${d['type']}';
      if (tipo != 'income' && tipo != 'expense') continue;
      // Fixa quitada como controle (Finance Pro): o débito do banco já entra.
      if ('${d['status']}' == 'paid' && FinanceLineOpening.foraDoSaldo(d)) continue;
      final quando = _data(d);
      if (quando == null) continue;
      final k = '${quando.year}-${quando.month.toString().padLeft(2, '0')}';
      final atual = mapa[k] ?? (r: 0.0, d: 0.0);
      mapa[k] = _receita(d)
          ? (r: atual.r + _valor(d), d: atual.d)
          : (r: atual.r, d: atual.d + _valor(d));
    }
    final chaves = mapa.keys.toList()..sort();
    final ultimas = chaves.length > widget.meses
        ? chaves.sublist(chaves.length - widget.meses)
        : chaves;
    return ultimas.map((k) {
      final mes = int.tryParse(k.split('-')[1]) ?? 1;
      return (
        chave: k,
        rotulo: _mesesCurtos[(mes - 1).clamp(0, 11)],
        receita: mapa[k]!.r,
        despesa: mapa[k]!.d,
      );
    }).toList();
  }

  /// Saldo acumulado dia a dia, partindo do saldo de abertura.
  List<({DateTime dia, double saldo})> get _acumulado {
    final porDia = <DateTime, double>{};
    for (final doc in widget.docs) {
      final d = doc.data();
      if ('${d['status']}' != 'paid') continue;
      // Quitação de controle (Finance Pro): fora do saldo.
      if (FinanceLineOpening.foraDoSaldo(d)) continue;
      final q = _data(d);
      if (q == null) continue;
      final dia = DateTime(q.year, q.month, q.day);
      porDia[dia] = (porDia[dia] ?? 0) + (_receita(d) ? _valor(d) : -_valor(d));
    }
    final dias = porDia.keys.toList()..sort();
    var saldo = widget.saldoAbertura;
    return dias.map((dia) {
      saldo += porDia[dia]!;
      return (dia: dia, saldo: saldo);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.docs.isEmpty) return const SizedBox.shrink();
    var rec = 0.0, desp = 0.0;
    for (final doc in widget.docs) {
      final d = doc.data();
      final t = '${d['type']}';
      if (financeForaDosTotais(d)) continue; // pagamento de fatura: só no saldo
      if (t == 'income') rec += _valor(d).abs();
      if (t == 'expense') desp += _valor(d).abs();
    }
    final neon = context.appNeon;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      decoration: context.appPanelDecoration(radius: 20, borderAccent: neon, borderAlpha: 0.22),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Faixa de título em degradê com o resumo do período.
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF0F172A), Color(0xFF1E3A8A), Color(0xFF0E7490)]),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.insights_rounded, size: 18, color: Colors.white),
                ),
                const SizedBox(width: 10),
                const Text('Gráficos do período',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Colors.white)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                _pilula('Receitas', rec, _kVerde),
                const SizedBox(width: 8),
                _pilula('Despesas', desp, _kVermelho),
                const SizedBox(width: 8),
                _pilula('Resultado', rec - desp, rec - desp >= 0 ? const Color(0xFF38BDF8) : const Color(0xFFF97316)),
              ]),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                _chip(_Aba.fluxo, 'Mês a mês', Icons.bar_chart_rounded),
                const SizedBox(width: 8),
                _chip(_Aba.categorias, 'Categorias', Icons.donut_large_rounded),
                const SizedBox(width: 8),
                _chip(_Aba.saldo, 'Saldo', Icons.show_chart_rounded),
              ]),
              const SizedBox(height: 14),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: switch (_aba) {
                  _Aba.fluxo => SizedBox(key: const ValueKey('f'), height: 220, child: _grafFluxo()),
                  _Aba.categorias => KeyedSubtree(key: const ValueKey('c'), child: _grafCategorias()),
                  _Aba.saldo => SizedBox(key: const ValueKey('s'), height: 220, child: _grafSaldo()),
                },
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _pilula(String rotulo, double valor, Color cor) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cor.withValues(alpha: 0.55)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(rotulo, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.8))),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(CurrencyFormats.formatBRL(valor),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color.lerp(cor, Colors.white, 0.35))),
            ),
          ]),
        ),
      );

  Widget _chip(_Aba a, String rotulo, IconData icone) {
    final ativo = _aba == a;
    final cor = context.appNeon;
    final texto = ativo ? context.appNeonOn : context.appTextSecondary;
    return Expanded(
      child: Material(
        color: ativo ? cor : context.appChipIdleBg,
        elevation: ativo ? 3 : 0,
        shadowColor: cor.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => _escolherAba(a),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icone, size: 15, color: texto),
              const SizedBox(width: 5),
              Flexible(
                child: Text(rotulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 11.5, color: texto)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ── 1) Mês a mês ──────────────────────────────────────────────────────────

  Widget _grafFluxo() {
    final meses = _porMes;
    // Mesmo desenho dos relatórios do Meu banco (widget compartilhado).
    return FinanceBarrasDuplas(
      serie: [
        for (final m in meses) (chave: m.chave, rotulo: m.rotulo, a: m.receita, b: m.despesa),
      ],
      gradienteA: const [Color(0xFF15803D), _kVerde],
      gradienteB: const [Color(0xFFB91C1C), _kVermelho],
    );
  }

  // ── 2) Categorias ─────────────────────────────────────────────────────────

  Widget _grafCategorias() {
    final uid = widget.uid;
    if (uid != null && uid.isNotEmpty) {
      return CategoriasPainel(
        uid: uid,
        onAbrir: widget.onAbrirCategoria == null ? null : (f, de, ate) => widget.onAbrirCategoria!(f.categoriaReal, de, ate),
        onAbrirIntervalo: widget.onAbrirPeriodo == null ? null : (de, ate, _) => widget.onAbrirPeriodo!(de, ate),
      );
    }
    final fatias = agruparCategorias(
        widget.docs.map((d) => d.data()).where((d) => '${d['type']}' == 'expense'));
    final agora = DateTime.now();
    return CategoriasRoscaModerna(
      fatias: fatias,
      onAbrir: widget.onAbrirCategoria == null
          ? null
          : (f) => widget.onAbrirCategoria!(f.categoriaReal, DateTime(agora.year, agora.month, 1),
              DateTime(agora.year, agora.month + 1, 0)),
    );
  }

  // ── 3) Saldo ──────────────────────────────────────────────────────────────

  Widget _grafSaldo() {
    final pontos = _acumulado;
    if (pontos.length < 2) return _vazio('Preciso de pelo menos dois dias pagos.');

    final valores = pontos.map((p) => p.saldo).toList();
    final menor = valores.reduce(math.min);
    final maior = valores.reduce(math.max);
    final folga = ((maior - menor).abs() * 0.15) + 1;

    return LineChart(
      LineChartData(
        minY: menor - folga,
        maxY: maior + folga,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: context.appBorderSubtle, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          topTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: math.max(1, (pontos.length / 4).floorToDouble()),
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= pontos.length) return const SizedBox.shrink();
                final d = pontos[i].dia;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${d.day}/${d.month}',
                      style: TextStyle(fontSize: 10, color: context.appTextSecondary)),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots.map((s) {
              final p = pontos[s.x.toInt()];
              return LineTooltipItem(
                '${p.dia.day}/${p.dia.month}\n${CurrencyFormats.formatBRL(p.saldo)}',
                const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < pontos.length; i++)
                FlSpot(i.toDouble(), pontos[i].saldo),
            ],
            isCurved: true,
            curveSmoothness: 0.22,
            color: context.appNeon,
            barWidth: 2.6,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  context.appNeon.withValues(alpha: 0.28),
                  context.appNeon.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _vazio(String texto) => Center(
        child: Text(texto,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: context.appTextSecondary)),
      );
}
