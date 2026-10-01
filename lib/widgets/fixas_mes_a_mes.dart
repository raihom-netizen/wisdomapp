import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../constants/currency_formats.dart';
import '../constants/finance_category_visuals.dart';
import '../theme/app_colors.dart';
import '../theme/theme_context.dart';
import '../utils/finance_transactions_realtime.dart';
import '../utils/fixas_resumo.dart';
import 'modern_module_ui.dart';
import 'periodo_campos.dart';

// «Quanto eu gasto (ou recebo) de fixa por mês?» — pedido do dono, 30/09/2026.
//
// Dois pedaços:
//  * [FixasPorMesCard]: cartão fixo no topo de Despesas/Receitas fixas com o
//    total do MÊS ATUAL (pago + em aberto), a divisão e a média de 12 meses.
//  * [FixasMesAMesPage]: o relatório — ano mês a mês em barras empilhadas
//    (pago × em aberto), variação contra o mês anterior, total, média, maior
//    mês e os lançamentos filtráveis (Todos / Pagos / Em aberto).
//
// Nenhuma conta nova: tudo sai de [fixasDosDocs] + [fixasPorMes], os mesmos
// números do painel «Visão geral» das fixas.

const _mesesCurtos = [
  'jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez',
];
const _mesesLongos = [
  'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
  'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
];

Color _clarear(Color c, double t) => Color.lerp(c, Colors.white, t)!;
Color _escurecer(Color c, double t) => Color.lerp(c, Colors.black, t)!;

Color _corDe(bool receita) => receita ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
Color _corClaraDe(bool receita) => receita ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5);

String _mesAno(DateTime d) => '${_mesesCurtos[d.month - 1]}/${d.year}';
String _dataCurta(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

List<FixaLinha> _linhasDe(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  bool receita,
  DateTime de,
  DateTime ate,
) {
  return fixasDosDocs(
    docs.map((d) => d.data()),
    receita: receita,
    data: (o) => o is Timestamp ? o.toDate() : DateTime.now(),
  ).where((l) => !l.data.isBefore(de) && !l.data.isAfter(ate)).toList()
    ..sort((a, b) => a.data.compareTo(b.data));
}

// ---------------------------------------------------------------------------
// Cartão do topo
// ---------------------------------------------------------------------------

/// «Suas despesas fixas por mês: R$ X» — tocar abre o relatório no mês atual;
/// o botão «Ver … mês a mês» abre o ano inteiro.
class FixasPorMesCard extends StatefulWidget {
  const FixasPorMesCard({
    super.key,
    required this.uid,
    required this.receita,
    this.margem = const EdgeInsets.fromLTRB(16, 12, 16, 0),
  });

  final String uid;
  final bool receita;
  final EdgeInsets margem;

  @override
  State<FixasPorMesCard> createState() => _FixasPorMesCardState();
}

class _FixasPorMesCardState extends State<FixasPorMesCard> {
  late final ({DateTime de, DateTime ate}) _r = fixasIntervalo(FixasPeriodo.ultimos12Meses);
  // Stream guardado: nada de .snapshots() inline no StreamBuilder.
  late final Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _stream =
      financeTransactionsPeriodDocs(uid: widget.uid, rangeStart: _r.de, rangeEnd: _r.ate);

  Color get _cor => _corDe(widget.receita);

  void _abrir(FixasPeriodo p) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => FixasMesAMesPage(uid: widget.uid, receita: widget.receita, periodoInicial: p),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: widget.margem,
      child: StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        stream: _stream,
        builder: (context, snap) {
          double? totalMes;
          double pago = 0, aberto = 0, media = 0;
          if (snap.hasData) {
            final linhas = _linhasDe(snap.data!, widget.receita, _r.de, _r.ate);
            final meses = fixasPorMes(linhas, _r.de, _r.ate);
            final atual = meses.isEmpty ? null : meses.last;
            pago = atual?.pago ?? 0;
            aberto = atual?.aVencer ?? 0;
            totalMes = atual?.total ?? 0;
            media = FixasEstatisticas.de(meses).media;
          }
          return _cartao(context, totalMes, pago, aberto, media);
        },
      ),
    );
  }

  Widget _cartao(BuildContext ctx, double? totalMes, double pago, double aberto, double media) {
    final agora = DateTime.now();
    final r = widget.receita;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _abrir(FixasPeriodo.mesAtual),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              colors: [_clarear(_cor, 0.06), _cor, _escurecer(_cor, 0.32)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(color: _cor.withValues(alpha: 0.30), blurRadius: 18, offset: const Offset(0, 8)),
            ],
          ),
          child: Stack(children: [
            Positioned(
              top: -40,
              right: -30,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    Colors.white.withValues(alpha: 0.22),
                    Colors.white.withValues(alpha: 0.0),
                  ]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      child: Icon(r ? Icons.savings_rounded : Icons.credit_card_rounded,
                          color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          r ? 'Suas receitas fixas por mês' : 'Suas despesas fixas por mês',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white),
                        ),
                        Text(
                          '${_mesesLongos[agora.month - 1]} de ${agora.year} · pago + em aberto',
                          style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.82)),
                        ),
                      ]),
                    ),
                    Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.9)),
                  ]),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 40,
                    child: totalMes == null
                        ? const Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            ),
                          )
                        : FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              CurrencyFormats.formatBRL(totalMes),
                              style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: -0.6),
                            ),
                          ),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _mini(r ? 'Recebido' : 'Pago', pago)),
                    const SizedBox(width: 6),
                    Expanded(child: _mini('Em aberto', aberto)),
                    const SizedBox(width: 6),
                    Expanded(child: _mini('Média 12 meses', media)),
                  ]),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: _escurecer(_cor, 0.15),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => _abrir(FixasPeriodo.anual),
                      icon: const Icon(Icons.bar_chart_rounded, size: 20),
                      label: Text(
                        r ? 'Ver receitas fixas mês a mês' : 'Ver despesas fixas mês a mês',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _mini(String rotulo, double valor) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.26)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(rotulo.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white.withValues(alpha: 0.82),
                  letterSpacing: 0.3)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(CurrencyFormats.formatBRL(valor),
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: Colors.white)),
          ),
        ]),
      );
}

// ---------------------------------------------------------------------------
// Relatório mês a mês
// ---------------------------------------------------------------------------

/// Relatório «Despesas fixas mês a mês» / «Receitas fixas mês a mês».
class FixasMesAMesPage extends StatefulWidget {
  const FixasMesAMesPage({
    super.key,
    required this.uid,
    required this.receita,
    this.periodoInicial = FixasPeriodo.anual,
  });

  final String uid;
  final bool receita;
  final FixasPeriodo periodoInicial;

  @override
  State<FixasMesAMesPage> createState() => _FixasMesAMesPageState();
}

class _FixasMesAMesPageState extends State<FixasMesAMesPage> {
  late FixasPeriodo _periodo = widget.periodoInicial;
  DateTime? _de;
  DateTime? _ate;
  late Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _stream;

  Color get _cor => _corDe(widget.receita);
  Color get _corClara => _corClaraDe(widget.receita);

  ({DateTime de, DateTime ate}) get _intervalo => fixasIntervalo(_periodo, de: _de, ate: _ate);

  @override
  void initState() {
    super.initState();
    _abrirStream();
  }

  void _abrirStream() {
    final r = _intervalo;
    _stream = financeTransactionsPeriodDocs(uid: widget.uid, rangeStart: r.de, rangeEnd: r.ate);
  }

  void _mudar(FixasPeriodo p) {
    if (p == FixasPeriodo.personalizado) {
      final r = _intervalo;
      setState(() {
        _periodo = p;
        _de ??= r.de;
        _ate ??= r.ate;
        _abrirStream();
      });
      return;
    }
    setState(() {
      _periodo = p;
      _abrirStream();
    });
  }

  void _aplicarIntervalo(DateTime de, DateTime ate) {
    setState(() {
      _periodo = FixasPeriodo.personalizado;
      _de = de;
      _ate = ate;
      _abrirStream();
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.receita;
    return Scaffold(
      backgroundColor: ModernModuleUI.scaffoldBgOf(context),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          r ? 'Receitas fixas mês a mês' : 'Despesas fixas mês a mês',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19, letterSpacing: 0.2),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: AppColors.logoGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 16, offset: Offset(0, 6))],
          ),
        ),
      ),
      body: StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        stream: _stream,
        builder: (context, snap) {
          final rg = _intervalo;
          final carregando = !snap.hasData && !snap.hasError;
          final linhas = snap.hasData ? _linhasDe(snap.data!, r, rg.de, rg.ate) : const <FixaLinha>[];
          final meses = fixasPorMes(linhas, rg.de, rg.ate);
          final est = FixasEstatisticas.de(meses);
          return ListView(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 32 + MediaQuery.paddingOf(context).bottom),
            children: [
              _seletor(context),
              if (_periodo == FixasPeriodo.personalizado && _de != null) ...[
                const SizedBox(height: 10),
                PeriodoCampos(de: _de!, ate: _ate!, cor: _cor, onAplicar: _aplicarIntervalo),
              ],
              const SizedBox(height: 14),
              if (snap.hasError)
                _aviso(context, 'Não consegui carregar o período.')
              else if (carregando)
                const SizedBox(height: 220, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
              else ...[
                _resumo(context, linhas, meses, est, rg.de, rg.ate),
                if (meses.length > 1) ...[
                  const SizedBox(height: 14),
                  _graficoCard(context, meses, est, linhas),
                  const SizedBox(height: 18),
                  _titulo(context, Icons.calendar_view_month_rounded, 'Mês a mês'),
                  const SizedBox(height: 8),
                  for (var i = 0; i < meses.length; i++)
                    _mesTile(context, meses[i], est.variacoes[i], est.media, linhas),
                ],
                const SizedBox(height: 18),
                _titulo(context, Icons.receipt_long_rounded,
                    meses.length == 1 ? 'Lançamentos de ${_mesAno(meses.first.inicio)}' : 'Lançamentos do período'),
                const SizedBox(height: 8),
                FixasLancamentosLista(linhas: linhas, receita: r),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _seletor(BuildContext ctx) {
    Widget chip(String rotulo, FixasPeriodo p) {
      final sel = _periodo == p;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(rotulo),
          selected: sel,
          onSelected: (_) => _mudar(p),
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
        chip('Anual (${DateTime.now().year})', FixasPeriodo.anual),
        chip('Últimos 12 meses', FixasPeriodo.ultimos12Meses),
        chip('Mês atual', FixasPeriodo.mesAtual),
        chip('Mês anterior', FixasPeriodo.mesAnterior),
        chip('3 meses', FixasPeriodo.tresMeses),
        chip('Período', FixasPeriodo.personalizado),
      ]),
    );
  }

  Widget _titulo(BuildContext ctx, IconData icone, String texto) => Row(children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [_cor, _escurecer(_cor, 0.2)]),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icone, color: Colors.white, size: 17),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(texto,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: ctx.appTextPrimary)),
        ),
      ]);

  /// Hero em degradê + três números: média/mês, maior mês, quantidade.
  Widget _resumo(BuildContext ctx, List<FixaLinha> linhas, List<FixaMes> meses, FixasEstatisticas est,
      DateTime de, DateTime ate) {
    final r = widget.receita;
    final pago = meses.fold<double>(0, (a, m) => a + m.pago);
    final aberto = meses.fold<double>(0, (a, m) => a + m.aVencer);
    final umMes = meses.length == 1;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [_clarear(_cor, 0.08), _cor, _escurecer(_cor, 0.28)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [BoxShadow(color: _cor.withValues(alpha: 0.30), blurRadius: 16, offset: const Offset(0, 7))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            umMes
                ? '${r ? 'Receitas fixas' : 'Despesas fixas'} de ${_mesesLongos[meses.first.inicio.month - 1].toLowerCase()}/${meses.first.inicio.year}'
                : '${r ? 'Receitas fixas' : 'Despesas fixas'} · ${_dataCurta(de)} a ${_dataCurta(ate)}',
            style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.88), fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(CurrencyFormats.formatBRL(est.total),
                style: const TextStyle(
                    fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.6)),
          ),
          const SizedBox(height: 10),
          if (est.total > 0) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (pago / est.total).clamp(0.0, 1.0),
                minHeight: 7,
                backgroundColor: Colors.white.withValues(alpha: 0.25),
                valueColor: const AlwaysStoppedAnimation(Colors.white),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(children: [
            Expanded(child: _vidro(r ? 'Recebido' : 'Pago', CurrencyFormats.formatBRL(pago))),
            const SizedBox(width: 8),
            Expanded(child: _vidro(r ? 'A receber' : 'Em aberto', CurrencyFormats.formatBRL(aberto))),
          ]),
        ]),
      ),
      if (!umMes) ...[
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _stat(ctx, Icons.functions_rounded, 'Média por mês', CurrencyFormats.formatBRL(est.media))),
          const SizedBox(width: 8),
          Expanded(
            child: _stat(
              ctx,
              Icons.arrow_upward_rounded,
              'Maior mês',
              est.maior == null ? '—' : CurrencyFormats.formatBRL(est.maior!.total),
              sub: est.maior == null ? null : _mesAno(est.maior!.inicio),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: _stat(ctx, Icons.receipt_rounded, 'Lançamentos', '${linhas.length}')),
        ]),
      ],
    ]);
  }

  Widget _vidro(String rotulo, String valor) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(rotulo.toUpperCase(),
              style: TextStyle(
                  fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white.withValues(alpha: 0.8), letterSpacing: 0.4)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(valor, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900, color: Colors.white)),
          ),
        ]),
      );

  Widget _stat(BuildContext ctx, IconData icone, String rotulo, String valor, {String? sub}) => Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: ctx.appModuleCardDecoration(radius: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icone, size: 14, color: _cor),
            const SizedBox(width: 4),
            Expanded(
              child: Text(rotulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: ctx.appTextSecondary)),
            ),
          ]),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(valor, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: ctx.appTextPrimary)),
          ),
          Text(sub ?? ' ', style: TextStyle(fontSize: 10.5, color: ctx.appTextSecondary)),
        ]),
      );

  Widget _graficoCard(BuildContext ctx, List<FixaMes> meses, FixasEstatisticas est, List<FixaLinha> linhas) {
    final r = widget.receita;
    Widget legenda(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 4),
          Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ctx.appTextSecondary)),
        ]);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [_cor.withValues(alpha: 0.18), _corClara.withValues(alpha: 0.06)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: Container(
          color: ctx.appSurface,
          padding: const EdgeInsets.fromLTRB(10, 12, 14, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 12, runSpacing: 4, children: [
              legenda(_cor, r ? 'Recebido' : 'Pago'),
              legenda(_corClara, r ? 'A receber' : 'Em aberto'),
              legenda(const Color(0xFFF59E0B), 'Média'),
            ]),
            const SizedBox(height: 10),
            SizedBox(height: 210, child: _grafico(ctx, meses, est, linhas)),
            const SizedBox(height: 4),
            Text('Toque numa barra para ver os lançamentos do mês.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: ctx.appTextSecondary)),
          ]),
        ),
      ),
    );
  }

  Widget _grafico(BuildContext ctx, List<FixaMes> meses, FixasEstatisticas est, List<FixaLinha> linhas) {
    final maior = meses.fold<double>(0, (a, m) => m.total > a ? m.total : a);
    final agora = DateTime.now();
    final r = widget.receita;
    return BarChart(
      BarChartData(
        maxY: maior <= 0 ? 1 : maior * 1.08,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(color: ctx.appBorderSubtle, strokeWidth: 1, dashArray: [4, 4]),
        ),
        borderData: FlBorderData(show: false),
        extraLinesData: ExtraLinesData(horizontalLines: [
          if (est.media > 0)
            HorizontalLine(
              y: est.media,
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
        barTouchData: BarTouchData(
          touchCallback: (event, resp) {
            if (event is! FlTapUpEvent) return;
            final i = resp?.spot?.touchedBarGroupIndex;
            if (i == null || i < 0 || i >= meses.length) return;
            _abrirMes(meses[i], linhas);
          },
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF0F172A),
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItem: (g, gi, rod, ri) {
              final m = meses[gi];
              return BarTooltipItem(
                '${_mesAno(m.inicio)}\n'
                '${CurrencyFormats.formatBRL(m.total)}\n'
                '${r ? 'recebido' : 'pago'} ${CurrencyFormats.formatBRL(m.pago)}\n'
                'em aberto ${CurrencyFormats.formatBRL(m.aVencer)}',
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
                  child: Text(_mesesCurtos[m.month - 1],
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
                  width: meses.length > 8 ? 14 : 22,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
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

  /// Linha de um mês: total, barra pago × em aberto e a variação contra o
  /// mês anterior. Na despesa subir é ruim (vermelho); na receita, bom.
  Widget _mesTile(BuildContext ctx, FixaMes m, double? variacao, double media, List<FixaLinha> linhas) {
    final r = widget.receita;
    final agora = DateTime.now();
    final atual = m.inicio.year == agora.year && m.inicio.month == agora.month;
    final futuro = m.inicio.isAfter(DateTime(agora.year, agora.month, 1));
    Widget? badge;
    if (variacao != null && variacao.abs() >= 0.05) {
      final sobe = variacao > 0;
      final bom = r ? sobe : !sobe;
      final c = bom ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(sobe ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 12, color: c),
          const SizedBox(width: 2),
          Text('${variacao.abs().toStringAsFixed(variacao.abs() >= 10 ? 0 : 1).replaceAll('.', ',')}%',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: c)),
        ]),
      );
    } else if (variacao != null) {
      badge = Text('= anterior', style: TextStyle(fontSize: 11, color: ctx.appTextSecondary));
    }
    final frac = m.total <= 0 ? 0.0 : (m.pago / m.total).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: m.total <= 0 ? null : () => _abrirMes(m, linhas),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: ModernModuleUI.cardBg(ctx),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: atual ? _cor.withValues(alpha: 0.7) : _cor.withValues(alpha: 0.16), width: atual ? 1.5 : 1),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Text('${_mesesLongos[m.inicio.month - 1]} ${m.inicio.year}',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: ctx.appTextPrimary)),
                if (atual) ...[
                  const SizedBox(width: 6),
                  _etiqueta('este mês', _cor),
                ] else if (futuro) ...[
                  const SizedBox(width: 6),
                  _etiqueta('previsto', const Color(0xFF6366F1)),
                ],
                const Spacer(),
                if (badge != null) badge,
                const SizedBox(width: 8),
                Text(CurrencyFormats.formatBRL(m.total),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: ctx.appTextPrimary)),
              ]),
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                  value: m.total <= 0 ? 0 : frac,
                  minHeight: 6,
                  backgroundColor: m.total <= 0 ? ctx.appBorderSubtle : _corClara.withValues(alpha: 0.7),
                  valueColor: AlwaysStoppedAnimation(_cor),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                m.total <= 0
                    ? 'Nenhum lançamento de fixa'
                    : '${r ? 'Recebido' : 'Pago'} ${CurrencyFormats.formatBRL(m.pago)} · '
                        'em aberto ${CurrencyFormats.formatBRL(m.aVencer)}',
                style: TextStyle(fontSize: 11.5, color: ctx.appTextSecondary),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _etiqueta(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(8)),
        child: Text(t, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: c)),
      );

  void _abrirMes(FixaMes m, List<FixaLinha> linhas) {
    final doMes = linhas.where((l) => l.data.year == m.inicio.year && l.data.month == m.inicio.month).toList();
    final r = widget.receita;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.appSurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: EdgeInsets.fromLTRB(16, 10, 16, 24 + MediaQuery.paddingOf(ctx).bottom),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: ctx.appBorderSubtle, borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(height: 12),
            Text('${r ? 'Receitas fixas' : 'Despesas fixas'} · ${_mesesLongos[m.inicio.month - 1]} ${m.inicio.year}',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: ctx.appTextPrimary)),
            const SizedBox(height: 2),
            Text(
              'Total ${CurrencyFormats.formatBRL(m.total)} · ${r ? 'recebido' : 'pago'} '
              '${CurrencyFormats.formatBRL(m.pago)} · em aberto ${CurrencyFormats.formatBRL(m.aVencer)}',
              style: TextStyle(fontSize: 12, color: ctx.appTextSecondary),
            ),
            const SizedBox(height: 12),
            FixasLancamentosLista(linhas: doMes, receita: r),
          ],
        ),
      ),
    );
  }

  Widget _aviso(BuildContext ctx, String texto) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text(texto, style: TextStyle(fontSize: 13, color: ctx.appTextSecondary))),
      );
}

// ---------------------------------------------------------------------------
// Lista de lançamentos com filtro
// ---------------------------------------------------------------------------

enum _Filtro { todos, pagos, abertos }

/// Lançamentos das fixas com o filtro «Todos / Pagos / Em aberto» e o status
/// de cada um (pago, vencido ou a pagar). Não rola sozinha: vai dentro de uma
/// lista maior.
class FixasLancamentosLista extends StatefulWidget {
  const FixasLancamentosLista({super.key, required this.linhas, required this.receita});

  final List<FixaLinha> linhas;
  final bool receita;

  @override
  State<FixasLancamentosLista> createState() => _FixasLancamentosListaState();
}

class _FixasLancamentosListaState extends State<FixasLancamentosLista> {
  _Filtro _filtro = _Filtro.todos;

  @override
  Widget build(BuildContext context) {
    final r = widget.receita;
    final cor = _corDe(r);
    final pagos = widget.linhas.where((l) => l.pago).toList();
    final abertos = widget.linhas.where((l) => !l.pago).toList();
    final lista = switch (_filtro) {
      _Filtro.todos => widget.linhas,
      _Filtro.pagos => pagos,
      _Filtro.abertos => abertos,
    };
    final soma = lista.fold<double>(0, (a, l) => a + l.valor);
    final hoje = DateTime.now();
    final inicioHoje = DateTime(hoje.year, hoje.month, hoje.day);

    Widget chip(_Filtro f, String rotulo, int qtd) {
      final sel = _filtro == f;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text('$rotulo ($qtd)'),
          selected: sel,
          onSelected: (_) => setState(() => _filtro = f),
          labelStyle: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
            color: sel ? Colors.white : context.appTextPrimary,
          ),
          selectedColor: cor,
          showCheckmark: false,
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          chip(_Filtro.todos, 'Todos', widget.linhas.length),
          chip(_Filtro.pagos, r ? 'Recebidos' : 'Pagos', pagos.length),
          chip(_Filtro.abertos, 'Em aberto', abertos.length),
        ]),
      ),
      const SizedBox(height: 6),
      Text('${lista.length} lançamento(s) · ${CurrencyFormats.formatBRL(soma)}',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.appTextSecondary)),
      const SizedBox(height: 8),
      if (lista.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: Text('Nada por aqui neste filtro.',
                style: TextStyle(fontSize: 13, color: context.appTextSecondary)),
          ),
        )
      else
        for (final l in lista) _tile(context, l, inicioHoje),
    ]);
  }

  Widget _tile(BuildContext ctx, FixaLinha l, DateTime inicioHoje) {
    final r = widget.receita;
    final vis = financeCategoryVisualFor(l.categoria, isIncome: r);
    final ({String t, Color c}) status = l.pago
        ? (l.controle
            // Finance Pro: paga só como controle (o saldo vem do banco).
            ? (
                t: l.conferidoNoBanco ? 'controle · conferido no banco' : 'controle · saldo pelo banco',
                c: const Color(0xFF7C3AED),
              )
            : (t: r ? 'Recebido' : 'Pago', c: const Color(0xFF16A34A)))
        : l.data.isBefore(inicioHoje)
            ? (t: 'Vencido', c: const Color(0xFFDC2626))
            : (t: r ? 'A receber' : 'A pagar', c: const Color(0xFFD97706));
    final titulo = l.descricao.isNotEmpty ? l.descricao : l.categoria;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: ModernModuleUI.cardBg(ctx),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: vis.color.withValues(alpha: 0.22)),
          boxShadow: [BoxShadow(color: vis.color.withValues(alpha: 0.10), blurRadius: 14, offset: const Offset(0, 5))],
        ),
        child: ListTile(
          visualDensity: VisualDensity.compact,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: financeCategoryLeadingTile(l.categoria, isIncome: r, size: 42),
          title: Text(titulo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w800, color: ctx.appTextPrimary, fontSize: 14)),
          subtitle: Text(
            l.descricao.isNotEmpty ? '${_dataCurta(l.data)} · ${l.categoria}' : _dataCurta(l.data),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: ctx.appTextSecondary),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(CurrencyFormats.formatBRL(l.valor),
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: ctx.appTextPrimary)),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: status.c.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(status.t, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: status.c)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
