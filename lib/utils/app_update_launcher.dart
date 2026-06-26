import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

import '../services/version_check_service.dart';
import 'pwa_install_helper.dart';
import 'url_launcher_helper.dart';

/// Google Play / APK: web fora do Safari iPhone e app Android nativo.
bool get showAndroidStoreUi {
  if (kIsWeb) return !isPwaIos;
  return defaultTargetPlatform == TargetPlatform.android;
}

/// TestFlight / iPhone: app iOS, PWA Safari iPhone ou web desktop; nunca no Android nativo.
bool get showIosStoreUi {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return false;
  }
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) return true;
  return true;
}

/// Abre atualização (web = recarga; Android = Play; iOS = TestFlight) e limpa o aviso pendente.
Future<void> launchControleTotalAppUpdate(BuildContext context) async {
  if (kIsWeb) {
    VersionCheckService.reloadWebPageNow();
    return;
  }
  final isIos = defaultTargetPlatform == TargetPlatform.iOS;
  try {
    if (isIos) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Abrindo TestFlight…')),
        );
      }
      await openUrlPreferChrome(VersionCheckService.effectiveTestFlightUrl);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Abrindo Play Store…')),
        );
      }
      final raw = VersionCheckService.apkDownloadUrl?.trim();
      var url = VersionCheckService.playStoreAppUrl;
      if (raw != null &&
          raw.isNotEmpty &&
          (raw.startsWith('http://') || raw.startsWith('https://'))) {
        if (raw.toLowerCase().contains('play.google.com')) url = raw;
      }
      await openUrlPreferChrome(url);
    }
    if (context.mounted) {
      VersionCheckService.clearPendingUpdate();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isIos
                ? 'No TestFlight, toque em Atualizar para a nova build.'
                : 'Na Play Store, toque em Atualizar.',
          ),
        ),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o link.')),
      );
    }
  }
}
