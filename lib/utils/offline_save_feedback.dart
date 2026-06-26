import 'package:connectivity_plus/connectivity_plus.dart';

import 'connectivity_offline.dart';

/// Mensagem padrão quando o Firestore grava na fila local (mobile).
class OfflineSaveFeedback {
  OfflineSaveFeedback._();

  static const String offlineSuffix =
      ' Guardado no aparelho; sincroniza quando houver internet.';

  static Future<bool> isDeviceOffline() async {
    try {
      return isConnectivityOffline(await Connectivity().checkConnectivity());
    } catch (_) {
      return false;
    }
  }

  static Future<String> appendOfflineHintIfNeeded(String baseMessage) async {
    if (await isDeviceOffline()) {
      return '$baseMessage$offlineSuffix';
    }
    return baseMessage;
  }
}
