import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../theme/theme_context.dart';
import '../../utils/admin_load_guard.dart';
import 'admin_notificacoes_diag_sheet.dart' show mensagemErroNotificacoes;
import 'admin_page_shell.dart';
import 'admin_ui_kit.dart';

/// Abre o teste de push em lote (SÓ master) em tela cheia.
Future<void> abrirTesteNotificacaoEmLote(BuildContext context, {String? preSelecionado}) {
  return Navigator.of(context).push<void>(MaterialPageRoute<void>(
    builder: (_) => Scaffold(
      backgroundColor: AdminPageShell.backgroundOf(context),
      appBar: AppBar(title: const Text('Teste de notificações')),
      body: AdminNotificacoesTesteLote(preSelecionado: preSelecionado),
    ),
  ));
}

/// Teste de push para alguns usuários, sem digitar (porte do Controle Total,
/// 02/10/2026 — só push, sem Telegram/e-mail/«aviso com OK»).
///
/// A lista vem do servidor com as plataformas dos aparelhos de cada usuário
/// (`ctAdminNotificacoesUsuarios`). O admin filtra, marca até [_maxLote]
/// pessoas, confirma e vê o resultado por usuário (`ctAdminNotificacoesTeste`,
/// só master — o servidor recusa os demais).
///
/// Precisa de altura limitada (usa `Expanded`): dentro de Scaffold/Expanded.
class AdminNotificacoesTesteLote extends StatefulWidget {
  const AdminNotificacoesTesteLote({super.key, this.preSelecionado});

  final String? preSelecionado;

  @override
  State<AdminNotificacoesTesteLote> createState() => _AdminNotificacoesTesteLoteState();
}

enum _Filtro { todos, iphone, android, web, semAparelho }

class _AdminNotificacoesTesteLoteState extends State<AdminNotificacoesTesteLote> {
  final _fn = FirebaseFunctions.instanceFor(region: 'us-central1');
  late Future<List<Map<String, dynamic>>> _usuarios = _carregar();
  final Set<String> _marcados = {};
  final _buscaCtrl = TextEditingController();
  _Filtro _filtro = _Filtro.todos;
  bool _enviando = false;
  int _maxLote = 20;
  Map<String, dynamic>? _resultado;
  String? _falha;

  @override
  void initState() {
    super.initState();
    final p = widget.preSelecionado;
    if (p != null && p.isNotEmpty) _marcados.add(p);
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _carregar() async {
    final r = await AdminLoadGuard.comPrazo(
      _fn
          .httpsCallable('ctAdminNotificacoesUsuarios', options: HttpsCallableOptions(timeout: AdminLoadGuard.callable))
          .call<dynamic>({}),
      prazo: AdminLoadGuard.callable + const Duration(seconds: 5),
      oQue: 'a lista de usuários',
    );
    final d = r.data is Map ? Map<String, dynamic>.from(r.data as Map) : <String, dynamic>{};
    final max = (d['maxLote'] as num?)?.toInt();
    if (max != null && max > 0) _maxLote = max;
    return ((d['usuarios'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static List<String> _plataformas(Map<String, dynamic> u) =>
      ((u['plataformas'] as List?) ?? const []).map((e) => '$e').toList();

  static bool _casaFiltro(Map<String, dynamic> u, _Filtro f) {
    final p = _plataformas(u);
    final n = (u['aparelhos'] as num?)?.toInt() ?? 0;
    return switch (f) {
      _Filtro.todos => true,
      _Filtro.iphone => p.contains('ios'),
      _Filtro.android => p.contains('android'),
      _Filtro.web => p.contains('web'),
      _Filtro.semAparelho => n == 0,
    };
  }

  bool _passaFiltro(Map<String, dynamic> u) {
    if (!_casaFiltro(u, _filtro)) return false;
    final q = _buscaCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    return '${u['nome'] ?? ''} ${u['email'] ?? ''} ${u['uid'] ?? ''}'.toLowerCase().contains(q);
  }

  static String _nomeDe(Map<String, dynamic> u) {
    final nome = '${u['nome'] ?? ''}'.trim();
    return nome.isNotEmpty ? nome : '${u['email'] ?? ''}';
  }

  static String _dataCurta(dynamic iso) {
    final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
    if (d == null) return 'nunca registrou aparelho';
    String p(int n) => n.toString().padLeft(2, '0');
    return 'aparelho visto em ${p(d.day)}/${p(d.month)}/${d.year}';
  }

  void _alternar(String uid) {
    setState(() {
      if (_marcados.contains(uid)) {
        _marcados.remove(uid);
      } else if (_marcados.length < _maxLote) {
        _marcados.add(uid);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No máximo $_maxLote usuários por teste.')),
        );
      }
    });
  }

  Future<void> _confirmarEEnviar(List<Map<String, dynamic>> todos) async {
    final escolhidos = todos.where((u) => _marcados.contains(u['uid'])).toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Enviar push de teste para ${_marcados.length} usuário(s)?'),
        content: Text(
          '${escolhidos.take(5).map(_nomeDe).join(', ')}'
          '${escolhidos.length > 5 ? ' e mais ${escolhidos.length - 5}' : ''}\n\n'
          'Cada um recebe de verdade «🔔 Teste de notificação» em todos os aparelhos. '
          'Token que a Firebase recusar como morto é apagado (mesma regra do envio normal). '
          'O envio fica registrado no log do admin.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AdminUi.roxo),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('Confirmar e enviar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _enviando = true;
      _resultado = null;
      _falha = null;
    });
    try {
      final r = await AdminLoadGuard.comPrazo(
        _fn
            .httpsCallable('ctAdminNotificacoesTeste', options: HttpsCallableOptions(timeout: AdminLoadGuard.callable))
            .call<dynamic>({'uids': _marcados.toList(), 'confirmar': true}),
        prazo: AdminLoadGuard.callable + const Duration(seconds: 5),
        oQue: 'o teste de notificação',
      );
      if (mounted) {
        setState(() => _resultado = r.data is Map ? Map<String, dynamic>.from(r.data as Map) : {});
      }
    } catch (e) {
      if (mounted) setState(() => _falha = mensagemErroNotificacoes(e, 'ctAdminNotificacoesTeste'));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Widget _chipFiltro(String rotulo, _Filtro f, IconData icone, int qtd) {
    final ativo = _filtro == f;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: ativo,
        onSelected: (_) => setState(() => _filtro = f),
        avatar: Icon(icone, size: 18, color: ativo ? Colors.white : AdminUi.roxo),
        label: Text('$rotulo · $qtd'),
        labelStyle: TextStyle(fontWeight: FontWeight.w800, color: ativo ? Colors.white : context.appTextPrimary),
        selectedColor: AdminUi.roxo,
        backgroundColor: context.appChipIdleBg,
        side: BorderSide(color: ativo ? AdminUi.roxo : context.appChipIdleBorder),
        showCheckmark: false,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  Widget _iconesPlataforma(List<String> p, int aparelhos) {
    if (aparelhos == 0) return const Icon(Icons.phonelink_erase_rounded, size: 17, color: AdminUi.vermelho);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (p.contains('ios')) const Icon(Icons.phone_iphone_rounded, size: 17, color: AdminUi.azul),
      if (p.contains('android')) const Icon(Icons.phone_android_rounded, size: 17, color: AdminUi.verde),
      if (p.contains('web')) const Icon(Icons.language_rounded, size: 17, color: AdminUi.teal),
      if (p.isEmpty) const Icon(Icons.devices_other_rounded, size: 17, color: AdminUi.cinza),
    ]);
  }

  Widget _painelResultado(List<Map<String, dynamic>> todos) {
    if (_falha != null) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AdminUi.vermelho.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline_rounded, color: AdminUi.vermelho),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Não foi possível enviar: $_falha',
                style: const TextStyle(color: AdminUi.vermelho, fontWeight: FontWeight.w700)),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _falha = null),
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ]),
      );
    }
    final r = _resultado;
    if (r == null) return const SizedBox.shrink();
    final resumo = Map<String, dynamic>.from((r['resumo'] as Map?) ?? const {});
    final itens = ((r['resultados'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final nomes = {for (final u in todos) '${u['uid']}': _nomeDe(u)};
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
      decoration: BoxDecoration(
        color: AdminUi.cardOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminUi.roxo.withValues(alpha: 0.45), width: 1.4),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 240),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(right: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.fact_check_rounded, color: AdminUi.roxo, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Resultado do teste',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: context.appTextPrimary)),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Fechar resultado',
                onPressed: () => setState(() => _resultado = null),
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ]),
            const SizedBox(height: 4),
            Wrap(spacing: 8, runSpacing: 6, children: [
              AdminSelo('${resumo['comEntrega'] ?? 0} com entrega', cor: AdminUi.verde, icone: Icons.check_rounded),
              AdminSelo('${resumo['semAparelho'] ?? 0} sem aparelho',
                  cor: AdminUi.ambar, icone: Icons.phonelink_erase_rounded),
              AdminSelo('${resumo['comFalha'] ?? 0} com falha', cor: AdminUi.vermelho, icone: Icons.error_rounded),
            ]),
            const SizedBox(height: 8),
            ...itens.map((i) {
              final entregues = (i['entregues'] as num?)?.toInt() ?? 0;
              final aparelhos = (i['aparelhos'] as num?)?.toInt() ?? 0;
              final erros = ((i['erros'] as List?) ?? const []).map((e) => '$e').toList();
              final cor = aparelhos == 0 ? AdminUi.ambar : (entregues > 0 ? AdminUi.verde : AdminUi.vermelho);
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: const EdgeInsets.only(top: 4), child: Icon(Icons.circle, size: 9, color: cor)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${nomes[i['uid']] ?? i['nome'] ?? i['uid']} — '
                      '${aparelhos == 0 ? 'sem aparelho registrado' : '$entregues de $aparelhos aparelho(s)'}'
                      '${erros.isNotEmpty ? ' · ${erros.join('; ')}' : ''}'
                      '${i['pushEnabled'] == false ? ' · push desligado no cadastro' : ''}',
                      style: TextStyle(fontSize: 12.5, color: context.appTextPrimary),
                    ),
                  ),
                ]),
              );
            }),
          ]),
        ),
      ),
    );
  }

  Widget _cardUsuario(Map<String, dynamic> u) {
    final uid = '${u['uid']}';
    final marcado = _marcados.contains(uid);
    final nome = '${u['nome'] ?? ''}';
    final email = '${u['email'] ?? ''}';
    final titulo = nome.isNotEmpty ? nome : email;
    final aparelhos = (u['aparelhos'] as num?)?.toInt() ?? 0;
    return Material(
      color: marcado ? AdminUi.roxo.withValues(alpha: context.isDarkMode ? 0.22 : 0.08) : AdminUi.cardOf(context),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _alternar(uid),
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: marcado ? AdminUi.roxo : AdminUi.bordaOf(context), width: marcado ? 1.5 : 1),
          ),
          child: Row(children: [
            Checkbox(
              value: marcado,
              onChanged: (_) => _alternar(uid),
              activeColor: AdminUi.roxo,
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo.isEmpty ? uid : titulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: context.appTextPrimary)),
                  const SizedBox(height: 2),
                  Text(
                    '${nome.isNotEmpty ? '$email · ' : ''}${_dataCurta(u['ultimoRegistro'])}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: context.appTextSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _iconesPlataforma(_plataformas(u), aparelhos),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _usuarios,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: AdminCarregando(texto: 'Lendo usuários e aparelhos…'));
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: AdminErroCard(
                erro: mensagemErroNotificacoes(snap.error, 'ctAdminNotificacoesUsuarios'),
                onTentar: () => setState(() => _usuarios = _carregar()),
              ),
            ),
          );
        }
        final todos = snap.data ?? const [];
        final visiveis = todos.where(_passaFiltro).toList();
        int qtd(_Filtro f) => todos.where((u) => _casaFiltro(u, f)).length;
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: AdminBusca(
              controller: _buscaCtrl,
              onChanged: (_) => setState(() {}),
              hint: 'Buscar por nome, e-mail ou UID',
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _chipFiltro('Todos', _Filtro.todos, Icons.groups_rounded, qtd(_Filtro.todos)),
                _chipFiltro('iPhone', _Filtro.iphone, Icons.phone_iphone_rounded, qtd(_Filtro.iphone)),
                _chipFiltro('Android', _Filtro.android, Icons.phone_android_rounded, qtd(_Filtro.android)),
                _chipFiltro('Web', _Filtro.web, Icons.language_rounded, qtd(_Filtro.web)),
                _chipFiltro('Sem aparelho', _Filtro.semAparelho, Icons.phonelink_erase_rounded,
                    qtd(_Filtro.semAparelho)),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            decoration: BoxDecoration(
              color: AdminUi.roxo.withValues(alpha: context.isDarkMode ? 0.25 : 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              const Icon(Icons.checklist_rounded, color: AdminUi.roxo, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_marcados.length} de no máximo $_maxLote selecionado(s)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: context.appTextPrimary),
                ),
              ),
              if (_marcados.isNotEmpty)
                IconButton(
                  tooltip: 'Limpar seleção',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(_marcados.clear),
                  icon: const Icon(Icons.clear_all_rounded, size: 20),
                ),
            ]),
          ),
          _painelResultado(todos),
          Expanded(
            child: visiveis.isEmpty
                ? const Center(child: AdminVazio(texto: 'Nenhum usuário neste filtro.'))
                : LayoutBuilder(builder: (context, c) {
                    final colunas = c.maxWidth >= 980 ? 3 : (c.maxWidth >= 640 ? 2 : 1);
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: colunas,
                        mainAxisExtent: 64,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: visiveis.length,
                      itemBuilder: (context, i) => _cardUsuario(visiveis[i]),
                    );
                  }),
          ),
          Container(
            decoration: BoxDecoration(
              color: AdminUi.cardOf(context),
              border: Border(top: BorderSide(color: AdminUi.bordaOf(context))),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: SizedBox(
                  height: 48,
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AdminUi.roxo,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _enviando || _marcados.isEmpty ? null : () => _confirmarEEnviar(todos),
                    icon: _enviando
                        ? const SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send_rounded, size: 19),
                    label: Text(_enviando ? 'Enviando…' : 'Testar push (${_marcados.length})',
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
              ),
            ),
          ),
        ]);
      },
    );
  }
}
