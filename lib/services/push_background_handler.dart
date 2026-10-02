import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

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

  // Android e iOS já mostram sozinhos o push com `notification` quando o app
  // está fechado/em segundo plano — desenhar de novo aqui dava aviso em dobro
  // (no iPhone acontecia quando o push vinha com content-available).
  // Só push de dados (despertador/soneca) é desenhado pelo app.
  if (hasSystemNotification) return;

  try {
    await FcmLocalNotificationPresenter.showRemoteMessage(message);
  } catch (_) {}
}
