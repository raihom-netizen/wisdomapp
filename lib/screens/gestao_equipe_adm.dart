import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/team_role_config.dart';
import '../services/admin_permissions_service.dart';
import '../services/logs_service.dart';
import '../theme/app_colors.dart';
import '../theme/theme_context.dart';
import '../utils/admin_load_guard.dart';
import '../widgets/admin/admin_page_shell.dart';
import '../widgets/admin/admin_ui_kit.dart';
import '../widgets/admin_guard.dart';
import '../widgets/admin_menu_lateral.dart';
import '../widgets/fast_text_field.dart';
import 'create_admin_user_screen.dart';

/// Gestão de equipe — Master gerencia ADMs, Gestores, Sócios e Editores.
///
/// 02/10/2026 (padrão Controle Total): a lista ficava «carregando» para
/// sempre. A escuta `.snapshots()` era criada num getter chamado no build —
/// cada letra da busca / troca de aba / teclado criava uma consulta nova, e no
/// Firestore Web isso trava o cliente (`Target ID already exists`); com o
/// faturamento desligado o SDK ainda repetia a escuta em silêncio. Agora é
/// UMA leitura (`get`) com prazo, erro visível com «Tentar de novo» e
/// recarga depois de cada ação.
class GestaoEquipeAdm extends StatefulWidget {
  const GestaoEquipeAdm({
    super.key,
    required this.canManageTeam,
    this.embeddedInAdmin = false,
  });

  final bool canManageTeam;
  final bool embeddedInAdmin;

  @override
  State<GestaoEquipeAdm> createState() => _GestaoEquipeAdmState();
}

enum _FiltroPapel { todos, admins, gestores, socios, editores }

class _Membro {
  _Membro(this.id, this.data)
      : role = TeamRoleConfig.fromFirestore(
          role: (data['role'] ?? '').toString(),
          adminLevel: (data['adminLevel'] ?? '').toString(),
        );

  final String id;
  final Map<String, dynamic> data;
  final TeamRole role;

  String get nome =>
      (data['name'] ?? data['displayName'] ?? '').toString().trim();
  String get email => (data['email'] ?? '').toString().trim();

  DateTime? get ultimoAcesso {
    final t = data['clientTelemetry'];
    final v = t is Map ? t['lastPingAt'] : null;
    if (v is Timestamp) return v.toDate();
    final u = data['updatedAt'];
    return u is Timestamp ? u.toDate() : null;
  }

  String get plataforma {
    final t = data['clientTelemetry'];
    return t is Map ? (t['platform'] ?? '').toString() : '';
  }

  DateTime? get criadoEm {
    final v = data['createdAt'];
    return v is Timestamp ? v.toDate() : null;
  }

  bool get isAdminGroup =>
      role == TeamRole.master ||
      role == TeamRole.admin ||
      role == TeamRole.suporte ||
      role == TeamRole.editor;
}

class _GestaoEquipeAdmState extends State<GestaoEquipeAdm> {
  final _buscaCtrl = TextEditingController();
  String _busca = '';
  _FiltroPapel _filtro = _FiltroPapel.todos;

  List<_Membro>? _membros;
  Object? _erro;
  bool _carregando = false;
  DateTime? _atualizadoEm;

  static const _roles = [
    'admin',
    'master',
    'gestor',
    'partner',
    'socio',
    'editor_conteudo',
  ];

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

  Future<void> _carregar() async {
    if (_carregando) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final snap = await AdminLoadGuard.comPrazo(
        FirebaseFirestore.instance
            .collection('users')
            .where('role', whereIn: _roles)
            .limit(300)
            .get(GetOptions(source: kIsWeb ? Source.server : Source.serverAndCache)),
        oQue: 'a equipe',
      );
      if (!mounted) return;
      setState(() {
        _membros = [for (final d in snap.docs) _Membro(d.id, d.data())]
          ..sort((a, b) {
            final ra = a.role.index.compareTo(b.role.index);
            if (ra != 0) return ra;
            return (a.nome.isEmpty ? a.email : a.nome)
                .toLowerCase()
                .compareTo((b.nome.isEmpty ? b.email : b.nome).toLowerCase());
          });
        _carregando = false;
        _atualizadoEm = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e;
        _carregando = false;
      });
    }
  }

  bool _passaFiltro(_Membro m) {
    switch (_filtro) {
      case _FiltroPapel.todos:
        break;
      case _FiltroPapel.admins:
        if (!m.isAdminGroup) return false;
        break;
      case _FiltroPapel.gestores:
        if (m.role != TeamRole.gestor) return false;
        break;
      case _FiltroPapel.socios:
        if (m.role != TeamRole.partner) return false;
        break;
      case _FiltroPapel.editores:
        if (m.role != TeamRole.editorConteudo) return false;
        break;
    }
    final q = _busca.trim().toLowerCase();
    if (q.isEmpty) return true;
    return '${m.nome} ${m.email} ${TeamRoleConfig.label(m.role)}'
        .toLowerCase()
        .contains(q);
  }

  bool _podeEditar(_Membro m) {
    if (!widget.canManageTeam) return false;
    if (m.id == FirebaseAuth.instance.currentUser?.uid) return false;
    return m.role != TeamRole.master;
  }

  void _snack(String msg, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: erro ? AppColors.error : null,
      ),
    );
  }

  // ── Ações ────────────────────────────────────────────────────────────

  Future<void> _novoMembro() async {
    final papel = await showModalBottomSheet<TeamRole>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            const Text(
              'Criar conta nova para…',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 8),
            for (final r in TeamRoleConfig.creatableRoles)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: TeamRoleConfig.color(r).withValues(alpha: 0.14),
                  child: Icon(TeamRoleConfig.icon(r), color: TeamRoleConfig.color(r)),
                ),
                title: Text(TeamRoleConfig.label(r),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(TeamRoleConfig.description(r),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(ctx, r),
              ),
          ],
        ),
      ),
    );
    if (papel == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminGuard(child: CreateAdminUserScreen(initialRole: papel)),
      ),
    );
    if (mounted) _carregar();
  }

  Future<TeamRole?> _escolherPapel({
    required String titulo,
    required TeamRole inicial,
    TextEditingController? nomeCtrl,
    TextEditingController? emailCtrl,
    required String confirmar,
  }) {
    var selected = TeamRoleConfig.creatableRoles.contains(inicial)
        ? inicial
        : TeamRole.admin;
    return showDialog<TeamRole>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(titulo),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (emailCtrl != null) ...[
                    FastTextField(
                      controller: emailCtrl,
                      kind: FastTextFieldKind.email,
                      decoration: const InputDecoration(
                        labelText: 'E-mail da conta (já cadastrada no app)',
                        hintText: 'usuario@email.com',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (nomeCtrl != null) ...[
                    FastTextField(
                      controller: nomeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nome',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  for (final r in TeamRoleConfig.creatableRoles)
                    RadioListTile<TeamRole>(
                      value: r,
                      groupValue: selected,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (v) => setLocal(() => selected = v ?? selected),
                      title: Row(
                        children: [
                          Icon(TeamRoleConfig.icon(r),
                              size: 18, color: TeamRoleConfig.color(r)),
                          const SizedBox(width: 6),
                          Text(TeamRoleConfig.label(r),
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      ),
                      subtitle: Text(
                        TeamRoleConfig.description(r),
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, selected),
              child: Text(confirmar),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic> _payloadPapel(TeamRole r) {
    final payload = <String, dynamic>{
      'role': TeamRoleConfig.firestoreRoleFor(r),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final lvl = TeamRoleConfig.adminLevelFor(r);
    payload['adminLevel'] = lvl ?? FieldValue.delete();
    return payload;
  }

  Future<void> _editar(_Membro m) async {
    final nomeCtrl = TextEditingController(text: m.nome);
    final papel = await _escolherPapel(
      titulo: 'Editar ${m.nome.isEmpty ? m.email : m.nome}',
      inicial: m.role,
      nomeCtrl: nomeCtrl,
      confirmar: 'Salvar',
    );
    final nome = nomeCtrl.text.trim();
    nomeCtrl.dispose();
    if (papel == null || !mounted) return;
    try {
      await AdminLoadGuard.comPrazo(
        FirebaseFirestore.instance
            .collection('users')
            .doc(m.id)
            .update({..._payloadPapel(papel), 'name': nome}),
        oQue: 'a alteração',
      );
      await LogsService().saveLog(
        modulo: 'Admin',
        acao: 'Editou membro da equipe',
        detalhes: '${nome.isEmpty ? m.email : nome} → ${TeamRoleConfig.label(papel)}',
      );
      _snack('Membro atualizado.');
      _carregar();
    } catch (e) {
      _snack(AdminLoadGuard.mensagem(e), erro: true);
    }
  }

  Future<void> _remover(_Membro m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover da equipe?'),
        content: Text(
          '${m.nome.isEmpty ? m.email : '${m.nome} (${m.email})'} perde o acesso '
          'ao Painel Admin e volta a ser usuário comum (plano Free).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await AdminLoadGuard.comPrazo(
        FirebaseFirestore.instance.collection('users').doc(m.id).update({
          'role': 'user',
          'plan': 'free',
          'adminLevel': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        }),
        oQue: 'a remoção',
      );
      await LogsService().saveLog(
        modulo: 'Admin',
        acao: 'Removeu membro da equipe',
        detalhes: m.nome.isEmpty ? m.email : '${m.nome} (${m.email})',
      );
      _snack('Membro removido.');
      _carregar();
    } catch (e) {
      _snack(AdminLoadGuard.mensagem(e), erro: true);
    }
  }

  /// «Convidar»: dá papel a uma conta que já existe no app (pelo e-mail).
  Future<void> _convidar() async {
    final emailCtrl = TextEditingController();
    final papel = await _escolherPapel(
      titulo: 'Convidar para a equipe',
      inicial: TeamRole.gestor,
      emailCtrl: emailCtrl,
      confirmar: 'Dar acesso',
    );
    final email = emailCtrl.text.trim().toLowerCase();
    emailCtrl.dispose();
    if (papel == null || !mounted || email.isEmpty) return;
    try {
      final snap = await AdminLoadGuard.comPrazo(
        FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: email)
            .limit(1)
            .get(),
        oQue: 'a conta',
      );
      if (snap.docs.isEmpty) {
        _snack('Nenhuma conta com $email. A pessoa precisa entrar no app uma '
            'vez, ou use «Novo membro» para criar a conta.');
        return;
      }
      await snap.docs.first.reference.update(_payloadPapel(papel));
      await LogsService().saveLog(
        modulo: 'Admin',
        acao: 'Promoveu usuário à equipe',
        detalhes: '$email → ${TeamRoleConfig.label(papel)}',
      );
      _snack('${TeamRoleConfig.label(papel)} ativado para $email.');
      _carregar();
    } catch (e) {
      _snack(AdminLoadGuard.mensagem(e), erro: true);
    }
  }

  // ── UI ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pad = widget.embeddedInAdmin
        ? AdminPageShell.listPadding(context, top: 4)
        : EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom);
    final membros = _membros;
    final visiveis = membros?.where(_passaFiltro).toList() ?? const <_Membro>[];

    int conta(bool Function(_Membro) f) => membros?.where(f).length ?? 0;

    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: pad.copyWith(bottom: pad.bottom + 32),
        children: [
          AdminHero(
            titulo: 'Equipe',
            subtitulo: membros == null
                ? (_carregando ? 'Carregando a equipe…' : 'Admins, gestores, sócios e editores')
                : '${membros.length} membro(s) com acesso ao painel'
                    '${_atualizadoEm == null ? '' : ' · atualizado às ${DateFormat('HH:mm').format(_atualizadoEm!)}'}',
            icone: Icons.groups_rounded,
            cores: const [Color(0xFF1E1B4B), Color(0xFF6D28D9), Color(0xFF0F766E)],
            carregando: _carregando,
            onAtualizar: _carregar,
          ),
          const SizedBox(height: 12),
          AdminKpiGrid(
            maxColunas: 4,
            children: [
              AdminKpi(
                rotulo: 'Todos',
                valor: membros == null ? '—' : '${membros.length}',
                sub: 'Com acesso ao painel',
                icone: Icons.groups_rounded,
                cor: AdminUi.roxo,
                selecionado: _filtro == _FiltroPapel.todos,
                onTap: () => setState(() => _filtro = _FiltroPapel.todos),
              ),
              AdminKpi(
                rotulo: 'Administradores',
                valor: membros == null ? '—' : '${conta((m) => m.isAdminGroup)}',
                sub: 'Master, admin, suporte',
                icone: Icons.admin_panel_settings_rounded,
                cor: AdminUi.azul,
                selecionado: _filtro == _FiltroPapel.admins,
                onTap: () => setState(() => _filtro = _FiltroPapel.admins),
              ),
              AdminKpi(
                rotulo: 'Gestores',
                valor: membros == null ? '—' : '${conta((m) => m.role == TeamRole.gestor)}',
                sub: 'Conteúdo + relatórios',
                icone: Icons.manage_accounts_rounded,
                cor: const Color(0xFF7C3AED),
                selecionado: _filtro == _FiltroPapel.gestores,
                onTap: () => setState(() => _filtro = _FiltroPapel.gestores),
              ),
              AdminKpi(
                rotulo: 'Sócios',
                valor: membros == null ? '—' : '${conta((m) => m.role == TeamRole.partner)}',
                sub: 'Somente leitura',
                icone: Icons.handshake_rounded,
                cor: AdminUi.teal,
                selecionado: _filtro == _FiltroPapel.socios,
                onTap: () => setState(() => _filtro = _FiltroPapel.socios),
              ),
              AdminKpi(
                rotulo: 'Editores de conteúdo',
                valor: membros == null
                    ? '—'
                    : '${conta((m) => m.role == TeamRole.editorConteudo)}',
                sub: 'Só Cursos e Dicas',
                icone: Icons.video_library_rounded,
                cor: AdminUi.vermelho,
                selecionado: _filtro == _FiltroPapel.editores,
                onTap: () => setState(() => _filtro = _FiltroPapel.editores),
              ),
            ],
          ),
          if (widget.canManageTeam) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _novoMembro,
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: const Text('Novo membro'),
                ),
                OutlinedButton.icon(
                  onPressed: _convidar,
                  icon: const Icon(Icons.forward_to_inbox_rounded, size: 18),
                  label: const Text('Convidar conta existente'),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 10),
            Text(
              'Só o super admin adiciona, edita ou remove membros.',
              style: TextStyle(fontSize: 12, color: AdminUi.apoioOf(context)),
            ),
          ],
          const SizedBox(height: 12),
          AdminBusca(
            controller: _buscaCtrl,
            hint: 'Buscar nome, e-mail ou papel…',
            onChanged: (v) => setState(() => _busca = v),
          ),
          const SizedBox(height: 10),
          if (_erro != null && membros == null)
            AdminErroCard(erro: _erro, onTentar: _carregar)
          else if (membros == null)
            const AdminCarregando(texto: 'Carregando a equipe…')
          else ...[
            if (_erro != null)
              AdminErroCard(
                erro: _erro,
                onTentar: _carregar,
                titulo: 'Não deu para atualizar (mostrando a última lista)',
              ),
            if (visiveis.isEmpty)
              AdminVazio(
                texto: membros.isEmpty
                    ? 'Ninguém na equipe ainda.'
                    : 'Nenhum membro neste filtro.',
                icone: Icons.group_off_rounded,
              )
            else
              _listaMembros(visiveis),
          ],
          AdminSecao(
            titulo: 'O que cada papel acessa',
            cor: AdminUi.roxo,
            icone: Icons.verified_user_rounded,
          ),
          const _MatrizPermissoes(),
        ],
      ),
    );
  }

  Widget _listaMembros(List<_Membro> lista) {
    return Container(
      decoration: BoxDecoration(
        color: AdminUi.cardOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminUi.bordaOf(context)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < lista.length; i++) ...[
            if (i > 0) Divider(height: 1, color: context.isDarkMode ? context.appBorderSubtle : Colors.grey.shade100),
            _linhaMembro(lista[i]),
          ],
        ],
      ),
    );
  }

  Widget _linhaMembro(_Membro m) {
    final c = TeamRoleConfig.color(m.role);
    final eu = m.id == FirebaseAuth.instance.currentUser?.uid;
    final ult = m.ultimoAcesso;
    final df = DateFormat('dd/MM/yy HH:mm');
    final pode = _podeEditar(m);
    return LayoutBuilder(builder: (context, cons) {
      final largo = cons.maxWidth >= 720;
      final info = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            m.nome.isEmpty ? '—' : m.nome,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          Text(
            m.email,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: context.isDarkMode ? context.appTextSecondary : Colors.grey.shade700),
          ),
          if (!largo) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                AdminSelo(eu ? '${TeamRoleConfig.label(m.role)} · você' : TeamRoleConfig.label(m.role),
                    cor: c, icone: TeamRoleConfig.icon(m.role)),
                if (ult != null)
                  Text('Último acesso ${df.format(ult)}',
                      style: TextStyle(fontSize: 11, color: AdminUi.apoioOf(context))),
              ],
            ),
          ],
        ],
      );
      final acoes = pode
          ? PopupMenuButton<String>(
              tooltip: 'Ações',
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (v) {
                if (v == 'editar') _editar(m);
                if (v == 'remover') _remover(m);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'editar',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.edit_rounded),
                    title: Text('Editar nome / papel'),
                  ),
                ),
                PopupMenuItem(
                  value: 'remover',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.person_remove_rounded, color: Colors.red.shade400),
                    title: Text('Remover da equipe',
                        style: TextStyle(color: Colors.red.shade400)),
                  ),
                ),
              ],
            )
          : const SizedBox(width: 48);
      return InkWell(
        onTap: pode ? () => _editar(m) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: c.withValues(alpha: 0.14),
                child: Icon(TeamRoleConfig.icon(m.role), color: c, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(flex: 5, child: info),
              if (largo) ...[
                Expanded(
                  flex: 3,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AdminSelo(
                      eu ? '${TeamRoleConfig.label(m.role)} · você' : TeamRoleConfig.label(m.role),
                      cor: c,
                      icone: TeamRoleConfig.icon(m.role),
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    ult == null
                        ? 'Sem registro de acesso'
                        : '${df.format(ult)}${m.plataforma.isEmpty ? '' : ' · ${m.plataforma}'}',
                    style: TextStyle(fontSize: 12, color: context.isDarkMode ? context.appTextSecondary : Colors.grey.shade700),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    m.criadoEm == null ? '' : 'Desde ${DateFormat('MM/yyyy').format(m.criadoEm!)}',
                    style: TextStyle(fontSize: 11.5, color: AdminUi.apoioOf(context)),
                  ),
                ),
              ],
              acoes,
            ],
          ),
        ),
      );
    });
  }
}

/// Matriz: módulos do painel liberados para cada papel (mesma regra do
/// [AdminPermissionsService] que o menu usa — sempre em sincronia).
class _MatrizPermissoes extends StatelessWidget {
  const _MatrizPermissoes();

  @override
  Widget build(BuildContext context) {
    const svc = AdminPermissionsService();
    final linhas = <(TeamRole, AdminCapability, String)>[
      (TeamRole.master, AdminCapability.superAdmin, 'Tudo, inclusive equipe, exclusão definitiva e forçar versão.'),
      (TeamRole.admin, AdminCapability.support, 'Painel completo; editar licenças. Sem gerir a equipe.'),
      (TeamRole.gestor, AdminCapability.contentGestor, 'Conteúdo, relatórios e recebimentos; usuários só leitura.'),
      (TeamRole.partner, AdminCapability.partner, 'Resumo da própria parte, usuários e recebimentos — leitura.'),
      (TeamRole.editorConteudo, AdminCapability.contentEditor, 'Só Cursos (vídeos) e Dicas financeiras. Bloqueado no servidor.'),
    ];
    return Column(
      children: [
        for (final (papel, cap, resumo) in linhas)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AdminUi.cardOf(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: TeamRoleConfig.color(papel).withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(TeamRoleConfig.icon(papel), size: 18, color: TeamRoleConfig.color(papel)),
                    const SizedBox(width: 6),
                    Text(TeamRoleConfig.label(papel),
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: TeamRoleConfig.color(papel))),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(resumo,
                          style: TextStyle(fontSize: 11.5, color: context.isDarkMode ? context.appTextSecondary : Colors.grey.shade700)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final item in svc.allowedMenuItems(cap))
                      AdminSelo(adminMenuItemTitulo(item), cor: TeamRoleConfig.color(papel)),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}
