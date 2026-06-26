import 'package:flutter/material.dart';

import '../services/in_app_floating_message_service.dart';
import '../services/version_check_service.dart';
import 'floating_in_app_message_strip.dart';
import 'floating_version_update_strip.dart';

/// Faixas flutuantes no rodapé do shell: mensagem in-app (resumo / promo) + aviso de nova versão.
class FloatingShellBanners extends StatelessWidget {
  const FloatingShellBanners({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<InAppFloatingPayload?>(
      valueListenable: InAppFloatingMessageService.notifier,
      builder: (context, msg, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: VersionCheckService.forceUpdateNotifier,
          builder: (context, _, __) {
            final payload = msg;
            final hasMsg = payload != null;
            final hasVersion = VersionCheckService.pendingUpdateVersion != null;
            if (!hasMsg && !hasVersion) return const SizedBox.shrink();
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (payload != null) InAppFloatingBannerCard(payload: payload),
                if (hasMsg && hasVersion) const SizedBox(height: 8),
                if (hasVersion) const FloatingVersionUpdateStrip(),
              ],
            );
          },
        );
      },
    );
  }
}
