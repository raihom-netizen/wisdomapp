import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

import '../firebase_options.dart';
import 'fcm_local_notification_presenter.dart';

/// Handler FCM com app em background ou fechado.
/// Mensagens com `notification` no payload: o SO exibe (Android/iOS).
/// Mensagens só-`data`: exibimos via [FcmLocalNotificationPresenter].
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  if (kIsWeb) return;

  final hasSystemNotification = message.notification != null;
  final isAndroid =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  // Android já mostra notification+data quando o app está morto/em background.
  if (hasSystemNotification && isAndroid) return;

  try {
    await FcmLocalNotificationPresenter.showRemoteMessage(message);
  } catch (_) {}
}
