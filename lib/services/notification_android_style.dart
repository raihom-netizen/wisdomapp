import 'dart:typed_data';

import 'package:flutter/material.dart' show Color;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_message_builder.dart';
import 'notification_module_theme.dart';

/// Estilo Android premium compartilhado — cor por módulo, ícone do app e banner rich.
class NotificationAndroidStyle {
  NotificationAndroidStyle._();

  static final Map<String, Uint8List?> _bannerBytesCache = {};

  static Future<Uint8List?> _bannerBytes(String? assetPath) async {
    if (assetPath == null || assetPath.isEmpty) return null;
    final cached = _bannerBytesCache[assetPath];
    if (cached != null) return cached.isEmpty ? null : cached;
    try {
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();
      _bannerBytesCache[assetPath] = bytes;
      return bytes;
    } catch (_) {
      _bannerBytesCache[assetPath] = Uint8List(0);
      return null;
    }
  }

  static Future<StyleInformation?> buildStyle({
    required NotificationModuleTheme theme,
    required String title,
    required String body,
    String? summary,
  }) async {
    final summaryText = (summary ?? theme.label).trim();
    final banner = await _bannerBytes(theme.bannerAsset);
    if (banner != null && banner.isNotEmpty) {
      // A versão atual do plugin não expõe `contentBody` no BigPicture.
      // Prioriza o texto completo no Android expandido; o banner continua no push FCM remoto.
      return BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: summaryText,
        htmlFormatContentTitle: false,
        htmlFormatSummaryText: false,
      );
    }
    return BigTextStyleInformation(
      body,
      contentTitle: title,
      summaryText: summaryText,
      htmlFormatContentTitle: false,
      htmlFormatSummaryText: false,
    );
  }

  static Future<AndroidNotificationDetails> buildDetails({
    required String channelKind,
    required String title,
    required String body,
    String? subtitle,
    Importance importance = Importance.high,
    Priority priority = Priority.high,
    bool playSound = true,
    bool enableVibration = true,
    String? channelIdOverride,
    String? channelNameOverride,
  }) async {
    final theme = NotificationModuleTheme.forKind(channelKind);
    final channelId = channelIdOverride ?? theme.channelId;
    final channelName = channelNameOverride ?? theme.channelName;
    final sub = (subtitle ?? '').trim();
    final moduleSubtitle = sub.isNotEmpty
        ? sub
        : NotificationMessageBuilder.pushSubtitle(null, theme.kind);

    return AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: theme.channelDescription,
      importance: importance,
      priority: priority,
      playSound: playSound,
      enableVibration: enableVibration,
      color: Color(theme.colorArgb),
      icon: '@mipmap/ic_launcher',
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      subText: '$moduleSubtitle · ${kNotificationBrandApp}',
      ticker: title,
      visibility: NotificationVisibility.public,
      category: AndroidNotificationCategory.reminder,
      groupKey: theme.threadId,
      styleInformation: await buildStyle(
        theme: theme,
        title: title,
        body: body,
        summary: moduleSubtitle,
      ),
    );
  }

  static Future<void> ensureAndroidChannels(
    AndroidFlutterLocalNotificationsPlugin androidImpl, {
    Importance importance = Importance.high,
    bool playSound = true,
    bool enableVibration = true,
  }) async {
    for (final kind in NotificationModuleTheme.allKinds) {
      final theme = NotificationModuleTheme.forKind(kind);
      try {
        await androidImpl.deleteNotificationChannel(channelId: theme.channelId);
      } catch (_) {}
      await androidImpl.createNotificationChannel(
        AndroidNotificationChannel(
          theme.channelId,
          theme.channelName,
          description: theme.channelDescription,
          importance: importance,
          playSound: playSound,
          enableVibration: enableVibration,
          showBadge: true,
          ledColor: Color(theme.colorArgb),
        ),
      );
    }
  }
}
