import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../utils/admin_load_guard.dart';
import '../widgets/admin/admin_page_shell.dart';
import '../widgets/admin/admin_ui_kit.dart';

/// «Uso dos módulos» (porte do Controle Total, 02/10/2026): quem usa cada
/// módulo do WISDOMAPP, ativos nos últimos 30 dias, último acesso do app e
/// receitas x despesas lançadas pelos usuários. Dados da callable
/// `ctAdminModulosUso` (Admin SDK; cache de 10 min no servidor).
class AdminUsoModulosTab extends StatefulWidget {
  const AdminUsoModulosTab({super.key});

  @override
  State<AdminUsoModulosTab> createState() => _AdminUsoModulosTabState();
}

class _AdminUsoModulosTabState extends State<AdminUsoModulosTab> {
  Map<String, dynamic>? _d;
  Object? _erro;
  bool _carregando = false;

  static final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  static final _df = DateFormat('dd/MM/yy HH:mm');

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
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable(
        'ctAdminModulosUso',
        options: HttpsCallableOptions(timeout: AdminLoadGuard.callable),
      );
      final res = await AdminLoadGuard.comPrazo(
        fn.call<dynamic>({'forcar': forcar}),
        prazo: AdminLoadGuard.callable + const Duration(seconds: 10),
        oQue: 'o uso dos módulos',
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
        _erro = e;
        _carregando = false;
      });
    }
  }

  Map<String, dynamic> _map(Object? v) =>
      v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};
  int _int(Object? v) => v is num ? v.toInt() : 0;
  double _num(Object? v) => v is num ? v.toDouble() : 0;

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final pad = AdminPageShell.listPadding(context, top: 4);
    final geradoEm = d == null ? null : _int(d['geradoEm']);
    return RefreshIndicator(
      onRefresh: () => _carregar(forcar: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: pad.copyWith(bottom: pad.bottom + 32),
        children: [
          AdminHero(
            titulo: 'Uso dos módulos',
            subtitulo: d == null
                ? (_carregando
                    ? 'Lendo a base inteira no servidor (pode levar até 1 min)…'
                    : 'Quem usa cada módulo do app')
                : 'Atualizado ${_df.format(DateTime.fromMillisecondsSinceEpoch(geradoEm ?? 0))}'
                    '${d['doCache'] == true ? ' (cache de 10 min — ↻ refaz)' : ''}',
            icone: Icons.dashboard_customize_rounded,
            cores: const [Color(0xFF052E16), Color(0xFF15803D), Color(0xFF0D9488)],
            carregando: _carregando,
            onAtualizar: () => _carregar(forcar: true),
          ),
          if (_erro != null)
            AdminErroCard(
              erro: _erro,
              onTentar: () => _carregar(forcar: true),
              titulo: d == null
                  ? 'Não foi possível carregar o uso dos módulos'
                  : 'Não deu para atualizar (mostrando o último resultado)',
            ),
          if (d == null && _carregando && _erro == null)
            const AdminCarregando(texto: 'Contando registros por módulo…'),
          if (d != null) ..._conteudo(d),
        ],
      ),
    );
  }

  List<Widget> _conteudo(Map<String, dynamic> d) {
    final atv = _map(d['atividade']);
    final fin = _map(d['financeiroTotais']);
    final total = _int(atv['total']);
    final modulos = (d['modulos'] is List ? d['modulos'] as List : const [])
        .map(_map)
        .toList();
    final plataformas = _map(atv['plataformas']).entries.toList()
      ..sort((a, b) => _int(b.value).compareTo(_int(a.value)));
    String pct(int n) => total == 0 ? '0%' : '${(n * 100 / total).round()}%';
    return [
      const AdminSecao(
        titulo: 'Atividade (último acesso do app)',
        cor: AdminUi.verde,
        icone: Icons.insights_rounded,
      ),
      AdminKpiGrid(children: [
        AdminKpi(
          rotulo: 'Ativos hoje',
          valor: '${_int(atv['hoje'])}',
          sub: '${pct(_int(atv['hoje']))} dos $total cadastros',
          icone: Icons.today_rounded,
          cor: AdminUi.verde,
        ),
        AdminKpi(
          rotulo: 'Ativos em 7 dias',
          valor: '${_int(atv['dias7'])}',
          sub: pct(_int(atv['dias7'])),
          icone: Icons.date_range_rounded,
          cor: AdminUi.teal,
        ),
        AdminKpi(
          rotulo: 'Ativos em 30 dias',
          valor: '${_int(atv['dias30'])}',
          sub: pct(_int(atv['dias30'])),
          icone: Icons.calendar_month_rounded,
          cor: AdminUi.azul,
        ),
        AdminKpi(
          rotulo: 'Sem registro de acesso',
          valor: '${_int(atv['semRegistro'])}',
          sub: 'Versões antigas ou nunca abriram',
          icone: Icons.help_outline_rounded,
          cor: AdminUi.cinza,
        ),
      ]),
      if (plataformas.isNotEmpty) ...[
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in plataformas)
              AdminSelo('${p.key}: ${_int(p.value)} (30 d)',
                  cor: AdminUi.azul, icone: _iconePlataforma(p.key)),
          ],
        ),
      ],
      const AdminSecao(
        titulo: 'Financeiro dos usuários',
        cor: AdminUi.ambar,
        icone: Icons.account_balance_wallet_rounded,
      ),
      AdminKpiGrid(children: [
        AdminKpi(
          rotulo: 'Receitas realizadas',
          valor: _moeda.format(_num(fin['receitas'])),
          sub: 'No mês: ${_moeda.format(_num(fin['receitasMes']))}',
          icone: Icons.trending_up_rounded,
          cor: AdminUi.verde,
        ),
        AdminKpi(
          rotulo: 'Despesas realizadas',
          valor: _moeda.format(_num(fin['despesas'])),
          sub: 'No mês: ${_moeda.format(_num(fin['despesasMes']))}',
          icone: Icons.trending_down_rounded,
          cor: AdminUi.vermelho,
        ),
        AdminKpi(
          rotulo: 'Pendentes (vencidos)',
          valor: _moeda.format(_num(fin['despesasPendentes'])),
          sub: 'A receber ${_moeda.format(_num(fin['receitasPendentes']))}',
          icone: Icons.pending_actions_rounded,
          cor: AdminUi.ambar,
        ),
        AdminKpi(
          rotulo: 'Usuários com lançamentos',
          valor: '${_int(fin['usuarios'])}',
          sub: '${_int(fin['qtdReceitas']) + _int(fin['qtdDespesas'])} lançamentos'
              '${_int(fin['ignorados']) > 0 ? ' · ${_int(fin['ignorados'])} de teste fora' : ''}',
          icone: Icons.people_alt_rounded,
          cor: AdminUi.azul,
        ),
      ]),
      const AdminSecao(
        titulo: 'Módulos',
        cor: AdminUi.teal,
        icone: Icons.apps_rounded,
      ),
      AdminKpiGrid(
        maxColunas: 3,
        children: [
          for (final m in modulos) _cartaoModulo(m, total, _map(d['usuarios'])),
        ],
      ),
    ];
  }

  IconData _iconePlataforma(String p) {
    switch (p) {
      case 'android':
        return Icons.android_rounded;
      case 'ios':
      case 'macos':
        return Icons.phone_iphone_rounded;
      case 'web':
        return Icons.public_rounded;
      default:
        return Icons.devices_other_rounded;
    }
  }

  Widget _cartaoModulo(
      Map<String, dynamic> m, int base, Map<String, dynamic> pessoas) {
    final usuarios = _int(m['usuarios']);
    final ativos = _int(m['ativos30']);
    final frac = base == 0 ? 0.0 : (usuarios / base).clamp(0.0, 1.0);
    const cor = AdminUi.teal;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: usuarios == 0 ? null : () => _abrirModulo(m, pessoas),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cor.withValues(alpha: 0.25)),
            gradient: LinearGradient(
              colors: [cor.withValues(alpha: 0.08), Colors.white],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      (m['titulo'] ?? '').toString(),
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5),
                    ),
                  ),
                  if (usuarios > 0)
                    Icon(Icons.chevron_right_rounded, color: Colors.grey.shade500),
                ],
              ),
              Text(
                (m['descricao'] ?? '').toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _num2('$usuarios', 'usuários'),
                  _num2('$ativos', 'ativos 30 d'),
                  _num2('${_int(m['registros'])}', 'registros'),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: frac,
                  minHeight: 6,
                  color: cor,
                  backgroundColor: cor.withValues(alpha: 0.12),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${(frac * 100).toStringAsFixed(frac > 0 && frac < 0.01 ? 1 : 0)}% da base'
                ' · ${_int(m['registros30'])} registros em 30 dias',
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _num2(String v, String r) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(v, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            Text(r, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
          ],
        ),
      );

  void _abrirModulo(Map<String, dynamic> m, Map<String, dynamic> pessoas) {
    final porUid = _map(m['porUid']);
    final linhas = porUid.entries.map((e) {
      final g = _map(e.value);
      final p = _map(pessoas[e.key]);
      return (
        uid: e.key,
        nome: (p['nome'] ?? '').toString(),
        email: (p['email'] ?? e.key).toString(),
        qtd: _int(g['qtd']),
        ult30: _int(g['ultimos30']),
        ultima: _int(g['ultima']),
        saldo: g.containsKey('saldo') ? _num(g['saldo']) : null,
      );
    }).toList()
      ..sort((a, b) => b.ultima.compareTo(a.ultima));
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _ListaModuloSheet(
        titulo: (m['titulo'] ?? '').toString(),
        linhas: linhas,
        moeda: _moeda,
        df: _df,
      ),
    );
  }
}

typedef _LinhaUso = ({
  String uid,
  String nome,
  String email,
  int qtd,
  int ult30,
  int ultima,
  double? saldo,
});

class _ListaModuloSheet extends StatefulWidget {
  const _ListaModuloSheet({
    required this.titulo,
    required this.linhas,
    required this.moeda,
    required this.df,
  });

  final String titulo;
  final List<_LinhaUso> linhas;
  final NumberFormat moeda;
  final DateFormat df;

  @override
  State<_ListaModuloSheet> createState() => _ListaModuloSheetState();
}

class _ListaModuloSheetState extends State<_ListaModuloSheet> {
  final _ctrl = TextEditingController();
  String _q = '';
  bool _so30 = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final lista = widget.linhas.where((l) {
      if (_so30 && l.ult30 == 0) return false;
      if (q.isEmpty) return true;
      return '${l.nome} ${l.email}'.toLowerCase().contains(q);
    }).toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.82,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.titulo} · ${widget.linhas.length} usuário(s)',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 10),
            AdminBusca(
              controller: _ctrl,
              hint: 'Buscar nome ou e-mail…',
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                label: const Text('Só ativos em 30 dias'),
                selected: _so30,
                onSelected: (v) => setState(() => _so30 = v),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: lista.isEmpty
                  ? const AdminVazio(texto: 'Ninguém neste filtro.')
                  : ListView.separated(
                      itemCount: lista.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, color: Colors.grey.shade200),
                      itemBuilder: (_, i) {
                        final l = lista[i];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            l.nome.isEmpty ? l.email : l.nome,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${l.nome.isEmpty ? '' : '${l.email} · '}'
                            '${l.qtd} registros · ${l.ult30} em 30 d'
                            '${l.ultima > 0 ? ' · último ${widget.df.format(DateTime.fromMillisecondsSinceEpoch(l.ultima))}' : ''}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: l.saldo == null
                              ? null
                              : Text(
                                  widget.moeda.format(l.saldo),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: (l.saldo ?? 0) < 0
                                        ? AdminUi.vermelho
                                        : AdminUi.verde,
                                  ),
                                ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
