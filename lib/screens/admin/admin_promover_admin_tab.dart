import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../constants/admin_master_config.dart';
import '../../constants/team_role_config.dart';
import '../../services/admin_team_role_service.dart';
import '../../theme/theme_context.dart';
import '../../utils/admin_load_guard.dart';
import '../../utils/admin_user_search.dart';
import '../../utils/admin_users_pager.dart';
import '../../widgets/admin/admin_page_shell.dart';
import '../../widgets/admin/admin_ui_kit.dart';

/// «Promover usuário a admin» — SÓ o master vê (02/10/2026).
///
/// Já abre com a LISTA de todos os usuários (paginada por e-mail com
/// «Carregar mais» via [AdminUsersPager] — `.get()` com cursor, nunca escuta
/// de milhares de docs), filtros rápidos por papel (a equipe vem de uma
/// consulta só por `role`) e busca que filtra na hora e completa com o
/// servidor. Busca a conta por e-mail/nome (prefixo no servidor), escolhe o papel da
/// equipe ([TeamRoleConfig.creatableRoles]: Administrador, Suporte, Editor,
/// Gestor, Sócio, Editor de conteúdo) e confirma; também rebaixa a usuário
/// comum. Grava pelo callable `ctAdminSetUserRole` (confere o master pelo
/// e-mail verificado do token e registra em `activity_logs`). Ninguém vira
/// master por aqui: master é só o e-mail dos donos.
class AdminPromoverAdminTab extends StatefulWidget {
  const AdminPromoverAdminTab({super.key});

  @override
  State<AdminPromoverAdminTab> createState() => _AdminPromoverAdminTabState();
}

enum _FiltroPapel { todos, admins, suporte, editores, editorConteudo, usuarios }

class _AdminPromoverAdminTabState extends State<AdminPromoverAdminTab> {
  final _buscaCtrl = TextEditingController();
  Timer? _debounce;
  String _buscaFeita = '';
  bool _buscandoServidor = false;
  final Set<String> _salvando = {};
  final AdminUsersPager _pager = AdminUsersPager();
  _FiltroPapel _filtro = _FiltroPapel.todos;

  /// Equipe (quem tem `role` de painel) — poucos docs, uma consulta só.
  List<AdminUserDoc> _equipe = const [];
  bool _equipeCarregando = true;
  Object? _equipeErro;

  static const _papeis = AdminTeamRoleService();

  @override
  void initState() {
    super.initState();
    _pager.addListener(_onPager);
    unawaited(_pager.reload());
    unawaited(_carregarEquipe());
  }

  void _onPager() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _buscaCtrl.dispose();
    _pager.removeListener(_onPager);
    _pager.dispose();
    super.dispose();
  }

  Future<void> _carregarEquipe() async {
    setState(() {
      _equipeCarregando = true;
      _equipeErro = null;
    });
    try {
      final snap = await AdminLoadGuard.comPrazo(
        FirebaseFirestore.instance
            .collection('users')
            .where('role', whereIn: TeamRoleConfig.firestoreRoles.toList())
            .limit(500)
            .get(),
        oQue: 'a equipe',
      );
      final docs = snap.docs.toList()
        ..sort((a, b) => (a.data()['email'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo((b.data()['email'] ?? '').toString().toLowerCase()));
      if (!mounted) return;
      setState(() {
        _equipe = docs;
        _equipeCarregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _equipeErro = e;
        _equipeCarregando = false;
      });
    }
  }

  void _agendarBusca(String v) {
    setState(() {}); // filtra na hora o que já está carregado
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _buscar);
  }

  /// Completa a lista com a busca por prefixo no servidor (e-mail, nome,
  /// CPF, UID) — quem ainda não apareceu nas páginas carregadas.
  Future<void> _buscar({bool forcar = false}) async {
    final q = _buscaCtrl.text.trim();
    if (q.length < 2) {
      _buscaFeita = '';
      return;
    }
    if (!forcar && q == _buscaFeita) return;
    _buscaFeita = q;
    setState(() => _buscandoServidor = true);
    try {
      final extra = await adminSearchUsersServer(q, limit: 25);
      if (!mounted) return;
      _pager.merge(extra);
    } catch (e) {
      _snack(AdminLoadGuard.mensagem(e), erro: true);
    } finally {
      if (mounted) setState(() => _buscandoServidor = false);
    }
  }

  bool _passaFiltro(Map<String, dynamic> d) {
    final p = _papelAtual(d);
    switch (_filtro) {
      case _FiltroPapel.todos:
        return true;
      case _FiltroPapel.admins:
        return p == TeamRole.master ||
            p == TeamRole.admin ||
            p == TeamRole.gestor ||
            p == TeamRole.partner;
      case _FiltroPapel.suporte:
        return p == TeamRole.suporte;
      case _FiltroPapel.editores:
        return p == TeamRole.editor;
      case _FiltroPapel.editorConteudo:
        return p == TeamRole.editorConteudo;
      case _FiltroPapel.usuarios:
        return p == null;
    }
  }

  /// Fonte da lista: equipe (consulta por papel) ou páginas de todos.
  bool get _filtroDeEquipe =>
      _filtro != _FiltroPapel.todos && _filtro != _FiltroPapel.usuarios;

  List<AdminUserDoc> _visiveis() {
    final base = _filtroDeEquipe ? _equipe : _pager.docs;
    final q = _buscaCtrl.text.trim();
    return base
        .where((d) => adminUserHasCompleteEmail(d.data()))
        .where((d) => _passaFiltro(d.data()))
        .where((d) => q.isEmpty || adminUserMatchesSearch(d.data(), d.id, q))
        .toList();
  }

  int _contar(_FiltroPapel f) {
    if (f == _FiltroPapel.todos || f == _FiltroPapel.usuarios) return -1;
    final antes = _filtro;
    _filtro = f;
    final n = _equipe.where((d) => _passaFiltro(d.data())).length;
    _filtro = antes;
    return n;
  }

  void _snack(String msg, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: erro ? Colors.red.shade700 : null,
    ));
  }

  TeamRole? _papelAtual(Map<String, dynamic> d) {
    final role = (d['role'] ?? '').toString().trim().toLowerCase();
    if (!TeamRoleConfig.firestoreRoles.contains(role)) return null;
    final r = TeamRoleConfig.fromFirestore(
      role: role,
      adminLevel: (d['adminLevel'] ?? '').toString(),
    );
    if (r == TeamRole.master &&
        !AdminMasterConfig.isMasterEmail((d['email'] ?? '').toString())) {
      return TeamRole.admin;
    }
    return r;
  }

  Future<void> _promover(AdminUserDoc doc) async {
    final d = doc.data();
    final email = (d['email'] ?? '').toString().trim();
    final nome = adminUserDisplayName(d);
    final atual = _papelAtual(d);
    var escolhido = atual != null && TeamRoleConfig.creatableRoles.contains(atual)
        ? atual
        : TeamRole.admin;
    final papel = await showDialog<TeamRole>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Papel de ${nome.isEmpty ? email : nome}'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(email,
                      style: TextStyle(
                          fontSize: 12.5, color: AdminUi.apoioOf(ctx))),
                  const SizedBox(height: 10),
                  for (final r in TeamRoleConfig.creatableRoles)
                    Card(
                      elevation: 0,
                      color: escolhido == r
                          ? TeamRoleConfig.color(r).withValues(alpha: 0.12)
                          : AdminUi.cardOf(ctx),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: escolhido == r
                              ? TeamRoleConfig.color(r)
                              : AdminUi.bordaOf(ctx),
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        onTap: () => setLocal(() => escolhido = r),
                        leading: Icon(TeamRoleConfig.icon(r),
                            color: TeamRoleConfig.color(r)),
                        title: Text(TeamRoleConfig.label(r),
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text(TeamRoleConfig.description(r),
                            style: const TextStyle(fontSize: 11.5)),
                        trailing: escolhido == r
                            ? Icon(Icons.check_circle_rounded,
                                color: TeamRoleConfig.color(r))
                            : null,
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
              onPressed: () => Navigator.pop(ctx, escolhido),
              child: const Text('Continuar'),
            ),
          ],
        ),
      ),
    );
    if (papel == null || !mounted) return;
    final ok = await _confirmar(
      titulo: 'Confirmar papel',
      texto: '${nome.isEmpty ? email : '$nome ($email)'} passa a ser '
          '«${TeamRoleConfig.label(papel)}» no Painel Admin.\n\n'
          '${TeamRoleConfig.description(papel)}',
      acao: 'Confirmar',
    );
    if (!ok) return;
    await _gravar(doc.id, papel, email,
        sucesso: '${TeamRoleConfig.label(papel)} ativado para $email.');
  }

  Future<void> _rebaixar(AdminUserDoc doc) async {
    final d = doc.data();
    final email = (d['email'] ?? '').toString().trim();
    final nome = adminUserDisplayName(d);
    final ok = await _confirmar(
      titulo: 'Remover do painel?',
      texto: '${nome.isEmpty ? email : '$nome ($email)'} perde o acesso ao '
          'Painel Admin e volta a ser usuário comum. O plano e a licença '
          'continuam como estão.',
      acao: 'Remover acesso',
      perigo: true,
    );
    if (!ok) return;
    await _gravar(doc.id, null, email, sucesso: 'Acesso removido de $email.');
  }

  Future<bool> _confirmar({
    required String titulo,
    required String texto,
    required String acao,
    bool perigo = false,
  }) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: perigo
                ? FilledButton.styleFrom(backgroundColor: Colors.red.shade700)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(acao),
          ),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _gravar(String uid, TeamRole? papel, String email,
      {required String sucesso}) async {
    setState(() => _salvando.add(uid));
    try {
      await _papeis.definirPapel(uid: uid, role: papel, emailAlvo: email);
      _snack(sucesso);
      await _pager.refreshOne(uid);
      unawaited(_carregarEquipe());
    } catch (e) {
      _snack(AdminLoadGuard.mensagem(e), erro: true);
    } finally {
      if (mounted) setState(() => _salvando.remove(uid));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = AdminPageShell.listPadding(context, top: 4);
    final docs = _visiveis();
    final carregando =
        _filtroDeEquipe ? _equipeCarregando : (_pager.loading && docs.isEmpty);
    final erro = _filtroDeEquipe ? _equipeErro : _pager.error;
    final total = _pager.total;
    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([_pager.reload(), _carregarEquipe()]);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: pad.copyWith(bottom: pad.bottom + 32),
        children: [
          const AdminHero(
            titulo: 'Promover a admin',
            subtitulo:
                'Dê ou tire acesso ao Painel Admin. Só o master vê esta tela.',
            icone: Icons.admin_panel_settings_rounded,
            cores: [Color(0xFF78350F), Color(0xFFD97706), Color(0xFF7C3AED)],
          ),
          const SizedBox(height: 12),
          AdminBusca(
            controller: _buscaCtrl,
            hint: 'Buscar por e-mail ou nome…',
            onChanged: _agendarBusca,
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final f in _FiltroPapel.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _chipFiltro(f),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  _resumoLista(docs.length, total),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AdminUi.apoioOf(context),
                  ),
                ),
              ),
              if (_buscandoServidor)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              IconButton(
                tooltip: 'Atualizar',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  unawaited(_pager.reload());
                  unawaited(_carregarEquipe());
                },
                icon: const Icon(Icons.refresh_rounded, size: 20),
              ),
            ],
          ),
          Text(
            'Master é só o e-mail dos donos '
            '(${AdminMasterConfig.kMasterEmails.join(' e ')}) — não dá para '
            'promover ninguém a master.',
            style: TextStyle(fontSize: 11.5, color: AdminUi.apoioOf(context)),
          ),
          const SizedBox(height: 12),
          if (erro != null && docs.isEmpty)
            AdminErroCard(
              erro: erro,
              titulo: 'Não deu para carregar os usuários',
              onTentar: () {
                if (_filtroDeEquipe) {
                  unawaited(_carregarEquipe());
                } else {
                  unawaited(_pager.reload());
                }
              },
            )
          else if (carregando)
            const AdminCarregando(texto: 'Carregando usuários…')
          else if (docs.isEmpty)
            AdminVazio(
              texto: _buscaCtrl.text.trim().isNotEmpty
                  ? 'Ninguém com esse e-mail ou nome nesta lista. '
                      'A pessoa precisa ter entrado no app ao menos uma vez.'
                  : 'Ninguém neste filtro.',
              icone: Icons.search_off_rounded,
            )
          else ...[
            for (final d in docs) _linha(d),
            if (!_filtroDeEquipe && _pager.hasMore) ...[
              const SizedBox(height: 6),
              Center(
                child: _pager.loading
                    ? const Padding(
                        padding: EdgeInsets.all(8),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : OutlinedButton.icon(
                        onPressed: () => unawaited(_pager.loadMore()),
                        icon: const Icon(Icons.expand_more_rounded),
                        label: const Text('Carregar mais'),
                      ),
              ),
              if (_pager.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    AdminLoadGuard.mensagem(_pager.error),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12, color: Colors.red.shade400),
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }

  String _resumoLista(int visiveis, int? total) {
    if (_filtroDeEquipe) return '$visiveis na equipe neste filtro';
    final carregados = _pager.docs.length;
    final t = total == null ? '' : ' de $total';
    if (_buscaCtrl.text.trim().isNotEmpty || _filtro == _FiltroPapel.usuarios) {
      return '$visiveis encontrados · $carregados carregados$t';
    }
    return '$carregados usuários carregados$t';
  }

  Widget _chipFiltro(_FiltroPapel f) {
    final (rotulo, icone, cor) = switch (f) {
      _FiltroPapel.todos => ('Todos', Icons.people_alt_rounded, AdminUi.azul),
      _FiltroPapel.admins => (
          'Admins',
          Icons.admin_panel_settings_rounded,
          TeamRoleConfig.color(TeamRole.admin)
        ),
      _FiltroPapel.suporte => (
          'Suporte',
          TeamRoleConfig.icon(TeamRole.suporte),
          TeamRoleConfig.color(TeamRole.suporte)
        ),
      _FiltroPapel.editores => (
          'Editores',
          TeamRoleConfig.icon(TeamRole.editor),
          TeamRoleConfig.color(TeamRole.editor)
        ),
      _FiltroPapel.editorConteudo => (
          'Editor de conteúdo',
          TeamRoleConfig.icon(TeamRole.editorConteudo),
          TeamRoleConfig.color(TeamRole.editorConteudo)
        ),
      _FiltroPapel.usuarios => ('Usuários', Icons.person_rounded, AdminUi.cinza),
    };
    final n = _equipeCarregando ? -1 : _contar(f);
    final sel = _filtro == f;
    return ChoiceChip(
      selected: sel,
      showCheckmark: false,
      avatar: Icon(icone, size: 16, color: sel ? Colors.white : cor),
      label: Text(n >= 0 ? '$rotulo · $n' : rotulo),
      labelStyle: TextStyle(
        fontWeight: FontWeight.w800,
        fontSize: 12.5,
        color: sel ? Colors.white : AdminUi.tintaOf(context),
      ),
      selectedColor: cor,
      backgroundColor: AdminUi.cardOf(context),
      side: BorderSide(color: sel ? cor : AdminUi.bordaOf(context)),
      onSelected: (_) => setState(() => _filtro = f),
    );
  }

  static DateTime? _quando(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is num && v > 0) {
      return DateTime.fromMillisecondsSinceEpoch(v.toInt());
    }
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  String _plano(Map<String, dynamic> d) {
    final p = (d['plan'] ?? d['licensePlan'] ?? '').toString().trim();
    return p.isEmpty ? 'free' : p;
  }

  String _ultimoAcesso(Map<String, dynamic> d) {
    final tel = d['clientTelemetry'];
    final dt = _quando(tel is Map ? tel['lastPingAt'] : null) ??
        _quando(d['lastLoginAt']) ??
        _quando(d['updatedAt']);
    if (dt == null) return 'sem registro de acesso';
    return 'último acesso ${DateFormat('dd/MM/yy HH:mm').format(dt)}';
  }

  Widget _linha(AdminUserDoc doc) {
    final d = doc.data();
    final email = (d['email'] ?? '').toString();
    final nome = adminUserDisplayName(d);
    final papel = _papelAtual(d);
    final dono = AdminMasterConfig.isMasterEmail(email);
    final salvando = _salvando.contains(doc.id);
    final cor = papel == null ? AdminUi.cinza : TeamRoleConfig.color(papel);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AdminUi.cardOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminUi.bordaOf(context)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: cor.withValues(alpha: 0.14),
            child: Icon(
                papel == null
                    ? Icons.person_rounded
                    : TeamRoleConfig.icon(papel),
                color: cor,
                size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nome.isEmpty ? '—' : nome,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AdminUi.tintaOf(context))),
                Text(email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        color: context.isDarkMode
                            ? context.appTextSecondary
                            : Colors.grey.shade700)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AdminSelo(
                      dono
                          ? 'Master (dono)'
                          : papel == null
                              ? 'Usuário comum'
                              : TeamRoleConfig.label(papel),
                      cor: dono ? TeamRoleConfig.color(TeamRole.master) : cor,
                    ),
                    AdminSelo(_plano(d),
                        cor: AdminUi.teal,
                        icone: Icons.workspace_premium_rounded),
                    Text(
                      _ultimoAcesso(d),
                      style: TextStyle(
                          fontSize: 11, color: AdminUi.apoioOf(context)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (salvando)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (!dono)
            Wrap(
              spacing: 4,
              children: [
                if (MediaQuery.sizeOf(context).width < 520)
                  IconButton.filledTonal(
                    tooltip: papel == null ? 'Promover' : 'Trocar papel',
                    onPressed: () => _promover(doc),
                    icon: const Icon(Icons.upgrade_rounded, size: 20),
                  )
                else
                  FilledButton.tonalIcon(
                    onPressed: () => _promover(doc),
                    icon: const Icon(Icons.upgrade_rounded, size: 18),
                    label: Text(papel == null ? 'Promover' : 'Trocar papel'),
                  ),
                if (papel != null)
                  IconButton(
                    tooltip: 'Remover do painel',
                    onPressed: () => _rebaixar(doc),
                    icon: Icon(Icons.person_remove_rounded,
                        color: Colors.red.shade400),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
