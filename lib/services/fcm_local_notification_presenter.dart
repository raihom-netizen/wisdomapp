import 'dart:convert';



import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:flutter/foundation.dart'

    show defaultTargetPlatform, kIsWeb, TargetPlatform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';



import 'notification_android_style.dart';

import 'notification_message_builder.dart';

import 'notification_module_theme.dart';



/// Exibe push FCM na bandeja do sistema (foreground / background data-only).

/// Canais alinhados ao servidor ([functions/index.js] `androidChannelForAgendaKind`).

class FcmLocalNotificationPresenter {

  FcmLocalNotificationPresenter._();



  static final FlutterLocalNotificationsPlugin _plugin =

      FlutterLocalNotificationsPlugin();

  static bool _ready = false;



  static bool get _isNativeMobile {

    if (kIsWeb) return false;

    return defaultTargetPlatform == TargetPlatform.android ||

        defaultTargetPlatform == TargetPlatform.iOS;

  }



  static Future<void> ensureReady() async {

    if (_ready || !_isNativeMobile) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');

    const ios = DarwinInitializationSettings(

      requestAlertPermission: false,

      requestBadgePermission: false,

      requestSoundPermission: false,

    );

    await _plugin.initialize(settings: const InitializationSettings(

      android: android,

      iOS: ios,

    ));

    if (defaultTargetPlatform == TargetPlatform.android) {

      final androidImpl = _plugin.resolvePlatformSpecificImplementation<

          AndroidFlutterLocalNotificationsPlugin>();

      if (androidImpl != null) {

        await NotificationAndroidStyle.ensureAndroidChannels(androidImpl);

      }

    }

    _ready = true;

  }



  /// Mostra alerta nativo a partir de [RemoteMessage] (data e/ou notification).

  static Future<void> showRemoteMessage(RemoteMessage message) async {

    if (!_isNativeMobile) return;

    await ensureReady();



    final d = message.data;

    final channelKind =

        NotificationModuleTheme.normalizeKind((d['channelKind'] ?? 'escala').toString());

    final theme = NotificationModuleTheme.forKind(channelKind);

    final title = (message.notification?.title ?? d['title'] ?? kNotificationBrandApp)

        .toString()

        .trim();

    final body =

        (message.notification?.body ?? d['body'] ?? d['subtitle'] ?? '')

            .toString()

            .trim();

    if (title.isEmpty && body.isEmpty) return;



    final subtitle = (d['subtitle'] ?? '').toString().trim();

    if (subtitle.isEmpty && channelKind.isNotEmpty) {

      // Paridade com servidor: «Audiência · Em 15 minutos».

    }



    final payloadMap = <String, dynamic>{

      ...d.map((k, v) => MapEntry(k, v.toString())),

      'click_action': 'FLUTTER_NOTIFICATION_CLICK',

      'channelKind': channelKind,

    };

    final link = (d['url'] ?? d['link'] ?? '').toString().trim();

    if (link.isNotEmpty) payloadMap['url'] = link;



    final displayTitle = title.isEmpty ? kNotificationBrandApp : title;

    final displayBody = body.isEmpty ? subtitle : body;

    final iosSubtitle = subtitle.isNotEmpty

        ? subtitle

        : NotificationMessageBuilder.pushSubtitle(null, channelKind);



    final id = DateTime.now().millisecondsSinceEpoch.remainder(0x7FFFFFFF);

    final androidDetails = defaultTargetPlatform == TargetPlatform.android

        ? await NotificationAndroidStyle.buildDetails(

            channelKind: channelKind,

            title: displayTitle,

            body: displayBody,

            subtitle: iosSubtitle,

          )

        : null;



    await _plugin.show(

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

        ),

      ),

      payload: jsonEncode(payloadMap),

    );

  }

}


