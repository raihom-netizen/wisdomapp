import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../constants/currency_formats.dart';
import '../theme/theme_context.dart';
import '../utils/finance_transactions_realtime.dart';
import '../utils/fixas_resumo.dart';
import 'categorias_painel.dart' show ComparativoPeriodo;
import 'categorias_rosca_moderna.dart';
import 'periodo_campos.dart';

Color _clarear(Color c, double t) => Color.lerp(c, Colors.white, t)!;
Color _escurecer(Color c, double t) => Color.lerp(c, Colors.black, t)!;

/// Visão geral das FIXAS no topo de «Despesas fixas» / «Receitas fixas».
///
/// Período: mês atual, 3 meses (este + 2 próximos), anual (mês a mês) ou um
/// intervalo escolhido no calendário ou digitado. Mostra o total, o pago × a
/// vencer, o gráfico e o rateio por categoria — abaixo dele continua a lista
/// das fixas cadastradas, para editar e adicionar.
///
/// É stream: pagar, editar ou cadastrar uma fixa atualiza o gráfico sozinho.
class FixasVisaoGeral extends StatefulWidget {
  const FixasVisaoGeral({
    super.key,
    required this.uid,
    required this.receita,
    this.pendentes = false,
    this.excluirContas = const {},
    this.margem = const EdgeInsets.fromLTRB(16, 12, 16, 4),
  });

  /// Dentro de uma lista que já tem recuo lateral, o painel não soma o dele.
  final EdgeInsets margem;

  final String uid;
  final bool receita;

  /// Modo «contas pendentes»: entra TODA pendente (fixa ou avulsa), e a
  /// divisão é vencido × a vencer — pago × a pagar não diz nada quando tudo
  /// ali ainda está em aberto.
  final bool pendentes;

  /// Contas de cartão: compra no cartão é fatura, não conta pendente.
  final Set<String> excluirContas;

  @override
  State<FixasVisaoGeral> createState() => _FixasVisaoGeralState();
}

class _FixasVisaoGeralState extends State<FixasVisaoGeral> {
  // Abre no MÊS ATUAL (pedido do dono, 30/09/2026): a pessoa vê o que tem no
  // mês; «3 meses», «Anual» e «Período» continuam no seletor.
  late FixasPeriodo _periodo = FixasPeriodo.mesAtual;

  /// Nas pendentes: «Em aberto» (só o que falta pagar: vencido × a vencer) ou
  /// «Previsão do mês» (tudo do período, pago + a pagar = quanto sai no mês).
  bool _previsao = false;

  /// Modo «em aberto» de verdade (pendentes e não na previsão).
  bool get _emAberto => widget.pendentes && !_previsao;
  DateTime? _de;
  DateTime? _ate;
  late Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _stream;

  static const _meses = [
    'jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez',
  ];

  Color get _cor => widget.receita ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
  Color get _corClara => widget.receita ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5);

  ({DateTime de, DateTime ate}) get _intervalo =>
      fixasIntervalo(_periodo, de: _de, ate: _ate);

  @override
  void initState() {
    super.initState();
    _abrir();
  }

  void _abrir() {
    final r = _intervalo;
    _stream = financeTransactionsPeriodDocs(uid: widget.uid, rangeStart: r.de, rangeEnd: r.ate);
  }

  void _mudar(FixasPeriodo p) {
    setState(() {
      _periodo = p;
      _abrir();
    });
  }

  /// «Período»: mostra os campos de data aqui mesmo (digitar ou tocar no
  /// calendário padrão do app) em vez de abrir um seletor de tela inteira.
  void _escolherPeriodo() {
    final r = _intervalo;
    setState(() {
      _periodo = FixasPeriodo.personalizado;
      _de ??= r.de;
      _ate ??= r.ate;
      _abrir();
    });
  }

  void _aplicarIntervalo(DateTime de, DateTime ate) {
    setState(() {
      _periodo = FixasPeriodo.personalizado;
      _de = de;
      _ate = ate;
      _abrir();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ctx = context;
    return Container(
      margin: widget.margem,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: ctx.appSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _cor.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(color: _cor.withValues(alpha: 0.10), blurRadius: 18, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.pendentes) ...[
            _modoPendentes(ctx),
            const SizedBox(height: 10),
          ],
          _seletor(ctx),
          if (_periodo == FixasPeriodo.personalizado && _de != null) ...[
            const SizedBox(height: 10),
            PeriodoCampos(de: _de!, ate: _ate!, cor: _cor, onAplicar: _aplicarIntervalo),
          ],
          const SizedBox(height: 12),
          StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
            stream: _stream,
            builder: (context, snap) {
              if (snap.hasError) {
                return _aviso(ctx, 'Não consegui carregar o período.');
              }
              if (!snap.hasData) {
                return const SizedBox(
                  height: 180,
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              final r = _intervalo;
              final hoje = DateTime.now();
              final inicioHoje = DateTime(hoje.year, hoje.month, hoje.day);
              var linhas = fixasDosDocs(
                snap.data!.map((d) => d.data()),
                receita: widget.receita,
                data: (o) => o is Timestamp ? o.toDate() : DateTime.now(),
                somenteFixas: !widget.pendentes,
                somentePendentes: _emAberto,
                excluirContas: widget.excluirContas,
              ).where((l) => !l.data.isBefore(r.de) && !l.data.isAfter(r.ate)).toList();
              if (_emAberto) {
                // Nas pendentes a parte «cheia» da barra é o que já VENCEU.
                linhas = linhas
                    .map((l) => FixaLinha(
                          data: l.data,
                          valor: l.valor,
                          pago: l.data.isBefore(inicioHoje),
                          categoria: l.categoria,
                          fixaId: l.fixaId,
                          descricao: l.descricao,
                          controle: l.controle,
                          conferidoNoBanco: l.conferidoNoBanco,
                        ))
                    .toList();
              }
              return _conteudo(ctx, linhas, r.de, r.ate);
            },
          ),
        ],
      ),
    );
  }

  /// «⏳ Em aberto» × «🔮 Previsão do mês» — dois botões grandes lado a lado.
  Widget _modoPendentes(BuildContext ctx) {
    Widget botao(bool previsao, IconData icone, String titulo, String sub) {
      final sel = _previsao == previsao;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() {
            _previsao = previsao;
            _abrir();
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              gradient: sel
                  ? LinearGradient(colors: [_cor, _cor.withValues(alpha: 0.78)])
                  : null,
              color: sel ? null : _cor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _cor.withValues(alpha: sel ? 0 : 0.35)),
            ),
            child: Row(
              children: [
                Icon(icone, size: 20, color: sel ? Colors.white : _cor),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titulo,
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13.5,
                              color: sel ? Colors.white : ctx.appTextPrimary)),
                      Text(sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11,
                              color: sel ? Colors.white.withValues(alpha: 0.9) : ctx.appTextSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        botao(false, Icons.hourglass_bottom_rounded, 'Em aberto', 'o que falta pagar'),
        const SizedBox(width: 10),
        botao(true, Icons.auto_graph_rounded, 'Previsão do mês', 'pago + a pagar'),
      ],
    );
  }

  Widget _seletor(BuildContext ctx) {
    Widget chip(String rotulo, FixasPeriodo p, {VoidCallback? onTap}) {
      final sel = _periodo == p;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(rotulo),
          selected: sel,
          onSelected: (_) => (onTap ?? () => _mudar(p))(),
          labelStyle: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
            color: sel ? Colors.white : ctx.appTextPrimary,
          ),
          selectedColor: _cor,
          showCheckmark: false,
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        chip('Mês atual', FixasPeriodo.mesAtual),
        chip('Mês anterior', FixasPeriodo.mesAnterior),
        chip('3 meses', FixasPeriodo.tresMeses),
        chip('Anual', FixasPeriodo.anual),
        chip(
          'Período',
          FixasPeriodo.personalizado,
          onTap: _escolherPeriodo,
        ),
      ]),
    );
  }

  Widget _conteudo(BuildContext ctx, List<FixaLinha> linhas, DateTime de, DateTime ate) {
    final pago = linhas.where((l) => l.pago).fold<double>(0, (a, l) => a + l.valor);
    final aVencer = linhas.where((l) => !l.pago).fold<double>(0, (a, l) => a + l.valor);
    final total = pago + aVencer;
    final meses = fixasPorMes(linhas, de, ate);
    final cats = fixasPorCategoria(linhas);
    final umMes = meses.length == 1;
    final rotuloPago = _emAberto ? 'Vencido' : (widget.receita ? 'Recebido' : 'Pago');
    final rotuloAVencer = _emAberto
        ? 'A vencer'
        : (widget.receita ? 'A receber' : 'A pagar');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _hero(ctx, total, pago, aVencer, rotuloPago, rotuloAVencer, linhas.length),
        const SizedBox(height: 14),
        if (linhas.isEmpty)
          _aviso(
            ctx,
            _emAberto
                ? 'Nada pendente neste período.'
                : _previsao
                ? 'Nada lançado neste período.'
                : (widget.receita
                    ? 'Nenhuma receita fixa neste período.'
                    : 'Nenhuma despesa fixa neste período.'),
          )
        else if (!umMes)
          _graficoCard(ctx, meses),
        if (cats.isNotEmpty) ...[
          const SizedBox(height: 14),
          _categoriaCard(ctx, cats, linhas, de, ate),
        ],
      ],
    );
  }

  /// Cartão em degradê (padrão dos gráficos modernos do app): valor total em
  /// destaque + pago/a vencer como mini-cartões de vidro.
  Widget _hero(BuildContext ctx, double total, double pago, double aVencer, String rotuloPago,
      String rotuloAVencer, int qtd) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [_clarear(_cor, 0.08), _cor, _escurecer(_cor, 0.28)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(color: _cor.withValues(alpha: 0.32), blurRadius: 16, offset: const Offset(0, 7)),
        ],
      ),
      child: Stack(children: [
        Positioned(
          top: -36,
          right: -24,
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                Colors.white.withValues(alpha: 0.22),
                Colors.white.withValues(alpha: 0.0),
              ]),
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(widget.receita ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                  color: Colors.white.withValues(alpha: 0.85), size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _previsao
                      ? (widget.receita ? 'Previsão de receitas no período' : 'Previsão de despesas no período')
                      : widget.pendentes
                      ? (widget.receita ? 'A receber no período' : 'A pagar no período')
                      : (widget.receita ? 'Receitas fixas no período' : 'Despesas fixas no período'),
                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85), fontWeight: FontWeight.w700),
                ),
              ),
              Text('$qtd lanç.', style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.75))),
            ]),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                CurrencyFormats.formatBRL(total),
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.6),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _miniHero(rotuloPago, pago)),
              const SizedBox(width: 8),
              Expanded(child: _miniHero(rotuloAVencer, aVencer)),
            ]),
          ],
        ),
      ]),
    );
  }

  Widget _miniHero(String rotulo, double valor) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(rotulo.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white.withValues(alpha: 0.8), letterSpacing: 0.4)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(CurrencyFormats.formatBRL(valor),
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900, color: Colors.white)),
          ),
        ]),
      );

  /// Moldura em degradê leve ao redor do gráfico mês a mês — mesmo padrão da
  /// fatura do cartão (Container gradiente + ClipRRect por dentro).
  Widget _graficoCard(BuildContext ctx, List<FixaMes> meses) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [_cor.withValues(alpha: 0.16), _corClara.withValues(alpha: 0.06)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: Container(
          width: double.infinity,
          color: ctx.appSurface,
          padding: const EdgeInsets.fromLTRB(10, 14, 14, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(height: 170, child: _grafico(ctx, meses)),
          ]),
        ),
      ),
    );
  }

  /// Cartão «Por categoria»: mesmo painel Ícones · Pizza · Barras (e
  /// Comparativo, quando há lançamentos para desenhar) do Financeiro —
  /// totais idênticos aos já calculados por [fixasPorCategoria], só a
  /// apresentação muda (pedido de 22/09/2026: padronizar o gráfico).
  Widget _categoriaCard(
    BuildContext ctx,
    List<({String categoria, double total, int quantidade})> cats,
    List<FixaLinha> linhas,
    DateTime de,
    DateTime ate,
  ) {
    final fatias = [
      for (final c in cats)
        CategoriaFatia(nome: c.categoria, valor: c.total, qtd: c.quantidade, categoriaReal: c.categoria),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: context.appModuleCardDecoration(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [_cor, _escurecer(_cor, 0.2)]),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(Icons.donut_large_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Text('Por categoria',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900, color: ctx.appTextPrimary)),
          ]),
          const SizedBox(height: 10),
          CategoriasRoscaModerna(
            titulo: widget.receita ? 'Receitas' : 'Despesas',
            fatias: fatias,
            mesAMes: linhas.isEmpty
                ? null
                : ComparativoPeriodo(
                    // Mesmos lançamentos já filtrados por fixasDosDocs (só
                    // fixas/pendentes conforme o modo da tela) — nada de
                    // dado novo, só reaproveitado no formato do comparativo.
                    lancamentos: [for (final l in linhas) {'amount': l.valor, '_data': l.data}],
                    de: de,
                    ate: ate,
                    dataDe: (d) => d['_data'] as DateTime?,
                    cor: _cor,
                  ),
          ),
        ],
      ),
    );
  }

  /// Barras mês a mês, empilhadas: pago embaixo (cor cheia), a vencer em cima.
  Widget _grafico(BuildContext ctx, List<FixaMes> meses) {
    final maior = meses.fold<double>(0, (a, m) => m.total > a ? m.total : a);
    final agora = DateTime.now();
    return BarChart(
      BarChartData(
        maxY: maior <= 0 ? 1 : maior * 1.08,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(color: ctx.appBorderSubtle, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF0F172A),
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItem: (g, gi, rod, ri) {
              final m = meses[gi];
              return BarTooltipItem(
                '${_meses[m.inicio.month - 1]}/${m.inicio.year % 100}\n'
                '${CurrencyFormats.formatBRL(m.total)}\n'
                '${_emAberto ? 'vencido' : (widget.receita ? 'recebido' : 'pago')} '
                '${CurrencyFormats.formatBRL(m.pago)}',
                const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          topTitles: AxisTitles(
            // Valor de cada mês sempre visível em cima da barra.
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 18,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= meses.length) return const SizedBox.shrink();
                return FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(valorCompactoBarra(meses[i].total),
                      style: TextStyle(fontSize: meses.length > 8 ? 8.5 : 10, fontWeight: FontWeight.w800, color: ctx.appTextPrimary)),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= meses.length) return const SizedBox.shrink();
                final m = meses[i].inicio;
                final atual = m.year == agora.year && m.month == agora.month;
                return Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(_meses[m.month - 1],
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: atual ? FontWeight.w900 : FontWeight.w700,
                        color: atual ? ctx.appNeon : ctx.appTextSecondary,
                      )),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < meses.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: meses[i].total,
                  width: meses.length > 8 ? 12 : 20,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                  rodStackItems: [
                    BarChartRodStackItem(0, meses[i].pago, _cor),
                    BarChartRodStackItem(meses[i].pago, meses[i].total, _corClara),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }


  Widget _aviso(BuildContext ctx, String texto) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text(texto, style: TextStyle(fontSize: 13, color: ctx.appTextSecondary)),
        ),
      );
}
