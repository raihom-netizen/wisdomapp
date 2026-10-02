import 'dart:async';

import 'package:flutter/material.dart';

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
/// Busca a conta por e-mail/nome (prefixo no servidor), escolhe o papel da
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

class _AdminPromoverAdminTabState extends State<AdminPromoverAdminTab> {
  final _buscaCtrl = TextEditingController();
  Timer? _debounce;
  String _buscaFeita = '';
  Future<List<AdminUserDoc>>? _resultado;
  final Set<String> _salvando = {};

  static const _papeis = AdminTeamRoleService();

  @override
  void dispose() {
    _debounce?.cancel();
    _buscaCtrl.dispose();
    super.dispose();
  }

  void _agendarBusca(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _buscar);
  }

  void _buscar({bool forcar = false}) {
    final q = _buscaCtrl.text.trim();
    if (q.length < 2) {
      setState(() {
        _buscaFeita = '';
        _resultado = null;
      });
      return;
    }
    if (!forcar && q == _buscaFeita) return;
    setState(() {
      _buscaFeita = q;
      _resultado = adminSearchUsersServer(q, limit: 20);
    });
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
      _buscar(forcar: true);
    } catch (e) {
      _snack(AdminLoadGuard.mensagem(e), erro: true);
    } finally {
      if (mounted) setState(() => _salvando.remove(uid));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = AdminPageShell.listPadding(context, top: 4);
    return ListView(
      padding: pad.copyWith(bottom: pad.bottom + 32),
      children: [
        const AdminHero(
          titulo: 'Promover a admin',
          subtitulo: 'Dê ou tire acesso ao Painel Admin. Só o master vê esta tela.',
          icone: Icons.admin_panel_settings_rounded,
          cores: [Color(0xFF78350F), Color(0xFFD97706), Color(0xFF7C3AED)],
        ),
        const SizedBox(height: 12),
        AdminBusca(
          controller: _buscaCtrl,
          hint: 'Início do e-mail ou do nome (mín. 2 letras)…',
          onChanged: _agendarBusca,
        ),
        const SizedBox(height: 8),
        Text(
          'Master é só o e-mail dos donos (${AdminMasterConfig.kMasterEmails.join(' e ')}) '
          '— não dá para promover ninguém a master.',
          style: TextStyle(fontSize: 12, color: AdminUi.apoioOf(context)),
        ),
        const SizedBox(height: 12),
        if (_resultado == null)
          const AdminVazio(
            texto: 'Busque a conta pelo e-mail ou pelo nome.',
            icone: Icons.person_search_rounded,
          )
        else
          FutureBuilder<List<AdminUserDoc>>(
            future: _resultado,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const AdminCarregando(texto: 'Buscando…');
              }
              if (snap.hasError) {
                return AdminErroCard(
                  erro: snap.error,
                  titulo: 'A busca falhou',
                  onTentar: () => _buscar(forcar: true),
                );
              }
              final docs = (snap.data ?? const <AdminUserDoc>[])
                  .where((d) => adminUserHasCompleteEmail(d.data()))
                  .toList();
              if (docs.isEmpty) {
                return const AdminVazio(
                  texto: 'Nenhuma conta encontrada. A pessoa precisa ter '
                      'entrado no app ao menos uma vez.',
                  icone: Icons.search_off_rounded,
                );
              }
              return Column(
                children: [for (final d in docs) _linha(d)],
              );
            },
          ),
      ],
    );
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
                AdminSelo(
                  dono
                      ? 'Master (dono)'
                      : papel == null
                          ? 'Usuário comum'
                          : TeamRoleConfig.label(papel),
                  cor: dono ? TeamRoleConfig.color(TeamRole.master) : cor,
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
