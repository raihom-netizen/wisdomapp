import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Ponte nativa leve: persist + redraw (iOS App Group) ou só redraw (Android).
class WidgetNativePlatformSync {
  WidgetNativePlatformSync._();

  static const _channel = MethodChannel('controletotal/widget_sync');
  static const String jsonKey = 'widget_events_json';

  /// Após [HomeWidget.saveWidgetData]: persist nativo com commit + redraw (iOS e Android).
  static Future<void> afterWidgetJsonSaved(String jsonStr) async {
    if (kIsWeb || jsonStr.isEmpty) return;
    if (Platform.isIOS || Platform.isAndroid) {
      await persistAndRedraw(jsonStr);
    }
  }

  /// Grava JSON com commit nativo + redesenha widget (iOS App Group / Android prefs).
  static Future<void> persistAndRedraw(String jsonStr) async {
    if (kIsWeb || jsonStr.isEmpty) return;
    if (!Platform.isIOS && !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('persistWidgetJson', <String, dynamic>{
        'key': jsonKey,
        'json': jsonStr,
      });
    } catch (_) {
      await forceWidgetRedraw();
    }
  }

  /// Redesenha todos os widgets (Android: 3 tamanhos + notify lista).
  static Future<void> forceWidgetRedraw() async {
    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('forceWidgetRedraw');
    } catch (_) {}
  }
}
