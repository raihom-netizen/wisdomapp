import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../constants/currency_formats.dart';
import '../theme/theme_context.dart';
import '../utils/finance_transactions_realtime.dart';
import 'categorias_rosca_moderna.dart';
import 'periodo_campos.dart';

/// Período do painel de categorias.
enum PainelPeriodo { mes, tresMeses, ano, personalizado }

/// Painel de categorias com PERÍODO PRÓPRIO (Mês · 3 meses · Ano · Período)
/// e as abas Ícones · Pizza · Barras · Mês a mês. Lê os lançamentos sozinho
/// — não depende do filtro da tela que o mostra.
///
/// [onAbrir] recebe a categoria tocada e o período: o dono abre a lista de
/// lançamentos editável em tela cheia. [onAbrirIntervalo] faz o mesmo para
/// uma barra do comparativo (um dia, uma semana ou um mês).
class CategoriasPainel extends StatefulWidget {
  const CategoriasPainel({
    super.key,
    required this.uid,
    this.contaId,
    this.receitas = false,
    this.onAbrir,
    this.onAbrirIntervalo,
  });

  final String uid;

  /// Só os lançamentos desta conta (ficha do banco). Nulo = todas.
  final String? contaId;

  /// Receitas em vez de despesas.
  final bool receitas;

  final void Function(CategoriaFatia fatia, DateTime de, DateTime ate)? onAbrir;
  final void Function(DateTime de, DateTime ate, String rotulo)? onAbrirIntervalo;

  @override
  State<CategoriasPainel> createState() => _CategoriasPainelState();
}

class _CategoriasPainelState extends State<CategoriasPainel> {
  PainelPeriodo _periodo = PainelPeriodo.mes;
  DateTime _ref = DateTime.now();
  DateTime? _de;
  DateTime? _ate;
  late Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _stream;

  static const _meses = ['Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho', 'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'];

  @override
  void initState() {
    super.initState();
    _abrir();
  }

  ({DateTime de, DateTime ate}) get _intervalo {
    final r = _ref;
    switch (_periodo) {
      case PainelPeriodo.mes:
        return (de: DateTime(r.year, r.month, 1), ate: DateTime(r.year, r.month + 1, 0, 23, 59, 59));
      case PainelPeriodo.tresMeses:
        return (de: DateTime(r.year, r.month - 2, 1), ate: DateTime(r.year, r.month + 1, 0, 23, 59, 59));
      case PainelPeriodo.ano:
        return (de: DateTime(r.year, 1, 1), ate: DateTime(r.year, 12, 31, 23, 59, 59));
      case PainelPeriodo.personalizado:
        final de = _de ?? DateTime(r.year, r.month, 1);
        final ate = _ate ?? DateTime(r.year, r.month + 1, 0);
        return (de: DateTime(de.year, de.month, de.day), ate: DateTime(ate.year, ate.month, ate.day, 23, 59, 59));
    }
  }

  /// Carrega o período e mais 5 meses para trás: o comparativo mensal
  /// precisa de meses anteriores mesmo quando o período é um mês só.
  void _abrir() {
    final r = _intervalo;
    final inicio = DateTime(r.ate.year, r.ate.month - 5, 1);
    _stream = financeTransactionsPeriodDocs(
      uid: widget.uid,
      rangeStart: inicio.isBefore(r.de) ? inicio : r.de,
      rangeEnd: r.ate,
    );
  }

  void _mudar(void Function() f) => setState(() {
        f();
        _abrir();
      });

  void _andar(int delta) => _mudar(() {
        _ref = switch (_periodo) {
          PainelPeriodo.ano => DateTime(_ref.year + delta, _ref.month, 1),
          PainelPeriodo.tresMeses => DateTime(_ref.year, _ref.month + 3 * delta, 1),
          _ => DateTime(_ref.year, _ref.month + delta, 1),
        };
      });

  String get _rotulo {
    final r = _intervalo;
    String dm(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    return switch (_periodo) {
      PainelPeriodo.mes => '${_meses[r.de.month - 1]} ${r.de.year}',
      PainelPeriodo.tresMeses => '${_meses[r.de.month - 1].substring(0, 3)} – ${_meses[r.ate.month - 1].substring(0, 3)} ${r.ate.year}',
      PainelPeriodo.ano => '${r.de.year}',
      PainelPeriodo.personalizado => '${dm(r.de)} – ${dm(r.ate)}',
    };
  }

  bool _doTipo(Map<String, dynamic> d) {
    if ('${d['type']}' != (widget.receitas ? 'income' : 'expense')) return false;
    final c = widget.contaId;
    return c == null || '${d['financeAccountId'] ?? ''}' == c;
  }

  DateTime? _data(Map<String, dynamic> d) {
    final v = d['effectiveDate'] ?? d['paidAt'] ?? d['date'];
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  Widget _seletor(BuildContext context) {
    Widget chip(PainelPeriodo p, String r) {
      final sel = p == _periodo;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: () => _mudar(() {
            _periodo = p;
            if (p == PainelPeriodo.personalizado) {
              final r = _intervalo;
              _de ??= r.de;
              _ate ??= r.ate;
            }
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              gradient: sel ? const LinearGradient(colors: [Color(0xFF0F172A), Color(0xFF334155)]) : null,
              color: sel ? null : context.appChipIdleBg,
              border: Border.all(color: sel ? Colors.transparent : context.appChipIdleBorder),
            ),
            child: Text(r,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w900, color: sel ? Colors.white : context.appTextSecondary)),
          ),
        ),
      );
    }

    final r = _intervalo;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          chip(PainelPeriodo.mes, 'Mês'),
          chip(PainelPeriodo.tresMeses, '3 meses'),
          chip(PainelPeriodo.ano, 'Anual'),
          chip(PainelPeriodo.personalizado, 'Período'),
        ]),
      ),
      const SizedBox(height: 6),
      if (_periodo == PainelPeriodo.personalizado)
        PeriodoCampos(
          de: r.de,
          ate: r.ate,
          onAplicar: (de, ate) => _mudar(() {
            _de = de;
            _ate = ate;
          }),
        )
      else
        Row(children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Anterior',
            onPressed: () => _andar(-1),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Text(_rotulo,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: context.appTextPrimary)),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Próximo',
            onPressed: () => _andar(1),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: _stream,
      builder: (context, snap) {
        final r = _intervalo;
        final todos = (snap.data ?? const []).map((d) => d.data()).where(_doTipo).toList();
        final doPeriodo = todos.where((d) {
          final q = _data(d);
          return q != null && !q.isBefore(r.de) && !q.isAfter(r.ate);
        }).toList();
        final carregando = !snap.hasData && !snap.hasError;
        return CategoriasRoscaModerna(
          titulo: widget.receitas ? 'Receitas' : 'Despesas',
          cabecalho: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _seletor(context),
            if (carregando) const LinearProgressIndicator(minHeight: 2),
          ]),
          fatias: agruparCategorias(doPeriodo),
          onAbrir: widget.onAbrir == null ? null : (f) => widget.onAbrir!(f, r.de, r.ate),
          mesAMes: ComparativoPeriodo(
            lancamentos: todos,
            de: r.de,
            ate: r.ate,
            dataDe: _data,
            cor: widget.receitas ? const Color(0xFF10B981) : const Color(0xFFEF4444),
            onAbrir: widget.onAbrirIntervalo,
          ),
        );
      },
    );
  }
}

/// Agrupamento do comparativo.
enum Granularidade { dia, semana, mes }

/// Comparativo em barras 3D: por DIA, por SEMANA ou MÊS A MÊS. O mensal
/// mostra os meses do período (ou os 6 últimos, quando o período é um mês
/// só). Tocar numa barra abre os lançamentos daquele intervalo.
class ComparativoPeriodo extends StatefulWidget {
  const ComparativoPeriodo({
    super.key,
    required this.lancamentos,
    required this.de,
    required this.ate,
    required this.dataDe,
    this.cor = const Color(0xFFEF4444),
    this.onAbrir,
  });

  final List<Map<String, dynamic>> lancamentos;
  final DateTime de;
  final DateTime ate;
  final DateTime? Function(Map<String, dynamic>) dataDe;
  final Color cor;
  final void Function(DateTime de, DateTime ate, String rotulo)? onAbrir;

  @override
  State<ComparativoPeriodo> createState() => _ComparativoPeriodoState();
}

class _ComparativoPeriodoState extends State<ComparativoPeriodo> {
  Granularidade _g = Granularidade.mes;
  int _tocada = -1;
  static const _mesesCurtos = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];

  List<({String rotulo, DateTime de, DateTime ate, double valor})> get _baldes {
    final out = <({String rotulo, DateTime de, DateTime ate, double valor})>[];
    final de = widget.de, ate = widget.ate;
    switch (_g) {
      case Granularidade.dia:
        var d = DateTime(de.year, de.month, de.day);
        var n = 0;
        while (!d.isAfter(ate) && n < 62) {
          out.add((rotulo: '${d.day}/${d.month}', de: d, ate: DateTime(d.year, d.month, d.day, 23, 59, 59), valor: 0));
          d = DateTime(d.year, d.month, d.day + 1);
          n++;
        }
      case Granularidade.semana:
        var d = DateTime(de.year, de.month, de.day);
        d = d.subtract(Duration(days: d.weekday - 1)); // segunda-feira
        var n = 0;
        while (!d.isAfter(ate) && n < 60) {
          final fim = DateTime(d.year, d.month, d.day + 6, 23, 59, 59);
          out.add((rotulo: '${d.day}/${d.month}', de: d, ate: fim, valor: 0));
          d = DateTime(d.year, d.month, d.day + 7);
          n++;
        }
      case Granularidade.mes:
        final meses = (ate.year - de.year) * 12 + ate.month - de.month + 1;
        final qtd = math.max(meses, 6);
        for (var i = qtd - 1; i >= 0; i--) {
          final m = DateTime(ate.year, ate.month - i, 1);
          out.add((
            rotulo: '${_mesesCurtos[m.month - 1]}${m.month == 1 || i == qtd - 1 ? '/${m.year % 100}' : ''}',
            de: m,
            ate: DateTime(m.year, m.month + 1, 0, 23, 59, 59),
            valor: 0,
          ));
        }
    }
    final valores = List<double>.filled(out.length, 0);
    for (final l in widget.lancamentos) {
      final q = widget.dataDe(l);
      if (q == null) continue;
      for (var i = 0; i < out.length; i++) {
        if (!q.isBefore(out[i].de) && !q.isAfter(out[i].ate)) {
          valores[i] += ((l['amount'] as num?) ?? 0).toDouble().abs();
          break;
        }
      }
    }
    return [for (var i = 0; i < out.length; i++) (rotulo: out[i].rotulo, de: out[i].de, ate: out[i].ate, valor: valores[i])];
  }

  @override
  Widget build(BuildContext context) {
    final baldes = _baldes;
    final maior = baldes.fold<double>(0, (a, b) => math.max(a, b.valor));
    final comValor = baldes.where((b) => b.valor > 0).toList();
    final media = comValor.isEmpty ? 0.0 : comValor.fold<double>(0, (a, b) => a + b.valor) / comValor.length;
    final cor = widget.cor;
    Widget opc(Granularidade g, String r) {
      final sel = g == _g;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() {
            _g = g;
            _tocada = -1;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: sel ? cor : context.appChipIdleBg,
              border: Border.all(color: sel ? cor : context.appChipIdleBorder),
            ),
            child: Text(r,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: sel ? Colors.white : context.appTextSecondary)),
          ),
        ),
      );
    }

    final larguraBarra = switch (_g) { Granularidade.dia => 16.0, Granularidade.semana => 26.0, Granularidade.mes => 30.0 };
    final passo = larguraBarra + 16;
    final sel = _tocada >= 0 && _tocada < baldes.length ? baldes[_tocada] : null;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        opc(Granularidade.dia, 'Por dia'),
        const SizedBox(width: 6),
        opc(Granularidade.semana, 'Por semana'),
        const SizedBox(width: 6),
        opc(Granularidade.mes, 'Mês a mês'),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        _resumo(context, sel == null ? 'Média' : sel.rotulo, sel?.valor ?? media, cor),
        const SizedBox(width: 8),
        _resumo(context, 'Maior', maior, const Color(0xFF6366F1)),
      ]),
      const SizedBox(height: 10),
      if (maior <= 0)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: Text('Sem lançamentos no período.', style: TextStyle(color: context.appTextMuted))),
        )
      else
        LayoutBuilder(builder: (context, c) {
          final largura = math.max(c.maxWidth, baldes.length * passo);
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: SizedBox(
              width: largura,
              height: 220,
              child: BarChart(
                BarChartData(
                  maxY: maior * 1.18,
                  alignment: BarChartAlignment.spaceAround,
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) => FlLine(color: context.appBorderSubtle, strokeWidth: 1, dashArray: [4, 4]),
                  ),
                  extraLinesData: ExtraLinesData(horizontalLines: [
                    if (media > 0)
                      HorizontalLine(
                        y: media,
                        color: const Color(0xFFF59E0B),
                        strokeWidth: 1.5,
                        dashArray: [6, 4],
                        label: HorizontalLineLabel(
                          show: true,
                          alignment: Alignment.topRight,
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFFD97706)),
                          labelResolver: (_) => 'média',
                        ),
                      ),
                  ]),
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
                          if (i < 0 || i >= baldes.length) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Text(baldes[i].rotulo,
                                style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: i == _tocada ? FontWeight.w900 : FontWeight.w700,
                                    color: i == _tocada ? cor : context.appTextSecondary)),
                          );
                        },
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => const Color(0xFF0F172A),
                      getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
                        '${baldes[gi].rotulo}\n${CurrencyFormats.formatBRL(rod.toY)}',
                        const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11),
                      ),
                    ),
                    touchCallback: (e, r) {
                      final i = r?.spot?.touchedBarGroupIndex;
                      if (i == null) return;
                      if (e is FlTapUpEvent) {
                        setState(() => _tocada = i);
                        final b = baldes[i];
                        if (b.valor > 0) widget.onAbrir?.call(b.de, b.ate, b.rotulo);
                      }
                    },
                  ),
                  barGroups: [
                    for (var i = 0; i < baldes.length; i++)
                      BarChartGroupData(x: i, barRods: [
                        BarChartRodData(
                          toY: baldes[i].valor,
                          width: larguraBarra,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(7), bottom: Radius.circular(2)),
                          // Volume: claro no topo, escuro na base; fundo
                          // até o teto marca a trilha.
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: i == _tocada
                                ? [const Color(0xFFA5B4FC), const Color(0xFF4F46E5)]
                                : [Color.lerp(cor, Colors.white, 0.35)!, cor, Color.lerp(cor, Colors.black, 0.25)!],
                          ),
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: maior * 1.18,
                            color: cor.withValues(alpha: 0.06),
                          ),
                        ),
                      ]),
                  ],
                ),
                duration: const Duration(milliseconds: 350),
              ),
            ),
          );
        }),
      if (widget.onAbrir != null && maior > 0)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Toque numa barra para ver e editar os lançamentos daquele ${switch (_g) {
            Granularidade.dia => 'dia',
            Granularidade.semana => 'semana',
            Granularidade.mes => 'mês',
          }}.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: context.appTextMuted)),
        ),
    ]);
  }

  Widget _resumo(BuildContext context, String rotulo, double valor, Color cor) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: cor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cor.withValues(alpha: 0.35)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(rotulo, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: context.appTextSecondary)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(CurrencyFormats.formatBRL(valor),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: context.appTextPrimary)),
            ),
          ]),
        ),
      );
}
