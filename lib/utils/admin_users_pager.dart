import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'admin_load_guard.dart';
import 'admin_user_search.dart';

typedef AdminUserDoc = QueryDocumentSnapshot<Map<String, dynamic>>;

/// Lista de usuários do painel admin em PÁGINAS (02/10/2026).
///
/// Antes a Lista de Usuários e o 360° escutavam até 2000 docs em tempo real
/// (`.snapshots()`), e a busca global lia 2000 de uma vez. Agora: `.get()`
/// paginado por e-mail com cursor («Carregar mais»), total por `count()` e
/// busca por PREFIXO no servidor (e-mail, nome, CPF, UID) — sem baixar a
/// base inteira.
class AdminUsersPager extends ChangeNotifier {
  AdminUsersPager({int? pageSize}) : pageSize = pageSize ?? _defaultPageSize;

  final int pageSize;

  static int get _defaultPageSize {
    if (kIsWeb) return 150;
    return (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)
        ? 60
        : 120;
  }

  final List<AdminUserDoc> _docs = [];
  final Set<String> _ids = {};
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _hasMore = true;
  bool _loading = false;
  Object? _error;
  int? _total;
  bool _disposed = false;

  List<AdminUserDoc> get docs => List.unmodifiable(_docs);
  bool get hasMore => _hasMore;
  bool get loading => _loading;
  Object? get error => _error;
  bool get loadedOnce => _cursor != null || !_hasMore || _docs.isNotEmpty;

  /// Total de usuários com e-mail (aggregate `count()`), quando disponível.
  int? get total => _total;

  Query<Map<String, dynamic>> get _base => adminUsersWithEmailQuery(
          FirebaseFirestore.instance.collection('users'))
      .orderBy('email');

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Recomeça do zero (botão «Atualizar» / «Tentar de novo»).
  Future<void> reload() async {
    _docs.clear();
    _ids.clear();
    _cursor = null;
    _hasMore = true;
    _error = null;
    _notify();
    await Future.wait([loadMore(), _loadTotal()]);
  }

  Future<void> _loadTotal() async {
    try {
      final agg = await AdminLoadGuard.comPrazo(
        adminUsersWithEmailQuery(FirebaseFirestore.instance.collection('users'))
            .count()
            .get(),
        oQue: 'o total de usuários',
      );
      _total = agg.count;
      _notify();
    } catch (e) {
      // Total é só informativo — a lista segue sem ele.
      debugPrint('AdminUsersPager total: $e');
    }
  }

  Future<void> loadMore() async {
    if (_loading || !_hasMore) return;
    _loading = true;
    _error = null;
    _notify();
    try {
      var q = _base.limit(pageSize);
      final c = _cursor;
      if (c != null) q = q.startAfterDocument(c);
      final snap = await AdminLoadGuard.comPrazo(
        q.get(),
        prazo: AdminLoadGuard.longo,
        oQue: 'os usuários',
      );
      for (final d in snap.docs) {
        if (_ids.add(d.id)) _docs.add(d);
      }
      if (snap.docs.isNotEmpty) _cursor = snap.docs.last;
      _hasMore = snap.docs.length >= pageSize;
    } catch (e) {
      _error = e;
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// Junta resultados da busca no servidor à lista (sem duplicar).
  void merge(Iterable<AdminUserDoc> extra) {
    var mudou = false;
    for (final d in extra) {
      if (_ids.add(d.id)) {
        _docs.add(d);
        mudou = true;
      }
    }
    if (mudou) _notify();
  }

  /// Relê um usuário (depois de editar no card) e troca na lista.
  Future<void> refreshOne(String uid) async {
    try {
      final snap = await AdminLoadGuard.comPrazo(
        FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, isEqualTo: uid)
            .limit(1)
            .get(),
        oQue: 'o usuário',
      );
      final i = _docs.indexWhere((d) => d.id == uid);
      if (snap.docs.isEmpty) {
        if (i >= 0) {
          _docs.removeAt(i);
          _ids.remove(uid);
        }
      } else if (i >= 0) {
        _docs[i] = snap.docs.first;
      } else {
        _docs.add(snap.docs.first);
        _ids.add(uid);
      }
      _notify();
    } catch (e) {
      debugPrint('AdminUsersPager.refreshOne($uid): $e');
    }
  }
}

/// Busca de usuários NO SERVIDOR por prefixo (e-mail, nome como digitado /
/// Capitalizado / minúsculo, CPF, UID exato). Lê no máximo [limit] por
/// consulta — nunca a base inteira. Erros sobem (a tela mostra «Tentar de
/// novo»).
Future<List<AdminUserDoc>> adminSearchUsersServer(
  String raw, {
  int limit = 25,
}) async {
  final q = raw.trim();
  if (q.length < 2) return const [];
  final col = FirebaseFirestore.instance.collection('users');
  final consultas = <Future<QuerySnapshot<Map<String, dynamic>>>>[];

  Query<Map<String, dynamic>> prefixo(String campo, String p) => col
      .where(campo, isGreaterThanOrEqualTo: p)
      .where(campo, isLessThan: '$p')
      .orderBy(campo)
      .limit(limit);

  final lower = q.toLowerCase();
  consultas.add(prefixo('email', lower).get());

  if (!q.contains('@')) {
    final cap = q
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase())
        .join(' ');
    final nomes = <String>{q, cap, lower};
    for (final n in nomes) {
      consultas.add(prefixo('name', n).get());
    }
    final digits = q.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 11) {
      consultas.add(col.where('cpf', isEqualTo: digits).limit(5).get());
    }
    // UID do Firebase Auth (28 caracteres alfanuméricos).
    if (RegExp(r'^[A-Za-z0-9]{20,36}$').hasMatch(q)) {
      consultas.add(
          col.where(FieldPath.documentId, isEqualTo: q).limit(1).get());
    }
  }

  final snaps = await AdminLoadGuard.comPrazo(
    Future.wait(consultas),
    oQue: 'a busca de usuários',
  );
  final vistos = <String>{};
  final out = <AdminUserDoc>[];
  for (final s in snaps) {
    for (final d in s.docs) {
      if (vistos.add(d.id)) out.add(d);
    }
  }
  return out;
}
