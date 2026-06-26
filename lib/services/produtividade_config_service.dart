import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/firestore_user_doc_id.dart';
import 'user_settings_docs_cache.dart';

/// Configuração do módulo Produtividade/Ocorrências.
/// users/{uid}/settings/produtividade — campo pontuacaoParaFolga (padrão 30).
class ProdutividadeConfigService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _ref(String uid) => _db
      .collection('users')
      .doc(firestoreUserDocIdForAppShell(uid))
      .collection('settings')
      .doc('produtividade');

  static const int defaultPontuacaoParaFolga = 30;

  /// Pontuação mínima para poder marcar uma folga (ex.: 30 na 24ª CIPM).
  Future<int> getPontuacaoParaFolga(String uid) async {
    final cached = UserSettingsDocsCache.peek(uid, 'produtividade');
    if (cached != null) {
      return _parsePontuacao(cached['pontuacaoParaFolga']);
    }
    final snap = await _ref(uid).get(const GetOptions(source: Source.serverAndCache));
    final data = snap.data();
    UserSettingsDocsCache.put(uid, 'produtividade', data);
    return _parsePontuacao(data?['pontuacaoParaFolga']);
  }

  int _parsePontuacao(Object? v) {
    if (v is int) return v.clamp(1, 999);
    if (v is num) return v.toInt().clamp(1, 999);
    return defaultPontuacaoParaFolga;
  }

  Stream<int> watchPontuacaoParaFolga(String uid) {
    return _ref(uid).snapshots().map((snap) {
      final v = snap.data()?['pontuacaoParaFolga'];
      if (v is int) return v.clamp(1, 999);
      if (v is num) return v.toInt().clamp(1, 999);
      return defaultPontuacaoParaFolga;
    });
  }

  Future<void> setPontuacaoParaFolga(String uid, int value) async {
    await _ref(uid).set({
      'pontuacaoParaFolga': value.clamp(1, 999),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    final prev = UserSettingsDocsCache.peek(uid, 'produtividade') ?? {};
    UserSettingsDocsCache.put(uid, 'produtividade', {
      ...prev,
      'pontuacaoParaFolga': value.clamp(1, 999),
    });
  }
}
