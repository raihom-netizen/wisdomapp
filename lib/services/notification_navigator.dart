import 'package:flutter/material.dart';

import '../screens/notification_center_screen.dart';

/// Serviço leve de navegação para abrir a Central de Notificações a partir
/// de toques em push (FCM) ou notificações locais — Android e iOS.
///
/// Registre o [navigatorKey] no MaterialApp e chame [openNotificationCenter]
/// quando o usuário tocar na notificação (app em background ou encerrado).
abstract final class NotificationNavigator {
  NotificationNavigator._();

  /// GlobalKey do Navigator raiz — definido no MaterialApp (main.dart).
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// Abre a Central de Notificações (push após frame para evitar conflito
  /// com build em andamento quando o app volta do background/terminated).
  static void openNotificationCenter({
    NotificationCenterTab? initialTab,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = navigatorKey.currentContext;
      if (ctx == null) return;
      Navigator.of(ctx).push(
        MaterialPageRoute<void>(
          builder: (_) => NotificationCenterScreen(
            initialTab: initialTab,
          ),
        ),
      );
    });
  }

  /// Extrai a aba alvo a partir do `channelKind` no payload FCM/local.
  static NotificationCenterTab? tabFromChannelKind(String? kind) {
    switch ((kind ?? '').toLowerCase().trim()) {
      case 'escala':
      case 'folga':
        return NotificationCenterTab.escalas;
      case 'compromisso':
        return NotificationCenterTab.compromissos;
      case 'audiencia':
        return NotificationCenterTab.compromissos;
      case 'financeiro':
        return NotificationCenterTab.contas;
      default:
        return null;
    }
  }
}
