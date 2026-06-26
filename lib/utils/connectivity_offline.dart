import 'package:connectivity_plus/connectivity_plus.dart';

/// True quando não há Wi‑Fi nem dados móveis (lista vazia trata-se como sem rede).
bool isConnectivityOffline(List<ConnectivityResult> results) {
  if (results.isEmpty) return true;
  return results.every((r) => r == ConnectivityResult.none);
}
