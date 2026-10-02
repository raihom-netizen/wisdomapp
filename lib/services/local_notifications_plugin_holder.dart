import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Instância única — Android/iOS exigem um único [FlutterLocalNotificationsPlugin.initialize].
final FlutterLocalNotificationsPlugin localNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

bool localNotificationsPluginReady = false;
