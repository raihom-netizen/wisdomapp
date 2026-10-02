import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'local_notifications_plugin_holder.dart';
import 'notification_android_style.dart';
import 'notification_message_builder.dart';
import 'notification_module_theme.dart';
import 'notification_soneca_service.dart';

/// Exibe push FCM na bandeja do sistema (foreground / background data-only).
/// Canais alinhados ao servidor ([functions/index.js] `androidChannelForAgendaKind`).
///
/// Despertador (soneca): o servidor manda o aviso como data-only no Android e
/// o app desenha a notificação com «Adiar 3 min», «Adiar 5 min» e «Encerrar»,
/// no canal de alarme do toque escolhido e insistente (só cala no botão).
class FcmLocalNotificationPresenter {
  FcmLocalNotificationPresenter._();

  static bool get _isNativeMobile {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  static bool _canaisProntos = false;

  static Future<void> ensureReady() async {
    if (!_isNativeMobile) return;
    if (!localNotificationsPluginReady) {
      // Fallback mínimo (ex.: isolate de segundo plano) — o app principal
      // inicializa pelo ScaleNotificationsService (com a navegação do toque).
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await localNotificationsPlugin.initialize(
        settings: const InitializationSettings(
          android: android,
          iOS: ios,
        ),
        onDidReceiveNotificationResponse: (resp) =>
            unawaited(NotificationSonecaService.tratarResposta(resp)),
        onDidReceiveBackgroundNotificationResponse:
            notificacaoSonecaEmSegundoPlano,
      );
      localNotificationsPluginReady = true;
    }
    if (_canaisProntos) return;
    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidImpl =
          localNotificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        await NotificationAndroidStyle.ensureAndroidChannels(androidImpl);
        await NotificationSonecaService.garantirCanaisDeSom(androidImpl);
      }
    }
    _canaisProntos = true;
  }

  /// Mostra alerta nativo a partir de [RemoteMessage] (data e/ou notification).
  static Future<void> showRemoteMessage(RemoteMessage message) async {
    if (!_isNativeMobile) return;
    await ensureReady();

    final d = message.data;
    final channelKind = NotificationModuleTheme.normalizeKind(
        (d['channelKind'] ?? 'escala').toString());
    final theme = NotificationModuleTheme.forKind(channelKind);
    final title =
        (message.notification?.title ?? d['title'] ?? kNotificationBrandApp)
            .toString()
            .trim();
    final body =
        (message.notification?.body ?? d['body'] ?? d['subtitle'] ?? '')
            .toString()
            .trim();
    if (title.isEmpty && body.isEmpty) return;

    final subtitle = (d['subtitle'] ?? '').toString().trim();

    final payloadMap = <String, dynamic>{
      ...d.map((k, v) => MapEntry(k, v.toString())),
      'click_action': 'FLUTTER_NOTIFICATION_CLICK',
      'channelKind': channelKind,
    };
    final link = (d['url'] ?? d['link'] ?? '').toString().trim();
    if (link.isNotEmpty) payloadMap['url'] = link;

    // Despertador: botões Adiar/Encerrar + toque escolhido (canal nativo).
    final soneca = NotificationSonecaService.temSoneca(d);
    if (soneca) {
      payloadMap.addAll(NotificationSonecaService.camposDoPayload(d));
    }
    final canalBase = NotificationSonecaService.canalPara(
      modoAviso: (d['modoAviso'] ?? '').toString(),
      soundId: (d['soundId'] ?? '').toString().trim(),
      canalAndroid: (d['canalAndroid'] ?? '').toString(),
    );
    // Despertador: o toque sai pelo canal de ALARME (volume de alarme) e a
    // notificação é insistente — repete até Encerrar/Adiar.
    final canal = soneca && defaultTargetPlatform == TargetPlatform.android
        ? await NotificationSonecaService.canalDoDespertador(canalBase)
        : canalBase;

    final displayTitle = title.isEmpty ? kNotificationBrandApp : title;
    final displayBody = body.isEmpty ? subtitle : body;
    final iosSubtitle = subtitle.isNotEmpty
        ? subtitle
        : NotificationMessageBuilder.pushSubtitle(null, channelKind);

    // Repetição do despertador SUBSTITUI a anterior na bandeja (mesmo id).
    final avisoId = (d['sonecaAvisoId'] ?? '').toString();
    final id = soneca && avisoId.isNotEmpty
        ? NotificationSonecaService.idDaNotificacao(avisoId)
        : DateTime.now().millisecondsSinceEpoch.remainder(0x7FFFFFFF);

    final androidDetails = defaultTargetPlatform == TargetPlatform.android
        ? await NotificationAndroidStyle.buildDetails(
            channelKind: channelKind,
            title: displayTitle,
            body: displayBody,
            subtitle: iosSubtitle,
            channelIdOverride: canal?.id,
            channelNameOverride: canal?.nome,
            actions: soneca ? NotificationSonecaService.acoesAndroid : null,
            despertador: soneca,
          )
        : null;

    await localNotificationsPlugin.show(
      id: id,
      title: displayTitle,
      body: displayBody,
      notificationDetails: NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          subtitle: iosSubtitle,
          threadIdentifier: theme.threadId,
          categoryIdentifier:
              soneca ? NotificationSonecaService.categoriaIos : null,
        ),
      ),
      payload: jsonEncode(payloadMap),
    );
  }
}
