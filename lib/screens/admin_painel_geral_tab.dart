import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/admin_painel_geral_service.dart';
import '../services/course_analytics_service.dart';
import '../theme/theme_context.dart';
import '../utils/firestore_reliable_read.dart';
import '../widgets/admin/admin_page_shell.dart';
import '../widgets/admin_menu_lateral.dart' show AdminMenuItem;
import '../utils/admin_load_guard.dart';
import '../widgets/admin/admin_ui_kit.dart';

final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
final _moedaCurta = NumberFormat.compactCurrency(locale: 'pt_BR', symbol: r'R$');
final _dataCurta = DateFormat('dd/MM/yy', 'pt_BR');

const _azul = Color(0xFF2563EB);
const _verde = Color(0xFF16A34A);
const _ambar = Color(0xFFD97706);
const _roxo = Color(0xFF7C3AED);
const _teal = Color(0xFF0D9488);
const _rosa = Color(0xFFDB2777);
const _vermelho = Color(0xFFDC2626);
const _cinza = Color(0xFF475569);

/// Admin — **Painel geral** (padrão «Controle total» do Controle Total App):
/// KPIs por seção, gráficos, receitas & despesas, previsão só de pagantes,
/// engajamento dos cursos e atalhos para cada área do painel.
class AdminPainelGeralTab extends StatefulWidget {
  const AdminPainelGeralTab({
    super.key,
    required this.onAbrir,
    this.podeAbrir,
  });

  /// Abre uma área do painel (mesma rotina do menu, com as permissões).
  final ValueChanged<AdminMenuItem> onAbrir;

  /// Filtra atalhos que o perfil atual não pode abrir.
  final bool Function(AdminMenuItem item)? podeAbrir;

  @override
  State<AdminPainelGeralTab> createState() => _AdminPainelGeralTabState();
}

class _AdminPainelGeralTabState extends State<AdminPainelGeralTab> {
  AdminPainelGeralData? _d;
  List<CourseStatSummary> _cursos = const [];
  Object? _erro;
  var _carregando = true;
  var _verTodosResultado = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      // Com prazo: sem resposta do servidor vira erro com «Tentar de novo»
      // (nunca «Carregando os números…» para sempre).
      final r = await AdminLoadGuard.comPrazo(
        Future.wait<Object?>([
          AdminPainelGeralData.carregar(),
          _carregarCursos(),
        ]),
        prazo: const Duration(seconds: 90),
        oQue: 'os números do painel',
      );
      if (!mounted) return;
      setState(() {
        _d = r[0] as AdminPainelGeralData;
        _cursos = r[1] as List<CourseStatSummary>;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e;
        _carregando = false;
      });
    }
  }

  Future<List<CourseStatSummary>> _carregarCursos() async {
    try {
      final snap = await firestoreQueryGetReliable(
        FirebaseFirestore.instance.collection('course_stats').limit(500),
      );
      final list = snap.docs.map(CourseStatSummary.fromDoc).toList()
        ..sort((a, b) => b.viewCount.compareTo(a.viewCount));
      return list;
    } catch (_) {
      return const [];
    }
  }

  bool _pode(AdminMenuItem i) => widget.podeAbrir?.call(i) ?? true;

  void _abrir(AdminMenuItem i) {
    if (_pode(i)) widget.onAbrir(i);
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: AdminPageShell.listPadding(context, top: 4)
            .copyWith(bottom: 40),
        children: [
          _hero(d),
          if (_erro != null)
            AdminErroCard(
              erro: _erro,
              onTentar: _carregar,
              titulo: d == null
                  ? 'Não foi possível carregar os números'
                  : 'Não deu para atualizar (mostrando os últimos números)',
            ),
          if (d == null && _carregando)
            const AdminCarregando(texto: 'Lendo cadastros e pagamentos…'),
          if (d != null) ...[
            if (d.limiteAtingido)
              _aviso(
                'Mostrando os primeiros ${AdminPainelGeralData.limiteUsuarios} '
                'cadastros — números de usuários podem estar parciais.',
                _ambar,
              ),
            _secao('Usuários', _verde, Icons.people_alt_rounded),
            _grade([
              _kpi('Cadastrados', '${d.totalUsuarios}',
                  '${d.equipe} da equipe', Icons.groups_rounded, _verde,
                  AdminMenuItem.usuarios),
              _kpi('Com acesso ativo', '${d.ativos}',
                  '${_pct(d.ativos, d.totalUsuarios)} da base',
                  Icons.verified_user_rounded, _verde, AdminMenuItem.usuarios),
              _kpi('Em teste grátis', '${d.emTeste}', 'Sem pagamento ainda',
                  Icons.hourglass_top_rounded, _teal, AdminMenuItem.usuarios),
              _kpi('Novos em 30 dias', '${d.novos30}', '${d.novos7} nos últimos 7',
                  Icons.rocket_launch_rounded, _teal, AdminMenuItem.usuarios),
              _kpi('Vencem em 7 dias', '${d.vencendo7}',
                  '${d.emCarencia} em carência',
                  Icons.event_busy_rounded, _ambar, AdminMenuItem.usuarios),
              _kpi('Bloqueados / vencidos', '${d.bloqueados}',
                  'Sem acesso hoje', Icons.lock_clock_rounded, _vermelho,
                  AdminMenuItem.usuarios),
              _kpi('Convênios', '${d.convenio}', 'Usuários por convênio',
                  Icons.handshake_rounded, _azul, AdminMenuItem.convenios),
              _kpi('Usuários 360°', '', 'Tudo de um usuário: uso e pagamentos',
                  Icons.hub_rounded, _verde, AdminMenuItem.usuarios360),
              _kpi('Usaram o app hoje', '${d.acessoHoje}',
                  '${d.acesso7} em 7 dias · ${d.acesso30} em 30 dias',
                  Icons.insights_rounded, _teal, AdminMenuItem.usoModulos),
              _kpi('Uso dos módulos', '',
                  'Quem usa Financeiro, Agenda, Cursos… (servidor)',
                  Icons.dashboard_customize_rounded, _verde,
                  AdminMenuItem.usoModulos),
            ]),
            const SizedBox(height: 12),
            _duasColunas(
              _cartaoGrafico(
                'Cadastros por mês',
                Icons.person_add_alt_1_rounded,
                _verde,
                _barras(
                  d.cadastrosPorMes.map((e) => e.toDouble()).toList(),
                  d.mesesLabels,
                  _verde,
                  inteiro: true,
                ),
              ),
              _cartaoGrafico(
                'Usuários por plano',
                Icons.pie_chart_rounded,
                _roxo,
                _pizzaPlanos(d.porPlano),
              ),
            ),
            _secao('Financeiro', _ambar, Icons.payments_rounded),
            _grade([
              _kpi('Recebido em 30 dias', _moeda.format(d.receita30),
                  'Líquido ${_moeda.format(d.liquido30)} · ${d.pagamentos30} pagamentos',
                  Icons.account_balance_wallet_rounded, _ambar,
                  AdminMenuItem.mercadopago),
              _kpi('Receita recorrente', _moeda.format(d.mrr),
                  '${d.pagantes} pagantes ativos', Icons.autorenew_rounded,
                  _ambar, AdminMenuItem.mercadopago),
              _kpi('Previsão 30 dias', _moeda.format(d.previsao30),
                  'Só pagantes · 90 dias ${_moeda.format(d.previsao90)}',
                  Icons.query_stats_rounded, _verde, AdminMenuItem.mercadopago),
              _kpi(
                'Lucro previsto no mês',
                _moeda.format(d.lucroPrevistoMes),
                'Recebido + renovações − custos',
                Icons.savings_rounded,
                d.lucroPrevistoMes < 0 ? _vermelho : _verde,
                AdminMenuItem.mercadopago,
              ),
              _kpi('Ticket médio', _moeda.format(d.ticketMedio30),
                  'Pagamentos dos últimos 30 dias', Icons.receipt_long_rounded,
                  _ambar, AdminMenuItem.mercadopago),
              _kpi('Cortesia (não pagam)', '${d.cortesia}',
                  'Premium ativo sem pagamento', Icons.card_giftcard_rounded,
                  _rosa, AdminMenuItem.usuarios),
              _kpi('Não renovaram', '${d.naoRenovaram}',
                  'Venceram nos últimos 30 dias', Icons.trending_down_rounded,
                  _vermelho, AdminMenuItem.usuarios),
              _kpi('Promoções', '', 'Cupons e preços especiais',
                  Icons.local_offer_rounded, _ambar, AdminMenuItem.promocoes),
            ]),
            const SizedBox(height: 12),
            _cartaoGrafico(
              'Receita por mês (bruto × líquido)',
              Icons.bar_chart_rounded,
              _ambar,
              _barrasDuplas(d.receitaPorMes, d.liquidoPorMes, d.mesesLabels),
              legenda: const [
                (_ambar, 'Bruto'),
                (_verde, 'Líquido (após taxas MP)'),
              ],
            ),
            _secao('Receitas & despesas do app', _teal,
                Icons.account_balance_rounded),
            _receitasDespesas(d),
            const SizedBox(height: 12),
            _resultadoPorUsuario(d),
            _secao('Cursos & engajamento', _vermelho, Icons.ondemand_video_rounded),
            _engajamentoCursos(),
            _secao('Atalhos do painel', _cinza, Icons.apps_rounded),
            _atalhos(),
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                'Atualizado às ${DateFormat('HH:mm').format(d.geradoEm)} · '
                '${d.usuariosLidos} cadastros lidos. Puxe para atualizar.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AdminUi.apoioOf(context), fontSize: 11.5),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Blocos ──────────────────────────────────────────────────────────

  Widget _hero(AdminPainelGeralData? d) {
    final sub = d == null
        ? (_carregando ? 'Carregando os números…' : 'Sem dados')
        : '${d.ativos} com acesso · ${d.pagantes} pagantes · '
            'lucro previsto ${_moeda.format(d.lucroPrevistoMes)} no mês';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF0D1B2A), Color(0xFF1D4ED8), Color(0xFF12B5A5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: _azul.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.space_dashboard_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Painel geral',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  sub,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: _carregando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _aviso(String t, Color cor) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cor.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, color: cor, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(t, style: TextStyle(color: cor, fontSize: 12.5)),
            ),
          ],
        ),
      );

  Widget _secao(String t, Color cor, IconData icone) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 22, 0, 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [cor.withValues(alpha: 0.9), cor.withValues(alpha: 0.6)],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icone, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
            Text(
              t,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AdminUi.tintaOf(context),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(height: 1, color: cor.withValues(alpha: 0.2)),
            ),
          ],
        ),
      );

  Widget _grade(List<Widget> cards) => LayoutBuilder(builder: (context, c) {
        final col = c.maxWidth >= 1200
            ? 4
            : c.maxWidth >= 860
                ? 3
                : c.maxWidth >= 520
                    ? 2
                    : 1;
        final w = (c.maxWidth - (col - 1) * 10) / col;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [for (final x in cards) SizedBox(width: w, child: x)],
        );
      });

  Widget _duasColunas(Widget a, Widget b) => LayoutBuilder(builder: (context, c) {
        if (c.maxWidth < 860) {
          return Column(children: [a, const SizedBox(height: 12), b]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: a),
            const SizedBox(width: 12),
            Expanded(child: b),
          ],
        );
      });

  Widget _kpi(
    String titulo,
    String valor,
    String sub,
    IconData icone,
    Color cor,
    AdminMenuItem destino,
  ) {
    final pode = _pode(destino);
    return Material(
      color: AdminUi.cardOf(context),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: pode ? () => _abrir(destino) : null,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: [cor.withValues(alpha: 0.12), cor.withValues(alpha: 0.02)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: cor.withValues(alpha: 0.28)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: cor.withValues(alpha: 0.15),
                child: Icon(icone, color: cor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AdminUi.tintaOf(context),
                      ),
                    ),
                    if (valor.isNotEmpty)
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          valor,
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            color: cor,
                          ),
                        ),
                      ),
                    if (sub.isNotEmpty)
                      Text(
                        sub,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: context.isDarkMode ? context.appTextSecondary : Colors.grey.shade700,
                        ),
                      ),
                  ],
                ),
              ),
              if (pode) Icon(Icons.chevron_right_rounded, color: cor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cartao({required Widget child, EdgeInsets? padding}) => Container(
        padding: padding ?? const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AdminUi.cardOf(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AdminUi.bordaOf(context)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: child,
      );

  Widget _cartaoGrafico(
    String titulo,
    IconData icone,
    Color cor,
    Widget grafico, {
    List<(Color, String)> legenda = const [],
  }) {
    return _cartao(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icone, color: cor, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: AdminUi.tintaOf(context),
                  ),
                ),
              ),
              for (final l in legenda) ...[
                const SizedBox(width: 10),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: l.$1,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 4),
                Text(l.$2,
                    style: TextStyle(fontSize: 11, color: context.isDarkMode ? context.appTextSecondary : Colors.grey.shade700)),
              ],
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(height: 210, child: grafico),
        ],
      ),
    );
  }

  Widget _rodapeMes(double v, TitleMeta meta, List<String> labels) {
    final i = v.toInt();
    if (i < 0 || i >= labels.length) return const SizedBox.shrink();
    if (labels.length > 8 && i.isOdd && i != labels.length - 1) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        labels[i],
        style: TextStyle(fontSize: 10, color: AdminUi.apoioOf(context)),
      ),
    );
  }

  Widget _barras(
    List<double> valores,
    List<String> labels,
    Color cor, {
    bool inteiro = false,
  }) {
    final maxV = valores.fold<double>(0, (m, v) => v > m ? v : m);
    return BarChart(
      BarChartData(
        maxY: maxV <= 0 ? 1 : maxV * 1.2,
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: AdminUi.bordaOf(context), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
              '${labels[g.x]}\n${inteiro ? rod.toY.toInt() : _moeda.format(rod.toY)}',
              const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: inteiro ? 30 : 52,
              getTitlesWidget: (v, meta) => Text(
                inteiro ? v.toInt().toString() : _moedaCurta.format(v),
                style: TextStyle(fontSize: 9.5, color: AdminUi.apoioOf(context)),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (v, meta) => _rodapeMes(v, meta, labels),
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < valores.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: valores[i],
                  width: 14,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                  gradient: LinearGradient(
                    colors: [cor.withValues(alpha: 0.55), cor],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _barrasDuplas(
    List<double> bruto,
    List<double> liquido,
    List<String> labels,
  ) {
    final maxV = bruto.fold<double>(0, (m, v) => v > m ? v : m);
    return BarChart(
      BarChartData(
        maxY: maxV <= 0 ? 1 : maxV * 1.2,
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: AdminUi.bordaOf(context), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
              '${labels[g.x]} · ${ri == 0 ? 'bruto' : 'líquido'}\n${_moeda.format(rod.toY)}',
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 52,
              getTitlesWidget: (v, meta) => Text(
                _moedaCurta.format(v),
                style: TextStyle(fontSize: 9.5, color: AdminUi.apoioOf(context)),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (v, meta) => _rodapeMes(v, meta, labels),
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < bruto.length; i++)
            BarChartGroupData(
              x: i,
              barsSpace: 3,
              barRods: [
                BarChartRodData(
                  toY: bruto[i],
                  width: 9,
                  color: _ambar,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(4)),
                ),
                BarChartRodData(
                  toY: i < liquido.length ? liquido[i] : 0,
                  width: 9,
                  color: _verde,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static const _coresPizza = [
    _azul,
    _verde,
    _ambar,
    _roxo,
    _rosa,
    _teal,
    _vermelho,
    _cinza,
  ];

  Widget _pizzaPlanos(Map<String, int> porPlano) {
    final entradas = porPlano.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entradas.fold<int>(0, (s, e) => s + e.value);
    if (total == 0) {
      return Center(
        child: Text('Sem cadastros',
            style: TextStyle(color: AdminUi.apoioOf(context))),
      );
    }
    return Row(
      children: [
        Expanded(
          child: PieChart(
            PieChartData(
              centerSpaceRadius: 38,
              sectionsSpace: 2,
              sections: [
                for (var i = 0; i < entradas.length; i++)
                  PieChartSectionData(
                    value: entradas[i].value.toDouble(),
                    color: _coresPizza[i % _coresPizza.length],
                    radius: 48,
                    title: entradas[i].value / total >= 0.07
                        ? '${(entradas[i].value * 100 / total).round()}%'
                        : '',
                    titleStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < entradas.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _coresPizza[i % _coresPizza.length],
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '${entradas[i].key} · ${entradas[i].value}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _linhaValor(String t, double v, {Color? cor, bool forte = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                t,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: forte ? FontWeight.w800 : FontWeight.w500,
                  color: AdminUi.tintaOf(context),
                ),
              ),
            ),
            Text(
              _moeda.format(v),
              style: TextStyle(
                fontSize: forte ? 15 : 13,
                fontWeight: forte ? FontWeight.w800 : FontWeight.w700,
                color: cor ?? AdminUi.tintaOf(context),
              ),
            ),
          ],
        ),
      );

  Widget _receitasDespesas(AdminPainelGeralData d) {
    final taxasMes = d.receitaMesAtual - d.liquidoMesAtual;
    final resumo = _cartao(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_month_rounded, color: _teal, size: 18),
              const SizedBox(width: 8),
              Text(
                'Mês atual · ${DateFormat('MMMM yyyy', 'pt_BR').format(d.geradoEm)}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _linhaValor('Receitas recebidas (bruto)', d.receitaMesAtual, cor: _verde),
          _linhaValor('Taxas do Mercado Pago', -taxasMes, cor: _vermelho),
          _linhaValor('Custos fixos do app', -d.custoMensal, cor: _vermelho),
          const Divider(),
          _linhaValor('Resultado até agora', d.resultadoMesAtual,
              cor: d.resultadoMesAtual < 0 ? _vermelho : _verde, forte: true),
          _linhaValor('Renovações previstas até o fim do mês',
              d.previsaoRestoDoMes, cor: _azul),
          _linhaValor('Lucro previsto no mês', d.lucroPrevistoMes,
              cor: d.lucroPrevistoMes < 0 ? _vermelho : _verde, forte: true),
          const SizedBox(height: 4),
          Text(
            'Previsão considera só quem já pagou (último valor pago, vencimento '
            'dentro do mês). Teste grátis, cortesia e convênio não entram.',
            style: TextStyle(fontSize: 11, color: AdminUi.apoioOf(context)),
          ),
        ],
      ),
    );

    final custos = _cartao(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_rounded, color: _vermelho, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Custos fixos mensais',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
              TextButton.icon(
                onPressed: () => _editarCustos(d.custos),
                icon: const Icon(Icons.edit_rounded, size: 16),
                label: const Text('Editar'),
              ),
            ],
          ),
          if (d.custos.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Nenhum custo cadastrado. Toque em Editar para lançar servidor, '
                'domínio, lojas, e-mail… (fica salvo só para você).',
                style: TextStyle(fontSize: 12, color: context.isDarkMode ? context.appTextSecondary : Colors.grey.shade700),
              ),
            )
          else ...[
            for (final c in d.custos) _linhaValor(c.nome, c.valorMensal),
            const Divider(),
            _linhaValor('Total por mês', d.custoMensal, forte: true),
          ],
        ],
      ),
    );
    return _duasColunas(resumo, custos);
  }

  Future<void> _editarCustos(List<AdminCusto> atuais) async {
    final linhas = [
      for (final c in atuais)
        (
          TextEditingController(text: c.nome),
          TextEditingController(
              text: c.valorMensal.toStringAsFixed(2).replaceAll('.', ',')),
        ),
    ];
    if (linhas.isEmpty) {
      linhas.add((TextEditingController(), TextEditingController()));
    }
    final salvar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Custos fixos mensais'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < linhas.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: linhas[i].$1,
                              decoration: const InputDecoration(
                                labelText: 'Custo',
                                hintText: 'Ex.: Firebase, domínio',
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: linhas[i].$2,
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'R\$ / mês',
                                isDense: true,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remover',
                            onPressed: () => setLocal(() => linhas.removeAt(i)),
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ],
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setLocal(() => linhas.add(
                          (TextEditingController(), TextEditingController()))),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Adicionar custo'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    if (salvar != true) return;
    final novos = <AdminCusto>[];
    for (final l in linhas) {
      final nome = l.$1.text.trim();
      final raw = l.$2.text.trim().replaceAll('R\$', '').replaceAll(' ', '');
      final norm = raw.contains(',')
          ? raw.replaceAll('.', '').replaceAll(',', '.')
          : raw;
      final v = double.tryParse(norm) ?? 0;
      if (nome.isNotEmpty) novos.add(AdminCusto(nome: nome, valorMensal: v));
    }
    try {
      await AdminPainelGeralData.salvarCustos(novos);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Custos salvos.')),
      );
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar custos: $e')),
      );
    }
  }

  Widget _resultadoPorUsuario(AdminPainelGeralData d) {
    final lista = d.resultadoUsuarios;
    final mostrar = _verTodosResultado ? lista : lista.take(10).toList();
    return _cartao(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_search_rounded, color: _teal, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Resultado por usuário pagante (12 meses) · ${lista.length}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Pago no período, líquido após taxas e custo fixo rateado entre '
            'os ${d.ativos} usuários com acesso.',
            style: TextStyle(fontSize: 11, color: AdminUi.apoioOf(context)),
          ),
          const SizedBox(height: 8),
          if (lista.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Nenhum pagamento aprovado vinculado a usuário nos últimos 12 meses.',
                style: TextStyle(color: context.isDarkMode ? context.appTextSecondary : Colors.grey.shade700),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 36,
                dataRowMinHeight: 40,
                dataRowMaxHeight: 52,
                columnSpacing: 18,
                headingTextStyle: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: context.isDarkMode ? context.appTextSecondary : const Color(0xFF334155),
                ),
                columns: const [
                  DataColumn(label: Text('Usuário')),
                  DataColumn(label: Text('Plano')),
                  DataColumn(label: Text('Pago'), numeric: true),
                  DataColumn(label: Text('Líquido'), numeric: true),
                  DataColumn(label: Text('Custo'), numeric: true),
                  DataColumn(label: Text('Resultado'), numeric: true),
                  DataColumn(label: Text('Vence')),
                ],
                rows: [
                  for (final u in mostrar)
                    DataRow(cells: [
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 220),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                u.nome.isEmpty ? u.email : u.nome,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 12.5),
                              ),
                              if (u.nome.isNotEmpty)
                                Text(
                                  u.email,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 11, color: AdminUi.apoioOf(context)),
                                ),
                            ],
                          ),
                        ),
                      ),
                      DataCell(Text(u.plano, style: const TextStyle(fontSize: 12))),
                      DataCell(Text(_moeda.format(u.pago12m))),
                      DataCell(Text(_moeda.format(u.liquido12m))),
                      DataCell(Text(_moeda.format(u.custoRateado12m))),
                      DataCell(Text(
                        _moeda.format(u.resultado),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: u.resultado < 0 ? _vermelho : _verde,
                        ),
                      )),
                      DataCell(Text(
                        u.vencimento == null ? '—' : _dataCurta.format(u.vencimento!),
                        style: const TextStyle(fontSize: 12),
                      )),
                    ]),
                ],
              ),
            ),
          if (lista.length > 10)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () =>
                    setState(() => _verTodosResultado = !_verTodosResultado),
                child: Text(_verTodosResultado
                    ? 'Mostrar só os 10 primeiros'
                    : 'Ver todos (${lista.length})'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _engajamentoCursos() {
    final views = _cursos.fold<int>(0, (s, c) => s + c.viewCount);
    final likes = _cursos.fold<int>(0, (s, c) => s + c.likeCount);
    final top = _cursos.where((c) => c.viewCount > 0).take(6).toList();

    // Visualizações por dia (30 dias) somando o mapa `daily` de cada conteúdo.
    final hoje = DateTime.now();
    final dias = [
      for (var i = 29; i >= 0; i--)
        DateTime(hoje.year, hoje.month, hoje.day).subtract(Duration(days: i)),
    ];
    final fmt = DateFormat('yyyy-MM-dd');
    final porDia = List<double>.filled(30, 0);
    for (final c in _cursos) {
      for (var i = 0; i < dias.length; i++) {
        porDia[i] += (c.daily[fmt.format(dias[i])] ?? 0).toDouble();
      }
    }
    final labelsDia = [for (final d in dias) DateFormat('dd/MM').format(d)];

    final kpis = _grade([
      _kpi('Visualizações', '$views', '${_cursos.length} conteúdos com métrica',
          Icons.visibility_rounded, _vermelho, AdminMenuItem.cursos),
      _kpi('Curtidas', '$likes', 'Botão «Gostei» dos alunos',
          Icons.thumb_up_alt_rounded, _rosa, AdminMenuItem.cursos),
      _kpi('Cursos em vídeo', '', 'Cadastrar, publicar e ver quem assistiu',
          Icons.ondemand_video_rounded, _vermelho, AdminMenuItem.cursos),
      _kpi('Dicas financeiras', '', 'Bíblicas e gerais no Início',
          Icons.lightbulb_rounded, _ambar, AdminMenuItem.dicasFinanceiras),
    ]);

    final ranking = _cartao(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.leaderboard_rounded, color: _vermelho, size: 18),
              SizedBox(width: 8),
              Text('Mais assistidos',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 10),
          if (top.isEmpty)
            Text('Ainda sem visualizações registradas.',
                style: TextStyle(color: AdminUi.apoioOf(context)))
          else
            for (final c in top)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.title.isEmpty ? c.courseId : c.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          '${c.viewCount} views · ${c.likeCount} curtidas',
                          style: TextStyle(
                              fontSize: 11.5, color: context.isDarkMode ? context.appTextSecondary : Colors.grey.shade700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: top.first.viewCount == 0
                            ? 0
                            : c.viewCount / top.first.viewCount,
                        minHeight: 6,
                        color: c.type == 'dica' ? _ambar : _vermelho,
                        backgroundColor: AdminUi.bordaOf(context),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );

    return Column(
      children: [
        kpis,
        const SizedBox(height: 12),
        _duasColunas(
          _cartaoGrafico(
            'Visualizações por dia (30 dias)',
            Icons.show_chart_rounded,
            _vermelho,
            _barras(porDia, labelsDia, _vermelho, inteiro: true),
          ),
          ranking,
        ),
      ],
    );
  }

  Widget _atalhos() {
    final grupos = <(String, Color, List<(String, String, IconData, AdminMenuItem)>)>[
      (
        'Usuários',
        _verde,
        [
          ('Usuários', 'Lista, filtros e licenças', Icons.people_rounded, AdminMenuItem.usuarios),
          ('WISDOMAPP 360°', 'Inteligência por usuário', Icons.hub_rounded, AdminMenuItem.usuarios360),
          ('Equipe', 'Admins e gestores', Icons.groups_rounded, AdminMenuItem.equipe),
          ('Sugestões', 'O que os usuários pedem', Icons.feedback_rounded, AdminMenuItem.sugestoes),
        ],
      ),
      (
        'Financeiro',
        _ambar,
        [
          ('Mercado Pago', 'Pagamentos e PIX', Icons.payment_rounded, AdminMenuItem.mercadopago),
          ('Relatórios', 'Receita e exportações', Icons.bar_chart_rounded, AdminMenuItem.relatorios),
          ('Promoções', 'Cupons e preços', Icons.local_offer_rounded, AdminMenuItem.promocoes),
          ('Convênios', 'Parcerias e membros', Icons.handshake_rounded, AdminMenuItem.convenios),
        ],
      ),
      (
        'Conteúdo',
        _vermelho,
        [
          ('Cursos em vídeo', 'Vídeos, aulas e métricas', Icons.ondemand_video_rounded, AdminMenuItem.cursos),
          ('Dicas financeiras', 'Grid compacta', Icons.lightbulb_rounded, AdminMenuItem.dicasFinanceiras),
          ('Landing', 'Site de divulgação', Icons.web_rounded, AdminMenuItem.landing),
          ('Downloads', 'Arquivos públicos', Icons.download_rounded, AdminMenuItem.downloads),
        ],
      ),
      (
        'Comunicação e sistema',
        _cinza,
        [
          ('E-mail', 'Envio e modelos', Icons.email_rounded, AdminMenuItem.email),
          ('Logs', 'Ações da equipe', Icons.history_rounded, AdminMenuItem.logs),
          ('Manutenção', 'Versão e avisos', Icons.construction_rounded, AdminMenuItem.manutencao),
          ('Backups', 'Cópias de segurança', Icons.cloud_rounded, AdminMenuItem.drive),
          ('Publicar nas Lojas', 'Android e iPhone', Icons.store_rounded, AdminMenuItem.lojas),
        ],
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final g in grupos)
          if (g.$3.any((x) => _pode(x.$4))) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 8, 0, 8),
              child: Text(
                g.$1.toUpperCase(),
                style: TextStyle(
                  color: g.$2,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            _grade([
              for (final x in g.$3)
                if (_pode(x.$4)) _kpi(x.$1, '', x.$2, x.$3, g.$2, x.$4),
            ]),
          ],
      ],
    );
  }

  static String _pct(int a, int b) =>
      b == 0 ? '0%' : '${(a * 100 / b).round()}%';
}
