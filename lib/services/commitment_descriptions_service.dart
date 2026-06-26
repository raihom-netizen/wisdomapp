import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import '../utils/firestore_user_doc_id.dart';
import 'user_categories_service.dart';

/// Persiste descrições de compromisso **customizadas** que o usuário criou
/// pelo botão "Incluir nova" no picker do "Compromisso expresso".
///
/// Caminho: `users/{uid}/settings/commitment_descriptions` (documento único
/// com array `items: [{name}]`). Mesma abordagem leve do
/// [UserCategoriesService] — sem subcoleção, leitura/escrita atômica.
class CommitmentDescriptionsService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _ref(String uid) => _db
      .collection('users')
      .doc(firestoreUserDocIdForAppShell(uid))
      .collection('settings')
      .doc('commitment_descriptions');

  /// Stream das descrições customizadas (vazio quando não há nada salvo).
  /// Respeita a sessão Firebase Auth: sem usuário, retorna lista vazia (evita
  /// `permission-denied` em web durante restauração de sessão).
  Stream<List<String>> watch(String uid) {
    return fa.FirebaseAuth.instance.authStateChanges().asyncExpand((user) {
      if (user == null) return Stream<List<String>>.value(const <String>[]);
      return _ref(uid).snapshots().map((snap) {
        final data = snap.data();
        return _itemsFrom(data?['items']);
      });
    });
  }

  Future<List<String>> listOnce(String uid) async {
    try {
      final snap = await _ref(uid).get();
      return _itemsFrom(snap.data()?['items']);
    } catch (_) {
      return const <String>[];
    }
  }

  /// Adiciona descrição evitando duplicatas (case-insensitive). Trim aplicado.
  Future<void> add(String uid, String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    final current = await listOnce(uid);
    final lower = n.toLowerCase();
    if (current.any((e) => e.toLowerCase() == lower)) return;
    final updated = [...current, n]..sort(UserCategoriesService.compareNamesPt);
    await _ref(uid).set({
      'items': updated,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> remove(String uid, String name) async {
    final n = name.trim().toLowerCase();
    final current = await listOnce(uid);
    final updated = current.where((e) => e.toLowerCase() != n).toList();
    await _ref(uid).set({
      'items': updated,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static List<String> _itemsFrom(dynamic raw) {
    if (raw is! List) return const <String>[];
    return raw
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
  }
}
