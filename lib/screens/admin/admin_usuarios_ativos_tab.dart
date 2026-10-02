import 'package:cloud_functions/cloud_functions.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../theme/theme_context.dart';
import '../../utils/admin_load_guard.dart';
import '../../widgets/admin/admin_page_shell.dart';
import '../../widgets/admin/admin_ui_kit.dart';
import '../admin_usuarios_inteligencia_tab.dart' show openAdminUser360Preview;

/// Admin — **Usuários ativos** (porte do Controle Total, 02/10/2026): quem usa
/// o sistema de verdade, dia a dia — não só quem baixou.
///
/// Dados da callable `ctAdminUsuariosAtivos` (functions/admin_usuarios_ativos.js;
/// cache de 10 min no servidor, ↻ refaz). Cada KPI abre a lista daqueles
/// usuários; tocar numa barra do gráfico mostra quem usou naquele dia.
class AdminUsuariosAtivosTab extends StatefulWidget {
  const AdminUsuariosAtivosTab({super.key});

  @override
  State<AdminUsuariosAtivosTab> createState() => _AdminUsuariosAtivosTabState();
}

/// Mensagem amigável quando a callable ainda não foi publicada.
String _mensagemErro(Object? e) {
  if (e is FirebaseFunctionsException &&
      (e.code == 'not-found' || e.code == 'unimplemented')) {
    return 'Função ainda não publicada no servidor (ctAdminUsuariosAtivos). '
        'Publique as Cloud Functions e tente de novo.';
  }
  return AdminLoadGuard.mensagem(e);
}

class _Usuario {
  _Usuario(Map<String, dynamic> m)
      : uid = '${m['uid'] ?? ''}',
        nome = '${m['nome'] ?? ''}',
        email = '${m['email'] ?? ''}',
        plataforma = '${m['plataforma'] ?? ''}',
        versao = '${m['versao'] ?? ''}',
        plano = '${m['plano'] ?? ''}',
        subLogin = m['subLogin'] == true,
        diasAtivos = (m['diasAtivos'] as num?)?.toInt() ?? 0,
        ultimoDiaAtivo = '${m['ultimoDiaAtivo'] ?? ''}',
        criadoEm = _data(m['criadoEm']),
        ultimoAcesso = _data(m['ultimoAcesso']);

  final String uid, nome, email, plataforma, versao, plano, ultimoDiaAtivo;
  final bool subLogin;
  final int diasAtivos;
  final DateTime? criadoEm, ultimoAcesso;

  String get rotulo => nome.isNotEmpty ? nome : (email.isNotEmpty ? email : uid);

  static DateTime? _data(Object? v) {
    final n = (v as num?)?.toInt() ?? 0;
    return n > 0 ? DateTime.fromMillisecondsSinceEpoch(n) : null;
  }
}

class _AdminUsuariosAtivosTabState extends State<AdminUsuariosAtivosTab> {
  static final _df = DateFormat('dd/MM/yy HH:mm');

  int _dias = 30;
  bool _carregando = false;
  Object? _erro;
  Map<String, dynamic>? _d;
  Map<String, dynamic> _resumo = const {};
  List<Map<String, dynamic>> _serie = const [];
  List<_Usuario> _usuarios = const [];
  int _minDias = 3;
  String _hoje = '';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar({bool forcar = false}) async {
    if (_carregando) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable(
        'ctAdminUsuariosAtivos',
        options: HttpsCallableOptions(timeout: AdminLoadGuard.callable),
      );
      final r = await AdminLoadGuard.comPrazo(
        fn.call<dynamic>({'dias': _dias, 'forcar': forcar}),
        prazo: AdminLoadGuard.callable + const Duration(seconds: 10),
        oQue: 'os usuários ativos',
      );
      final data = r.data;
      if (data is! Map) throw StateError('Resposta vazia do servidor.');
      final d = Map<String, dynamic>.from(data);
      if (!mounted) return;
      setState(() {
        _d = d;
        _resumo = Map<String, dynamic>.from((d['resumo'] as Map?) ?? const {});
        _serie = ((d['serie'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
        _usuarios = ((d['usuarios'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => _Usuario(Map<String, dynamic>.from(m)))
            .toList();
        _minDias = (d['minDiasClienteReal'] as num?)?.toInt() ?? 3;
        _hoje = '${d['hoje'] ?? ''}';
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

  int _n(String k) => (_resumo[k] as num?)?.toInt() ?? 0;

  Set<String> _uidsDoDia(String dia) {
    for (final s in _serie) {
      if (s['dia'] == dia) {
        return ((s['uids'] as List?) ?? const []).map((e) => '$e').toSet();
      }
    }
    return {};
  }

  Set<String> _uidsUltimos(int dias) => _serie
      .skip((_serie.length - dias).clamp(0, _serie.length))
      .expand((s) => ((s['uids'] as List?) ?? const []).map((e) => '$e'))
      .toSet();

  void _abrirGrid(String titulo, bool Function(_Usuario) filtro) {
    final lista = _usuarios.where(filtro).toList();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _GridUsuariosPage(titulo: titulo, usuarios: lista, dias: _dias),
      ),
    );
  }

  static String _diaCurto(String iso) {
    final p = iso.split('-');
    return p.length == 3 ? '${p[2]}/${p[1]}' : iso;
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final pad = AdminPageShell.listPadding(context, top: 4);
    final geradoEm = (d?['geradoEm'] as num?)?.toInt() ?? 0;
    return RefreshIndicator(
      onRefresh: () => _carregar(forcar: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: pad.copyWith(bottom: pad.bottom + 32),
        children: [
          AdminHero(
            titulo: 'Usuários ativos',
            subtitulo: d == null
                ? 'Quem usa o sistema de verdade — não só quem baixou.'
                : 'Atualizado ${_df.format(DateTime.fromMillisecondsSinceEpoch(geradoEm))}'
                    '${d['doCache'] == true ? ' (cache de 10 min — ↻ refaz)' : ''}',
            icone: Icons.insights_rounded,
            carregando: _carregando,
            onAtualizar: () => _carregar(forcar: true),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 7, label: Text('7 dias')),
                ButtonSegment(value: 30, label: Text('30 dias')),
                ButtonSegment(value: 90, label: Text('90 dias')),
              ],
              selected: {_dias},
              showSelectedIcon: false,
              onSelectionChanged: _carregando
                  ? null
                  : (s) {
                      setState(() => _dias = s.first);
                      _carregar();
                    },
            ),
          ),
          if (_erro != null)
            AdminErroCard(
              erro: _mensagemErro(_erro),
              onTentar: () => _carregar(forcar: true),
              titulo: d == null
                  ? 'Não foi possível carregar os usuários ativos'
                  : 'Não deu para atualizar (mostrando o último resultado)',
            ),
          if (d == null && _carregando && _erro == null)
            const AdminCarregando(texto: 'Contando quem usou o app em cada dia…'),
          if (d != null) ...[
            for (final a in ((d['avisos'] as List?) ?? const []))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: AdminSelo('$a', cor: AdminUi.ambar, icone: Icons.info_outline_rounded),
              ),
            const SizedBox(height: 4),
            _indicadores(),
            AdminSecao(
              titulo: 'Ativos por dia — toque numa barra para ver quem',
              cor: AdminUi.azul,
              icone: Icons.bar_chart_rounded,
            ),
            _grafico(),
            const SizedBox(height: 10),
            _nota(),
          ],
        ],
      ),
    );
  }

  Widget _indicadores() {
    return AdminKpiGrid(
      maxColunas: 3,
      children: [
        AdminKpi(
          rotulo: 'Ativos hoje',
          valor: '${_n('ativosHoje')}',
          sub: 'Abriram o app ou lançaram algo hoje',
          icone: Icons.today_rounded,
          cor: AdminUi.azul,
          onTap: () {
            final u = _uidsDoDia(_hoje);
            _abrirGrid('Ativos hoje', (x) => u.contains(x.uid));
          },
        ),
        AdminKpi(
          rotulo: 'Ativos em 7 dias',
          valor: '${_n('ativos7')}',
          sub: 'Média de ${_resumo['mediaDiaria7'] ?? 0} por dia',
          icone: Icons.date_range_rounded,
          cor: AdminUi.roxo,
          onTap: () {
            final u = _uidsUltimos(7);
            _abrirGrid('Ativos nos últimos 7 dias', (x) => u.contains(x.uid));
          },
        ),
        AdminKpi(
          rotulo: 'Clientes reais',
          valor: '${_n('clientesReais')}',
          sub: 'Usaram em $_minDias dias ou mais ($_dias d)',
          icone: Icons.verified_rounded,
          cor: AdminUi.verde,
          onTap: () => _abrirGrid('Clientes reais ($_minDias+ dias em $_dias d)',
              (x) => x.diasAtivos >= _minDias),
        ),
        AdminKpi(
          rotulo: 'Usaram pouco',
          valor: '${_n('usaramPouco')}',
          sub: 'Só 1 a ${_minDias - 1} dia(s) no período',
          icone: Icons.hourglass_bottom_rounded,
          cor: AdminUi.ambar,
          onTap: () => _abrirGrid('Usaram pouco (1 a ${_minDias - 1} dias)',
              (x) => x.diasAtivos > 0 && x.diasAtivos < _minDias),
        ),
        AdminKpi(
          rotulo: 'Só cadastraram',
          valor: '${_n('soCadastro')}',
          sub: 'Nenhum dia de uso em $_dias d',
          icone: Icons.person_off_rounded,
          cor: AdminUi.cinza,
          onTap: () => _abrirGrid('Só cadastraram (sem uso em $_dias d)', (x) => x.diasAtivos == 0),
        ),
        AdminKpi(
          rotulo: 'Cadastrados',
          valor: '${_n('cadastrados')}',
          sub: 'Contas com e-mail completo',
          icone: Icons.people_alt_rounded,
          cor: AdminUi.teal,
          onTap: () => _abrirGrid('Todos os cadastrados', (_) => true),
        ),
      ],
    );
  }

  Widget _grafico() {
    if (_serie.isEmpty) return const AdminVazio(texto: 'Sem dados no período.');
    final maior = _serie
        .map((s) => (s['total'] as num?)?.toDouble() ?? 0)
        .fold<double>(1, (a, b) => b > a ? b : a);
    final passoRotulo = _serie.length <= 10 ? 1 : (_serie.length / 8).ceil();
    final grade = context.isDarkMode ? context.appBorderSubtle : Colors.grey.shade200;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 14, 14, 8),
      decoration: BoxDecoration(
        color: AdminUi.cardOf(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AdminUi.bordaOf(context)),
      ),
      child: SizedBox(
        height: 240,
        child: BarChart(
          BarChartData(
            maxY: (maior * 1.15).ceilToDouble(),
            gridData: FlGridData(
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) => FlLine(color: grade, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 32,
                  getTitlesWidget: (v, meta) => Text(
                    v.toInt().toString(),
                    style: TextStyle(fontSize: 10, color: AdminUi.apoioOf(context)),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 22,
                  getTitlesWidget: (v, meta) {
                    final i = v.toInt();
                    if (i < 0 || i >= _serie.length) return const SizedBox.shrink();
                    final ultimo = i == _serie.length - 1;
                    if (!ultimo && i % passoRotulo != 0) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _diaCurto('${_serie[i]['dia']}'),
                        style: TextStyle(fontSize: 10, color: AdminUi.apoioOf(context)),
                      ),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => const Color(0xFF0F172A),
                getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
                  '${_diaCurto('${_serie[g.x]['dia']}')}\n${rod.toY.toInt()} ativos',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
              touchCallback: (evento, resposta) {
                if (evento is! FlTapUpEvent) return;
                final i = resposta?.spot?.touchedBarGroupIndex;
                if (i == null || i < 0 || i >= _serie.length) return;
                final dia = '${_serie[i]['dia']}';
                final u = _uidsDoDia(dia);
                _abrirGrid('Ativos em ${_diaCurto(dia)}', (x) => u.contains(x.uid));
              },
            ),
            barGroups: [
              for (var i = 0; i < _serie.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: (_serie[i]['total'] as num?)?.toDouble() ?? 0,
                      width: _serie.length > 45 ? 4 : 10,
                      color: '${_serie[i]['dia']}' == _hoje ? AdminUi.verde : AdminUi.azul,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _nota() {
    final retratos = (_d?['retratosGuardados'] as num?)?.toInt() ?? 0;
    return Text(
      'Conta como ativo no dia quem abriu o app (Web, Android ou iPhone — '
      '`clientTelemetry.lastPingAt`) ou lançou/alterou um lançamento ou compromisso. '
      'O «abriu o app» só é guardado dia a dia pela rotina noturna '
      '(ctAdminAtivosDiario; $retratos dia(s) guardado(s) no período) — antes '
      'disso o gráfico mostra quem lançou algo, por isso os dias antigos ficam '
      'mais baixos. «Cliente real» = usou em $_minDias dias ou mais no período.',
      style: TextStyle(fontSize: 12, height: 1.4, color: AdminUi.apoioOf(context)),
    );
  }
}

/// Grid (tabela) dos usuários de um indicador — ordena, filtra e copia.
class _GridUsuariosPage extends StatefulWidget {
  const _GridUsuariosPage({required this.titulo, required this.usuarios, required this.dias});

  final String titulo;
  final List<_Usuario> usuarios;
  final int dias;

  @override
  State<_GridUsuariosPage> createState() => _GridUsuariosPageState();
}

class _GridUsuariosPageState extends State<_GridUsuariosPage> {
  final _busca = TextEditingController();
  int _col = 2;
  bool _asc = false;
  static final _fmt = DateFormat('dd/MM/yyyy');
  static final _fmtHora = DateFormat('dd/MM HH:mm');

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  static String _plataforma(String p) => switch (p) {
        'web' => 'Web',
        'android' => 'Android',
        'ios' => 'iPhone',
        '' => '—',
        _ => p,
      };

  static String _diaBr(String iso) {
    final p = iso.split('-');
    return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : '—';
  }

  List<_Usuario> get _linhas {
    final q = _busca.text.trim().toLowerCase();
    final l = widget.usuarios
        .where((u) =>
            q.isEmpty ||
            u.nome.toLowerCase().contains(q) ||
            u.email.toLowerCase().contains(q) ||
            u.uid.toLowerCase().contains(q))
        .toList();
    int cmp(_Usuario a, _Usuario b) => switch (_col) {
          0 => a.rotulo.toLowerCase().compareTo(b.rotulo.toLowerCase()),
          1 => a.email.compareTo(b.email),
          2 => a.diasAtivos.compareTo(b.diasAtivos),
          3 => a.ultimoDiaAtivo.compareTo(b.ultimoDiaAtivo),
          4 => (a.ultimoAcesso?.millisecondsSinceEpoch ?? 0)
              .compareTo(b.ultimoAcesso?.millisecondsSinceEpoch ?? 0),
          5 => a.plataforma.compareTo(b.plataforma),
          6 => a.versao.compareTo(b.versao),
          7 => (a.criadoEm?.millisecondsSinceEpoch ?? 0)
              .compareTo(b.criadoEm?.millisecondsSinceEpoch ?? 0),
          _ => a.plano.compareTo(b.plano),
        };
    l.sort((a, b) => _asc ? cmp(a, b) : cmp(b, a));
    return l;
  }

  Future<void> _copiar(List<_Usuario> linhas) async {
    final b = StringBuffer('Nome;E-mail;Dias ativos (${widget.dias} d);Último dia ativo;'
        'Último acesso;Plataforma;Versão;Cadastro;Plano\n');
    for (final u in linhas) {
      b.writeln([
        u.nome,
        u.email,
        u.diasAtivos,
        _diaBr(u.ultimoDiaAtivo),
        u.ultimoAcesso == null ? '' : _fmtHora.format(u.ultimoAcesso!),
        _plataforma(u.plataforma),
        u.versao,
        u.criadoEm == null ? '' : _fmt.format(u.criadoEm!),
        u.plano,
      ].join(';'));
    }
    await Clipboard.setData(ClipboardData(text: b.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${linhas.length} linha(s) copiadas — cole no Excel/Planilhas.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final linhas = _linhas;
    DataColumn col(String t, {bool num = false}) => DataColumn(
          label: Text(t, style: const TextStyle(fontWeight: FontWeight.w800)),
          numeric: num,
          onSort: (c, asc) => setState(() {
            _col = c;
            _asc = asc;
          }),
        );
    return Scaffold(
      backgroundColor: AdminPageShell.backgroundOf(context),
      appBar: AppBar(
        title: Text('${widget.titulo} · ${linhas.length}'),
        actions: [
          IconButton(
            tooltip: 'Copiar relatório (CSV)',
            onPressed: linhas.isEmpty ? null : () => _copiar(linhas),
            icon: const Icon(Icons.copy_all_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: AdminBusca(
              controller: _busca,
              onChanged: (_) => setState(() {}),
              hint: 'Buscar por nome, e-mail ou UID…',
            ),
          ),
          Expanded(
            child: linhas.isEmpty
                ? const Center(child: AdminVazio(texto: 'Ninguém nesta lista.'))
                : Scrollbar(
                    child: SingleChildScrollView(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          sortColumnIndex: _col,
                          sortAscending: _asc,
                          showCheckboxColumn: false,
                          headingRowHeight: 40,
                          dataRowMinHeight: 40,
                          dataRowMaxHeight: 52,
                          columns: [
                            col('Nome'),
                            col('E-mail'),
                            col('Dias ativos', num: true),
                            col('Último dia ativo'),
                            col('Último acesso'),
                            col('Plataforma'),
                            col('Versão'),
                            col('Cadastro'),
                            col('Plano'),
                          ],
                          rows: [
                            for (final u in linhas)
                              DataRow(
                                onSelectChanged: (_) => openAdminUser360Preview(
                                  context,
                                  uid: u.uid,
                                  displayName: u.nome,
                                  email: u.email,
                                ),
                                cells: [
                                  DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                                    Text(u.rotulo, style: const TextStyle(fontWeight: FontWeight.w700)),
                                    if (u.subLogin)
                                      const Padding(
                                        padding: EdgeInsets.only(left: 6),
                                        child: Tooltip(
                                          message: 'Sub-login (acesso compartilhado)',
                                          child: Icon(Icons.link_rounded, size: 14),
                                        ),
                                      ),
                                  ])),
                                  DataCell(Text(u.email)),
                                  DataCell(Text('${u.diasAtivos}')),
                                  DataCell(Text(_diaBr(u.ultimoDiaAtivo))),
                                  DataCell(Text(u.ultimoAcesso == null ? '—' : _fmtHora.format(u.ultimoAcesso!))),
                                  DataCell(Text(_plataforma(u.plataforma))),
                                  DataCell(Text(u.versao.isEmpty ? '—' : u.versao)),
                                  DataCell(Text(u.criadoEm == null ? '—' : _fmt.format(u.criadoEm!))),
                                  DataCell(Text(u.plano.isEmpty ? '—' : u.plano)),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
