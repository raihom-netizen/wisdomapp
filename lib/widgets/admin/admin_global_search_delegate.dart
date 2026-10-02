import 'package:flutter/material.dart';

import '../../utils/admin_user_search.dart';
import '../../utils/admin_users_pager.dart';
import 'admin_ui_kit.dart';
typedef AdminGlobalSearchSelect = void Function(
  String uid,
  String name,
  String email,
);

/// Busca global de utilizadores no painel admin.
class AdminGlobalSearchDelegate extends SearchDelegate<String?> {
  AdminGlobalSearchDelegate({required this.onSelect});

  final AdminGlobalSearchSelect onSelect;

  @override
  String? get searchFieldLabel => 'Nome, e-mail ou ID';

  @override
  List<Widget>? buildActions(BuildContext context) {
    if (query.isEmpty) return null;
    return [
      IconButton(
        icon: const Icon(Icons.clear_rounded),
        onPressed: () => query = '',
      ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back_rounded),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.trim().length < 2) {
      return Center(
        child: Text(
          'Digite pelo menos 2 caracteres',
          style: TextStyle(color: AdminUi.apoioOf(context)),
        ),
      );
    }
    return _buildList(context);
  }

  /// Future guardado por texto (o build do SearchDelegate roda a cada
  /// tecla/frame — sem isto cada rebuild disparava as consultas de novo).
  String? _futuroPara;
  Future<List<_AdminSearchHit>>? _futuro;

  Future<List<_AdminSearchHit>> _futuroDe(String q) {
    if (_futuro == null || _futuroPara != q) {
      _futuroPara = q;
      _futuro = _search(q);
    }
    return _futuro!;
  }

  Widget _buildList(BuildContext context) {
    final q = query.trim();
    if (q.length < 2) return const SizedBox.shrink();

    return FutureBuilder<List<_AdminSearchHit>>(
      future: _futuroDe(q),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AdminErroCard(
                erro: snap.error,
                titulo: 'A busca falhou',
                onTentar: () {
                  _futuro = null;
                  showSuggestions(context);
                },
              ),
            ],
          );
        }
        final hits = snap.data ?? [];
        if (hits.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Nenhum utilizador encontrado.\n'
                'A busca procura o INÍCIO do e-mail ou do nome '
                '(ex.: «joao@», «Maria Sil»), CPF completo ou UID.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AdminUi.apoioOf(context)),
              ),
            ),
          );
        }
        return ListView.builder(
          itemCount: hits.length,
          itemBuilder: (context, i) {
            final hit = hits[i];
            return ListTile(
              minVerticalPadding: 12,
              leading: CircleAvatar(
                child: Text(
                  hit.name.isNotEmpty ? hit.name[0].toUpperCase() : '?',
                ),
              ),
              title: Text(hit.name.isNotEmpty ? hit.name : hit.email),
              subtitle: Text(hit.email.isNotEmpty ? hit.email : hit.uid),
              onTap: () {
                onSelect(hit.uid, hit.name, hit.email);
                close(context, hit.uid);
              },
            );
          },
        );
      },
    );
  }

  /// 02/10/2026: busca por PREFIXO no servidor (e-mail, nome, CPF, UID) com
  /// limite por consulta — sem o antigo «lê 2000 usuários» e sem engolir
  /// erro (a tela mostra «Tentar de novo»).
  Future<List<_AdminSearchHit>> _search(String q) async {
    final docs = await adminSearchUsersServer(q, limit: 15);
    final results = <String, _AdminSearchHit>{};
    for (final d in docs) {
      final data = d.data();
      if (!adminUserHasCompleteEmail(data)) continue;
      results[d.id] = _AdminSearchHit(
        uid: d.id,
        name: adminUserDisplayName(data),
        email: (data['email'] ?? '').toString(),
      );
    }
    final list = results.values.toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list.take(30).toList();
  }
}

class _AdminSearchHit {
  final String uid;
  final String name;
  final String email;

  const _AdminSearchHit({
    required this.uid,
    required this.name,
    required this.email,
  });
}
