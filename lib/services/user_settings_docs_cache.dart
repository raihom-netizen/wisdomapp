import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../utils/firestore_user_doc_id.dart';

/// Cache em memória dos docs `users/{uid}/settings/*` — evita vários listeners
/// e GETs repetidos ao abrir Configurações.
class UserSettingsDocsCache {
  UserSettingsDocsCache._();

  static final Map<String, Map<String, Map<String, dynamic>?>> _byUid = {};

  static String _docUid(String uid) => firestoreUserDocIdForAppShell(uid);

  static Map<String, dynamic>? peek(String uid, String settingsDocId) {
    final clean = _docUid(uid);
    if (clean.isEmpty) return null;
    return _byUid[clean]?[settingsDocId];
  }

  static void put(String uid, String settingsDocId, Map<String, dynamic>? data) {
    final clean = _docUid(uid);
    if (clean.isEmpty) return;
    _byUid.putIfAbsent(clean, () => {})[settingsDocId] = data;
  }

  static void invalidate(String uid, [String? settingsDocId]) {
    final clean = _docUid(uid);
    if (clean.isEmpty) return;
    if (settingsDocId == null) {
      _byUid.remove(clean);
    } else {
      _byUid[clean]?.remove(settingsDocId);
    }
  }

  /// Pré-carrega planning, backup e produtividade em paralelo (cache Firestore).
  static Future<void> prefetch(String uid) async {
    final clean = _docUid(uid);
    if (clean.isEmpty) return;
    try {
      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(clean)
          .collection('settings');
      const opts = GetOptions(source: Source.serverAndCache);
      final snaps = await Future.wait([
        col.doc('planning').get(opts),
        col.doc('backup').get(opts),
        col.doc('produtividade').get(opts),
      ]);
      final bucket = <String, Map<String, dynamic>?>{};
      bucket['planning'] = snaps[0].data();
      bucket['backup'] = snaps[1].data();
      bucket['produtividade'] = snaps[2].data();
      _byUid[clean] = {...?_byUid[clean], ...bucket};
    } catch (e, st) {
      debugPrint('UserSettingsDocsCache.prefetch: $e\n$st');
    }
  }

  static Future<Map<String, dynamic>?> ensure(
    String uid,
    String settingsDocId,
  ) async {
    final cached = peek(uid, settingsDocId);
    if (cached != null) return cached;
    final clean = _docUid(uid);
    if (clean.isEmpty) return null;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(clean)
          .collection('settings')
          .doc(settingsDocId)
          .get(const GetOptions(source: Source.serverAndCache));
      final data = snap.data();
      put(uid, settingsDocId, data);
      return data;
    } catch (_) {
      return null;
    }
  }
}
