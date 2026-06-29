import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/admin_user_search.dart';
import '../utils/firestore_user_doc_id.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_version.dart';

/// Grava no Firestore metadados leves do cliente (versão, plataforma, último ping) para o painel admin.
/// Throttle local para não escrever a cada rebuild.
class UserClientTelemetryService {
  UserClientTelemetryService._();

  static const _prefsKeyPrefix = 'client_telemetry_last_';
  static const _minInterval = Duration(minutes: 25);

  /// Valor gravado em Firestore: [clientTelemetry.platform]. Texto amigável para o painel admin.
  static String platformDisplayPt(dynamic raw) {
    final s = (raw ?? '').toString().trim().toLowerCase();
    switch (s) {
      case 'web':
        return 'Web (navegador)';
      case 'android':
        return 'Android';
      case 'ios':
        return 'iPhone (iOS)';
      case 'windows':
        return 'Windows';
      case 'macos':
        return 'macOS';
      case 'linux':
        return 'Linux';
      case '':
        return '— (sem telemetria)';
      default:
        return s;
    }
  }

  static IconData platformIcon(dynamic raw) {
    final s = (raw ?? '').toString().trim().toLowerCase();
    switch (s) {
      case 'web':
        return Icons.language_rounded;
      case 'android':
        return Icons.android_rounded;
      case 'ios':
        return Icons.phone_iphone_rounded;
      case 'windows':
        return Icons.laptop_windows_rounded;
      case 'macos':
        return Icons.laptop_mac_rounded;
      case 'linux':
        return Icons.terminal_rounded;
      default:
        return Icons.devices_rounded;
    }
  }

  static String _platformLabel() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.linux:
        return 'linux';
      default:
        return 'unknown';
    }
  }

  static Future<void> pingIfDue(String uid) async {
    if (uid.isEmpty) return;
    final id = firestoreUserDocIdForAppShell(uid);
    if (id.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_prefsKeyPrefix$id';
      final last = prefs.getInt(key) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - last < _minInterval.inMilliseconds) return;

      final ref = FirebaseFirestore.instance.collection('users').doc(id);
      final snap = await ref.get(const GetOptions(source: Source.serverAndCache));
      if (!snap.exists) return;
      if (!adminUserHasCompleteEmail(snap.data() ?? const {})) return;

      await prefs.setInt(key, now);

      await ref.set(
        {
          'clientTelemetry': {
            'appVersion': AppVersion.current,
            'buildNumber': AppVersion.buildNumber,
            'platform': _platformLabel(),
            'lastPingAt': FieldValue.serverTimestamp(),
          },
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {}
  }
}
