import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/default_ocorrencias_naturezas.dart';
import '../utils/firestore_user_doc_id.dart';

/// Naturezas de ocorrência: padrão (editáveis) + customizadas por usuário.
/// Salvas em users/{uid}/settings/ocorrencias_naturezas.
class OcorrenciasNaturezasService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _ref(String uid) => _db
      .collection('users')
      .doc(firestoreUserDocIdForAppShell(uid))
      .collection('settings')
      .doc('ocorrencias_naturezas');

  /// Carrega naturezas: primeiro as padrão (podem ter sido editadas), depois as customizadas.
  /// Estrutura no doc: { items: [ { id, label, pontos }, ... ] }
  /// Padrão tem id 01..07; customizadas têm id gerado.
  Future<List<OcorrenciaNatureza>> load(String uid) async {
    final snap = await _ref(uid).get();
    final data = snap.data();
    final list = _listFrom(data?['items']);
    if (list.isEmpty) {
      return List<OcorrenciaNatureza>.from(kDefaultOcorrenciasNaturezas);
    }
    final byId = <String, OcorrenciaNatureza>{};
    for (final n in list) {
      byId[n.id] = n;
    }
    final result = <OcorrenciaNatureza>[];
    for (final d in kDefaultOcorrenciasNaturezas) {
      result.add(byId[d.id] ?? d);
    }
    for (final n in list) {
      if (int.tryParse(n.id) == null || int.parse(n.id) > 7) {
        result.add(n);
      }
    }
    return result;
  }

  List<OcorrenciaNatureza> _listFrom(dynamic v) {
    if (v is! List) return [];
    return v
        .map((e) => e is Map ? OcorrenciaNatureza.fromMap(Map<String, dynamic>.from(e as Map)) : null)
        .whereType<OcorrenciaNatureza>()
        .toList();
  }

  /// Salva a lista completa (após editar padrão ou adicionar/remover customizadas).
  Future<void> saveAll(String uid, List<OcorrenciaNatureza> list) async {
    final payload = <String, dynamic>{
      'items': list.map((e) => e.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await _ref(uid).set(payload, SetOptions(merge: true));
  }

  /// Atualiza uma natureza existente (por id).
  Future<void> update(String uid, OcorrenciaNatureza natureza) async {
    final list = await load(uid);
    final idx = list.indexWhere((e) => e.id == natureza.id);
    if (idx < 0) return;
    final updated = List<OcorrenciaNatureza>.from(list)..[idx] = natureza;
    await saveAll(uid, updated);
  }

  /// Adiciona nova natureza customizada (id único).
  Future<void> add(String uid, String label, int pontos) async {
    final list = await load(uid);
    final maxNum = list
        .map((e) => int.tryParse(e.id))
        .whereType<int>()
        .fold<int>(7, (a, b) => b > a ? b : a);
    final newId = (maxNum + 1).toString();
    final nova = OcorrenciaNatureza(id: newId, label: label.trim(), pontos: pontos);
    if (nova.label.isEmpty) return;
    final updated = [...list, nova];
    await saveAll(uid, updated);
  }

  /// Remove apenas natureza customizada (id > 7 ou não numérico).
  Future<void> remove(String uid, String id) async {
    final list = await load(uid);
    final numId = int.tryParse(id);
    if (numId != null && numId >= 1 && numId <= 7) return;
    final updated = list.where((e) => e.id != id).toList();
    await saveAll(uid, updated);
  }
}
