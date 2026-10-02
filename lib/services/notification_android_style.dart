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
    List<AndroidNotificationAction>? actions,
    bool despertador = false,
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
      importance: despertador ? Importance.max : importance,
      priority: despertador ? Priority.max : priority,
      // Despertador: FLAG_INSISTENT (4) — o som (ou a vibração, no «só
      // vibrar») repete até a notificação sair da bandeja: «Encerrar» /
      // «Adiar» (cancelNotification) ou toque no corpo. `ongoing` impede que
      // um deslize sem querer cale o alarme. Áudio de alarme no Android < 8
      // (do 8 em diante vale o do canal `ct_desp1_*`).
      additionalFlags: despertador ? Int32List.fromList(const [4]) : null,
      ongoing: despertador,
      audioAttributesUsage: despertador
          ? AudioAttributesUsage.alarm
          : AudioAttributesUsage.notification,
      playSound: playSound,
      enableVibration: enableVibration,
      color: Color(theme.colorArgb),
      icon: '@mipmap/ic_launcher',
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      subText: '$moduleSubtitle · $kNotificationBrandApp',
      ticker: title,
      visibility: NotificationVisibility.public,
      // Despertador (soneca): categoria de alarme fura o «não perturbe» dos
      // aparelhos que respeitam e os botões Adiar/Encerrar ficam visíveis.
      category: despertador
          ? AndroidNotificationCategory.alarm
          : AndroidNotificationCategory.reminder,
      actions: actions,
      groupKey: theme.threadId,
      styleInformation: await buildStyle(
        theme: theme,
        title: title,
        body: body,
        summary: moduleSubtitle,
      ),
    );
  }

  /// Cria/atualiza os canais de notificação do Android.
  ///
  /// Todos os canais em importância máxima (padrão do Controle Total):
  /// aviso com hora marcada tem que abrir sobre a tela, não só na gaveta.
  static Future<void> ensureAndroidChannels(
    AndroidFlutterLocalNotificationsPlugin androidImpl, {
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
          importance: Importance.max,
          playSound: playSound,
          enableVibration: enableVibration,
          showBadge: true,
          ledColor: Color(theme.colorArgb),
        ),
      );
    }
  }
}
