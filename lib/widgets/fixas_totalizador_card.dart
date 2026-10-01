import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../constants/currency_formats.dart';
import '../constants/finance_category_visuals.dart';
import '../theme/theme_context.dart';
import '../utils/finance_transactions_realtime.dart';
import 'modern_module_ui.dart';

/// Totalizador das fixas cadastradas: quanto somam por mês as que estão
/// valendo (sem data de término ou com término de hoje em diante), a
/// projeção de 12 meses, a maior delas e a pizza por categoria.
/// Pedido do dono (30/09/2026): card moderno, gráfico pizza e valor total.
class FixasTotalizadorCard extends StatefulWidget {
  const FixasTotalizadorCard({super.key, required this.items, required this.receita, this.uid});

  final List<Map<String, dynamic>> items;
  final bool receita;

  /// Com [uid], o total usa o valor LANÇADO no mês atual de cada fixa (quando
  /// existe) — assim bate com «Despesas fixas no período» (dono, 01/10/2026:
  /// a Claro lançada a R$ 89,91 com cadastro de R$ 59,90 dava diferença).
  final String? uid;

  @override
  State<FixasTotalizadorCard> createState() => _FixasTotalizadorCardState();
}

class _Fatia {
  _Fatia(this.nome, this.cor, this.icone);
  final String nome;
  final Color cor;
  final IconData icone;
  double valor = 0;
  int qtd = 0;
}

class _FixasTotalizadorCardState extends State<FixasTotalizadorCard> {
  int _tocada = -1;

  // Stream guardado: nada de .snapshots() inline no StreamBuilder.
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>? _mesStream;

  @override
  void initState() {
    super.initState();
    final uid = widget.uid ?? '';
    if (uid.isNotEmpty) {
      final h = DateTime.now();
      _mesStream = financeTransactionsPeriodDocs(
          uid: uid, rangeStart: DateTime(h.year, h.month, 1), rangeEnd: DateTime(h.year, h.month + 1, 0));
    }
  }

  /// Valor lançado no mês atual por fixa (id da fixa → soma).
  Map<String, double> _valoresDoMes(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final campo = widget.receita ? 'fixedIncomeId' : 'fixedExpenseId';
    final out = <String, double>{};
    for (final d in docs) {
      final m = d.data();
      final id = (m[campo] ?? '').toString();
      if (id.isEmpty) continue;
      out[id] = (out[id] ?? 0) + ((m['amount'] as num?)?.toDouble().abs() ?? 0);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final s = _mesStream;
    if (s == null) return _conteudo(context, const {});
    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: s,
      builder: (context, snap) => _conteudo(context, _valoresDoMes(snap.data ?? const [])),
    );
  }

  static bool _ativa(Map<String, dynamic> e, DateTime hoje) {
    final fim = e['endDate'];
    if (fim is! Timestamp) return true;
    final d = fim.toDate();
    return !DateTime(d.year, d.month, d.day).isBefore(hoje);
  }

  static String _pct(double v, double total) =>
      '${(total > 0 ? v / total * 100 : 0).toStringAsFixed(1).replaceAll('.', ',')}%';

  Widget _conteudo(BuildContext context, Map<String, double> doMes) {
    final receita = widget.receita;
    final diferentes = <String>[];
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    var total = 0.0;
    var ativas = 0;
    var maior = 0.0;
    var maiorNome = '';
    final porCategoria = <String, _Fatia>{};
    for (final e in widget.items) {
      if (!_ativa(e, hoje)) continue;
      final cadastro = (e['amount'] as num?)?.toDouble().abs() ?? 0;
      final lancado = doMes[(e['id'] ?? '').toString()];
      final v = lancado ?? cadastro;
      if (lancado != null && (lancado - cadastro).abs() >= 0.01) {
        final desc = (e['description'] ?? e['category'] ?? '').toString().trim();
        diferentes.add('$desc: ${CurrencyFormats.formatBRL(lancado)} neste mês (cadastro ${CurrencyFormats.formatBRL(cadastro)})');
      }
      ativas++;
      total += v;
      if (v > maior) {
        maior = v;
        final desc = (e['description'] ?? '').toString().trim();
        maiorNome = desc.isNotEmpty ? desc : (e['category'] ?? '').toString();
      }
      final cat = (e['category'] ?? '').toString().trim();
      final nome = cat.isEmpty ? 'Outros' : cat;
      final vis = financeCategoryVisualFor(nome, isIncome: receita);
      final f = porCategoria.putIfAbsent(nome, () => _Fatia(nome, vis.color, vis.icon));
      f.valor += v;
      f.qtd++;
    }
    final fatias = porCategoria.values.toList()..sort((a, b) => b.valor.compareTo(a.valor));
    // Categorias com a mesma cor ficam distintas na pizza.
    const reserva = [
      Color(0xFF6366F1), Color(0xFF14B8A6), Color(0xFFF59E0B), Color(0xFFEC4899),
      Color(0xFF8B5CF6), Color(0xFF0EA5E9), Color(0xFF84CC16), Color(0xFFF97316),
    ];
    final usadas = <int>{};
    final cores = <Color>[];
    for (var i = 0; i < fatias.length; i++) {
      var c = fatias[i].cor;
      if (usadas.contains(c.toARGB32())) c = reserva[i % reserva.length];
      usadas.add(c.toARGB32());
      cores.add(c);
    }
    final encerradas = widget.items.length - ativas;
    final grad = receita
        ? const [Color(0xFF059669), Color(0xFF10B981), Color(0xFF34D399)]
        : const [Color(0xFFB91C1C), Color(0xFFEF4444), Color(0xFFF97316)];
    final rotulo = receita ? 'receitas fixas' : 'despesas fixas';

    Widget chip(IconData i, String t) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(i, size: 14, color: Colors.white),
            const SizedBox(width: 5),
            Text(t, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.white)),
          ]),
        );

    final cabecalho = Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: grad, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.functions_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Total das suas $rotulo',
                style: TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w800, color: Colors.white.withValues(alpha: 0.95))),
          ),
        ]),
        const SizedBox(height: 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(TextSpan(children: [
            TextSpan(
                text: CurrencyFormats.formatBRL(total),
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white)),
            TextSpan(
                text: ' /mês',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white.withValues(alpha: 0.85))),
          ])),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          chip(Icons.check_circle_rounded, '$ativas ${ativas == 1 ? 'ativa' : 'ativas'}'),
          if (encerradas > 0) chip(Icons.event_busy_rounded, '$encerradas encerrada${encerradas == 1 ? '' : 's'}'),
          chip(Icons.calendar_month_rounded, '12 meses: ${CurrencyFormats.formatBRL(total * 12)}'),
          if (maior > 0) chip(Icons.trending_up_rounded, 'Maior: $maiorNome · ${CurrencyFormats.formatBRL(maior)}'),
        ]),
        if (diferentes.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final t in diferentes)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.info_outline_rounded, size: 15, color: Colors.white),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(t,
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.95))),
                ),
              ]),
            ),
        ],
      ]),
    );

    final sel = _tocada >= 0 && _tocada < fatias.length ? fatias[_tocada] : null;
    // Pizza 3D com sombra — mesmo estilo do gráfico «Por categoria» do
    // Financeiro (dono, 01/10/2026): base escura deslocada, fatias com
    // degradê e borda branca, sombra embaixo e centro elevado.
    Color clarear(Color c, double t) => Color.lerp(c, Colors.white, t)!;
    Color escurecer(Color c, double t) => Color.lerp(c, Colors.black, t)!;
    List<PieChartSectionData> secoes({required bool fundo}) => [
          for (var i = 0; i < fatias.length; i++)
            PieChartSectionData(
              value: fatias[i].valor <= 0 ? 0.0001 : fatias[i].valor,
              radius: i == _tocada ? 36 : 28,
              showTitle: !fundo && total > 0 && fatias[i].valor / total >= 0.07,
              title: '${(fatias[i].valor / total * 100).round()}%',
              titleStyle: const TextStyle(
                  color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w900, shadows: [Shadow(blurRadius: 3)]),
              titlePositionPercentageOffset: 0.55,
              gradient: fundo
                  ? null
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [clarear(cores[i], 0.28), cores[i], escurecer(cores[i], 0.18)],
                    ),
              color: fundo ? escurecer(cores[i], 0.42) : cores[i],
              borderSide: fundo ? BorderSide.none : BorderSide(color: Colors.white.withValues(alpha: 0.55), width: 1.2),
            ),
        ];
    final pizza = SizedBox(
      width: 210,
      height: 222,
      child: Stack(alignment: Alignment.topCenter, children: [
        Positioned(
          bottom: 0,
          child: Container(
            width: 170,
            height: 22,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(100),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 18, spreadRadius: 2)],
            ),
          ),
        ),
        Positioned(
          top: 9,
          child: SizedBox(
            width: 210,
            height: 204,
            child: IgnorePointer(
              child: PieChart(
                PieChartData(sectionsSpace: 2.5, centerSpaceRadius: 62, startDegreeOffset: -90, sections: secoes(fundo: true)),
                duration: const Duration(milliseconds: 260),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 210,
          height: 204,
          child: Stack(alignment: Alignment.center, children: [
            PieChart(
              PieChartData(
                sectionsSpace: 2.5,
                centerSpaceRadius: 62,
                startDegreeOffset: -90,
                pieTouchData: PieTouchData(touchCallback: (ev, resp) {
                  if (!ev.isInterestedForInteractions) return;
                  final i = resp?.touchedSection?.touchedSectionIndex ?? -1;
                  if (i != _tocada) setState(() => _tocada = i);
                }),
                sections: secoes(fundo: false),
              ),
              duration: const Duration(milliseconds: 260),
            ),
            Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.appSurface,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.16), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(sel?.nome ?? 'Total',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: context.appTextSecondary)),
                FittedBox(
                  child: Text(CurrencyFormats.formatBRL(sel?.valor ?? total),
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: context.appTextPrimary)),
                ),
                if (sel != null)
                  Text(_pct(sel.valor, total),
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: cores[_tocada])),
              ]),
            ),
          ]),
        ),
      ]),
    );

    final legenda = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < fatias.length; i++)
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _tocada = _tocada == i ? -1 : i),
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: cores[i].withValues(alpha: i == _tocada ? 0.16 : 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cores[i].withValues(alpha: i == _tocada ? 0.55 : 0.18)),
            ),
            child: Row(children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: cores[i], borderRadius: BorderRadius.circular(8)),
                child: Icon(fatias[i].icone, size: 16, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(fatias[i].nome,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: context.appTextPrimary)),
                  const SizedBox(height: 3),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: total > 0 ? fatias[i].valor / total : 0,
                      minHeight: 5,
                      backgroundColor: cores[i].withValues(alpha: 0.12),
                      valueColor: AlwaysStoppedAnimation(cores[i]),
                    ),
                  ),
                ]),
              ),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(CurrencyFormats.formatBRL(fatias[i].valor),
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: context.appTextPrimary)),
                Text('${_pct(fatias[i].valor, total)} · ${fatias[i].qtd}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.appTextSecondary)),
              ]),
            ]),
          ),
        ),
    ]);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: ModernModuleUI.cardBg(context),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: grad[1].withValues(alpha: 0.30)),
          boxShadow: [BoxShadow(color: grad[1].withValues(alpha: 0.16), blurRadius: 18, offset: const Offset(0, 8))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          cabecalho,
          if (fatias.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Icon(Icons.pie_chart_rounded, size: 18, color: grad[1]),
                  const SizedBox(width: 6),
                  Text('Por categoria',
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900, color: context.appTextPrimary)),
                ]),
                const SizedBox(height: 10),
                LayoutBuilder(builder: (context, c) {
                  if (c.maxWidth >= 560) {
                    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      pizza,
                      const SizedBox(width: 18),
                      Expanded(child: legenda),
                    ]);
                  }
                  return Column(children: [pizza, const SizedBox(height: 12), legenda]);
                }),
              ]),
            ),
        ]),
      ),
    );
  }
}
