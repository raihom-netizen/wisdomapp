import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/team_role_config.dart';
import '../services/logs_service.dart';
import '../theme/app_colors.dart';
import '../utils/admin_responsive.dart';
import '../widgets/admin/admin_page_shell.dart';
import '../widgets/admin_guard.dart';
import '../widgets/fast_text_field.dart';
import 'create_admin_user_screen.dart';

/// Gestão de equipe — Master gerencia ADMs, Gestores e Sócios.
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

class _GestaoEquipeAdmState extends State<GestaoEquipeAdm>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  String _filterQuery = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> get _teamStream =>
      FirebaseFirestore.instance
          .collection('users')
          .where('role', whereIn: ['admin', 'master', 'gestor', 'partner', 'socio'])
          .snapshots();

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final q = _filterQuery.trim().toLowerCase();
    var list = docs.toList()
      ..sort((a, b) {
        final na = (a.data()['name'] ?? a.data()['email'] ?? '').toString();
        final nb = (b.data()['name'] ?? b.data()['email'] ?? '').toString();
        return na.toLowerCase().compareTo(nb.toLowerCase());
      });

    if (_tabs.index == 1) {
      list = list.where((d) {
        final r = TeamRoleConfig.fromFirestore(
          role: (d.data()['role'] ?? '').toString(),
          adminLevel: (d.data()['adminLevel'] ?? '').toString(),
        );
        return r == TeamRole.master || r == TeamRole.admin || r == TeamRole.suporte || r == TeamRole.editor;
      }).toList();
    } else if (_tabs.index == 2) {
      list = list.where((d) {
        final r = TeamRoleConfig.fromFirestore(
          role: (d.data()['role'] ?? '').toString(),
        );
        return r == TeamRole.gestor;
      }).toList();
    } else if (_tabs.index == 3) {
      list = list.where((d) {
        final r = TeamRoleConfig.fromFirestore(
          role: (d.data()['role'] ?? '').toString(),
        );
        return r == TeamRole.partner;
      }).toList();
    }

    if (q.isNotEmpty) {
      list = list.where((d) {
        final data = d.data();
        final blob = '${data['name']} ${data['email']} ${data['role']}'.toLowerCase();
        return blob.contains(q);
      }).toList();
    }
    return list;
  }

  bool _canEditMember(Map<String, dynamic> data) {
    if (!widget.canManageTeam) return false;
    final role = TeamRoleConfig.fromFirestore(
      role: (data['role'] ?? '').toString(),
      adminLevel: (data['adminLevel'] ?? '').toString(),
    );
    return role != TeamRole.master;
  }

  Future<void> _openCreate(TeamRole preset) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminGuard(
          child: CreateAdminUserScreen(initialRole: preset),
        ),
      ),
    );
  }

  Future<void> _editMember(String uid, Map<String, dynamic> data) async {
    final nameCtrl = TextEditingController(text: (data['name'] ?? '').toString());
    var selected = TeamRoleConfig.fromFirestore(
      role: (data['role'] ?? '').toString(),
      adminLevel: (data['adminLevel'] ?? '').toString(),
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Editar membro'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FastTextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Nome',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<TeamRole>(
                  value: TeamRoleConfig.creatableRoles.contains(selected)
                      ? selected
                      : TeamRole.admin,
                  decoration: InputDecoration(
                    labelText: 'Papel',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: TeamRoleConfig.creatableRoles
                      .map(
                        (r) => DropdownMenuItem(
                          value: r,
                          child: Text(TeamRoleConfig.label(r)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setLocal(() => selected = v ?? TeamRole.admin),
                ),
                const SizedBox(height: 8),
                Text(
                  TeamRoleConfig.description(selected),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.35),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
          ],
        ),
      ),
    );

    if (saved != true || !mounted) return;

    try {
      final payload = <String, dynamic>{
        'name': nameCtrl.text.trim(),
        'role': TeamRoleConfig.firestoreRoleFor(selected),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      final lvl = TeamRoleConfig.adminLevelFor(selected);
      if (lvl != null) {
        payload['adminLevel'] = lvl;
      } else {
        payload['adminLevel'] = FieldValue.delete();
      }
      await FirebaseFirestore.instance.collection('users').doc(uid).update(payload);
      await LogsService().saveLog(
        modulo: 'Admin',
        acao: 'Editou membro da equipe',
        detalhes: '${nameCtrl.text.trim()} → ${TeamRoleConfig.label(selected)}',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Membro atualizado.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: ${e.toString().split('\n').first}'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _removeMember(String uid, String nome, String email) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover da equipe?'),
        content: Text(
          '$nome ($email) perderá acesso ao Painel Admin.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
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
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'role': 'user',
        'plan': 'free',
        'adminLevel': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await LogsService().saveLog(
        modulo: 'Admin',
        acao: 'Removeu membro da equipe',
        detalhes: nome.isEmpty ? email : '$nome ($email)',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Membro removido.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _promoteExisting() async {
    final emailCtrl = TextEditingController();
    var selected = TeamRole.gestor;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Promover usuário existente'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FastTextField(
                controller: emailCtrl,
                kind: FastTextFieldKind.email,
                decoration: const InputDecoration(
                  labelText: 'E-mail do usuário',
                  hintText: 'usuario@email.com',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<TeamRole>(
                value: selected,
                decoration: const InputDecoration(labelText: 'Novo papel'),
                items: TeamRoleConfig.creatableRoles
                    .map((r) => DropdownMenuItem(value: r, child: Text(TeamRoleConfig.label(r))))
                    .toList(),
                onChanged: (v) => setLocal(() => selected = v ?? TeamRole.gestor),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Promover')),
          ],
        ),
      ),
    );

    if (ok != true || !mounted) return;
    final email = emailCtrl.text.trim().toLowerCase();
    if (email.isEmpty) return;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Usuário não encontrado. Use «Novo membro» para criar conta.')),
          );
        }
        return;
      }
      final doc = snap.docs.first;
      final payload = <String, dynamic>{
        'role': TeamRoleConfig.firestoreRoleFor(selected),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      final lvl = TeamRoleConfig.adminLevelFor(selected);
      if (lvl != null) {
        payload['adminLevel'] = lvl;
      } else {
        payload['adminLevel'] = FieldValue.delete();
      }
      await doc.reference.update(payload);
      await LogsService().saveLog(
        modulo: 'Admin',
        acao: 'Promoveu usuário à equipe',
        detalhes: '$email → ${TeamRoleConfig.label(selected)}',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${TeamRoleConfig.label(selected)} ativado para $email.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = widget.embeddedInAdmin
        ? AdminPageShell.listPadding(context, top: 4)
        : EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _teamStream,
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        final filtered = snap.hasData ? _filterDocs(docs) : <QueryDocumentSnapshot<Map<String, dynamic>>>[];

        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            SliverPadding(
              padding: pad.copyWith(bottom: 0),
              sliver: SliverToBoxAdapter(child: _HeroHeader(count: docs.length)),
            ),
            if (widget.canManageTeam) ...[
              SliverPadding(
                padding: EdgeInsets.fromLTRB(pad.left, 12, pad.right, 8),
                sliver: SliverToBoxAdapter(child: _ActionButtons(onCreate: _openCreate, onPromote: _promoteExisting)),
              ),
            ],
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad.left, 0, pad.right, 10),
              sliver: SliverToBoxAdapter(child: _RoleGuideCards()),
            ),
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: pad.left),
              sliver: SliverToBoxAdapter(child: _TeamTabBar(tabs: _tabs, total: docs.length)),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad.left, 10, pad.right, 8),
              sliver: SliverToBoxAdapter(
                child: TextField(
                  onChanged: (v) => setState(() => _filterQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Buscar nome ou e-mail…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
            if (snap.hasError)
              SliverFillRemaining(
                child: Center(child: Text('Erro: ${snap.error}')),
              )
            else if (snap.connectionState == ConnectionState.waiting && !snap.hasData)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            else if (filtered.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      widget.canManageTeam
                          ? 'Nenhum membro nesta aba. Use «Novo Admin» ou «Novo Gestor».'
                          : 'Nenhum membro listado.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(pad.left, 0, pad.right, pad.bottom + 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final doc = filtered[i];
                      final data = doc.data();
                      final role = TeamRoleConfig.fromFirestore(
                        role: (data['role'] ?? '').toString(),
                        adminLevel: (data['adminLevel'] ?? '').toString(),
                      );
                      final isSelf = doc.id == FirebaseAuth.instance.currentUser?.uid;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _MemberCard(
                          name: (data['name'] ?? '').toString(),
                          email: (data['email'] ?? '').toString(),
                          role: role,
                          isSelf: isSelf,
                          canEdit: _canEditMember(data),
                          onEdit: () => _editMember(doc.id, data),
                          onRemove: () => _removeMember(
                            doc.id,
                            (data['name'] ?? '').toString(),
                            (data['email'] ?? '').toString(),
                          ),
                        ),
                      );
                    },
                    childCount: filtered.length,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF0B1B4B), Color(0xFF0F766E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0B1B4B).withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.groups_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Gestão de equipe',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$count membro(s) · Admin, Gestor e Sócio',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({required this.onCreate, required this.onPromote});

  final void Function(TeamRole) onCreate;
  final VoidCallback onPromote;

  @override
  Widget build(BuildContext context) {
    final narrow = AdminResponsive.useMobileLayout(context);
    final children = [
      Expanded(
        child: FilledButton.icon(
          onPressed: () => onCreate(TeamRole.admin),
          icon: const Icon(Icons.admin_panel_settings_rounded),
          label: Text(narrow ? 'Novo Admin' : 'Novo administrador'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: FilledButton.icon(
          onPressed: () => onCreate(TeamRole.gestor),
          icon: const Icon(Icons.manage_accounts_rounded),
          label: Text(narrow ? 'Novo Gestor' : 'Novo gestor'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF7C3AED),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (narrow) ...[
          SizedBox(width: double.infinity, child: children[0]),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => onCreate(TeamRole.gestor),
              icon: const Icon(Icons.manage_accounts_rounded),
              label: const Text('Novo Gestor'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ] else
          Row(children: children),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => onCreate(TeamRole.partner),
              icon: const Icon(Icons.handshake_rounded, size: 18),
              label: const Text('Novo sócio'),
            ),
            OutlinedButton.icon(
              onPressed: onPromote,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: const Text('Promover existente'),
            ),
          ],
        ),
      ],
    );
  }
}

class _RoleGuideCards extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const roles = [
      TeamRole.master,
      TeamRole.admin,
      TeamRole.gestor,
      TeamRole.partner,
    ];
    return SizedBox(
      height: 118,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: roles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final r = roles[i];
          final c = TeamRoleConfig.color(r);
          return Container(
            width: 220,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.withValues(alpha: 0.28)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(TeamRoleConfig.icon(r), size: 18, color: c),
                    const SizedBox(width: 6),
                    Text(
                      TeamRoleConfig.label(r),
                      style: TextStyle(fontWeight: FontWeight.w900, color: c, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Text(
                    TeamRoleConfig.description(r),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade800, height: 1.3),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TeamTabBar extends StatelessWidget {
  const _TeamTabBar({required this.tabs, required this.total});

  final TabController tabs;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
      ),
      child: TabBar(
        controller: tabs,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(colors: [Color(0xFF0B1B4B), Color(0xFF0F766E)]),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.grey.shade700,
        labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
        tabs: [
          Tab(text: 'Todos ($total)'),
          const Tab(text: 'Admins'),
          const Tab(text: 'Gestores'),
          const Tab(text: 'Sócios'),
        ],
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.name,
    required this.email,
    required this.role,
    required this.isSelf,
    required this.canEdit,
    required this.onEdit,
    required this.onRemove,
  });

  final String name;
  final String email;
  final TeamRole role;
  final bool isSelf;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = TeamRoleConfig.color(role);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: c.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: c.withValues(alpha: 0.15),
                child: Icon(TeamRoleConfig.icon(role), color: c, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? '—' : name,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    Text(email, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: c.withValues(alpha: 0.35)),
                ),
                child: Text(
                  isSelf ? '${TeamRoleConfig.label(role)} · você' : TeamRoleConfig.label(role),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c),
                ),
              ),
            ],
          ),
          if (canEdit) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('Editar'),
                ),
                TextButton.icon(
                  onPressed: onRemove,
                  icon: Icon(Icons.person_remove_rounded, size: 18, color: Colors.red.shade400),
                  label: Text('Remover', style: TextStyle(color: Colors.red.shade400)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
