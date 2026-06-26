import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_profile.dart';

/// Perfil do utilizador em disco — reabertura do app sem spinner à espera do Firestore.
class UserProfileStartupCache {
  UserProfileStartupCache._();

  static const _kUid = 'profile_cache_uid_v1';
  static const _kJson = 'profile_cache_json_v1';

  static UserProfile? _memory;
  static String? _memoryUid;

  static Future<void> warmUp() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = (prefs.getString(_kUid) ?? '').trim();
    if (uid.isEmpty) {
      _memory = null;
      _memoryUid = null;
      return;
    }
    final raw = prefs.getString(_kJson);
    if (raw == null || raw.isEmpty) {
      _memory = null;
      _memoryUid = null;
      return;
    }
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _memoryUid = uid;
      _memory = UserProfile.fromStartupCacheMap(uid, map);
    } catch (e, st) {
      debugPrint('UserProfileStartupCache.warmUp: $e\n$st');
      _memory = null;
      _memoryUid = null;
    }
  }

  static UserProfile? getSync(String uid) {
    final clean = uid.trim();
    if (clean.isEmpty || _memoryUid != clean) return null;
    return _memory;
  }

  static Future<void> save(String uid, UserProfile profile) async {
    final clean = uid.trim();
    if (clean.isEmpty) return;
    _memoryUid = clean;
    _memory = profile;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUid, clean);
    await prefs.setString(_kJson, jsonEncode(profile.toStartupCacheMap()));
  }

  static Future<void> clear() async {
    _memory = null;
    _memoryUid = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUid);
    await prefs.remove(_kJson);
  }

  /// Atualiza cache a partir do Firestore (cache local primeiro).
  static Future<void> prefetch(String uid) async {
    final clean = uid.trim();
    if (clean.isEmpty) return;
    try {
      final ref =
          FirebaseFirestore.instance.collection('users').doc(clean);
      DocumentSnapshot<Map<String, dynamic>> snap;
      try {
        snap = await ref.get(const GetOptions(source: Source.cache));
        if (!snap.exists) {
          snap = await ref.get(
            const GetOptions(source: Source.serverAndCache),
          );
        }
      } catch (_) {
        snap = await ref.get(
          const GetOptions(source: Source.serverAndCache),
        );
      }
      final d = snap.data() ?? <String, dynamic>{};
      await save(clean, UserProfile.fromFirestoreMap(clean, d));
    } catch (e, st) {
      debugPrint('UserProfileStartupCache.prefetch: $e\n$st');
    }
  }
}
