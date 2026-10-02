import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../theme/theme_context.dart';
import '../../utils/admin_load_guard.dart';
import '../../widgets/admin/admin_page_shell.dart';
import '../../widgets/admin/admin_ui_kit.dart';
import '../admin_usuarios_inteligencia_tab.dart' show openAdminUser360Preview;

/// Admin — **E-mails com problema** (porte do Controle Total, 02/10/2026).
///
/// O envio do WISDOMAPP (Gmail SMTP em `functions/index.js`) não registra
/// falha nem bounce. A callable `ctAdminEmailsComProblema`
/// (functions/admin_emails_problema.js) junta, só lendo: configuração do envio,
/// cadastros com e-mail inválido/digitado errado/repetido, login não verificado
/// ou diferente do cadastro e avisos da Agenda que não saíram nos últimos 30
/// dias. Nada aqui grava no Firestore.
///
/// Widget embutível no painel (sem Scaffold). Para abrir em tela cheia use
/// [EmailsComProblemaPage].
class EmailsComProblemaTab extends StatefulWidget {
  const EmailsComProblemaTab({super.key});

  @override
  State<EmailsComProblemaTab> createState() => _EmailsComProblemaTabState();
}

/// Mesma tela com Scaffold próprio (para `Navigator.push`).
class EmailsComProblemaPage extends StatelessWidget {
  const EmailsComProblemaPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminPageShell.backgroundOf(context),
      appBar: AppBar(title: const Text('E-mails com problema')),
      body: const EmailsComProblemaTab(),
    );
  }
}

const _rotulos = <String, (String, Color)>{
  'formato': ('Formato inválido', AdminUi.vermelho),
  'dominio': ('Domínio errado', AdminUi.vermelho),
  'sem_email': ('Sem e-mail', AdminUi.vermelho),
  'aviso_nao_saiu': ('Aviso não saiu', AdminUi.ambar),
  'diferente_login': ('Login ≠ cadastro', AdminUi.roxo),
  'duplicado': ('E-mail repetido', AdminUi.roxo),
  'desativado': ('Login desativado', AdminUi.cinza),
  'nao_verificado': ('Não verificado', AdminUi.azul),
  'espaco': ('Com espaço', AdminUi.ambar),
  'maiuscula': ('Maiúscula', AdminUi.cinza),
};

class _EmailsComProblemaTabState extends State<EmailsComProblemaTab> {
  static final _df = DateFormat('dd/MM/yy HH:mm');
  final _busca = TextEditingController();
  Map<String, dynamic>? _d;
  Object? _erro;
  bool _carregando = false;
  String? _filtro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _carregar({bool forcar = false}) async {
    if (_carregando) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable(
        'ctAdminEmailsComProblema',
        options: HttpsCallableOptions(timeout: AdminLoadGuard.longo),
      );
      final r = await AdminLoadGuard.comPrazo(
        fn.call<dynamic>({'forcar': forcar}),
        prazo: AdminLoadGuard.longo + const Duration(seconds: 10),
        oQue: 'os e-mails com problema',
      );
      if (r.data is! Map) throw StateError('Resposta vazia do servidor.');
      if (!mounted) return;
      setState(() {
        _d = Map<String, dynamic>.from(r.data as Map);
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

  Object? get _erroAmigavel {
    final e = _erro;
    if (e is FirebaseFunctionsException && (e.code == 'not-found' || e.code == 'unimplemented')) {
      return 'Função ainda não publicada no servidor (ctAdminEmailsComProblema).';
    }
    return e;
  }

  List<Map<String, dynamic>> get _itens => ((_d?['itens'] as List?) ?? const [])
      .whereType<Map>()
      .map((m) => Map<String, dynamic>.from(m))
      .toList();

  List<Map<String, dynamic>> get _filtrados {
    final t = _busca.text.trim().toLowerCase();
    return _itens.where((i) {
      final codigos = ((i['codigos'] as List?) ?? const []).map((e) => '$e');
      if (_filtro != null && !codigos.contains(_filtro)) return false;
      if (t.isEmpty) return true;
      final alvo = '${i['email']} ${i['nome']} ${i['uid']} ${((i['problemas'] as List?) ?? const []).join(' ')}'
          .toLowerCase();
      return alvo.contains(t);
    }).toList();
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
            titulo: 'E-mails com problema',
            subtitulo: d == null
                ? 'Cadastros e avisos em que o e-mail não chega'
                : 'Atualizado ${_df.format(DateTime.fromMillisecondsSinceEpoch(geradoEm))}'
                    '${d['doCache'] == true ? ' (cache de 10 min — ↻ refaz)' : ''}',
            icone: Icons.unsubscribe_rounded,
            cores: const [Color(0xFF450A0A), Color(0xFFB91C1C), Color(0xFFF59E0B)],
            carregando: _carregando,
            onAtualizar: () => _carregar(forcar: true),
          ),
          if (_erro != null)
            AdminErroCard(
              erro: _erroAmigavel,
              onTentar: () => _carregar(forcar: true),
              titulo: d == null ? 'Não foi possível carregar a lista' : 'Não deu para atualizar',
            ),
          if (d == null && _carregando && _erro == null)
            const AdminCarregando(texto: 'Conferindo cadastros, login e avisos…'),
          if (d != null) ..._conteudo(d),
        ],
      ),
    );
  }

  List<Widget> _conteudo(Map<String, dynamic> d) {
    final cfg = Map<String, dynamic>.from((d['config'] as Map?) ?? const {});
    final c = Map<String, dynamic>.from((d['contagem'] as Map?) ?? const {});
    final veredito = ((d['veredito'] as List?) ?? const []).map((e) => '$e').toList();
    final avisos = ((d['avisos'] as List?) ?? const []).map((e) => '$e').toList();
    final lista = _filtrados;
    int n(String k) => (c[k] as num?)?.toInt() ?? 0;
    return [
      const SizedBox(height: 12),
      _cartaoConfig(cfg),
      if (veredito.isNotEmpty) ...[
        const SizedBox(height: 10),
        for (final v in veredito)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.warning_amber_rounded, size: 18, color: AdminUi.ambar),
              const SizedBox(width: 8),
              Expanded(
                child: Text(v, style: TextStyle(fontSize: 13, color: AdminUi.tintaOf(context))),
              ),
            ]),
          ),
      ],
      AdminSecao(titulo: 'Resumo', cor: AdminUi.vermelho, icone: Icons.analytics_rounded),
      AdminKpiGrid(children: [
        for (final e in _rotulos.entries)
          if (n(e.key) > 0 || e.key == 'formato' || e.key == 'aviso_nao_saiu')
            AdminKpi(
              rotulo: e.value.$1,
              valor: '${n(e.key)}',
              icone: Icons.alternate_email_rounded,
              cor: e.value.$2,
              selecionado: _filtro == e.key,
              onTap: () => setState(() => _filtro = _filtro == e.key ? null : e.key),
            ),
      ]),
      const SizedBox(height: 6),
      Text(
        '${n('perfis')} cadastro(s) lidos · ${n('fantasmas')} perfil(is) vazio(s) sem nome nem e-mail '
        'ficaram de fora. O envio não registra bounce: «Aviso não saiu» vem da fila da Agenda '
        '(status «skipped» nos últimos 30 dias).',
        style: TextStyle(fontSize: 11.5, height: 1.35, color: AdminUi.apoioOf(context)),
      ),
      for (final a in avisos)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: AdminSelo(a, cor: AdminUi.ambar, icone: Icons.info_outline_rounded),
        ),
      AdminSecao(
        titulo: _filtro == null
            ? 'Contas com problema (${(d['total'] as num?)?.toInt() ?? 0})'
            : '${_rotulos[_filtro]?.$1 ?? _filtro} (${lista.length})',
        cor: AdminUi.azul,
        icone: Icons.list_alt_rounded,
        trailing: IconButton(
          tooltip: 'Copiar lista (CSV)',
          onPressed: lista.isEmpty ? null : () => _copiar(lista),
          icon: const Icon(Icons.copy_all_rounded, size: 20),
        ),
      ),
      AdminBusca(
        controller: _busca,
        onChanged: (_) => setState(() {}),
        hint: 'Buscar por e-mail, nome ou problema',
      ),
      const SizedBox(height: 10),
      if (lista.isEmpty)
        AdminVazio(
          icone: Icons.mark_email_read_rounded,
          texto: _busca.text.trim().isEmpty && _filtro == null
              ? 'Nenhum e-mail com problema — ótimo sinal.'
              : 'Nada encontrado para esse filtro.',
        )
      else ...[
        for (final i in lista.take(200)) _cartao(i),
        if (lista.length > 200)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Mostrando 200 de ${lista.length}. Use a busca ou copie o CSV.',
                style: TextStyle(fontSize: 12, color: AdminUi.apoioOf(context))),
          ),
        if (d['cortado'] == true)
          Text('A lista do servidor foi cortada em 400 contas (as mais graves primeiro).',
              style: TextStyle(fontSize: 12, color: AdminUi.apoioOf(context))),
      ],
    ];
  }

  Widget _cartaoConfig(Map<String, dynamic> cfg) {
    final ok = cfg['configurado'] == true;
    final cor = ok ? AdminUi.verde : AdminUi.vermelho;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: context.isDarkMode ? 0.16 : 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cor.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Icon(ok ? Icons.mark_email_read_rounded : Icons.mail_lock_rounded, color: cor),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            ok
                ? 'Envio configurado (settings/email: ${cfg['usuario'] ?? ''}, senha de app presente).'
                : 'Envio de e-mail NÃO configurado: falta ${cfg['temSenha'] == true ? 'o usuário' : 'a senha de app'} '
                    'em settings/email. Nenhum e-mail sai até corrigir.',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AdminUi.tintaOf(context)),
          ),
        ),
      ]),
    );
  }

  Widget _cartao(Map<String, dynamic> i) {
    final codigos = ((i['codigos'] as List?) ?? const []).map((e) => '$e').toList();
    final problemas = ((i['problemas'] as List?) ?? const []).map((e) => '$e').toList();
    final email = '${i['email'] ?? ''}';
    final nome = '${i['nome'] ?? ''}';
    final uid = '${i['uid'] ?? ''}';
    final falha = (i['ultimaFalha'] as num?)?.toInt() ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AdminUi.cardOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminUi.bordaOf(context)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => openAdminUser360Preview(context, uid: uid, displayName: nome, email: email),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.alternate_email_rounded, size: 18, color: AdminUi.vermelho),
              const SizedBox(width: 8),
              Expanded(
                child: SelectableText(
                  email.isEmpty ? '(sem e-mail) · $uid' : email,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AdminUi.tintaOf(context)),
                ),
              ),
            ]),
            if (nome.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 26, top: 2),
                child: Text(nome, style: TextStyle(fontSize: 12, color: AdminUi.apoioOf(context))),
              ),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final c in codigos) AdminSelo(_rotulos[c]?.$1 ?? c, cor: _rotulos[c]?.$2 ?? AdminUi.cinza),
              if ('${i['plano'] ?? ''}'.isNotEmpty) AdminSelo('${i['plano']}', cor: AdminUi.azul),
              if (falha > 0)
                AdminSelo('Última falha ${_df.format(DateTime.fromMillisecondsSinceEpoch(falha))}',
                    cor: AdminUi.ambar),
            ]),
            const SizedBox(height: 8),
            for (final p in problemas)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('• $p',
                    style: TextStyle(fontSize: 12, height: 1.35, color: context.appTextSecondary)),
              ),
          ]),
        ),
      ),
    );
  }

  Future<void> _copiar(List<Map<String, dynamic>> l) async {
    final b = StringBuffer('E-mail;Nome;UID;Plano;Problemas\n');
    for (final i in l) {
      b.writeln([
        i['email'] ?? '',
        i['nome'] ?? '',
        i['uid'] ?? '',
        i['plano'] ?? '',
        ((i['problemas'] as List?) ?? const []).join(' | '),
      ].join(';'));
    }
    await Clipboard.setData(ClipboardData(text: b.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('${l.length} linha(s) copiadas — cole no Excel.')));
  }
}
