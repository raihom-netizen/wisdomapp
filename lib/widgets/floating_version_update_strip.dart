import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

import '../services/version_check_service.dart';
import '../theme/app_colors.dart';
import '../utils/app_update_launcher.dart';

/// Faixa flutuante compacta: aviso de nova versão com link (Play Store / TestFlight / recarga web).
/// Só aparece quando o admin grava `forceUpdate: true` no servidor.
class FloatingVersionUpdateStrip extends StatelessWidget {
  const FloatingVersionUpdateStrip({super.key});

  String _subtitle(String? serverVersion) {
    final v = serverVersion?.trim();
    final label = (v != null && v.isNotEmpty) ? v : 'nova';
    if (kIsWeb) return 'Versão $label no servidor · toque para recarregar';
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return 'Versão $label · toque para abrir o TestFlight';
    }
    return 'Versão $label · toque para abrir a Play Store';
  }

  String _actionLabel() {
    if (kIsWeb) return 'Atualizar';
    if (defaultTargetPlatform == TargetPlatform.iOS) return 'TestFlight';
    return 'Play Store';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: VersionCheckService.forceUpdateNotifier,
      builder: (context, _, __) {
        final serverVersion = VersionCheckService.pendingUpdateVersion;
        if (serverVersion == null) {
          return const SizedBox.shrink();
        }
        final bottomInset = MediaQuery.paddingOf(context).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset > 0 ? 2 : 0),
          child: Material(
            elevation: 12,
            shadowColor: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: () => launchControleTotalAppUpdate(context),
              borderRadius: BorderRadius.circular(16),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    colors: [
                      AppColors.deepBlueDark,
                      AppColors.deepBlue,
                      AppColors.accent.withValues(alpha: 0.95),
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        kIsWeb ? Icons.auto_awesome_rounded : Icons.system_update_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Nova versão disponível',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                                letterSpacing: 0.2,
                              ),
                            ),
                            Text(
                              _subtitle(serverVersion),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.88),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: VersionCheckService.clearPendingUpdate,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Ver depois', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                      ),
                      const SizedBox(width: 4),
                      FilledButton.tonal(
                        onPressed: () => launchControleTotalAppUpdate(context),
                        style: FilledButton.styleFrom(
                          foregroundColor: AppColors.deepBlueDark,
                          backgroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          _actionLabel(),
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
