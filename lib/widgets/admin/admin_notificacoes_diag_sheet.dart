import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../theme/theme_context.dart';
import '../../utils/admin_load_guard.dart';
import 'admin_notificacoes_teste_lote.dart';
import 'admin_ui_kit.dart';

/// Diagnóstico de notificações de UM usuário (porte do Controle Total,
/// 02/10/2026 — só push; sem Telegram nem «aviso com OK»).
///
/// Mostra num lugar só o que explica «não recebo notificação»: aparelhos e
/// tokens (conferidos na Firebase em dry-run, nada é entregue), última
/// atividade da conta, preferências, fila de avisos da Agenda, últimos push,
/// eventos futuros — e um veredito. O botão «Testar push» (só master,
/// [podeTestar]) manda uma notificação de verdade, com confirmação.
/// Servidor: `ctAdminNotificacoesDiag` / `ctAdminNotificacoesTeste`.
Future<void> abrirDiagnosticoNotificacoes(
  BuildContext context, {
  required String uid,
  String nome = '',
  bool podeTestar = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.appSurface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _DiagnosticoSheet(uid: uid, nome: nome, podeTestar: podeTestar),
  );
}

/// Erro de callable em português (com o caso «função não publicada»).
String mensagemErroNotificacoes(Object? e, String funcao) {
  if (e is FirebaseFunctionsException && (e.code == 'not-found' || e.code == 'unimplemented')) {
    return 'Função ainda não publicada no servidor ($funcao).';
  }
  if (e is FirebaseFunctionsException && e.code == 'permission-denied') {
    return e.message ?? AdminLoadGuard.mensagem(e);
  }
  return AdminLoadGuard.mensagem(e);
}

class _DiagnosticoSheet extends StatefulWidget {
  const _DiagnosticoSheet({required this.uid, required this.nome, required this.podeTestar});

  final String uid;
  final String nome;
  final bool podeTestar;

  @override
  State<_DiagnosticoSheet> createState() => _DiagnosticoSheetState();
}

class _DiagnosticoSheetState extends State<_DiagnosticoSheet> {
  final _fn = FirebaseFunctions.instanceFor(region: 'us-central1');
  late Future<Map<String, dynamic>> _diag = _carregar();
  bool _testando = false;
  Map<String, dynamic>? _teste;
  String? _falhaTeste;

  Future<Map<String, dynamic>> _carregar() async {
    final r = await AdminLoadGuard.comPrazo(
      _fn
          .httpsCallable('ctAdminNotificacoesDiag', options: HttpsCallableOptions(timeout: AdminLoadGuard.longo))
          .call<dynamic>({'uid': widget.uid}),
      prazo: AdminLoadGuard.longo + const Duration(seconds: 5),
      oQue: 'o diagnóstico',
    );
    if (r.data is! Map) throw StateError('Resposta vazia do servidor.');
    return Map<String, dynamic>.from(r.data as Map);
  }

  void _recarregar() => setState(() => _diag = _carregar());

  Future<void> _testar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enviar push de teste?'),
        content: Text(
          '${widget.nome.isEmpty ? 'Este usuário' : widget.nome} vai receber de verdade a '
          'notificação «🔔 Teste de notificação» em todos os aparelhos registrados.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _testando = true;
      _teste = null;
      _falhaTeste = null;
    });
    try {
      final r = await AdminLoadGuard.comPrazo(
        _fn
            .httpsCallable('ctAdminNotificacoesTeste', options: HttpsCallableOptions(timeout: AdminLoadGuard.longo))
            .call<dynamic>({
          'uids': [widget.uid],
          'confirmar': true,
        }),
        prazo: AdminLoadGuard.longo + const Duration(seconds: 5),
        oQue: 'o teste de notificação',
      );
      final d = r.data is Map ? Map<String, dynamic>.from(r.data as Map) : <String, dynamic>{};
      final res = ((d['resultados'] as List?) ?? const []).whereType<Map>().toList();
      if (mounted) {
        setState(() => _teste = res.isEmpty ? <String, dynamic>{} : Map<String, dynamic>.from(res.first));
      }
    } catch (e) {
      if (mounted) setState(() => _falhaTeste = mensagemErroNotificacoes(e, 'ctAdminNotificacoesTeste'));
    } finally {
      if (mounted) setState(() => _testando = false);
    }
  }

  static String _dataHora(dynamic iso, {bool curta = false}) {
    final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
    if (d == null) return '—';
    String p(int n) => n.toString().padLeft(2, '0');
    return curta
        ? '${p(d.day)}/${p(d.month)} ${p(d.hour)}:${p(d.minute)}'
        : '${p(d.day)}/${p(d.month)}/${d.year} ${p(d.hour)}:${p(d.minute)}';
  }

  static IconData _iconePlataforma(String p) => switch (p) {
        'ios' => Icons.phone_iphone_rounded,
        'android' => Icons.phone_android_rounded,
        'web' => Icons.language_rounded,
        _ => Icons.devices_other_rounded,
      };

  Color get _fundoCard =>
      context.isDarkMode ? context.appSurfaceHigh.withValues(alpha: 0.35) : const Color(0xFFF8FAFC);

  Widget _secao(String titulo, IconData icone, Color cor, List<Widget> filhos, {Color? borda}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _fundoCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borda ?? context.appBorderSubtle, width: borda == null ? 1 : 1.4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: cor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
            child: Icon(icone, color: cor, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(titulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5, color: context.appTextPrimary)),
          ),
        ]),
        const SizedBox(height: 12),
        ...filhos,
      ]),
    );
  }

  Widget _linha(String rotulo, String valor, {Color? cor}) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 120,
            child: Text(rotulo, style: TextStyle(fontSize: 12.5, color: context.appTextSecondary)),
          ),
          Expanded(
            child: Text(valor,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cor ?? context.appTextPrimary)),
          ),
        ]),
      );

  Widget _itemVeredito(String texto, bool ok) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(ok ? Icons.check_circle_rounded : Icons.error_rounded,
                size: 17, color: ok ? AdminUi.verde : AdminUi.ambar),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(texto, style: TextStyle(fontSize: 13, height: 1.35, color: context.appTextPrimary)),
          ),
        ]),
      );

  Widget _chip(String texto, bool ligado) =>
      AdminSelo(texto, cor: ligado ? AdminUi.verde : AdminUi.cinza, icone: ligado ? Icons.check_rounded : Icons.close_rounded);

  Widget _mini(String rotulo, String valor, IconData icone, Color cor) => Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.appBorderSubtle),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icone, size: 14, color: cor),
            const SizedBox(width: 5),
            Expanded(
              child: Text(rotulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: context.appTextSecondary)),
            ),
          ]),
          const SizedBox(height: 4),
          SizedBox(
            height: 20,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(valor,
                  maxLines: 1,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: context.appTextPrimary)),
            ),
          ),
        ]),
      );

  Widget _grade2(List<Widget> itens) => LayoutBuilder(builder: (context, c) {
        final largura = (c.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final i in itens) SizedBox(width: largura, child: i)],
        );
      });

  Widget _aparelho(Map<String, dynamic> a, {bool resultadoDeTeste = false}) {
    final valido = a['valido'] == true;
    final validado = a['validado'] == true || resultadoDeTeste;
    final plataforma = '${a['plataforma'] ?? ''}';
    final cor = !validado ? AdminUi.azul : (valido ? AdminUi.verde : AdminUi.vermelho);
    final detalhes = [
      'Registrado ${_dataHora(a['ultimoRegistro'], curta: true)}',
      if (a['subLogin'] != null) 'aparelho do sub-login',
    ].join(' · ');
    final selo = resultadoDeTeste
        ? (valido ? 'Entregue' : 'Falhou')
        : (!validado ? 'Não conferido' : (valido ? 'Token válido' : 'Recusado'));
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.appBorderSubtle),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: cor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
          child: Icon(_iconePlataforma(plataforma), color: cor, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(
                  '${plataforma.toUpperCase()} · …${a['tokenFim'] ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: context.appTextPrimary),
                ),
              ),
              const SizedBox(width: 6),
              AdminSelo(selo, cor: cor),
            ]),
            const SizedBox(height: 2),
            Text(detalhes, style: TextStyle(fontSize: 11.5, color: context.appTextSecondary)),
            if (!valido && a['erro'] != null)
              Text('${a['erro']}', style: const TextStyle(fontSize: 11.5, color: AdminUi.vermelho)),
          ]),
        ),
      ]),
    );
  }

  Widget _resultadoTeste() {
    if (_falhaTeste != null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AdminUi.vermelho.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.error_outline_rounded, color: AdminUi.vermelho),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Não foi possível testar: $_falhaTeste',
                style: const TextStyle(color: AdminUi.vermelho, fontWeight: FontWeight.w700)),
          ),
        ]),
      );
    }
    final t = _teste;
    if (t == null) return const SizedBox.shrink();
    final push = ((t['push'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    final entregues = push.where((p) => p['valido'] == true).length;
    final apagados = (t['tokensApagados'] as num?)?.toInt() ?? 0;
    return _secao(
      'Resultado do teste',
      Icons.fact_check_rounded,
      AdminUi.roxo,
      borda: AdminUi.roxo.withValues(alpha: 0.55),
      [
        _grade2([
          _mini('Aparelhos', '${push.length}', Icons.devices_rounded, AdminUi.azul),
          _mini('Entregues', '$entregues', Icons.check_circle_rounded, entregues > 0 ? AdminUi.verde : AdminUi.vermelho),
        ]),
        const SizedBox(height: 10),
        if (push.isEmpty) _itemVeredito('Nenhum aparelho para enviar o push.', false),
        ...push.map((a) => _aparelho(a, resultadoDeTeste: true)),
        if (apagados > 0) _linha('Limpeza', '$apagados token(s) morto(s) apagado(s)', cor: AdminUi.ambar),
        const SizedBox(height: 8),
        Text(
          '«Entregue» quer dizer que a Apple/Google aceitou. Se não aparecer na tela, o bloqueio é no '
          'aparelho (Foco/Não perturbe, notificações do app desligadas nos Ajustes ou app com outra conta).',
          style: TextStyle(fontSize: 11.5, height: 1.35, color: context.appTextSecondary),
        ),
      ],
    );
  }

  Widget _rodape() {
    return Container(
      decoration: BoxDecoration(
        color: context.appSurface,
        border: Border(top: BorderSide(color: context.appBorderSubtle)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AdminUi.azul,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _testando ? null : _testar,
                  icon: _testando
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_to_mobile_rounded, size: 19),
                  label: Text(_testando ? 'Enviando…' : 'Testar push',
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AdminUi.azul,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => abrirTesteNotificacaoEmLote(context, preSelecionado: widget.uid),
                  icon: const Icon(Icons.groups_rounded, size: 19),
                  label: const Text('Vários usuários', style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      maxChildSize: 0.97,
      builder: (context, scroll) => FutureBuilder<Map<String, dynamic>>(
        future: _diag,
        builder: (context, snap) {
          final cabecalho = Container(
            margin: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF1E3A8A), AdminUi.roxo, AdminUi.teal]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
                child: const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Diagnóstico de notificações',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                  Text(widget.nome.isEmpty ? widget.uid : widget.nome,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                ]),
              ),
              IconButton(
                onPressed: snap.connectionState == ConnectionState.done ? _recarregar : null,
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                tooltip: 'Atualizar',
              ),
            ]),
          );
          if (snap.connectionState != ConnectionState.done) {
            return Column(children: [
              cabecalho,
              const Expanded(child: AdminCarregando(texto: 'Lendo aparelhos, preferências e fila de avisos…')),
            ]);
          }
          if (snap.hasError || snap.data?['success'] != true) {
            return Column(children: [
              cabecalho,
              Padding(
                padding: const EdgeInsets.all(16),
                child: AdminErroCard(
                  erro: mensagemErroNotificacoes(snap.error ?? snap.data?['error'], 'ctAdminNotificacoesDiag'),
                  onTentar: _recarregar,
                ),
              ),
            ]);
          }
          return Column(children: [
            cabecalho,
            Expanded(child: _corpo(snap.data!, scroll)),
            if (widget.podeTestar) _rodape(),
          ]);
        },
      ),
    );
  }

  Widget _corpo(Map<String, dynamic> d, ScrollController scroll) {
    Map<String, dynamic> mapa(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
    List<Map<String, dynamic>> lista(Object? v) =>
        (v is List ? v : const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    final veredito = mapa(d['veredito']);
    final avisos = ((veredito['avisos'] as List?) ?? const []).map((e) => '$e').toList();
    final oks = ((veredito['ok'] as List?) ?? const []).map((e) => '$e').toList();
    final aparelhos = lista(d['aparelhos']);
    final usuario = mapa(d['usuario']);
    final sessao = mapa(d['sessao']);
    final pref = mapa(d['preferencias']);
    final fila = mapa(d['fila']);
    final eventos = mapa(d['eventosFuturos']);
    final ultimosPush = lista(d['ultimosPush']);
    final testes = lista(d['testes']);
    final falhas = lista(fila['falhasRecentes']);
    final leads = ((pref['antecedencias'] as List?) ?? const [])
        .map((e) => switch ('$e') { '1440' => '1 dia', '60' => '1 hora', '30' => '30 min', _ => '$e min' })
        .join(' · ');
    final proximo = fila['proximo'] is Map ? Map<String, dynamic>.from(fila['proximo'] as Map) : null;
    String n(Object? v) => v == null ? '—' : '$v';

    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        _resultadoTeste(),
        _secao(
          avisos.isEmpty ? 'Tudo certo' : 'O que pode estar impedindo',
          avisos.isEmpty ? Icons.verified_rounded : Icons.warning_amber_rounded,
          avisos.isEmpty ? AdminUi.verde : AdminUi.ambar,
          borda: (avisos.isEmpty ? AdminUi.verde : AdminUi.ambar).withValues(alpha: 0.45),
          [
            ...avisos.map((a) => _itemVeredito(a, false)),
            ...oks.map((a) => _itemVeredito(a, true)),
          ],
        ),
        if (!widget.podeTestar)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('O envio de push de teste é só do master.',
                style: TextStyle(fontSize: 12, color: context.appTextSecondary)),
          ),
        _secao('Aparelhos', Icons.devices_rounded, AdminUi.azul, [
          if (aparelhos.isEmpty) _itemVeredito('O app não registrou aparelho desta conta.', false),
          ...aparelhos.map(_aparelho),
          _grade2([
            _mini('Último login', _dataHora(sessao['ultimoLogin']), Icons.login_rounded, AdminUi.azul),
            _mini('Última atividade', _dataHora(sessao['ultimaAtividade']), Icons.bolt_rounded, AdminUi.azul),
            _mini('Último acesso do app', _dataHora(usuario['ultimoAcessoApp']), Icons.touch_app_rounded, AdminUi.teal),
            _mini(
              'App',
              '${usuario['plataforma'] ?? '—'} ${usuario['appVersao'] ?? ''}'.trim(),
              Icons.info_outline_rounded,
              AdminUi.teal,
            ),
          ]),
        ]),
        _secao('Preferências', Icons.tune_rounded, AdminUi.teal, [
          Wrap(spacing: 6, runSpacing: 6, children: [
            _chip('Push no cadastro', usuario['pushEnabled'] == true),
            _chip('Push', pref['push'] == true),
            _chip('E-mail', pref['email'] == true),
            _chip('Escalas', pref['escalas'] == true),
            _chip('Compromissos', pref['compromissos'] == true),
            _chip('Audiências', pref['audiencias'] == true),
            _chip('Financeiro', pref['financeiro'] == true),
            _chip('Resumo diário', pref['resumoDiario'] == true),
          ]),
          const SizedBox(height: 4),
          _linha('Quando avisar', leads.isEmpty ? '—' : leads),
          if (pref['configurado'] != true)
            _linha('Observação', 'Usuário nunca abriu a tela de notificações (valores padrão).'),
        ]),
        _secao('Fila de avisos da Agenda', Icons.schedule_send_rounded, AdminUi.roxo, [
          _grade2([
            _mini('Programados', n(fila['pendentes']), Icons.pending_actions_rounded, AdminUi.roxo),
            _mini('Enviados', n(fila['enviados']), Icons.done_all_rounded, AdminUi.verde),
            _mini('Não saíram', n(fila['pulados']), Icons.block_rounded, AdminUi.vermelho),
            _mini(
              'Último envio',
              fila['ultimoEnvio'] == null
                  ? '—'
                  : _dataHora(
                      DateTime.fromMillisecondsSinceEpoch((fila['ultimoEnvio'] as num).toInt()).toIso8601String(),
                      curta: true),
              Icons.history_rounded,
              AdminUi.teal,
            ),
          ]),
          const SizedBox(height: 4),
          _linha(
            proximo?['tipo'] != null ? 'Próximo · ${proximo!['tipo']}' : 'Próximo',
            proximo == null ? '—' : _dataHora(proximo['quando']),
          ),
          _linha('Eventos futuros',
              '${n(eventos['escalas'])} escala(s) · ${n(eventos['compromissos'])} compromisso(s) · ${n(eventos['contas'])} conta(s)'),
          for (final f in falhas)
            _linha('Falha ${_dataHora(f['quando'], curta: true)}', '${f['tipo'] ?? ''} · ${f['motivo']}',
                cor: AdminUi.vermelho),
        ]),
        if (ultimosPush.isNotEmpty)
          _secao('Últimos push avulsos', Icons.notifications_rounded, AdminUi.azul, [
            for (final p in ultimosPush)
              _linha(_dataHora(p['quando'], curta: true), '${p['titulo']} — ${p['corpo']}'),
          ]),
        if (testes.isNotEmpty)
          _secao('Testes anteriores', Icons.science_rounded, AdminUi.rosa, [
            for (final t in testes)
              _linha(_dataHora(t['quando'], curta: true),
                  '${t['entregues']} de ${t['aparelhos']} aparelho(s)${t['por'] != null ? ' · ${t['por']}' : ''}'),
          ]),
      ],
    );
  }
}
