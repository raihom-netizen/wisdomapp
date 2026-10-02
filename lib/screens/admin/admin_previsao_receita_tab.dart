import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/theme_context.dart';
import '../../utils/admin_load_guard.dart';
import '../../widgets/admin/admin_page_shell.dart';
import '../../widgets/admin/admin_ui_kit.dart';

/// «Previsão & planos» com receita REAL (porte do Controle Total,
/// 02/10/2026). Só conta quem PAGA: pagamento de licença aprovado no Mercado
/// Pago (`mp_payments`) + licença válida (`users.licenseExpiresAt`). Teste,
/// cortesia e convênio aparecem como contagem, fora da previsão; App Store
/// (iOS) aparece à parte, com valor estimado pelo preço do checkout.
/// Dados da callable `ctAdminPrevisaoReceita` (cache de 10 min no servidor).
class AdminPrevisaoReceitaTab extends StatefulWidget {
  const AdminPrevisaoReceitaTab({super.key});

  @override
  State<AdminPrevisaoReceitaTab> createState() =>
      _AdminPrevisaoReceitaTabState();
}

class _AdminPrevisaoReceitaTabState extends State<AdminPrevisaoReceitaTab> {
  static const _fnNome = 'ctAdminPrevisaoReceita';
  static final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  static final _df = DateFormat('dd/MM/yy HH:mm');
  static final _dfDia = DateFormat('dd/MM/yy');

  Map<String, dynamic>? _d;
  Object? _erro;
  bool _carregando = false;
  String _filtro = 'pagante_ativo';
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
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable(
        _fnNome,
        options: HttpsCallableOptions(timeout: AdminLoadGuard.callable),
      );
      final res = await AdminLoadGuard.comPrazo(
        fn.call<dynamic>({'forcar': forcar}),
        prazo: AdminLoadGuard.callable + const Duration(seconds: 10),
        oQue: 'a previsão de receita',
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

  Map<String, dynamic> _map(Object? v) =>
      v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};
  List<Map<String, dynamic>> _lista(Object? v) =>
      v is List ? v.map(_map).toList() : const <Map<String, dynamic>>[];
  int _int(Object? v) => v is num ? v.toInt() : 0;
  double _num(Object? v) => v is num ? v.toDouble() : 0;
  String _data(int ms) =>
      ms > 0 ? _dfDia.format(DateTime.fromMillisecondsSinceEpoch(ms)) : '—';

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
            titulo: 'Previsão & planos',
            subtitulo: d == null
                ? (_carregando
                    ? 'Separando quem paga de quem está em teste/cortesia…'
                    : 'Receita prevista só de quem paga de verdade')
                : 'Atualizado ${_df.format(DateTime.fromMillisecondsSinceEpoch(geradoEm))}'
                    '${d['doCache'] == true ? ' (cache de 10 min — ↻ refaz)' : ''}',
            icone: Icons.insights_rounded,
            cores: const [Color(0xFF1E1B4B), Color(0xFF4F46E5), Color(0xFF0D9488)],
            carregando: _carregando,
            onAtualizar: () => _carregar(forcar: true),
          ),
          if (_erro != null)
            AdminErroCard(
              erro: _erro,
              onTentar: () => _carregar(forcar: true),
              titulo: d == null
                  ? 'Não foi possível carregar a previsão'
                  : 'Não deu para atualizar (mostrando o último resultado)',
            ),
          if (d == null && _carregando && _erro == null)
            const AdminCarregando(texto: 'Lendo pagamentos e licenças…'),
          if (d != null) ..._conteudo(d),
        ],
      ),
    );
  }

  List<Widget> _conteudo(Map<String, dynamic> d) {
    final r = _map(d['resumo']);
    final ios = _map(d['ios']);
    final planos = _lista(d['planos']);
    final lucro = _num(r['lucroPrevistoMes']);
    return [
      if (d['limiteAtingido'] == true || d['iosLimiteAtingido'] == true)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: AdminSelo(
            'Base grande: parte dos pagamentos/assinaturas pode ter ficado de fora',
            cor: AdminUi.ambar,
            icone: Icons.warning_amber_rounded,
          ),
        ),
      const AdminSecao(
        titulo: 'Receita recorrente (Mercado Pago)',
        cor: AdminUi.azul,
        icone: Icons.autorenew_rounded,
      ),
      AdminKpiGrid(children: [
        AdminKpi(
          rotulo: 'MRR (por mês)',
          valor: _moeda.format(_num(r['mrr'])),
          sub: 'ARR ${_moeda.format(_num(r['arr']))} · ticket '
              '${_moeda.format(_num(r['ticketMedio']))}',
          icone: Icons.trending_up_rounded,
          cor: AdminUi.azul,
        ),
        AdminKpi(
          rotulo: 'Pagantes ativos',
          valor: '${_int(r['pagantesAtivos'])}',
          sub: '${_int(r['pagantesVencidos'])} vencido(s) sem renovar',
          icone: Icons.verified_rounded,
          cor: AdminUi.verde,
          selecionado: _filtro == 'pagante_ativo',
          onTap: () => setState(() => _filtro = 'pagante_ativo'),
        ),
        AdminKpi(
          rotulo: 'Previsto no mês',
          valor: _moeda.format(_num(r['receitaPrevistaMes'])),
          sub: 'Já entrou ${_moeda.format(_num(r['pagoMesTotal']))} · '
              'a receber ${_moeda.format(_num(r['aReceberMes']))}',
          icone: Icons.event_available_rounded,
          cor: AdminUi.teal,
        ),
        AdminKpi(
          rotulo: lucro >= 0 ? 'Lucro previsto' : 'Prejuízo previsto',
          valor: _moeda.format(lucro),
          sub: 'Custos ${_moeda.format(_num(r['custoMes']))} '
              '(fixos ${_moeda.format(_num(r['custoFixoMes']))} + taxa MP '
              '${_num(r['taxaMediaMp']).toStringAsFixed(1)}%)',
          icone: lucro >= 0
              ? Icons.savings_rounded
              : Icons.money_off_csred_rounded,
          cor: lucro >= 0 ? AdminUi.verde : AdminUi.vermelho,
        ),
        AdminKpi(
          rotulo: 'Renovam em 30 dias',
          valor: _moeda.format(_num(r['renovam30'])),
          sub: 'Valor do último pagamento de quem vence',
          icone: Icons.schedule_rounded,
          cor: AdminUi.ambar,
        ),
        AdminKpi(
          rotulo: 'Pagantes vencidos',
          valor: '${_int(r['pagantesVencidos'])}',
          sub: 'Já pagaram e não renovaram',
          icone: Icons.history_toggle_off_rounded,
          cor: AdminUi.vermelho,
          selecionado: _filtro == 'pagante_vencido',
          onTap: () => setState(() => _filtro = 'pagante_vencido'),
        ),
      ]),
      const AdminSecao(
        titulo: 'Quem não entra na previsão',
        cor: AdminUi.cinza,
        icone: Icons.groups_rounded,
      ),
      AdminKpiGrid(children: [
        AdminKpi(
          rotulo: 'Licença sem pagamento',
          valor: '${_int(r['licencaSemPagamento'])}',
          sub: 'Teste, cortesia ou convênio · '
              '${_int(r['licencaValida'])} licenças válidas no total',
          icone: Icons.card_giftcard_rounded,
          cor: AdminUi.roxo,
        ),
        AdminKpi(
          rotulo: 'Convênio',
          valor: '${_int(r['convenio'])}',
          sub: 'Cadastros com parceria',
          icone: Icons.handshake_rounded,
          cor: AdminUi.rosa,
        ),
        AdminKpi(
          rotulo: 'Grátis',
          valor: '${_int(r['free'])}',
          sub: 'de ${_int(r['usuarios'])} cadastros',
          icone: Icons.person_outline_rounded,
          cor: AdminUi.cinza,
        ),
        AdminKpi(
          rotulo: 'App Store (iOS)',
          valor: '${_int(r['iosAtivos'])} ativos',
          sub: '≈ ${_moeda.format(_num(r['iosMrrEstimado']))}/mês estimado '
              '(${_int(ios['mensais'])} mensal · ${_int(ios['anuais'])} anual) · '
              'bruto, antes da taxa da Apple',
          icone: Icons.phone_iphone_rounded,
          cor: AdminUi.tinta,
        ),
      ]),
      if (_num(r['pagoContasApagadas']) > 0 || _int(r['pagamentosSemDono']) > 0)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Fora da previsão: ${_moeda.format(_num(r['pagoContasApagadas']))} '
            'pagos por contas apagadas · ${_int(r['pagamentosSemDono'])} '
            'pagamento(s) sem usuário identificado.',
            style: TextStyle(fontSize: 11.5, color: AdminUi.apoioOf(context)),
          ),
        ),
      const AdminSecao(
        titulo: 'Por plano',
        cor: AdminUi.roxo,
        icone: Icons.workspace_premium_rounded,
      ),
      if (planos.isEmpty)
        const AdminVazio(texto: 'Nenhum pagamento aprovado ainda.')
      else
        for (final p in planos) _cardPlano(p),
      const AdminSecao(
        titulo: 'Pagantes',
        cor: AdminUi.teal,
        icone: Icons.people_alt_rounded,
      ),
      ..._usuarios(d),
    ];
  }

  Widget _cardPlano(Map<String, dynamic> p) {
    final tinta = AdminUi.tintaOf(context);
    final apoio = AdminUi.apoioOf(context);
    Widget celula(String rotulo, String valor) => SizedBox(
          width: 132,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(rotulo, style: TextStyle(fontSize: 11, color: apoio)),
              Text(valor,
                  style: TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w800, color: tinta)),
            ],
          ),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AdminUi.cardOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminUi.bordaOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text((p['rotulo'] ?? p['id'] ?? '').toString(),
                    style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14, color: tinta)),
              ),
              if (p['licenca'] == false)
                const AdminSelo('Adicional', cor: AdminUi.ambar),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              celula('Ativos', '${_int(p['ativos'])}'),
              celula('Vencidos', '${_int(p['vencidos'])}'),
              celula('MRR', _moeda.format(_num(p['mrr']))),
              celula('Renovam 30 d',
                  '${_int(p['renovam30'])} · ${_moeda.format(_num(p['valorRenovam30']))}'),
              celula('Pago no mês', _moeda.format(_num(p['pagoMes']))),
              celula('Pago no total', _moeda.format(_num(p['pagoTotal']))),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _usuarios(Map<String, dynamic> d) {
    final todos = _lista(d['usuarios']);
    final q = _busca.trim().toLowerCase();
    final lista = todos.where((u) {
      if (_filtro != 'todos' && u['classe'] != _filtro) return false;
      if (q.isEmpty) return true;
      return (u['nome'] ?? '').toString().toLowerCase().contains(q) ||
          (u['email'] ?? '').toString().toLowerCase().contains(q);
    }).toList();
    const filtros = {
      'pagante_ativo': 'Ativos',
      'pagante_vencido': 'Vencidos',
      'todos': 'Todos',
    };
    return [
      Wrap(
        spacing: 8,
        children: [
          for (final f in filtros.entries)
            ChoiceChip(
              label: Text(f.value),
              selected: _filtro == f.key,
              onSelected: (_) => setState(() => _filtro = f.key),
            ),
        ],
      ),
      const SizedBox(height: 8),
      AdminBusca(
        controller: _buscaCtrl,
        onChanged: (v) => setState(() => _busca = v),
        hint: 'Buscar por nome ou e-mail…',
      ),
      if (_int(d['usuariosTotal']) > todos.length)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Lista limitada a ${todos.length} de ${_int(d['usuariosTotal'])} pagantes.',
            style: TextStyle(fontSize: 11.5, color: AdminUi.apoioOf(context)),
          ),
        ),
      const SizedBox(height: 8),
      if (lista.isEmpty)
        const AdminVazio(texto: 'Ninguém neste filtro.')
      else
        for (final u in lista) _linhaUsuario(u),
    ];
  }

  Widget _linhaUsuario(Map<String, dynamic> u) {
    final classe = (u['classe'] ?? '').toString();
    final nome = (u['nome'] ?? '').toString();
    final email = (u['email'] ?? '').toString();
    final vence = _int(u['vence']);
    final (rotulo, cor) = switch (classe) {
      'pagante_ativo' => ('Pagante ativo', AdminUi.verde),
      'pagante_vencido' => ('Vencido', AdminUi.vermelho),
      'equipe' => ('Equipe', AdminUi.cinza),
      _ => ('Só adicional', AdminUi.ambar),
    };
    final diasParaVencer = vence > 0
        ? (vence - DateTime.now().millisecondsSinceEpoch) ~/ 86400000
        : null;
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
                '${_moeda.format(_num(u['mensalEquivalente']))}/mês',
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: AdminUi.azul),
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
              AdminSelo(rotulo, cor: cor),
              if ((u['rotuloPlano'] ?? '').toString().isNotEmpty)
                AdminSelo(u['rotuloPlano'].toString(), cor: AdminUi.azul),
              if (u['ios'] == true)
                const AdminSelo('Também iOS', cor: AdminUi.tinta),
              if (classe == 'pagante_ativo' &&
                  diasParaVencer != null &&
                  diasParaVencer <= 30)
                AdminSelo('Vence em $diasParaVencer d', cor: AdminUi.ambar),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Último pagamento ${_data(_int(u['ultimoPagamento']))} '
            '(${_moeda.format(_num(u['ultimoValor']))}) · licença até '
            '${_data(vence)} · ${_int(u['pagamentos'])} pagamento(s), '
            '${_moeda.format(_num(u['totalPago']))} no total',
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
}
