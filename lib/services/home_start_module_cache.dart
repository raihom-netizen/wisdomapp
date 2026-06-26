import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/home_start_module_picker.dart';

/// Índice da tela inicial preferida — abre direto no módulo escolhido, sem flash em «Início».
class HomeStartModuleCache {
  HomeStartModuleCache._();

  static const _kUid = 'home_start_mod_uid_v1';
  static const _kIdx = 'home_start_mod_idx_v1';

  static int? _memory;
  static String? _memoryUid;

  static Future<void> warmUp() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = (prefs.getString(_kUid) ?? '').trim();
    if (uid.isEmpty) {
      _memory = null;
      _memoryUid = null;
      return;
    }
    final idx = prefs.getInt(_kIdx);
    if (idx == null) {
      _memory = null;
      _memoryUid = null;
      return;
    }
    final normalized = normalizeHomeStartModuleIndex(idx);
    if (!kHomeDefaultStartModuleLabels.containsKey(normalized)) {
      _memory = null;
      _memoryUid = null;
      return;
    }
    _memoryUid = uid;
    _memory = normalized;
  }

  static int? getSync(String uid) {
    final clean = uid.trim();
    if (clean.isEmpty || _memoryUid != clean) return null;
    return _memory;
  }

  static Future<void> save(String uid, int moduleIndex) async {
    final clean = uid.trim();
    final normalized = normalizeHomeStartModuleIndex(moduleIndex);
    if (clean.isEmpty || !kHomeDefaultStartModuleLabels.containsKey(normalized)) {
      return;
    }
    _memoryUid = clean;
    _memory = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUid, clean);
    await prefs.setInt(_kIdx, normalized);
  }

  static Future<void> clear() async {
    _memory = null;
    _memoryUid = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUid);
    await prefs.remove(_kIdx);
  }

  static Future<void> prefetch(String uid) async {
    final clean = uid.trim();
    if (clean.isEmpty) return;
    try {
      final snap = await homePlanningRef(clean).get(
        const GetOptions(source: Source.serverAndCache),
      );
      final raw = snap.data()?[kHomeDefaultStartModuleField];
      final preferred = normalizeHomeStartModuleIndex(
        raw is num ? raw.toInt() : 1,
      );
      if (!kHomeDefaultStartModuleLabels.containsKey(preferred)) return;
      await save(clean, preferred);
    } catch (e, st) {
      debugPrint('HomeStartModuleCache.prefetch: $e\n$st');
    }
  }
}
