import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/pending_storage_upload_service.dart';
import '../services/scale_rates_service.dart';
import 'global_web_offline_stub.dart'
    if (dart.library.html) 'global_web_offline_web.dart' as impl;

/// Faixa discreta no topo (web + mobile) com mensagem positiva off→on:
/// - **Offline**: "Modo offline — você pode lançar normalmente; sincronizamos sozinho quando a internet voltar."
/// - **Reconectando**: "Sincronizando alterações…" enquanto o Firestore esvazia a fila local.
/// - **Sincronizado**: "Sincronizado" por 2 segundos e some.
///
/// Funciona em web (via `navigator.onLine`) e em APK/iOS (via `connectivity_plus`).
/// Sempre que o usuário voltar a ter rede, força `enableNetwork()` e
/// `waitForPendingWrites()` para esvaziar a fila local do Firestore. UX off→on
/// pioneira: o usuário usa o sistema normalmente offline, sem perceber.
class GlobalWebOfflineBanner extends StatefulWidget {
  final Widget child;

  const GlobalWebOfflineBanner({super.key, required this.child});

  @override
  State<GlobalWebOfflineBanner> createState() => _GlobalWebOfflineBannerState();
}

enum _SyncState { online, offline, syncing, justSynced }

class _GlobalWebOfflineBannerState extends State<GlobalWebOfflineBanner> {
  _SyncState _state = _SyncState.online;
  VoidCallback? _onOnline;
  VoidCallback? _onOffline;
  Timer? _hideTimer;
  StreamSubscription<List<ConnectivityResult>>? _mobileConnSub;

  static bool _connectivityIsOffline(List<ConnectivityResult> result) {
    if (result.isEmpty) return true;
    return result.every((r) => r == ConnectivityResult.none);
  }

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _state = impl.isOnline() ? _SyncState.online : _SyncState.offline;
      _onOnline = _handleOnline;
      _onOffline = _handleOffline;
      impl.addOnlineListener(_onOnline!);
      impl.addOfflineListener(_onOffline!);
      return;
    }
    Future<void> bootstrap() async {
      try {
        final r = await Connectivity().checkConnectivity();
        if (!mounted) return;
        setState(() => _state = _connectivityIsOffline(r) ? _SyncState.offline : _SyncState.online);
      } catch (_) {}
    }

    bootstrap();
    _mobileConnSub = Connectivity().onConnectivityChanged.listen((results) {
      if (!mounted) return;
      final offline = _connectivityIsOffline(results);
      if (offline) {
        _handleOffline();
      } else if (_state == _SyncState.offline) {
        _handleOnline();
      }
    });
  }

  Future<void> _handleOnline() async {
    if (!mounted) return;
    setState(() => _state = _SyncState.syncing);
    try {
      await FirebaseFirestore.instance.enableNetwork();
    } catch (_) {}
    try {
      await FirebaseFirestore.instance.waitForPendingWrites();
    } catch (_) {}
    unawaited(PendingStorageUploadService.drainAll().catchError((_) {}));
    ScaleRatesService().invalidateMemory(null, false);
    if (!mounted) return;
    setState(() => _state = _SyncState.justSynced);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _state = _SyncState.online);
    });
  }

  void _handleOffline() {
    if (!mounted) return;
    _hideTimer?.cancel();
    setState(() => _state = _SyncState.offline);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _mobileConnSub?.cancel();
    if (kIsWeb && _onOnline != null && _onOffline != null) {
      impl.removeOnlineListener(_onOnline!);
      impl.removeOfflineListener(_onOffline!);
    }
    super.dispose();
  }

  ({Color color, IconData icon, String text})? _bannerContent() {
    switch (_state) {
      case _SyncState.offline:
        return (
          color: const Color(0xFFEA8B14),
          icon: Icons.cloud_off_rounded,
          text: 'Modo offline — você pode lançar normalmente. Sincronizamos sozinho quando voltar a internet.',
        );
      case _SyncState.syncing:
        return (
          color: const Color(0xFF1A237E),
          icon: Icons.cloud_sync_rounded,
          text: 'Sincronizando alterações…',
        );
      case _SyncState.justSynced:
        return (
          color: const Color(0xFF0D9488),
          icon: Icons.cloud_done_rounded,
          text: 'Sincronizado',
        );
      case _SyncState.online:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = _bannerContent();
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (content != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Material(
              color: content.color,
              elevation: 4,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Icon(content.icon, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          content.text,
                          style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.25, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
