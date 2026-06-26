import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../constants/app_version.dart';
import 'version_check_web_stub.dart'
    if (dart.library.html) 'version_check_web_impl.dart' as reload_impl;

/// Checagem de versão no start: só avisa usuários quando o admin grava
/// `forceUpdate: true` em Firestore (`app_config/version`) pelo painel Admin.
/// Deploy web publica `version.json` mas **não** dispara aviso sozinho.
/// Mobile: marca [pendingUpdateVersion] para banner/diálogo ou tela bloqueante.
class VersionCheckService {
  VersionCheckService._();

  static const _collection = 'app_config';
  static const _docId = 'version';
  static const _field = 'version';

  /// No mobile, quando há versão nova no servidor, fica aqui para a UI mostrar aviso.
  static String? pendingUpdateVersion;

  /// Link de atualização no Android (Play Store). Campo legado no Firestore: `apkDownloadUrl`.
  static String? apkDownloadUrl;

  /// Google Play — app oficial (banner "Nova versão" no painel).
  static const String playStoreAppUrl =
      'https://play.google.com/store/apps/details?id=com.wisdomapp.app';

  /// Link público TestFlight (beta iOS). Firestore `testFlightUrl`.
  static String? testFlightUrl;

  static const String defaultTestFlightPublicUrl =
      'https://testflight.apple.com/join/pugVHQ6C';

  static const String testFlightJoinUrl = defaultTestFlightPublicUrl;

  static String get effectiveTestFlightUrl {
    final t = testFlightUrl?.trim();
    if (t != null && t.isNotEmpty && (t.startsWith('http://') || t.startsWith('https://'))) {
      return t;
    }
    return defaultTestFlightPublicUrl;
  }

  /// Quando true, o app bloqueia e exibe tela de atualização obrigatória.
  /// Só fica true se o admin gravou `forceUpdate: true` no Firestore.
  static bool forceUpdateRequired = false;

  static final ValueNotifier<bool> forceUpdateNotifier = ValueNotifier<bool>(false);

  static void clearPendingUpdate() {
    pendingUpdateVersion = null;
    apkDownloadUrl = null;
    forceUpdateNotifier.value = !forceUpdateNotifier.value;
  }

  static String _resolveAndroidUpdateUrl(String? serverUrl) {
    final hasValidServerUrl = serverUrl != null &&
        serverUrl.isNotEmpty &&
        (serverUrl.startsWith('http://') || serverUrl.startsWith('https://'));
    if (hasValidServerUrl) {
      final lower = serverUrl.toLowerCase();
      if (lower.contains('play.google.com')) return serverUrl;
    }
    return playStoreAppUrl;
  }

  static void _onNewVersionFound(String serverVersion, {required bool forceBlock}) {
    pendingUpdateVersion = serverVersion;
    forceUpdateRequired = forceBlock;
    forceUpdateNotifier.value = true;
  }

  static int? _parsePositiveInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v >= 0 ? v : null;
    return int.tryParse(v.toString().trim());
  }

  static bool _serverIsNewer({required int? serverBuild, required String? serverVersion}) {
    if (serverBuild != null && serverBuild > AppVersion.buildNumber) return true;
    if (serverVersion != null &&
        serverVersion.isNotEmpty &&
        AppVersion.isNewer(serverVersion, AppVersion.current)) {
      return true;
    }
    return false;
  }

  static bool _isAdminForcedUpdate(dynamic forceVal) => forceVal == true;

  static void reloadWebPageNow({bool force = true}) {
    if (!kIsWeb || pendingUpdateVersion == null) return;
    reload_impl.reloadPage(pendingUpdateVersion, force);
  }

  static void forceWebReload() {
    if (kIsWeb) reload_impl.reloadPage(null, true);
  }

  /// Firestore com `forceUpdate: true` + versão/build mais novos que o cliente.
  static Future<void> checkAndReloadIfNeeded() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection(_collection)
          .doc(_docId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 2));
      final data = snap.data();
      if (data == null) return;

      final forceVal = data['forceUpdate'];
      if (!_isAdminForcedUpdate(forceVal)) return;

      final serverVersion = data[_field]?.toString().trim();
      final serverBuild = _parsePositiveInt(data['buildNumber']);
      if (!_serverIsNewer(serverBuild: serverBuild, serverVersion: serverVersion)) {
        return;
      }

      final tf = data['testFlightUrl']?.toString().trim();
      if (tf != null && tf.isNotEmpty && (tf.startsWith('http://') || tf.startsWith('https://'))) {
        testFlightUrl = tf;
      } else {
        testFlightUrl = null;
      }

      final url = data['apkDownloadUrl']?.toString().trim();
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        apkDownloadUrl = _resolveAndroidUpdateUrl(url);
      } else {
        final hasValidUrl = url != null &&
            url.isNotEmpty &&
            (url.startsWith('http://') || url.startsWith('https://'));
        apkDownloadUrl = hasValidUrl ? url : null;
      }

      final label =
          serverVersion != null && serverVersion.isNotEmpty ? serverVersion : AppVersion.current;
      _onNewVersionFound(label, forceBlock: true);
    } catch (_) {}
  }

  static void startWatchingForUpdates() {
    reload_impl.registerUpdateChecker(() {
      checkAndReloadIfNeeded();
    });
  }
}
