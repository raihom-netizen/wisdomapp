import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/clt_labor_config.dart';
import '../utils/firestore_user_doc_id.dart';

class CltLaborConfigService {
  CltLaborConfigService._();
  factory CltLaborConfigService() => _instance;
  static final CltLaborConfigService _instance = CltLaborConfigService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final Map<String, CltLaborConfig> _cache = {};

  DocumentReference<Map<String, dynamic>> _doc(String uid) => _db
      .collection('users')
      .doc(firestoreUserDocIdForAppShell(uid))
      .collection('settings')
      .doc('clt_labor');

  Future<CltLaborConfig> getConfig(String uid) async {
    final key = firestoreUserDocIdForAppShell(uid);
    final hit = _cache[key];
    if (hit != null) return hit;
    try {
      final snap = await _doc(uid).get();
      final cfg = CltLaborConfig.fromMap(snap.data());
      _cache[key] = cfg;
      return cfg;
    } catch (_) {
      return CltLaborConfig.defaults();
    }
  }

  Future<void> setConfig(String uid, CltLaborConfig config) async {
    if (uid.isEmpty) return;
    final map = config.toMap();
    map['updatedAt'] = FieldValue.serverTimestamp();
    await _doc(uid).set(map, SetOptions(merge: true));
    _cache[firestoreUserDocIdForAppShell(uid)] = config;
  }

  void invalidate(String? uid) {
    if (uid == null) {
      _cache.clear();
      return;
    }
    _cache.remove(firestoreUserDocIdForAppShell(uid));
  }
}
