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

/// Admin — **Usuários · Painel** (porte do Controle Total, 02/10/2026): um card
/// por grupo (situação de pagamento, licença, uso em 30 dias, recém-cadastrados
/// e cada módulo). Tocar abre a lista com filtros completos.
///
/// Junta três callables, pelo uid (se uma falhar, mostra o que as outras
/// trouxeram e avisa):
///  - `ctAdminUsuariosPainel` → situação (pagante, cortesia, convênio, free…),
///    licença, cadastro, pagamentos e receita do mês (fonte principal);
///  - `ctAdminUsuariosAtivos` → dias de uso em 30 dias;
///  - `ctAdminModulosUso`     → quais módulos cada um usa.
class AdminUsuariosPainelTab extends StatefulWidget {
  const AdminUsuariosPainelTab({super.key});

  @override
  State<AdminUsuariosPainelTab> createState() => _AdminUsuariosPainelTabState();
}

final _fmtData = DateFormat('dd/MM/yyyy');
final _fmtHora = DateFormat('dd/MM/yy HH:mm');
final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
/// Sem vencimento vai para o fim da ordem «Vence primeiro» (01/01/2100).
const _semData = 4102444800000;
double _num(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
DateTime? _ms(Object? v) {
  final n = _num(v).toInt();
  return n > 0 ? DateTime.fromMillisecondsSinceEpoch(n) : null;
}

const _situacoes = <String, (String, Color, String)>{
  'pagante_ativo': ('Pagante ativo', AdminUi.verde, 'Pagou e a licença está válida'),
  'pagante_vencido': ('Não renovou', AdminUi.vermelho, 'Pagou e deixou vencer'),
  'cortesia': ('Cortesia', AdminUi.ambar, 'Premium sem pagamento'),
  'convenio': ('Convênio', AdminUi.roxo, 'Licença pelo convênio/parceria'),
  'free': ('Free', AdminUi.cinza, 'Plano gratuito'),
  'equipe': ('Equipe', Color(0xFF0EA5E9), 'Admin / master'),
  'subconta': ('Sub-conta', Color(0xFF94A3B8), 'Acesso compartilhado'),
};

const _atividades = <String, (String, Color)>{
  'hoje': ('Usou hoje', AdminUi.verde),
  'semana': ('Usou na semana', Color(0xFF22C55E)),
  'real': ('Cliente real (3+ dias)', AdminUi.azul),
  'pouco': ('Usou pouco (1–2 dias)', AdminUi.ambar),
  'parado': ('Parado (0 dias)', AdminUi.vermelho),
};

const _cadastros = <String, (String, int)>{
  '7': ('Novos 7 dias', 7),
  '30': ('Novos 30 dias', 30),
  '90': ('Novos 90 dias', 90),
};

const _licencas = <String, (String, Color)>{
  'ativa': ('Licença ativa', AdminUi.verde),
  'vence7': ('Vence em 7 dias', AdminUi.ambar),
  'vence30': ('Vence em 30 dias', Color(0xFFF59E0B)),
  'vencida': ('Licença vencida', AdminUi.vermelho),
};

const _plataformas = <String, String>{
  'web': 'Web',
  'android': 'Android',
  'ios': 'iPhone',
  '': 'Sem registro',
};

class _U {
  _U(this.uid);
  final String uid;
  String nome = '', email = '', situacao = 'free', plano = '', convenio = '';
  String plataforma = '', versao = '', ultimoDiaAtivo = '';
  DateTime? criadoEm, ultimoAcesso, vence, ultimoPagamento;
  int diasAtivos = 0, pagamentos = 0;
  bool removido = false;
  double totalPago = 0;
  final Set<String> modulos = {};

  String get rotulo => nome.isNotEmpty ? nome : (email.isNotEmpty ? email : uid);

  bool atividade(String a, String hoje) {
    final agora = DateTime.now();
    return switch (a) {
      'hoje' => ultimoDiaAtivo == hoje,
      'semana' => (ultimoAcesso != null && agora.difference(ultimoAcesso!).inDays < 7) ||
          (ultimoDiaAtivo.isNotEmpty &&
              agora.difference(DateTime.tryParse(ultimoDiaAtivo) ?? DateTime(2000)).inDays < 7),
      'real' => diasAtivos >= 3,
      'pouco' => diasAtivos > 0 && diasAtivos < 3,
      'parado' => diasAtivos == 0,
      _ => true,
    };
  }

  bool licenca(String l) {
    if (removido || plano == 'free' || situacao == 'subconta') return false;
    final v = vence;
    final agora = DateTime.now();
    return switch (l) {
      'ativa' => v != null && v.isAfter(agora),
      'vence7' => v != null && v.isAfter(agora) && v.difference(agora).inDays < 7,
      'vence30' => v != null && v.isAfter(agora) && v.difference(agora).inDays < 30,
      'vencida' => v != null && v.isBefore(agora),
      _ => true,
    };
  }

  int? get diasDeCadastro => criadoEm == null ? null : DateTime.now().difference(criadoEm!).inDays;
}

class _Modulo {
  const _Modulo(this.id, this.titulo, this.usuarios, this.ativos30, this.registros);
  final String id, titulo;
  final int usuarios, ativos30, registros;
}

/// O que um card abre: filtros já marcados.
class _Preset {
  const _Preset({
    this.situacoes = const {},
    this.atividades = const {},
    this.cadastro,
    this.licenca,
    this.modulos = const {},
  });
  final Set<String> situacoes;
  final Set<String> atividades;
  final String? cadastro;
  final String? licenca;
  final Set<String> modulos;
}

class _AdminUsuariosPainelTabState extends State<AdminUsuariosPainelTab> {
  bool _carregando = false;
  Object? _erro;
  final List<String> _avisos = [];
  Map<String, dynamic>? _painel;
  bool _temAtividade = false;
  List<_U> _usuarios = const [];
  List<_Modulo> _modulos = const [];
  String _hoje = '';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<Map<String, dynamic>?> _call(String nome, Map<String, dynamic> arg, {bool principal = false}) async {
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable(nome, options: HttpsCallableOptions(timeout: AdminLoadGuard.callable));
      final r = await AdminLoadGuard.comPrazo(
        fn.call<dynamic>(arg),
        prazo: AdminLoadGuard.callable + const Duration(seconds: 10),
        oQue: nome,
      );
      return r.data is Map ? Map<String, dynamic>.from(r.data as Map) : null;
    } catch (e) {
      if (principal) rethrow;
      final naoPublicada = e is FirebaseFunctionsException &&
          (e.code == 'not-found' || e.code == 'unimplemented');
      _avisos.add(naoPublicada
          ? '$nome: função ainda não publicada no servidor.'
          : '$nome: ${AdminLoadGuard.mensagem(e)}');
      return null;
    }
  }

  Future<void> _carregar({bool forcar = false}) async {
    if (_carregando) return;
    setState(() {
      _carregando = true;
      _erro = null;
      _avisos.clear();
    });
    try {
      final res = await Future.wait<Map<String, dynamic>?>([
        _call('ctAdminUsuariosPainel', {'forcar': forcar}, principal: true),
        _call('ctAdminUsuariosAtivos', {'dias': 30, 'forcar': forcar}),
        _call('ctAdminModulosUso', {'forcar': forcar}),
      ]);
      final painel = res[0] ?? const <String, dynamic>{};
      final ativos = res[1];
      final mods = res[2];

      final porUid = <String, _U>{};
      _U u(String uid) => porUid.putIfAbsent(uid, () => _U(uid));
      for (final m in ((painel['usuarios'] as List?) ?? const []).whereType<Map>()) {
        final x = u('${m['uid']}');
        x.nome = '${m['nome'] ?? ''}';
        x.email = '${m['email'] ?? ''}';
        x.situacao = '${m['situacao'] ?? 'free'}';
        x.plano = '${m['plano'] ?? ''}';
        x.convenio = '${m['convenio'] ?? ''}';
        x.criadoEm = _ms(m['criadoEm']);
        x.vence = _ms(m['vence']);
        x.ultimoAcesso = _ms(m['ultimoAcesso']);
        x.plataforma = '${m['plataforma'] ?? ''}';
        x.versao = '${m['versao'] ?? ''}';
        x.removido = m['removido'] == true;
        x.totalPago = _num(m['totalPago']);
        x.pagamentos = _num(m['pagamentos']).toInt();
        x.ultimoPagamento = _ms(m['ultimoPagamento']);
      }
      for (final m in ((ativos?['usuarios'] as List?) ?? const []).whereType<Map>()) {
        final x = porUid['${m['uid']}'];
        if (x == null) continue;
        x.diasAtivos = _num(m['diasAtivos']).toInt();
        x.ultimoDiaAtivo = '${m['ultimoDiaAtivo'] ?? ''}';
      }
      final modulos = <_Modulo>[];
      for (final m in ((mods?['modulos'] as List?) ?? const []).whereType<Map>()) {
        final id = '${m['id']}';
        modulos.add(_Modulo(id, '${m['titulo'] ?? id}', _num(m['usuarios']).toInt(),
            _num(m['ativos30']).toInt(), _num(m['registros']).toInt()));
        final porUidMod = m['porUid'];
        if (porUidMod is Map) {
          for (final k in porUidMod.keys) {
            porUid['$k']?.modulos.add(id);
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _painel = painel;
        _temAtividade = ativos != null;
        _usuarios = porUid.values.toList();
        _modulos = modulos;
        _hoje = '${ativos?['hoje'] ?? painel['hoje'] ?? DateFormat('yyyy-MM-dd').format(DateTime.now())}';
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

  void _abrir(String titulo, _Preset preset) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _ListaUsuariosPage(
        titulo: titulo,
        usuarios: _usuarios,
        modulos: _modulos,
        hoje: _hoje,
        preset: preset,
        temAtividade: _temAtividade,
      ),
    ));
  }

  int _conta(bool Function(_U) f) => _usuarios.where(f).length;

  @override
  Widget build(BuildContext context) {
    final d = _painel;
    final pad = AdminPageShell.listPadding(context, top: 4);
    final geradoEm = _ms(d?['geradoEm']);
    final erroMsg = _erro is FirebaseFunctionsException &&
            ((_erro as FirebaseFunctionsException).code == 'not-found' ||
                (_erro as FirebaseFunctionsException).code == 'unimplemented')
        ? 'Função ainda não publicada no servidor (ctAdminUsuariosPainel).'
        : _erro;
    return RefreshIndicator(
      onRefresh: () => _carregar(forcar: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: pad.copyWith(bottom: pad.bottom + 32),
        children: [
          AdminHero(
            titulo: 'Usuários · Painel',
            subtitulo: geradoEm == null
                ? 'Toque num card para ver quem é — com filtros completos.'
                : 'Atualizado ${_fmtHora.format(geradoEm)}'
                    '${d?['doCache'] == true ? ' (cache de 10 min — ↻ refaz)' : ''}',
            icone: Icons.space_dashboard_rounded,
            cores: const [Color(0xFF1E1B4B), Color(0xFF4338CA), Color(0xFF0EA5E9)],
            carregando: _carregando,
            onAtualizar: () => _carregar(forcar: true),
          ),
          if (_erro != null)
            AdminErroCard(
              erro: erroMsg,
              onTentar: () => _carregar(forcar: true),
              titulo: d == null ? 'Não foi possível carregar o painel' : 'Não deu para atualizar',
            ),
          if (d == null && _carregando && _erro == null)
            const AdminCarregando(texto: 'Lendo cadastros, licenças e pagamentos…'),
          if (d != null) ..._conteudo(d),
        ],
      ),
    );
  }

  List<Widget> _conteudo(Map<String, dynamic> d) {
    final c = Map<String, dynamic>.from((d['contagem'] as Map?) ?? const {});
    int n(String k) => _num(c[k]).toInt();
    final avisosServidor = ((d['avisos'] as List?) ?? const []).map((e) => '$e');
    final todosAvisos = [..._avisos, ...avisosServidor];
    return [
      if (todosAvisos.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AdminUi.ambar.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AdminUi.ambar.withValues(alpha: 0.35)),
          ),
          child: Text(
            'Parte dos dados não veio:\n${todosAvisos.join('\n')}',
            style: TextStyle(fontSize: 12, color: context.isDarkMode ? AdminUi.ambar : const Color(0xFFB45309)),
          ),
        ),
      AdminSecao(titulo: 'Base de cadastros', cor: AdminUi.azul, icone: Icons.people_alt_rounded),
      AdminKpiGrid(children: [
        AdminKpi(
          rotulo: 'Titulares',
          valor: '${n('titulares')}',
          sub: '${n('totalDocs')} perfis no banco · ${n('fantasmas')} sem e-mail',
          icone: Icons.people_alt_rounded,
          cor: AdminUi.azul,
          onTap: () => _abrir('Todos os usuários', const _Preset()),
        ),
        AdminKpi(
          rotulo: 'Novos hoje / 7 d',
          valor: '${n('novosHoje')} / ${n('novos7')}',
          sub: '${n('novos30')} em 30 dias',
          icone: Icons.person_add_alt_1_rounded,
          cor: AdminUi.teal,
          onTap: () => _abrir('Novos 7 dias', const _Preset(cadastro: '7')),
        ),
        AdminKpi(
          rotulo: 'Novos no mês',
          valor: '${n('novosMes')}',
          sub: 'Mês anterior: ${n('novosMesAnterior')}',
          icone: Icons.calendar_month_rounded,
          cor: AdminUi.roxo,
          onTap: () => _abrir('Novos 30 dias', const _Preset(cadastro: '30')),
        ),
        AdminKpi(
          rotulo: 'Abriram o app (7 / 30 d)',
          valor: '${n('ativos7')} / ${n('ativos30')}',
          sub: 'Pelo último acesso registrado',
          icone: Icons.touch_app_rounded,
          cor: AdminUi.verde,
          onTap: _temAtividade ? () => _abrir('Usaram na semana', const _Preset(atividades: {'semana'})) : null,
        ),
      ]),
      AdminSecao(titulo: 'Situação de pagamento', cor: AdminUi.verde, icone: Icons.payments_rounded),
      AdminKpiGrid(children: [
        for (final e in _situacoes.entries)
          AdminKpi(
            rotulo: e.value.$1,
            valor: '${_conta((x) => x.situacao == e.key)}',
            sub: e.value.$3,
            icone: Icons.circle,
            cor: e.value.$2,
            onTap: () => _abrir(e.value.$1, _Preset(situacoes: {e.key})),
          ),
      ]),
      AdminSecao(titulo: 'Licença', cor: AdminUi.ambar, icone: Icons.workspace_premium_rounded),
      AdminKpiGrid(children: [
        for (final e in _licencas.entries)
          AdminKpi(
            rotulo: e.value.$1,
            valor: '${_conta((x) => x.licenca(e.key))}',
            icone: Icons.event_available_rounded,
            cor: e.value.$2,
            onTap: () => _abrir(e.value.$1, _Preset(licenca: e.key)),
          ),
      ]),
      if (_temAtividade) ...[
        AdminSecao(titulo: 'Uso nos últimos 30 dias', cor: AdminUi.roxo, icone: Icons.bolt_rounded),
        AdminKpiGrid(children: [
          for (final e in _atividades.entries)
            AdminKpi(
              rotulo: e.value.$1,
              valor: '${_conta((x) => x.situacao != 'subconta' && x.atividade(e.key, _hoje))}',
              icone: Icons.bolt_rounded,
              cor: e.value.$2,
              onTap: () => _abrir(e.value.$1, _Preset(atividades: {e.key})),
            ),
        ]),
        AdminSecao(titulo: 'Recém-cadastrados', cor: AdminUi.teal, icone: Icons.rocket_launch_rounded),
        AdminKpiGrid(children: [
          for (final e in _cadastros.entries) ...[
            AdminKpi(
              rotulo: '${e.value.$1} · usando',
              valor: '${_conta((x) => (x.diasDeCadastro ?? 99999) <= e.value.$2 && x.diasAtivos > 0)}',
              sub: 'Cadastraram e já usaram',
              icone: Icons.rocket_launch_rounded,
              cor: AdminUi.verde,
              onTap: () => _abrir('${e.value.$1} · usando',
                  _Preset(cadastro: e.key, atividades: const {'real', 'pouco'})),
            ),
            AdminKpi(
              rotulo: '${e.value.$1} · sem usar',
              valor: '${_conta((x) => (x.diasDeCadastro ?? 99999) <= e.value.$2 && x.diasAtivos == 0)}',
              sub: 'Cadastraram e não usaram',
              icone: Icons.person_off_rounded,
              cor: AdminUi.vermelho,
              onTap: () => _abrir('${e.value.$1} · sem usar',
                  _Preset(cadastro: e.key, atividades: const {'parado'})),
            ),
          ],
        ]),
      ],
      if (_modulos.isNotEmpty) ...[
        AdminSecao(titulo: 'Por módulo', cor: AdminUi.rosa, icone: Icons.widgets_rounded),
        AdminKpiGrid(children: [
          for (final m in _modulos)
            AdminKpi(
              rotulo: m.titulo,
              valor: '${m.usuarios}',
              sub: '${m.ativos30} ativos em 30 d · ${m.registros} registros',
              icone: Icons.widgets_rounded,
              cor: _corModulo(m.id),
              onTap: () => _abrir(m.titulo, _Preset(modulos: {m.id})),
            ),
        ]),
      ],
      AdminSecao(titulo: 'Receita (Mercado Pago)', cor: AdminUi.verde, icone: Icons.attach_money_rounded),
      _receita(d),
      AdminSecao(titulo: 'Novos cadastros por mês', cor: AdminUi.azul, icone: Icons.bar_chart_rounded),
      _graficoMensal(d),
    ];
  }

  Widget _receita(Map<String, dynamic> d) {
    final hist = ((d['historico'] as List?) ?? const []).whereType<Map>().toList();
    if (hist.isEmpty) return const AdminVazio(texto: 'Sem pagamentos registrados.');
    final mes = Map<String, dynamic>.from(hist.last);
    return Column(children: [
      AdminKpiGrid(children: [
        AdminKpi(
          rotulo: 'Receita do mês',
          valor: _moeda.format(_num(mes['receita'])),
          sub: '${_num(mes['pagamentos']).toInt()} pagamento(s) · estornos ${_moeda.format(_num(mes['estornos']))}',
          icone: Icons.trending_up_rounded,
          cor: AdminUi.verde,
        ),
        AdminKpi(
          rotulo: 'Líquido do mês',
          valor: _moeda.format(_num(mes['receitaLiquida'])),
          sub: 'Depois da taxa do Mercado Pago',
          icone: Icons.account_balance_wallet_rounded,
          cor: AdminUi.teal,
        ),
      ]),
      const SizedBox(height: 10),
      Container(
        decoration: BoxDecoration(
          color: AdminUi.cardOf(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AdminUi.bordaOf(context)),
        ),
        child: Column(children: [
          for (final h in hist.reversed)
            ListTile(
              dense: true,
              title: Text('${h['mes']}',
                  style: TextStyle(fontWeight: FontWeight.w700, color: AdminUi.tintaOf(context))),
              subtitle: Text('${_num(h['pagamentos']).toInt()} pagamento(s)',
                  style: TextStyle(color: AdminUi.apoioOf(context), fontSize: 12)),
              trailing: Text(_moeda.format(_num(h['receita'])),
                  style: TextStyle(fontWeight: FontWeight.w800, color: AdminUi.tintaOf(context))),
            ),
        ]),
      ),
    ]);
  }

  Widget _graficoMensal(Map<String, dynamic> d) {
    final serie = ((d['serieMensal'] as List?) ?? const []).whereType<Map>().toList();
    if (serie.isEmpty) return const SizedBox.shrink();
    final maior = serie.map((s) => _num(s['novos'])).fold<double>(1, (a, b) => b > a ? b : a);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 14, 14, 8),
      decoration: BoxDecoration(
        color: AdminUi.cardOf(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AdminUi.bordaOf(context)),
      ),
      child: SizedBox(
        height: 200,
        child: BarChart(BarChartData(
          maxY: (maior * 1.2).ceilToDouble(),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                getTitlesWidget: (v, m) => Text('${v.toInt()}',
                    style: TextStyle(fontSize: 10, color: AdminUi.apoioOf(context))),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (v, m) {
                  final i = v.toInt();
                  if (i < 0 || i >= serie.length) return const SizedBox.shrink();
                  final mes = '${serie[i]['mes']}';
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(mes.length >= 7 ? '${mes.substring(5)}/${mes.substring(2, 4)}' : mes,
                        style: TextStyle(fontSize: 9.5, color: AdminUi.apoioOf(context))),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF0F172A),
              getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
                '${serie[g.x]['mes']}\n${rod.toY.toInt()} novo(s)',
                const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < serie.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: _num(serie[i]['novos']),
                  width: 14,
                  color: AdminUi.azul,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ]),
          ],
        )),
      ),
    );
  }
}

Color _corModulo(String id) {
  const cores = [
    AdminUi.azul, AdminUi.verde, AdminUi.roxo, AdminUi.ambar,
    Color(0xFF0EA5E9), AdminUi.rosa, AdminUi.teal, Color(0xFFEA580C),
  ];
  return cores[id.hashCode.abs() % cores.length];
}

/// Lista com filtros completos (chips coloridos) + busca + ordenação + CSV.
class _ListaUsuariosPage extends StatefulWidget {
  const _ListaUsuariosPage({
    required this.titulo,
    required this.usuarios,
    required this.modulos,
    required this.hoje,
    required this.preset,
    required this.temAtividade,
  });
  final String titulo;
  final List<_U> usuarios;
  final List<_Modulo> modulos;
  final String hoje;
  final _Preset preset;
  final bool temAtividade;

  @override
  State<_ListaUsuariosPage> createState() => _ListaUsuariosPageState();
}

class _ListaUsuariosPageState extends State<_ListaUsuariosPage> {
  final _busca = TextEditingController();
  late Set<String> _sit = {...widget.preset.situacoes};
  late Set<String> _atv = {...widget.preset.atividades};
  late String? _cad = widget.preset.cadastro;
  late String? _lic = widget.preset.licenca;
  late Set<String> _mod = {...widget.preset.modulos};
  final Set<String> _plat = {};
  late String _ordem = widget.temAtividade ? 'dias' : 'cadastro';
  bool _mostrarFiltros = true;

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  List<_U> get _filtrados {
    final q = _busca.text.trim().toLowerCase();
    final l = widget.usuarios.where((u) {
      if (_sit.isNotEmpty && !_sit.contains(u.situacao)) return false;
      if (_atv.isNotEmpty && !_atv.any((a) => u.atividade(a, widget.hoje))) return false;
      if (_cad != null && (u.diasDeCadastro ?? 99999) > _cadastros[_cad]!.$2) return false;
      if (_lic != null && !u.licenca(_lic!)) return false;
      if (_plat.isNotEmpty && !_plat.contains(u.plataforma)) return false;
      if (_mod.isNotEmpty && !_mod.every(u.modulos.contains)) return false;
      if (q.isNotEmpty && !'${u.nome} ${u.email} ${u.uid} ${u.plano} ${u.convenio}'.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList();
    int c(_U a, _U b) => switch (_ordem) {
          'nome' => a.rotulo.toLowerCase().compareTo(b.rotulo.toLowerCase()),
          'cadastro' => (b.criadoEm?.millisecondsSinceEpoch ?? 0).compareTo(a.criadoEm?.millisecondsSinceEpoch ?? 0),
          'acesso' => (b.ultimoAcesso?.millisecondsSinceEpoch ?? 0)
              .compareTo(a.ultimoAcesso?.millisecondsSinceEpoch ?? 0),
          'vence' => (a.vence?.millisecondsSinceEpoch ?? _semData).compareTo(b.vence?.millisecondsSinceEpoch ?? _semData),
          'pago' => b.totalPago.compareTo(a.totalPago),
          'modulos' => b.modulos.length.compareTo(a.modulos.length),
          _ => b.diasAtivos.compareTo(a.diasAtivos),
        };
    l.sort(c);
    return l;
  }

  String _nomeModulo(String id) {
    for (final m in widget.modulos) {
      if (m.id == id) return m.titulo;
    }
    return id;
  }

  Widget _chip(String rotulo, bool sel, Color cor, VoidCallback onTap) => FilterChip(
        selected: sel,
        showCheckmark: false,
        label: Text(rotulo),
        labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: sel ? Colors.white : cor),
        selectedColor: cor,
        backgroundColor: cor.withValues(alpha: 0.08),
        side: BorderSide(color: cor.withValues(alpha: 0.35)),
        onSelected: (_) => setState(onTap),
      );

  Widget _grupo(String titulo, List<Widget> chips) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titulo,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AdminUi.apoioOf(context))),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 6, children: chips),
        ]),
      );

  void _toggle(Set<String> s, String k) => s.contains(k) ? s.remove(k) : s.add(k);

  Future<void> _copiar(List<_U> l) async {
    final b = StringBuffer('Nome;E-mail;Situação;Plano;Convênio;Vence;Dias ativos 30d;Último acesso;'
        'Plataforma;Versão;Cadastro;Total pago;Módulos\n');
    for (final u in l) {
      b.writeln([
        u.nome,
        u.email,
        _situacoes[u.situacao]?.$1 ?? u.situacao,
        u.plano,
        u.convenio,
        u.vence == null ? '' : _fmtData.format(u.vence!),
        u.diasAtivos,
        u.ultimoAcesso == null ? '' : DateFormat('dd/MM/yyyy HH:mm').format(u.ultimoAcesso!),
        _plataformas[u.plataforma] ?? u.plataforma,
        u.versao,
        u.criadoEm == null ? '' : _fmtData.format(u.criadoEm!),
        u.totalPago.toStringAsFixed(2).replaceAll('.', ','),
        u.modulos.map(_nomeModulo).join(', '),
      ].join(';'));
    }
    await Clipboard.setData(ClipboardData(text: b.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('${l.length} usuário(s) copiados — cole no Excel.')));
  }

  @override
  Widget build(BuildContext context) {
    final l = _filtrados;
    final ativosFiltros =
        _sit.length + _atv.length + _mod.length + _plat.length + (_cad == null ? 0 : 1) + (_lic == null ? 0 : 1);
    return Scaffold(
      backgroundColor: AdminPageShell.backgroundOf(context),
      appBar: AppBar(
        title: Text('${widget.titulo} · ${l.length}'),
        actions: [
          IconButton(
            tooltip: _mostrarFiltros ? 'Esconder filtros' : 'Mostrar filtros',
            onPressed: () => setState(() => _mostrarFiltros = !_mostrarFiltros),
            icon: Badge(
              isLabelVisible: ativosFiltros > 0,
              label: Text('$ativosFiltros'),
              child: const Icon(Icons.tune_rounded),
            ),
          ),
          IconButton(
            tooltip: 'Copiar relatório (CSV)',
            onPressed: l.isEmpty ? null : () => _copiar(l),
            icon: const Icon(Icons.copy_all_rounded),
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(children: [
            Expanded(
              child: AdminBusca(
                controller: _busca,
                onChanged: (_) => setState(() {}),
                hint: 'Buscar por nome, e-mail, UID ou plano…',
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: _ordem,
              underline: const SizedBox.shrink(),
              items: [
                if (widget.temAtividade) const DropdownMenuItem(value: 'dias', child: Text('Mais ativos')),
                const DropdownMenuItem(value: 'acesso', child: Text('Último acesso')),
                const DropdownMenuItem(value: 'cadastro', child: Text('Mais novos')),
                const DropdownMenuItem(value: 'vence', child: Text('Vence primeiro')),
                const DropdownMenuItem(value: 'pago', child: Text('Mais pagou')),
                if (widget.modulos.isNotEmpty)
                  const DropdownMenuItem(value: 'modulos', child: Text('Mais módulos')),
                const DropdownMenuItem(value: 'nome', child: Text('Nome A–Z')),
              ],
              onChanged: (v) => setState(() => _ordem = v ?? 'cadastro'),
            ),
          ]),
        ),
        if (_mostrarFiltros)
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.38),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _grupo('SITUAÇÃO', [
                  for (final e in _situacoes.entries)
                    _chip(e.value.$1, _sit.contains(e.key), e.value.$2, () => _toggle(_sit, e.key)),
                ]),
                _grupo('LICENÇA', [
                  for (final e in _licencas.entries)
                    _chip(e.value.$1, _lic == e.key, e.value.$2, () => _lic = _lic == e.key ? null : e.key),
                ]),
                if (widget.temAtividade)
                  _grupo('USO (30 DIAS)', [
                    for (final e in _atividades.entries)
                      _chip(e.value.$1, _atv.contains(e.key), e.value.$2, () => _toggle(_atv, e.key)),
                  ]),
                _grupo('CADASTRO', [
                  for (final e in _cadastros.entries)
                    _chip(e.value.$1, _cad == e.key, AdminUi.teal, () => _cad = _cad == e.key ? null : e.key),
                ]),
                _grupo('PLATAFORMA', [
                  for (final e in _plataformas.entries)
                    _chip(e.value, _plat.contains(e.key), const Color(0xFF0EA5E9), () => _toggle(_plat, e.key)),
                ]),
                if (widget.modulos.isNotEmpty)
                  _grupo('USA O MÓDULO (todos marcados)', [
                    for (final m in widget.modulos)
                      _chip(m.titulo, _mod.contains(m.id), _corModulo(m.id), () => _toggle(_mod, m.id)),
                  ]),
                if (ativosFiltros > 0)
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _sit = {};
                      _atv = {};
                      _mod = {};
                      _plat.clear();
                      _cad = null;
                      _lic = null;
                    }),
                    icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                    label: const Text('Limpar filtros'),
                  ),
              ]),
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: l.isEmpty
              ? const Center(child: AdminVazio(texto: 'Ninguém com esses filtros.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: l.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _linha(l[i]),
                ),
        ),
      ]),
    );
  }

  Widget _linha(_U u) {
    final sit = _situacoes[u.situacao] ?? ('—', AdminUi.cinza, '');
    final corDias = u.diasAtivos >= 3
        ? AdminUi.verde
        : u.diasAtivos > 0
            ? AdminUi.ambar
            : AdminUi.vermelho;
    return Material(
      color: AdminUi.cardOf(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => openAdminUser360Preview(context, uid: u.uid, displayName: u.nome, email: u.email),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border(left: BorderSide(color: sit.$2, width: 4)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(u.rotulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w800, color: AdminUi.tintaOf(context))),
              ),
              AdminSelo(sit.$1, cor: sit.$2),
            ]),
            if (u.email.isNotEmpty && u.email != u.rotulo)
              Text(u.email, style: TextStyle(fontSize: 12, color: AdminUi.apoioOf(context))),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (u.plano.isNotEmpty) AdminSelo(u.plano, cor: AdminUi.azul),
              if (widget.temAtividade) AdminSelo('${u.diasAtivos} dia(s) de uso em 30 d', cor: corDias),
              if (u.vence != null)
                AdminSelo('Vence ${_fmtData.format(u.vence!)}',
                    cor: u.vence!.isBefore(DateTime.now()) ? AdminUi.vermelho : AdminUi.teal),
              if (u.ultimoAcesso != null)
                AdminSelo('Acesso ${DateFormat('dd/MM HH:mm').format(u.ultimoAcesso!)}', cor: AdminUi.azul),
              if (u.plataforma.isNotEmpty)
                AdminSelo(_plataformas[u.plataforma] ?? u.plataforma, cor: const Color(0xFF0EA5E9)),
              if (u.criadoEm != null) AdminSelo('Cadastro ${_fmtData.format(u.criadoEm!)}', cor: AdminUi.teal),
              if (u.totalPago > 0) AdminSelo('Pagou ${_moeda.format(u.totalPago)}', cor: AdminUi.verde),
              if (u.convenio.isNotEmpty) AdminSelo(u.convenio, cor: AdminUi.roxo),
              if (u.removido) const AdminSelo('Removido', cor: AdminUi.vermelho),
              for (final m in u.modulos.take(8)) AdminSelo(_nomeModulo(m), cor: _corModulo(m)),
              if (u.modulos.length > 8) AdminSelo('+${u.modulos.length - 8}', cor: AdminUi.cinza),
            ]),
          ]),
        ),
      ),
    );
  }
}
