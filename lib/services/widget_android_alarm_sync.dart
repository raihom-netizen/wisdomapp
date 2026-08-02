import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// AlarmManager Android — 00:00 e 12:00 com app fechado (redesenho + flag para sync Firestore).
class WidgetAndroidAlarmSync {
  WidgetAndroidAlarmSync._();

  static const _channel = MethodChannel('controletotal/widget_sync');

  static Future<void> scheduleAlarmsIfNeeded() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('scheduleAlarms');
    } catch (_) {}
  }

  /// Redesenha widget quando plantão expira (fim + 2h) com app fechado.
  static Future<void> scheduleExpiryAlarm(int expiryMs) async {
    if (kIsWeb || !Platform.isAndroid || expiryMs <= 0) return;
    try {
      await _channel.invokeMethod<void>('scheduleExpiryAlarm', expiryMs);
    } catch (_) {}
  }

  /// True se o alarme nativo disparou e ainda não foi consumido pelo Flutter.
  static Future<bool> consumeNativeSyncDue() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final due = await _channel.invokeMethod<bool>('consumeSyncDue');
      return due == true;
    } catch (_) {
      return false;
    }
  }
}
