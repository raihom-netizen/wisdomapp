import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/theme_context.dart';
import '../utils/admin_load_guard.dart';
import '../widgets/admin/admin_page_shell.dart';
import '../widgets/admin/admin_ui_kit.dart';

/// Logs de atividade do painel (`activity_logs`) — padrão Controle Total.
///
/// 02/10/2026: antes era um StatelessWidget com `.snapshots()` dentro do
/// build (escuta nova a cada rebuild do admin → no Firestore Web podia ficar
/// girando para sempre). Agora: páginas de 50 por `get()` com prazo,
/// «Carregar mais», filtros por módulo/período/busca e erro visível.
/// Filtro por módulo no servidor usa o índice `activity_logs (modulo ↑,
/// timestamp ↓)`; sem o índice publicado cai no filtro local e avisa.
class LogsAtividadePage extends StatelessWidget {
  final bool isMaster;

  /// Dentro do [AdminScreen]: sem Scaffold/AppBar próprios — full screen no painel.
  final bool embeddedInAdmin;

  const LogsAtividadePage({
    super.key,
    this.isMaster = false,
    this.embeddedInAdmin = false,
  });

  @override
  Widget build(BuildContext context) {
    final body = _LogsBody(isMaster: isMaster);
    if (embeddedInAdmin) return body;
    return Scaffold(
      backgroundColor: AdminPageShell.backgroundOf(context),
      appBar: AppBar(
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Voltar',
              )
            : null,
        title: const Text('Auditoria do Sistema'),
        elevation: 0,
      ),
      body: SafeArea(child: body),
    );
  }
}

class _LogsBody extends StatefulWidget {
  const _LogsBody({required this.isMaster});

  final bool isMaster;

  @override
  State<_LogsBody> createState() => _LogsBodyState();
}

enum _Periodo { hoje, dias7, dias30, tudo }

class _LogsBodyState extends State<_LogsBody> {
  static const _pagina = 50;
  static const _modulosFixos = ['Admin', 'Financeiro', 'Escalas', 'Agenda', 'Cursos'];

  final _buscaCtrl = TextEditingController();
  String _busca = '';
  String? _modulo;
  _Periodo _periodo = _Periodo.dias30;

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];
  bool _carregando = false;
  bool _fim = false;
  Object? _erro;
  bool _semIndice = false;

  @override
  void initState() {
    super.initState();
    _recarregar();
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  DateTime? get _desde {
    final agora = DateTime.now();
    switch (_periodo) {
      case _Periodo.hoje:
        return DateTime(agora.year, agora.month, agora.day);
      case _Periodo.dias7:
        return agora.subtract(const Duration(days: 7));
      case _Periodo.dias30:
        return agora.subtract(const Duration(days: 30));
      case _Periodo.tudo:
        return null;
    }
  }

  Query<Map<String, dynamic>> _consulta({required bool comModulo}) {
    Query<Map<String, dynamic>> q =
        FirebaseFirestore.instance.collection('activity_logs');
    if (comModulo && _modulo != null) {
      q = q.where('modulo', isEqualTo: _modulo);
    }
    final desde = _desde;
    if (desde != null) {
      q = q.where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(desde));
    }
    return q.orderBy('timestamp', descending: true);
  }

  Future<void> _recarregar() async {
    setState(() {
      _docs.clear();
      _fim = false;
      _erro = null;
      _semIndice = false;
    });
    await _carregarMais();
  }

  Future<void> _carregarMais() async {
    if (_carregando || _fim) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    final opts = GetOptions(source: kIsWeb ? Source.server : Source.serverAndCache);
    Future<QuerySnapshot<Map<String, dynamic>>> buscar(bool comModulo) {
      var q = _consulta(comModulo: comModulo).limit(_pagina);
      if (_docs.isNotEmpty) q = q.startAfterDocument(_docs.last);
      return AdminLoadGuard.comPrazo(q.get(opts), oQue: 'os logs');
    }

    try {
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await buscar(!_semIndice);
      } catch (e) {
        if (!AdminLoadGuard.faltaIndice(e) || _modulo == null) rethrow;
        // Índice (modulo, timestamp) ainda não publicado: filtra no aparelho.
        _semIndice = true;
        snap = await buscar(false);
      }
      if (!mounted) return;
      setState(() {
        _docs.addAll(snap.docs);
        _fim = snap.docs.length < _pagina;
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

  bool _passa(Map<String, dynamic> d) {
    if (_modulo != null && (d['modulo'] ?? '').toString() != _modulo) {
      return false;
    }
    final q = _busca.trim().toLowerCase();
    if (q.isEmpty) return true;
    return '${d['acao']} ${d['adminEmail']} ${d['detalhes']} ${d['modulo']}'
        .toLowerCase()
        .contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final pad = AdminPageShell.listPadding(context, top: 4);
    final visiveis = _docs.where((d) => _passa(d.data())).toList();
    final hoje = DateTime.now();
    final inicioHoje = DateTime(hoje.year, hoje.month, hoje.day);
    var nHoje = 0;
    final porAdmin = <String, int>{};
    final modulos = <String>{..._modulosFixos};
    for (final d in _docs) {
      final m = d.data();
      final t = (m['timestamp'] as Timestamp?)?.toDate();
      if (t != null && !t.isBefore(inicioHoje)) nHoje++;
      final quem = (m['adminEmail'] ?? '—').toString();
      porAdmin[quem] = (porAdmin[quem] ?? 0) + 1;
      final mod = (m['modulo'] ?? '').toString();
      if (mod.isNotEmpty) modulos.add(mod);
    }
    final topAdmin = porAdmin.entries.isEmpty
        ? null
        : (porAdmin.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first;

    return RefreshIndicator(
      onRefresh: _recarregar,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: pad.copyWith(bottom: pad.bottom + 32),
        children: [
          AdminHero(
            titulo: 'Logs de atividade',
            subtitulo: widget.isMaster
                ? 'Auditoria de tudo o que a equipe fez no painel.'
                : 'Ações recentes da equipe no painel.',
            icone: Icons.history_rounded,
            cores: const [Color(0xFF0F172A), Color(0xFF334155), Color(0xFF64748B)],
            carregando: _carregando,
            onAtualizar: _recarregar,
          ),
          const SizedBox(height: 12),
          AdminKpiGrid(children: [
            AdminKpi(
              rotulo: 'Carregados',
              valor: '${_docs.length}${_fim ? '' : '+'}',
              sub: _rotuloPeriodo(_periodo),
              icone: Icons.list_alt_rounded,
              cor: AdminUi.cinza,
            ),
            AdminKpi(
              rotulo: 'Hoje',
              valor: '$nHoje',
              sub: 'Ações desde 00:00',
              icone: Icons.today_rounded,
              cor: AdminUi.azul,
            ),
            AdminKpi(
              rotulo: 'Quem mais agiu',
              valor: topAdmin == null ? '—' : '${topAdmin.value}',
              sub: topAdmin?.key ?? 'Sem registros',
              icone: Icons.person_search_rounded,
              cor: AdminUi.roxo,
            ),
            AdminKpi(
              rotulo: 'Após filtros',
              valor: '${visiveis.length}',
              sub: _modulo == null ? 'Todos os módulos' : 'Módulo $_modulo',
              icone: Icons.filter_alt_rounded,
              cor: AdminUi.teal,
            ),
          ]),
          const SizedBox(height: 12),
          AdminBusca(
            controller: _buscaCtrl,
            hint: 'Buscar ação, e-mail ou detalhe…',
            onChanged: (v) => setState(() => _busca = v),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final p in _Periodo.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(_rotuloPeriodo(p)),
                      selected: _periodo == p,
                      onSelected: (_) {
                        if (_periodo == p) return;
                        _periodo = p;
                        _recarregar();
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: const Text('Todos os módulos'),
                    selected: _modulo == null,
                    onSelected: (_) {
                      if (_modulo == null) return;
                      _modulo = null;
                      _recarregar();
                    },
                  ),
                ),
                for (final m in (modulos.toList()..sort()))
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      avatar: Icon(_iconeModulo(m).$1, size: 16, color: _iconeModulo(m).$2),
                      label: Text(m),
                      selected: _modulo == m,
                      onSelected: (_) {
                        _modulo = _modulo == m ? null : m;
                        _recarregar();
                      },
                    ),
                  ),
              ],
            ),
          ),
          if (_semIndice)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Filtro por módulo feito no aparelho (falta publicar o índice '
                'activity_logs modulo+timestamp). Use «Carregar mais» para ver mais.',
                style: TextStyle(fontSize: 11.5, color: Colors.orange.shade800),
              ),
            ),
          const SizedBox(height: 10),
          if (_erro != null)
            AdminErroCard(erro: _erro, onTentar: _docs.isEmpty ? _recarregar : _carregarMais),
          if (_docs.isEmpty && _carregando)
            const AdminCarregando(texto: 'Carregando os logs…')
          else if (_docs.isNotEmpty || _erro == null) ...[
            if (visiveis.isEmpty && !_carregando)
              AdminVazio(
                texto: _docs.isEmpty
                    ? 'Nenhum log neste período.'
                    : 'Nenhum log corresponde à busca.',
                icone: Icons.history_toggle_off_rounded,
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: AdminUi.cardOf(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AdminUi.bordaOf(context)),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < visiveis.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: context.isDarkMode ? context.appBorderSubtle : Colors.grey.shade100),
                      _LogLinha(log: visiveis[i].data()),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 12),
            if (!_fim && _docs.isNotEmpty)
              Center(
                child: OutlinedButton.icon(
                  onPressed: _carregando ? null : _carregarMais,
                  icon: _carregando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.expand_more_rounded),
                  label: Text(_carregando ? 'Carregando…' : 'Carregar mais $_pagina'),
                ),
              )
            else if (_docs.isNotEmpty)
              Center(
                child: Text(
                  'Fim dos logs deste período.',
                  style: TextStyle(fontSize: 12, color: AdminUi.apoioOf(context)),
                ),
              ),
          ],
        ],
      ),
    );
  }

  static String _rotuloPeriodo(_Periodo p) {
    switch (p) {
      case _Periodo.hoje:
        return 'Hoje';
      case _Periodo.dias7:
        return '7 dias';
      case _Periodo.dias30:
        return '30 dias';
      case _Periodo.tudo:
        return 'Tudo';
    }
  }
}

(IconData, Color) _iconeModulo(String modulo) {
  switch (modulo) {
    case 'Financeiro':
      return (Icons.attach_money_rounded, Colors.green);
    case 'Escalas':
      return (Icons.calendar_month_rounded, Colors.orange);
    case 'Admin':
      return (Icons.admin_panel_settings_rounded, Colors.purple);
    case 'Agenda':
      return (Icons.event_rounded, Colors.blue);
    case 'Cursos':
      return (Icons.ondemand_video_rounded, Colors.red);
    default:
      return (Icons.history_rounded, Colors.blueGrey);
  }
}

class _LogLinha extends StatelessWidget {
  const _LogLinha({required this.log});

  final Map<String, dynamic> log;

  @override
  Widget build(BuildContext context) {
    final modulo = (log['modulo'] ?? '').toString();
    final (icone, cor) = _iconeModulo(modulo);
    final data = (log['timestamp'] as Timestamp?)?.toDate();
    final detalhes = (log['detalhes'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: cor.withValues(alpha: 0.12),
            child: Icon(icone, color: cor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (log['acao'] ?? '').toString(),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (modulo.isNotEmpty) AdminSelo(modulo, cor: cor),
                    Text(
                      (log['adminEmail'] ?? '—').toString(),
                      style: TextStyle(color: AdminUi.apoioOf(context), fontSize: 12),
                    ),
                  ],
                ),
                if (detalhes.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    detalhes,
                    style: TextStyle(
                      color: context.isDarkMode ? context.appTextSecondary : Colors.grey.shade700,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            data == null ? '—' : DateFormat('dd/MM HH:mm').format(data),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
              color: AdminUi.azul,
            ),
          ),
        ],
      ),
    );
  }
}
