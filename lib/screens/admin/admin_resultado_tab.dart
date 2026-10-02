import 'dart:math' as math;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../theme/theme_context.dart';
import '../../utils/admin_load_guard.dart';
import '../../widgets/admin/admin_page_shell.dart';
import '../../widgets/admin/admin_ui_kit.dart';

/// «Receitas & Despesas» do Painel Admin (porte do Controle Total,
/// 02/10/2026): resultado do app mês a mês e por usuário pagante.
///
/// Tudo vem da callable `ctAdminResultado` (Admin SDK, cache de 10 min):
/// receita = pagamentos aprovados do Mercado Pago (`mp_payments`), menos
/// estornos e taxa do MP; despesas = taxa do MP + custos fixos mensais que o
/// admin lança aqui (gravados no servidor em `admin_stats/custos_fixos`).
class AdminResultadoTab extends StatefulWidget {
  const AdminResultadoTab({super.key});

  @override
  State<AdminResultadoTab> createState() => _AdminResultadoTabState();
}

class _AdminResultadoTabState extends State<AdminResultadoTab> {
  static const _fnNome = 'ctAdminResultado';
  static final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  static final _df = DateFormat('dd/MM/yy HH:mm');
  static final _dfDia = DateFormat('dd/MM/yy');

  Map<String, dynamic>? _d;
  Object? _erro;
  bool _carregando = false;
  int _meses = 12;
  String _busca = '';
  final _buscaCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  HttpsCallable get _fn => FirebaseFunctions.instanceFor(region: 'us-central1')
      .httpsCallable(
        _fnNome,
        options: HttpsCallableOptions(timeout: AdminLoadGuard.callable),
      );

  /// Mensagem própria para «função ainda não publicada»; o resto segue o
  /// padrão do [AdminLoadGuard].
  static Object _erroAmigavel(Object e) {
    if (e is FirebaseFunctionsException &&
        (e.code == 'not-found' || e.code == 'unimplemented')) {
      return 'A função «$_fnNome» ainda não foi publicada no servidor '
          '(falta o deploy das Cloud Functions).';
    }
    return e;
  }

  Future<void> _carregar({bool forcar = false}) async {
    if (_carregando) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final res = await AdminLoadGuard.comPrazo(
        _fn.call<dynamic>({'acao': 'resumo', 'meses': _meses, 'forcar': forcar}),
        prazo: AdminLoadGuard.callable + const Duration(seconds: 10),
        oQue: 'receitas e despesas',
      );
      final data = res.data;
      if (data is! Map) throw StateError('Resposta vazia do servidor.');
      if (!mounted) return;
      setState(() {
        _d = Map<String, dynamic>.from(data);
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = _erroAmigavel(e);
        _carregando = false;
      });
    }
  }

  void _trocarPeriodo(int meses) {
    if (meses == _meses || _carregando) return;
    setState(() => _meses = meses);
    _carregar();
  }

  Map<String, dynamic> _map(Object? v) =>
      v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};
  List<Map<String, dynamic>> _lista(Object? v) =>
      v is List ? v.map(_map).toList() : const <Map<String, dynamic>>[];
  int _int(Object? v) => v is num ? v.toInt() : 0;
  double _num(Object? v) => v is num ? v.toDouble() : 0;

  String _mesCurto(String chave) {
    final p = chave.split('-');
    if (p.length != 2) return chave;
    const nomes = [
      'jan', 'fev', 'mar', 'abr', 'mai', 'jun',
      'jul', 'ago', 'set', 'out', 'nov', 'dez',
    ];
    final m = int.tryParse(p[1]) ?? 1;
    return '${nomes[(m - 1).clamp(0, 11)]}/${p[0].substring(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final pad = AdminPageShell.listPadding(context, top: 4);
    final geradoEm = d == null ? 0 : _int(d['geradoEm']);
    return RefreshIndicator(
      onRefresh: () => _carregar(forcar: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: pad.copyWith(bottom: pad.bottom + 32),
        children: [
          AdminHero(
            titulo: 'Receitas & Despesas',
            subtitulo: d == null
                ? (_carregando
                    ? 'Somando os pagamentos no servidor…'
                    : 'Resultado do app mês a mês e por pagante')
                : 'Atualizado ${_df.format(DateTime.fromMillisecondsSinceEpoch(geradoEm))}'
                    '${d['doCache'] == true ? ' (cache de 10 min — ↻ refaz)' : ''}',
            icone: Icons.account_balance_wallet_rounded,
            cores: const [Color(0xFF0B1F3A), Color(0xFF1D4ED8), Color(0xFF16A34A)],
            carregando: _carregando,
            onAtualizar: () => _carregar(forcar: true),
          ),
          const SizedBox(height: 10),
          _seletorPeriodo(),
          if (_erro != null)
            AdminErroCard(
              erro: _erro,
              onTentar: () => _carregar(forcar: true),
              titulo: d == null
                  ? 'Não foi possível carregar receitas e despesas'
                  : 'Não deu para atualizar (mostrando o último resultado)',
            ),
          if (d == null && _carregando && _erro == null)
            const AdminCarregando(texto: 'Lendo pagamentos e custos…'),
          if (d != null) ..._conteudo(d),
        ],
      ),
    );
  }

  Widget _seletorPeriodo() {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Período:',
            style: TextStyle(fontSize: 12.5, color: AdminUi.apoioOf(context))),
        for (final m in const [3, 6, 12, 24])
          ChoiceChip(
            label: Text('$m meses'),
            selected: _meses == m,
            onSelected: _carregando ? null : (_) => _trocarPeriodo(m),
          ),
      ],
    );
  }

  List<Widget> _conteudo(Map<String, dynamic> d) {
    final atual = _map(d['mesAtual']);
    final total = _map(d['total']);
    final custos = _map(d['custos']);
    final meses = _lista(d['meses']);
    final resAtual = _num(atual['resultado']);
    final resTotal = _num(total['resultado']);
    final margemTotal = total['margem'];
    return [
      if (d['limiteAtingido'] == true)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: AdminSelo(
            'Base com mais de 5.000 pagamentos: a soma pode estar incompleta',
            cor: AdminUi.ambar,
            icone: Icons.warning_amber_rounded,
          ),
        ),
      AdminSecao(
        titulo: 'Este mês (${_mesCurto((atual['mes'] ?? '').toString())})',
        cor: AdminUi.azul,
        icone: Icons.calendar_month_rounded,
      ),
      AdminKpiGrid(children: [
        AdminKpi(
          rotulo: 'Receita bruta',
          valor: _moeda.format(_num(atual['receitaBruta'])),
          sub: '${_int(atual['pagamentos'])} pagamento(s) · '
              '${_int(atual['pagantes'])} pagante(s)',
          icone: Icons.payments_rounded,
          cor: AdminUi.verde,
        ),
        AdminKpi(
          rotulo: 'Despesas',
          valor: _moeda.format(_num(atual['despesas'])),
          sub: 'Taxa MP ${_moeda.format(_num(atual['taxaMp']))} · '
              'fixos ${_moeda.format(_num(atual['custosFixos']))}',
          icone: Icons.receipt_long_rounded,
          cor: AdminUi.vermelho,
        ),
        AdminKpi(
          rotulo: 'Estornos',
          valor: _moeda.format(_num(atual['estornos'])),
          sub: 'Devolvidos / chargeback',
          icone: Icons.undo_rounded,
          cor: AdminUi.ambar,
        ),
        AdminKpi(
          rotulo: resAtual >= 0 ? 'Lucro do mês' : 'Prejuízo do mês',
          valor: _moeda.format(resAtual),
          sub: atual['margem'] == null
              ? 'Sem receita no mês'
              : 'Margem ${_num(atual['margem']).toStringAsFixed(1)}%',
          icone: resAtual >= 0
              ? Icons.trending_up_rounded
              : Icons.trending_down_rounded,
          cor: resAtual >= 0 ? AdminUi.teal : AdminUi.vermelho,
        ),
      ]),
      AdminSecao(
        titulo: 'Últimos $_meses meses',
        cor: AdminUi.roxo,
        icone: Icons.stacked_bar_chart_rounded,
      ),
      AdminKpiGrid(children: [
        AdminKpi(
          rotulo: 'Receita bruta',
          valor: _moeda.format(_num(total['receitaBruta'])),
          sub: 'Líquida ${_moeda.format(_num(total['receitaLiquida']))}',
          icone: Icons.savings_rounded,
          cor: AdminUi.verde,
        ),
        AdminKpi(
          rotulo: 'Despesas',
          valor: _moeda.format(_num(total['despesas'])),
          sub: 'Taxa MP ${_moeda.format(_num(total['taxaMp']))} · '
              'fixos ${_moeda.format(_num(total['custosFixos']))}',
          icone: Icons.receipt_rounded,
          cor: AdminUi.vermelho,
        ),
        AdminKpi(
          rotulo: resTotal >= 0 ? 'Lucro no período' : 'Prejuízo no período',
          valor: _moeda.format(resTotal),
          sub: margemTotal == null
              ? 'Sem receita'
              : 'Margem ${_num(margemTotal).toStringAsFixed(1)}%',
          icone: Icons.query_stats_rounded,
          cor: resTotal >= 0 ? AdminUi.teal : AdminUi.vermelho,
        ),
        AdminKpi(
          rotulo: 'Pagantes únicos',
          valor: '${_int(total['pagantesUnicos'])}',
          sub: 'Ticket médio ${_moeda.format(_num(total['ticketMedio']))} · '
              '${_int(d['usuariosBase'])} cadastros',
          icone: Icons.people_alt_rounded,
          cor: AdminUi.azul,
        ),
      ]),
      if (_int(total['taxasEstimadas']) > 0)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '${_int(total['taxasEstimadas'])} pagamento(s) sem a taxa real do '
            'Mercado Pago: taxa estimada (0,99% Pix · 4,99% cartão).',
            style: TextStyle(fontSize: 11.5, color: AdminUi.apoioOf(context)),
          ),
        ),
      if (meses.isNotEmpty) ...[
        const SizedBox(height: 12),
        _grafico(meses),
        const SizedBox(height: 8),
        _tabelaMeses(meses),
      ],
      _porPlano(_map(total['porPlano'])),
      AdminSecao(
        titulo: 'Custos fixos do app',
        cor: AdminUi.ambar,
        icone: Icons.build_circle_rounded,
        trailing: TextButton.icon(
          onPressed: () => _editarCustos(_lista(custos['itens'])),
          icon: const Icon(Icons.edit_rounded, size: 18),
          label: const Text('Editar'),
        ),
      ),
      _cardCustos(custos),
      AdminSecao(
        titulo: 'Por usuário (top pagantes)',
        cor: AdminUi.teal,
        icone: Icons.leaderboard_rounded,
      ),
      ..._usuarios(d),
    ];
  }

  Widget _caixa({required Widget child, EdgeInsets? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AdminUi.cardOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminUi.bordaOf(context)),
      ),
      child: child,
    );
  }

  Widget _grafico(List<Map<String, dynamic>> meses) {
    double maxY = 0;
    for (final m in meses) {
      maxY = math.max(maxY, _num(m['receitaBruta']) - _num(m['estornos']));
      maxY = math.max(maxY, _num(m['despesas']));
    }
    if (maxY <= 0) maxY = 1;
    final apoio = AdminUi.apoioOf(context);
    final passo = meses.length > 12 ? 3 : (meses.length > 6 ? 2 : 1);
    return _caixa(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _legenda(AdminUi.verde, 'Receita (− estornos)'),
              const SizedBox(width: 14),
              _legenda(AdminUi.vermelho, 'Despesas'),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                maxY: maxY * 1.15,
                alignment: BarChartAlignment.spaceAround,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: AdminUi.bordaOf(context),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, _, rod, rodIndex) => BarTooltipItem(
                      '${_mesCurto((meses[group.x]['mes'] ?? '').toString())}\n'
                      '${rodIndex == 0 ? 'Receita' : 'Despesas'}: '
                      '${_moeda.format(rod.toY)}',
                      const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 44,
                      getTitlesWidget: (v, meta) {
                        if (v == meta.max) return const SizedBox.shrink();
                        return Text(
                          NumberFormat.compact(locale: 'pt_BR').format(v),
                          style: TextStyle(fontSize: 10, color: apoio),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= meses.length || i % passo != 0) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _mesCurto((meses[i]['mes'] ?? '').toString()),
                            style: TextStyle(fontSize: 10, color: apoio),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < meses.length; i++)
                    BarChartGroupData(
                      x: i,
                      barsSpace: 2,
                      barRods: [
                        BarChartRodData(
                          toY: math.max(0,
                              _num(meses[i]['receitaBruta']) - _num(meses[i]['estornos'])),
                          color: AdminUi.verde,
                          width: meses.length > 12 ? 4 : 7,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        BarChartRodData(
                          toY: _num(meses[i]['despesas']),
                          color: AdminUi.vermelho,
                          width: meses.length > 12 ? 4 : 7,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legenda(Color cor, String texto) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration:
              BoxDecoration(color: cor, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 5),
        Text(texto,
            style: TextStyle(fontSize: 11.5, color: AdminUi.apoioOf(context))),
      ],
    );
  }

  Widget _tabelaMeses(List<Map<String, dynamic>> meses) {
    final cab = TextStyle(
        fontSize: 11, fontWeight: FontWeight.w800, color: AdminUi.apoioOf(context));
    final txt = TextStyle(fontSize: 12, color: AdminUi.tintaOf(context));
    return _caixa(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 34,
          dataRowMinHeight: 32,
          dataRowMaxHeight: 36,
          columnSpacing: 18,
          horizontalMargin: 12,
          columns: [
            DataColumn(label: Text('Mês', style: cab)),
            DataColumn(label: Text('Receita', style: cab), numeric: true),
            DataColumn(label: Text('Estornos', style: cab), numeric: true),
            DataColumn(label: Text('Taxa MP', style: cab), numeric: true),
            DataColumn(label: Text('Fixos', style: cab), numeric: true),
            DataColumn(label: Text('Resultado', style: cab), numeric: true),
            DataColumn(label: Text('Pagantes', style: cab), numeric: true),
          ],
          rows: [
            for (final m in meses.reversed)
              DataRow(cells: [
                DataCell(Text(_mesCurto((m['mes'] ?? '').toString()), style: txt)),
                DataCell(Text(_moeda.format(_num(m['receitaBruta'])), style: txt)),
                DataCell(Text(_moeda.format(_num(m['estornos'])), style: txt)),
                DataCell(Text(_moeda.format(_num(m['taxaMp'])), style: txt)),
                DataCell(Text(_moeda.format(_num(m['custosFixos'])), style: txt)),
                DataCell(Text(
                  _moeda.format(_num(m['resultado'])),
                  style: txt.copyWith(
                    fontWeight: FontWeight.w800,
                    color: _num(m['resultado']) >= 0
                        ? AdminUi.verde
                        : AdminUi.vermelho,
                  ),
                )),
                DataCell(Text('${_int(m['pagantes'])}', style: txt)),
              ]),
          ],
        ),
      ),
    );
  }

  Widget _porPlano(Map<String, dynamic> porPlano) {
    if (porPlano.isEmpty) return const SizedBox.shrink();
    final itens = porPlano.entries.toList()
      ..sort((a, b) => _num(b.value).compareTo(_num(a.value)));
    final soma = itens.fold<double>(0, (s, e) => s + _num(e.value));
    const cores = [
      AdminUi.azul, AdminUi.verde, AdminUi.roxo, AdminUi.ambar, AdminUi.rosa,
      AdminUi.teal, AdminUi.cinza,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AdminSecao(
          titulo: 'De onde vem o dinheiro',
          cor: AdminUi.verde,
          icone: Icons.pie_chart_rounded,
        ),
        _caixa(
          child: Column(
            children: [
              for (var i = 0; i < itens.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(itens[i].key,
                                style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: AdminUi.tintaOf(context))),
                          ),
                          Text(
                            '${_moeda.format(_num(itens[i].value))} · '
                            '${soma > 0 ? (_num(itens[i].value) * 100 / soma).toStringAsFixed(0) : 0}%',
                            style: TextStyle(
                                fontSize: 12, color: AdminUi.apoioOf(context)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: soma > 0 ? _num(itens[i].value) / soma : 0,
                          minHeight: 6,
                          color: cores[i % cores.length],
                          backgroundColor:
                              cores[i % cores.length].withValues(alpha: 0.12),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cardCustos(Map<String, dynamic> custos) {
    final itens = _lista(custos['itens']);
    final origem = (custos['origem'] ?? '').toString();
    return _caixa(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (itens.isEmpty)
            Text(
              'Nenhum custo fixo lançado. Toque em «Editar» para incluir '
              'servidor, domínio, lojas, ferramentas…',
              style: TextStyle(fontSize: 12.5, color: AdminUi.apoioOf(context)),
            )
          else ...[
            for (final c in itens)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text((c['nome'] ?? '').toString(),
                          style: TextStyle(
                              fontSize: 13, color: AdminUi.tintaOf(context))),
                    ),
                    Text('${_moeda.format(_num(c['valorMensal']))}/mês',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AdminUi.tintaOf(context))),
                  ],
                ),
              ),
            Divider(color: AdminUi.bordaOf(context)),
            Row(
              children: [
                Expanded(
                  child: Text('Total por mês',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AdminUi.tintaOf(context))),
                ),
                Text(_moeda.format(_num(custos['totalMensal'])),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, color: AdminUi.vermelho)),
              ],
            ),
          ],
          if (origem == 'lista_antiga_do_admin')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Valores da sua lista antiga (Resumo). Toque em «Editar» e '
                'salve para valer para toda a equipe.',
                style: TextStyle(fontSize: 11.5, color: AdminUi.ambar),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            'O custo fixo de cada mês é dividido entre quem pagou naquele mês.',
            style: TextStyle(fontSize: 11.5, color: AdminUi.apoioOf(context)),
          ),
        ],
      ),
    );
  }

  List<Widget> _usuarios(Map<String, dynamic> d) {
    final todos = _lista(d['usuarios']);
    if (todos.isEmpty) {
      return const [AdminVazio(texto: 'Nenhum pagamento no período.')];
    }
    final q = _busca.trim().toLowerCase();
    final lista = q.isEmpty
        ? todos
        : todos
            .where((u) =>
                (u['nome'] ?? '').toString().toLowerCase().contains(q) ||
                (u['email'] ?? '').toString().toLowerCase().contains(q))
            .toList();
    final comPag = _int(d['usuariosComPagamento']);
    return [
      AdminBusca(
        controller: _buscaCtrl,
        onChanged: (v) => setState(() => _busca = v),
        hint: 'Buscar por nome ou e-mail…',
      ),
      if (comPag > todos.length)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Mostrando os ${todos.length} que mais pagaram de $comPag.',
            style: TextStyle(fontSize: 11.5, color: AdminUi.apoioOf(context)),
          ),
        ),
      const SizedBox(height: 8),
      if (lista.isEmpty) const AdminVazio(texto: 'Ninguém com esse nome/e-mail.'),
      for (final u in lista) _linhaUsuario(u),
    ];
  }

  Widget _linhaUsuario(Map<String, dynamic> u) {
    final res = _num(u['resultado']);
    final nome = (u['nome'] ?? '').toString();
    final email = (u['email'] ?? '').toString();
    final ultimo = _int(u['ultimoPagamento']);
    final vence = _int(u['vence']);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AdminUi.cardOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminUi.bordaOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  nome.isNotEmpty ? nome : (email.isNotEmpty ? email : 'Sem nome'),
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                      color: AdminUi.tintaOf(context)),
                ),
              ),
              Text(
                _moeda.format(res),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: res >= 0 ? AdminUi.verde : AdminUi.vermelho,
                ),
              ),
            ],
          ),
          if (nome.isNotEmpty && email.isNotEmpty)
            Text(email,
                style:
                    TextStyle(fontSize: 11.5, color: AdminUi.apoioOf(context))),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if ((u['ultimoPlano'] ?? '').toString().isNotEmpty)
                AdminSelo((u['ultimoPlano']).toString(), cor: AdminUi.azul),
              if (u['existe'] == false)
                const AdminSelo('Conta apagada', cor: AdminUi.cinza),
              if (_num(u['estornos']) > 0)
                AdminSelo('Estorno ${_moeda.format(_num(u['estornos']))}',
                    cor: AdminUi.ambar),
              if (vence > 0)
                AdminSelo(
                  'Licença até ${_dfDia.format(DateTime.fromMillisecondsSinceEpoch(vence))}',
                  cor: vence >= DateTime.now().millisecondsSinceEpoch
                      ? AdminUi.teal
                      : AdminUi.vermelho,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Pagou ${_moeda.format(_num(u['receitaBruta']))} em '
            '${_int(u['pagamentos'])} pagamento(s) · taxa MP '
            '${_moeda.format(_num(u['taxaMp']))} · custo rateado '
            '${_moeda.format(_num(u['custoRateado']))}'
            '${ultimo > 0 ? ' · último ${_dfDia.format(DateTime.fromMillisecondsSinceEpoch(ultimo))}' : ''}',
            style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: context.isDarkMode
                    ? context.appTextSecondary
                    : Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  Future<void> _editarCustos(List<Map<String, dynamic>> atuais) async {
    final itens = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (_) => _CustosDialog(iniciais: atuais),
    );
    if (itens == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _carregando = true);
    try {
      await AdminLoadGuard.comPrazo(
        _fn.call<dynamic>({'acao': 'salvarCustos', 'itens': itens}),
        prazo: AdminLoadGuard.longo,
        oQue: 'os custos fixos',
      );
      if (!mounted) return;
      setState(() => _carregando = false);
      messenger.showSnackBar(
          const SnackBar(content: Text('Custos fixos salvos.')));
      await _carregar(forcar: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      messenger.showSnackBar(SnackBar(
          content: Text(
              'Não salvou: ${AdminLoadGuard.mensagem(_erroAmigavel(e))}')));
    }
  }
}

/// Edição da lista de custos fixos mensais (nome + valor).
class _CustosDialog extends StatefulWidget {
  const _CustosDialog({required this.iniciais});

  final List<Map<String, dynamic>> iniciais;

  @override
  State<_CustosDialog> createState() => _CustosDialogState();
}

class _CustosDialogState extends State<_CustosDialog> {
  final _nomes = <TextEditingController>[];
  final _valores = <TextEditingController>[];

  @override
  void initState() {
    super.initState();
    for (final c in widget.iniciais) {
      final v = c['valorMensal'];
      _adicionar(
        (c['nome'] ?? '').toString(),
        v is num ? v.toStringAsFixed(2).replaceAll('.', ',') : '',
      );
    }
    if (_nomes.isEmpty) _adicionar('', '');
  }

  @override
  void dispose() {
    for (final c in [..._nomes, ..._valores]) {
      c.dispose();
    }
    super.dispose();
  }

  void _adicionar(String nome, String valor) {
    _nomes.add(TextEditingController(text: nome));
    _valores.add(TextEditingController(text: valor));
  }

  void _remover(int i) {
    setState(() {
      _nomes.removeAt(i).dispose();
      _valores.removeAt(i).dispose();
    });
  }

  double? _valor(String s) {
    final t = s.trim().replaceAll('R\$', '').replaceAll(' ', '');
    if (t.isEmpty) return null;
    final norm = t.contains(',') ? t.replaceAll('.', '').replaceAll(',', '.') : t;
    return double.tryParse(norm);
  }

  void _salvar() {
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < _nomes.length; i++) {
      final nome = _nomes[i].text.trim();
      final v = _valor(_valores[i].text);
      if (nome.isEmpty && v == null) continue;
      if (nome.isEmpty || v == null || v < 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Linha ${i + 1}: preencha nome e valor válido.')));
        return;
      }
      out.add({'nome': nome, 'valorMensal': v});
    }
    Navigator.of(context).pop(out);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AdminUi.cardOf(context),
      title: const Text('Custos fixos mensais'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Servidor, domínio, contas das lojas, ferramentas… '
                'Valor por mês. Fica salvo no servidor para toda a equipe.',
                style: TextStyle(fontSize: 12, color: AdminUi.apoioOf(context)),
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < _nomes.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _nomes[i],
                          maxLength: 60,
                          decoration: const InputDecoration(
                            labelText: 'Nome',
                            isDense: true,
                            counterText: '',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _valores[i],
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'R\$/mês',
                            isDense: true,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remover',
                        onPressed: () => _remover(i),
                        icon: const Icon(Icons.delete_outline_rounded,
                            color: AdminUi.vermelho),
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _nomes.length >= 50
                      ? null
                      : () => setState(() => _adicionar('', '')),
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _salvar, child: const Text('Salvar')),
      ],
    );
  }
}
