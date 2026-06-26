import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/controle_total_config.dart';
import '../utils/firestore_user_doc_id.dart';

/// Configurações do Controle Total por usuário (padrão horas, tipo servidor, adicionais).
/// Configuração global do app é do Estado de Goiás; aqui o usuário escolhe usar essa ou a dele.
class ControleTotalConfigService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String uid) => _db
      .collection('users')
      .doc(firestoreUserDocIdForAppShell(uid))
      .collection('settings')
      .doc('controle_total_config');

  Future<ControleTotalConfig> getConfig(String uid) async {
    if (uid.isEmpty) return const ControleTotalConfig();
    final snap = await _doc(uid).get();
    return ControleTotalConfig.fromMap(snap.data());
  }

  /// Offline: lê do cache persistente do Firestore antes da rede.
  Future<ControleTotalConfig> getConfigCacheFirst(String uid) async {
    if (uid.isEmpty) return const ControleTotalConfig();
    try {
      final cached =
          await _doc(uid).get(const GetOptions(source: Source.cache));
      if (cached.exists) {
        return ControleTotalConfig.fromMap(cached.data());
      }
    } catch (_) {}
    try {
      final snap = await _doc(uid).get();
      return ControleTotalConfig.fromMap(snap.data());
    } catch (_) {
      try {
        final cached =
            await _doc(uid).get(const GetOptions(source: Source.cache));
        return ControleTotalConfig.fromMap(cached.data());
      } catch (_) {
        return const ControleTotalConfig();
      }
    }
  }

  Stream<ControleTotalConfig> watchConfig(String uid) {
    if (uid.isEmpty) return Stream.value(const ControleTotalConfig());
    return _doc(uid).snapshots().map((s) => ControleTotalConfig.fromMap(s.data()));
  }

  Future<void> setConfig(String uid, ControleTotalConfig config) async {
    if (uid.isEmpty) return;
    final map = config.toMap();
    map['updatedAt'] = FieldValue.serverTimestamp();
    await _doc(uid).set(map, SetOptions(merge: true));
  }
}
