import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../utils/admin_user_search.dart';
typedef AdminGlobalSearchSelect = void Function(
  String uid,
  String name,
  String email,
);

/// Busca global de utilizadores no painel admin.
class AdminGlobalSearchDelegate extends SearchDelegate<String?> {
  AdminGlobalSearchDelegate({required this.onSelect});

  final AdminGlobalSearchSelect onSelect;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

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
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }
    return _buildList(context);
  }

  Widget _buildList(BuildContext context) {
    final q = query.trim().toLowerCase();
    if (q.length < 2) return const SizedBox.shrink();

    return FutureBuilder<List<_AdminSearchHit>>(
      future: _search(q),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Erro: ${snap.error}'));
        }
        final hits = snap.data ?? [];
        if (hits.isEmpty) {
          return const Center(child: Text('Nenhum utilizador encontrado.'));
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

  Future<List<_AdminSearchHit>> _search(String q) async {
    final results = <String, _AdminSearchHit>{};

    void addDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
      final data = d.data();
      results[d.id] = _AdminSearchHit(
        uid: d.id,
        name: adminUserDisplayName(data),
        email: (data['email'] ?? '').toString(),
      );
    }

    Future<void> byField(String field) async {
      final snap = await _db
          .collection('users')
          .orderBy(field)
          .startAt([q])
          .endAt(['$q\uf8ff'])
          .limit(12)
          .get();
      for (final d in snap.docs) {
        addDoc(d);
      }
    }

    try {
      await byField('email');
    } catch (_) {}
    try {
      await byField('name');
    } catch (_) {}
    try {
      await byField('displayName');
    } catch (_) {}

    // Fallback: prefixo no Firestore pode falhar (índice/campo vazio) — filtra em memória.
    if (results.length < 8) {
      try {
        final snap = await _db.collection('users').limit(2000).get();
        for (final d in snap.docs) {
          if (adminUserMatchesSearch(d.data(), d.id, q)) {
            addDoc(d);
          }
          if (results.length >= 20) break;
        }
      } catch (_) {}
    }

    if (q.length >= 20) {
      final direct = await _db.collection('users').doc(q).get();
      if (direct.exists) {
        final data = direct.data() ?? {};
        results[direct.id] = _AdminSearchHit(
          uid: direct.id,
          name: adminUserDisplayName(data),
          email: (data['email'] ?? '').toString(),
        );
      }
    }

    final list = results.values.toList();
    list.sort((a, b) {
      final na = a.name.toLowerCase();
      final nb = b.name.toLowerCase();
      return na.compareTo(nb);
    });
    return list.take(20).toList();
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
