import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;

import '../utils/agenda_delivery_channel_prefs.dart';
import '../utils/agenda_notification_plan.dart';
import '../utils/agenda_reminder_end_of_day.dart';
import '../utils/agenda_reminder_notify_times.dart';
import 'local_notification_preferences.dart';
import 'notification_audio_player.dart';
import 'notification_android_style.dart';
import 'notification_message_builder.dart';
import 'notification_module_theme.dart';
import 'notification_sound_preferences.dart';

/// Categoria do canal Android (controla qual som tocar e qual chave de
/// preferência usar).
enum _Channel { escala, compromisso, audiencia, financeiro, folga }

extension _ChannelMeta on _Channel {
  String get id => switch (this) {
        _Channel.escala => 'controletotal_escala',
        _Channel.compromisso => 'controletotal_compromisso',
        _Channel.audiencia => 'controletotal_audiencia',
        _Channel.financeiro => 'controletotal_financeiro',
        _Channel.folga => 'controletotal_folga',
      };

  String get name => switch (this) {
        _Channel.escala => 'Escalas e Plantões',
        _Channel.compromisso => 'Compromissos',
        _Channel.audiencia => 'Audiências',
        _Channel.financeiro => 'Contas a pagar',
        _Channel.folga => 'Folgas (Produtividade)',
      };

  NotificationSoundCategory get category => switch (this) {
        _Channel.escala => NotificationSoundCategory.escala,
        _Channel.compromisso => NotificationSoundCategory.compromisso,
        _Channel.audiencia => NotificationSoundCategory.audiencia,
        _Channel.financeiro => NotificationSoundCategory.financeiro,
        _Channel.folga => NotificationSoundCategory.escala,
      };
}

/// Implementação mobile (Android/iOS) para lembretes de plantão, compromisso,
/// audiência e contas a pagar.
///
/// Premium: cada categoria tem seu próprio **canal Android** (e payload no
/// callback) — assim o usuário pode silenciar, manter o som padrão ou colocar
/// um áudio próprio por categoria sem que uma mude o som da outra.
class ScaleNotificationsService {
  static final ScaleNotificationsService _instance =
      ScaleNotificationsService._();
  factory ScaleNotificationsService() => _instance;

  ScaleNotificationsService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  Future<void>? _initFuture;

  /// iOS limita ~64 notificações locais pendentes no SO (usamos 60 com margem).
  /// Um aviso por evento ([compactAgendaPlanForIosLocalSlots]) → até ~60 eventos.
  static const int _kMaxPendingLocalNotifications = 60;
  int _pendingScheduledCount = 0;

  /// Avisos iminentes (catch-up / cadastro em cima da hora) — paridade com Web.
  Timer? _agendaImminentTimer;
  final List<_AgendaImminentEntry> _imminentQueue = [];
  final Set<String> _shownImminentKeys = {};

  /// Início do reagendamento em lote (cancela pendentes e zera contador iOS).
  Future<void> beginRescheduleBatch() async {
    _pendingScheduledCount = 0;
    _imminentQueue.clear();
    _shownImminentKeys.clear();
    await cancelAllScaleReminders();
  }

  /// Canal antigo (legado). Mantido somente para limpar instalações que ainda
  /// tinham notificações no canal antigo.
  static const _legacyChannelId = 'controletotal_plantao';

  bool get isSupported => Platform.isAndroid || Platform.isIOS;

  Future<void> init() async {
    if (!isSupported || _initialized) return;
    final inFlight = _initFuture;
    if (inFlight != null) return inFlight;
    _initFuture = _initInternal().whenComplete(() {
      _initFuture = null;
    });
    return _initFuture!;
  }

  Future<void> _initInternal() async {
    try {
      tz_data.initializeTimeZones();
      try {
        tz.setLocalLocation(tz.getLocation('America/Sao_Paulo'));
      } catch (_) {}
      final android = AndroidInitializationSettings('@mipmap/ic_launcher');
      final ios = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      final settings = InitializationSettings(android: android, iOS: ios);
      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: _handleResponse,
      );
      if (Platform.isAndroid) {
        await _ensureAndroidChannels();
        final androidImpl = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        await androidImpl?.requestNotificationsPermission();
      }
      if (Platform.isIOS) {
        final iosImpl = _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        await iosImpl?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
      }
      _startAgendaImminentTimer();
      _initialized = true;
    } catch (_) {}
  }

  void _startAgendaImminentTimer() {
    _agendaImminentTimer?.cancel();
    _agendaImminentTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_flushImminentNotifications()),
    );
  }

  void checkDueNow() {
    unawaited(_flushImminentNotifications());
  }

  Future<void> _flushImminentNotifications() async {
    if (!_initialized) return;
    final now = DateTime.now();
    final toRemove = <_AgendaImminentEntry>[];
    for (final entry in _imminentQueue) {
      if (now.isBefore(entry.when)) continue;
      final key = entry.dedupeKey;
      if (_shownImminentKeys.contains(key)) {
        toRemove.add(entry);
        continue;
      }
      _shownImminentKeys.add(key);
      await _showNotificationNow(
        id: entry.notificationId,
        title: entry.title,
        body: entry.body,
        details: entry.details,
        payload: entry.payload,
      );
      toRemove.add(entry);
    }
    for (final e in toRemove) {
      _imminentQueue.remove(e);
    }
  }

  Future<void> _showNotificationNow({
    required int id,
    required String title,
    required String body,
    required NotificationDetails details,
    required String payload,
  }) async {
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payload,
      );
      await _playAudioFromPayload(payload);
    } catch (_) {}
  }

  Future<void> _playAudioFromPayload(String payload) async {
    try {
      final mode = _deliveryModeFromPayload(payload);
      if (mode == NotificationSoundMode.silent ||
          mode == NotificationSoundMode.vibrateOnly) {
        return;
      }
      final soundId = _soundIdFromPayload(payload);
      if (soundId != null && soundId.isNotEmpty) {
        await NotificationAudioPlayer.instance.playBundledById(soundId);
        return;
      }
      if (_payloadIsPerEventOnly(payload)) return;
      final cat = _categoryFromPayload(payload);
      if (cat != null) {
        await NotificationAudioPlayer.instance.playForCategory(cat);
      }
    } catch (_) {}
  }

  /// Agenda no SO ou enfileira para exibição imediata (catch-up / ≤90 s).
  Future<void> _scheduleOrShowAt({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails details,
    required String payload,
    String? dedupeDocId,
    DateTime? dedupeNotifyAt,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    final grace = now.add(
      const Duration(seconds: kAgendaImminentGraceSeconds),
    );
    if (!scheduledDate.isAfter(grace)) {
      final localWhen = scheduledDate.toLocal();
      _imminentQueue.add(
        _AgendaImminentEntry(
          when: localWhen,
          notificationId: id,
          title: title,
          body: body,
          details: details,
          payload: payload,
          dedupeKey: dedupeDocId != null && dedupeNotifyAt != null
              ? '${dedupeDocId}_${dedupeNotifyAt.millisecondsSinceEpoch}'
              : 'id_$id',
        ),
      );
      if (scheduledDate.isAfter(now)) {
        try {
          await _plugin.zonedSchedule(
            id: id,
            title: title,
            body: body,
            scheduledDate: scheduledDate,
            notificationDetails: details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            payload: payload,
          );
          _pendingScheduledCount++;
        } catch (_) {}
      } else {
        await _flushImminentNotifications();
      }
      return;
    }
    try {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payload,
      );
      _pendingScheduledCount++;
    } catch (_) {}
  }

  /// Cria os 4 canais (escala/compromisso/audiência/financeiro) e remove o
  /// canal legado se ainda existir. Importance segue a preferência local
  /// "showAsPopup" (popup = max, senão default). Som segue a preferência por
  /// categoria (silenciado quando categoria está em "silent" OU usa áudio
  /// próprio — pois neste caso quem toca é o app em foreground).
  Future<void> _ensureAndroidChannels({bool forceRecreate = false}) async {
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl == null) return;
    final showPopup = await LocalNotificationPreferences().showAsPopupOnPhone;
    final imp = showPopup ? Importance.max : Importance.defaultImportance;
    for (final ch in _Channel.values) {
      final kind = switch (ch) {
        _Channel.audiencia => 'audiencia',
        _Channel.compromisso => 'compromisso',
        _Channel.financeiro => 'financeiro',
        _Channel.folga => 'folga',
        _ => 'escala',
      };
      final theme = NotificationModuleTheme.forKind(kind);
      final pref =
          await NotificationSoundPreferences.instance.read(ch.category);
      if (forceRecreate) {
        try {
          await androidImpl.deleteNotificationChannel(channelId: ch.id);
        } catch (_) {}
      }
      await androidImpl.createNotificationChannel(
        AndroidNotificationChannel(
          theme.channelId,
          theme.channelName,
          description: theme.channelDescription,
          importance: imp,
          playSound: pref.channelShouldPlaySound,
          enableVibration: pref.channelShouldVibrate,
          showBadge: true,
          ledColor: Color(theme.colorArgb),
        ),
      );
    }
    // Apaga canal legado (não usaremos mais — itens novos vão pelos 4 novos).
    try {
      await androidImpl.deleteNotificationChannel(channelId: _legacyChannelId);
    } catch (_) {}
  }

  /// Atualiza o canal de notificação no celular para exibir (ou não) em pop-up.
  /// Recria os 4 canais (escala/compromisso/audiência/financeiro).
  Future<void> updateChannelShowAsPopup(bool showAsPopup) async {
    if (!Platform.isAndroid) return;
    await _ensureAndroidChannels(forceRecreate: true);
  }

  /// Deve ser chamado após o usuário trocar o som de UMA categoria — para o
  /// Android recriar o canal correspondente com o novo `playSound`.
  Future<void> refreshChannelsAfterSoundChange() async {
    if (!Platform.isAndroid) return;
    await _ensureAndroidChannels(forceRecreate: true);
  }

  /// Callback quando o usuário toca/abre a notificação (ou ela é entregue
  /// estando o app em foreground em alguns casos). Aqui tocamos:
  ///  - o **tom escolhido para o evento** (`sound:<id>` no payload), quando
  ///    houver — banco offline `notification_sound_catalog.dart`;
  ///  - senão, o áudio personalizado escolhido para a **categoria** via
  ///    [NotificationAudioPlayer].
  static Future<void> _handleResponse(NotificationResponse resp) async {
    try {
      final payload = resp.payload ?? '';
      final mode = _deliveryModeFromPayload(payload);
      // Modo "Só vibrar" e "Só push": app não toca nenhum áudio.
      if (mode == NotificationSoundMode.silent ||
          mode == NotificationSoundMode.vibrateOnly) {
        return;
      }
      final soundId = _soundIdFromPayload(payload);
      if (soundId != null && soundId.isNotEmpty) {
        await NotificationAudioPlayer.instance.playBundledById(soundId);
        return;
      }
      // Lembrete **personalizado por evento**: não tocar o áudio global da
      // categoria (ex.: «padrão do sistema» no evento + «meu áudio» nas prefs).
      if (_payloadIsPerEventOnly(payload)) {
        return;
      }
      final cat = _categoryFromPayload(payload);
      if (cat != null) {
        await NotificationAudioPlayer.instance.playForCategory(cat);
      }
    } catch (_) {}
  }

  static NotificationSoundMode? _deliveryModeFromPayload(String payload) {
    for (final part in payload.split('|')) {
      if (part.startsWith('mode:')) {
        return NotificationSoundMode.fromValue(
            part.substring('mode:'.length).trim());
      }
    }
    return null;
  }

  /// Payload formato: `cat:<categoria>` opcionalmente seguido por
  /// `|sound:<id_do_catalogo>` (ex.: `cat:audiencia|sound:urgente`).
  static NotificationSoundCategory? _categoryFromPayload(String payload) {
    final head = payload.split('|').first;
    switch (head) {
      case 'cat:escala':
        return NotificationSoundCategory.escala;
      case 'cat:compromisso':
        return NotificationSoundCategory.compromisso;
      case 'cat:audiencia':
        return NotificationSoundCategory.audiencia;
      case 'cat:financeiro':
        return NotificationSoundCategory.financeiro;
      default:
        return null;
    }
  }

  static String? _soundIdFromPayload(String payload) {
    for (final part in payload.split('|')) {
      if (part.startsWith('sound:')) {
        final id = part.substring('sound:'.length).trim();
        if (id.isNotEmpty) return id;
      }
    }
    return null;
  }

  /// `src:e` = notificação definida **só no evento** (ignora prefs gerais no
  /// callback). `src:g` ou ausência = herda prefs gerais (comportamento antigo).
  static bool _payloadIsPerEventOnly(String payload) {
    for (final part in payload.split('|')) {
      if (part == 'src:e') return true;
      if (part == 'src:g') return false;
    }
    return false;
  }

  /// Modo de entrega final para o lembrete.
  ///
  /// - **Sem personalização** (`notificationDeliveryMode` vazio no doc):
  ///   usa só as **Preferências gerais** da categoria (som, vibrar, silêncio).
  /// - **Com personalização** (doc com modo explícito): **ignora** o padrão
  ///   geral e aplica só o que foi cadastrado naquele evento.
  Future<_EffectiveDelivery> _effectiveDeliveryFor({
    required _Channel ch,
    String? eventDeliveryMode,
    String? eventSoundId,
  }) async {
    final pref = await NotificationSoundPreferences.instance.read(ch.category);
    final evRaw = (eventDeliveryMode ?? '').trim();
    final personalized = evRaw.isNotEmpty;
    if (!personalized) {
      return _EffectiveDelivery(pref.mode);
    }

    NotificationSoundMode mode;
    final ev = evRaw.toLowerCase();
    if (ev == 'audio' || ev == 'audio_on' || ev == 'on') {
      // Áudio só deste evento — com tom do banco ou padrão do sistema no
      // aparelho (não mistura com «meu áudio» global da categoria).
      mode = (eventSoundId != null && eventSoundId.isNotEmpty)
          ? NotificationSoundMode.customAudio
          : NotificationSoundMode.systemDefault;
    } else if (ev == 'vibrate' || ev == 'vibration' || ev == 'so_vibrar') {
      mode = NotificationSoundMode.vibrateOnly;
    } else if (ev == 'silent' || ev == 'push' || ev == 'push_only' ||
        ev == 'so_push') {
      mode = NotificationSoundMode.silent;
    } else {
      // Valor desconhecido no doc: não regressar para prefs gerais.
      mode = NotificationSoundMode.systemDefault;
    }
    return _EffectiveDelivery(mode);
  }

  /// Monta o `NotificationDetails` para o canal, levando em conta o modo
  /// efetivo (categoria + override do evento).
  Future<NotificationDetails> _detailsForChannelAndDelivery(
    _Channel ch,
    _EffectiveDelivery delivery, {
    required String title,
    required String body,
    String? subtitle,
  }) async {
    final showPopup =
        await LocalNotificationPreferences().showAsPopupOnPhone;
    final importance = showPopup ? Importance.max : Importance.defaultImportance;
    final priority = showPopup ? Priority.max : Priority.defaultPriority;
    final playSoundAndroid =
        delivery.mode == NotificationSoundMode.systemDefault;
    final enableVibrationAndroid = switch (delivery.mode) {
      NotificationSoundMode.systemDefault => true,
      NotificationSoundMode.vibrateOnly => true,
      NotificationSoundMode.customAudio => true,
      NotificationSoundMode.silent => false,
    };
    final presentSoundIos =
        delivery.mode == NotificationSoundMode.systemDefault;
    final channelKind = switch (ch) {
      _Channel.audiencia => 'audiencia',
      _Channel.compromisso => 'compromisso',
      _Channel.financeiro => 'financeiro',
      _Channel.folga => 'folga',
      _ => 'escala',
    };
    final theme = NotificationModuleTheme.forKind(channelKind);
    final moduleSubtitle = (subtitle ?? '').trim().isNotEmpty
        ? subtitle!.trim()
        : NotificationMessageBuilder.pushSubtitle(null, channelKind);
    return NotificationDetails(
      android: await NotificationAndroidStyle.buildDetails(
        channelKind: channelKind,
        title: title,
        body: body,
        subtitle: moduleSubtitle,
        importance: importance,
        priority: priority,
        playSound: playSoundAndroid,
        enableVibration: enableVibrationAndroid,
        channelIdOverride: ch.id,
        channelNameOverride: ch.name,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: presentSoundIos,
        subtitle: moduleSubtitle,
        threadIdentifier: theme.threadId,
      ),
    );
  }

  String _payloadFor(
    _Channel ch, {
    String? soundId,
    NotificationSoundMode? deliveryMode,
    required bool perEvent,
  }) {
    final cat = switch (ch) {
      _Channel.escala => 'cat:escala',
      _Channel.compromisso => 'cat:compromisso',
      _Channel.audiencia => 'cat:audiencia',
      _Channel.financeiro => 'cat:financeiro',
      _Channel.folga => 'cat:folga',
    };
    final parts = <String>[cat, perEvent ? 'src:e' : 'src:g'];
    if (deliveryMode != null) {
      parts.add('mode:${deliveryMode.value}');
    }
    final sid = soundId?.trim();
    if (sid != null &&
        sid.isNotEmpty &&
        deliveryMode == NotificationSoundMode.customAudio) {
      parts.add('sound:$sid');
    }
    return parts.join('|');
  }

  /// Agenda lembretes para um evento. [channel] determina som e canal.
  /// [eventSoundId] (opcional) = id do catálogo offline escolhido só para
  /// este evento — toca via [NotificationAudioPlayer] quando a notificação
  /// for aberta com o app em foreground.
  /// [eventDeliveryMode] (opcional) = 'audio'/'vibrate'/'push' do doc.
  Future<int> _scheduleRemindersForOneEvent({
    required _Channel channel,
    required tz.TZDateTime when,
    required List<int> reminderLeads,
    required String notificationTitle,
    required String notificationBody,
    required int idStart,
    String? eventSoundId,
    String? eventDeliveryMode,
    AgendaNotificationMessageFactory? messageForLead,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    int id = idStart;
    final personalized =
        (eventDeliveryMode ?? '').trim().isNotEmpty;
    final soundIdForPayload = personalized ? eventSoundId : null;
    final delivery = await _effectiveDeliveryFor(
      ch: channel,
      eventDeliveryMode: eventDeliveryMode,
      eventSoundId: eventSoundId,
    );
    final channelKindStr = switch (channel) {
      _Channel.audiencia => 'audiencia',
      _Channel.compromisso => 'compromisso',
      _Channel.financeiro => 'financeiro',
      _Channel.folga => 'folga',
      _ => 'escala',
    };
    final payload = _payloadFor(
      channel,
      soundId: soundIdForPayload,
      deliveryMode: delivery.mode,
      perEvent: personalized,
    );
    var notifyTimes = agendaEffectiveNotifyAtList(
      eventAt: when.toLocal(),
      leadMinutes: reminderLeads,
      now: now.toLocal(),
    );
    if (Platform.isIOS && notifyTimes.length > 1) {
      notifyTimes = [notifyTimes.first];
    }
    for (final localWhen in notifyTimes) {
      if (Platform.isIOS &&
          _pendingScheduledCount >= _kMaxPendingLocalNotifications) {
        break;
      }
      final leadUsed = inferAgendaNotificationLeadMinutes(
        when.toLocal(),
        localWhen,
        reminderLeads,
        now.toLocal(),
      );
      final msg = messageForLead != null
          ? messageForLead(leadUsed)
          : (title: notificationTitle, body: notificationBody);
      final subtitle = NotificationMessageBuilder.pushSubtitle(
        leadUsed,
        channelKindStr,
      );
      final details = await _detailsForChannelAndDelivery(
        channel,
        delivery,
        title: msg.title,
        body: msg.body,
        subtitle: subtitle,
      );
      final dataAviso = tz.TZDateTime.from(localWhen, tz.local);
      await _scheduleOrShowAt(
        id: id++,
        title: msg.title,
        body: msg.body,
        scheduledDate: dataAviso,
        details: details,
        payload: payload,
      );
    }
    return id;
  }

  _Channel _channelFromKind(AgendaNotificationChannelKind kind) =>
      switch (kind) {
        AgendaNotificationChannelKind.audiencia => _Channel.audiencia,
        AgendaNotificationChannelKind.compromisso => _Channel.compromisso,
        AgendaNotificationChannelKind.escala => _Channel.escala,
        AgendaNotificationChannelKind.financeiro => _Channel.financeiro,
      };

  /// Reagenda tudo numa fila única: prioridade audiência > compromisso > escala;
  /// horários mais próximos primeiro; limite iOS respeitado.
  Future<void> scheduleAgendaBatch({
    required String uid,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> reminders,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> scales,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> transactions,
    DateTime? forwardCutoff,
    String? userDisplayName,
  }) async {
    if (!isSupported || !_initialized || uid.isEmpty) return;
    try {
      await beginRescheduleBatch();
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('notifications')
          .get();
      final settings = parseAgendaNotificationUserSettings(snap.data());
      if (!settings.reminderEnabled) return;

      final now = DateTime.now();
      final plan = buildAgendaNotificationPlan(
        now: now,
        settings: settings,
        reminders: reminders,
        scales: scales,
        transactions: transactions,
        forwardCutoff: forwardCutoff,
        includeFinancial: transactions.isNotEmpty,
        userDisplayName: userDisplayName,
      );

      // iOS: 1 lembrete local por evento (próximo horário); demais leads = servidor.
      final entries = Platform.isIOS
          ? compactAgendaPlanForIosLocalSlots(plan)
          : plan;

      for (final entry in entries) {
        if (Platform.isIOS &&
            _pendingScheduledCount >= _kMaxPendingLocalNotifications) {
          break;
        }
        final dataAviso = tz.TZDateTime.from(entry.notifyAt, tz.local);

        final channel = _channelFromKind(entry.channelKind);
        final delivery = await _effectiveDeliveryFor(ch: channel);
        final details = await _detailsForChannelAndDelivery(
          channel,
          delivery,
          title: entry.title,
          body: entry.body,
          subtitle: NotificationMessageBuilder.pushSubtitle(
            null,
            switch (channel) {
              _Channel.audiencia => 'audiencia',
              _Channel.compromisso => 'compromisso',
              _Channel.financeiro => 'financeiro',
              _Channel.folga => 'folga',
              _ => 'escala',
            },
          ),
        );
        final payload = _payloadFor(
          channel,
          deliveryMode: delivery.mode,
          perEvent: false,
        );
        await _scheduleOrShowAt(
          id: stableAgendaNotificationId(entry.docId, entry.notifyAt),
          title: entry.title,
          body: entry.body,
          scheduledDate: dataAviso,
          details: details,
          payload: payload,
          dedupeDocId: entry.docId,
          dedupeNotifyAt: entry.notifyAt,
        );
      }
      await _flushImminentNotifications();
    } catch (_) {}
  }

  Future<void> scheduleFromScales(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      {String? uid}) async {
    if (!isSupported || !_initialized) return;
    try {
      List<int> globalLeads =
          List<int>.from(LocalNotificationPreferences.kDefaultLeads);
      bool reminderEnabled = true;
      bool notifEscalas = true;
      bool notifCompromissosAudiencias = true;
      AgendaNotificationUserSettings? userSettings;
      if (uid != null && uid.isNotEmpty) {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('settings')
            .doc('notifications')
            .get();
        final data = snap.data();
        userSettings = parseAgendaNotificationUserSettings(data);
        reminderEnabled = userSettings.reminderEnabled;
        notifEscalas = userSettings.notifEscalas;
        notifCompromissosAudiencias = userSettings.notifCompromissosAudiencias;
        final raw = data?['scaleReminderLeads'];
        if (raw is List && raw.isNotEmpty) {
          globalLeads = raw
              .map((e) =>
                  (e is num ? e.toInt() : int.tryParse(e.toString()) ?? 0))
              .where((m) => m > 0)
              .toList();
          if (globalLeads.isEmpty) {
            final m = data?['scaleReminderMinutes'];
            globalLeads = m is num
                ? [m.toInt()]
                : List<int>.from(LocalNotificationPreferences.kDefaultLeads);
          }
        } else if (data?['scaleReminderMinutes'] != null) {
          final m = data!['scaleReminderMinutes'];
          globalLeads = [(m is int) ? m : (m is num ? m.toInt() : 60)];
        }
      }
      if (!reminderEnabled) {
        await cancelAllScaleReminders();
        return;
      }
      final now = tz.TZDateTime.now(tz.local);
      int id = 1000;
      for (final doc in docs) {
        final d = doc.data();
        // Espelhos da Agenda NÃO disparam aqui — já são notificados via
        // scheduleFromReminders (coleção reminders). Sem isso, o usuário
        // receberia 2 notificações por item.
        if (d['isAgendaMirror'] == true) continue;
        if (d['isProdutividadeFolgaMirror'] == true) continue;
        final isCompromisso = (d['isCompromisso'] ?? false) as bool;
        if (isCompromisso && !(userSettings?.notifCompromissos ?? true)) continue;
        if (!isCompromisso && !notifEscalas) continue;
        if (userSettings != null) {
          final delivery = isCompromisso
              ? userSettings.deliveryCompromisso
              : userSettings.deliveryEscala;
          if (!agendaAllowsLocalOrPushDelivery(delivery)) continue;
        }
        final date = (d['date'] as Timestamp?)?.toDate();
        final startStr = d['start'] as String?;
        if (date == null || startStr == null) continue;
        final startParts = startStr.split(':');
        final hour = int.tryParse(startParts.first) ?? 8;
        final minute = startParts.length > 1
            ? (int.tryParse(startParts[1]) ?? 0)
            : 0;
        final shiftStart = tz.TZDateTime(
            tz.local, date.year, date.month, date.day, hour, minute);
        if (shiftStart.isBefore(now)) continue;

        final List<int> leads = _reminderLeadsForDoc(d, globalLeads);

        id = await _scheduleRemindersForOneEvent(
          channel: isCompromisso ? _Channel.compromisso : _Channel.escala,
          when: shiftStart,
          reminderLeads: leads,
          notificationTitle: '',
          notificationBody: '',
          messageForLead: (leadMin) =>
              NotificationMessageBuilder.buildScaleNotificationMessage(
            d,
            eventAt: shiftStart.toLocal(),
            leadMin: leadMin,
          ),
          idStart: id,
        );
      }
    } catch (_) {}
  }

  List<int> _reminderLeadsForDoc(
      Map<String, dynamic> d, List<int> globalLeads) {
  // Só antecedências globais (Configurações).
    final parsed = globalLeads.where((m) => m > 0).toSet().toList()..sort();
    if (parsed.isNotEmpty) return parsed;
    return List<int>.from(LocalNotificationPreferences.kDefaultLeads);
  }

  /// Agenda lembretes da Agenda (audiências e compromissos da coleção reminders).
  Future<void> scheduleFromReminders(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      {String? uid}) async {
    if (!isSupported || !_initialized || uid == null || uid.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('notifications')
          .get();
      final data = snap.data();
      final userSettings = parseAgendaNotificationUserSettings(data);
      if (!userSettings.reminderEnabled) return;
      if (!userSettings.notifAudiencias && !userSettings.notifCompromissos) return;
      List<int> globalLeads =
          List<int>.from(LocalNotificationPreferences.kDefaultLeads);
      final raw = data?['scaleReminderLeads'];
      if (raw is List && raw.isNotEmpty) {
        globalLeads = raw
            .map((e) =>
                (e is num ? e.toInt() : int.tryParse(e.toString()) ?? 0))
            .where((m) => m > 0)
            .toList();
        if (globalLeads.isEmpty) {
          globalLeads = [
            data?['scaleReminderMinutes'] is num
                ? (data!['scaleReminderMinutes'] as num).toInt()
                : 60
          ];
        }
      } else if (data?['scaleReminderMinutes'] != null) {
        final m = data!['scaleReminderMinutes'];
        globalLeads = [(m is int) ? m : (m is num ? m.toInt() : 60)];
      }
      String? userDisplayName;
      try {
        final userSnap =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final n = (userSnap.data()?['name'] ?? '').toString().trim();
        if (n.isNotEmpty) userDisplayName = n;
      } catch (_) {}

      final now = tz.TZDateTime.now(tz.local);
      int id = 2000;
      for (final doc in docs) {
        final d = doc.data();
        final dateTs = d['date'];
        if (dateTs == null) continue;
        final date = (dateTs as Timestamp).toDate();
        final timeStr = (d['time'] ?? '09:00').toString();
        final parts = timeStr.split(':');
        final hour = int.tryParse(parts.first) ?? 9;
        final minute =
            parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
        final eventAt = tz.TZDateTime(
            tz.local, date.year, date.month, date.day, hour, minute);
        if (!agendaReminderEligibleForNotifySchedule(d, now.toLocal())) {
          continue;
        }
        final isAudiencia =
            (d['type'] ?? 'compromisso').toString() == 'audiencia';
        final delivery = isAudiencia
            ? userSettings.deliveryAudiencia
            : userSettings.deliveryCompromisso;
        if (!agendaAllowsLocalOrPushDelivery(delivery)) continue;
        final leads = _reminderLeadsForDoc(d, globalLeads);
        id = await _scheduleRemindersForOneEvent(
          channel:
              isAudiencia ? _Channel.audiencia : _Channel.compromisso,
          when: eventAt,
          reminderLeads: leads,
          notificationTitle: '',
          notificationBody: '',
          messageForLead: (leadMin) =>
              NotificationMessageBuilder.fromReminderDoc(
            d,
            userName: userDisplayName,
            eventAt: eventAt.toLocal(),
            leadMin: leadMin,
          ),
          idStart: id,
        );
      }
    } catch (_) {}
  }

  /// Agenda lembretes de despesas pendentes (só quando status != 'paid').
  Future<void> scheduleFinancialReminders(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      {String? uid}) async {
    if (!isSupported || !_initialized || uid == null || uid.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('notifications')
          .get();
      final data = snap.data();
      if (data?['notifFinanceiro'] == false) return;
      List<int> globalLeads = [1440];
      final raw = data?['scaleReminderLeads'];
      if (raw is List && raw.isNotEmpty) {
        globalLeads = raw
            .map((e) =>
                (e is num ? e.toInt() : int.tryParse(e.toString()) ?? 0))
            .where((m) => m > 0)
            .toList();
        if (globalLeads.isEmpty) globalLeads = [1440];
      }
      final now = tz.TZDateTime.now(tz.local);
      int id = 3000;
      for (final doc in docs) {
        final d = doc.data();
        if ((d['type'] ?? 'expense').toString() == 'income') continue;
        if ((d['status'] ?? 'paid').toString() == 'paid') continue;
        final dateTs = d['date'];
        if (dateTs == null) continue;
        final dueDate = (dateTs as Timestamp).toDate();
        final dueAt = tz.TZDateTime(
            tz.local, dueDate.year, dueDate.month, dueDate.day, 9, 0);
        if (dueAt.isBefore(now)) continue;
        final desc =
            (d['description'] ?? d['category'] ?? 'Despesa').toString();
        final amount = (d['amount'] ?? 0).toDouble();
        id = await _scheduleRemindersForOneEvent(
          channel: _Channel.financeiro,
          when: dueAt,
          reminderLeads: globalLeads,
          notificationTitle: '',
          notificationBody: '',
          messageForLead: (leadMin) =>
              NotificationMessageBuilder.buildContaPagarNotification(
            desc: desc,
            valor: amount.toStringAsFixed(2),
            eventAt: dueAt.toLocal(),
            leadMin: leadMin,
          ),
          idStart: id,
        );
      }
    } catch (_) {}
  }

  Future<void> cancelAllScaleReminders() async {
    if (!isSupported) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  /// Push FCM com app aberto: bandeja do sistema (Android/iOS), alinhado ao padrão YAHWEH.
  Future<void> showFcmPushNotification({
    required String title,
    required String body,
    String channelKind = 'escala',
    String? payload,
  }) async {
    if (!isSupported) return;
    if (!_initialized) await init();
    final t = title.trim();
    final b = body.trim();
    if (t.isEmpty && b.isEmpty) return;
    final ch = switch (channelKind.toLowerCase()) {
      'audiencia' => _Channel.audiencia,
      'compromisso' => _Channel.compromisso,
      'financeiro' => _Channel.financeiro,
      'folga' => _Channel.folga,
      _ => _Channel.escala,
    };
    final delivery = _EffectiveDelivery(NotificationSoundMode.systemDefault);
    final displayTitle = t.isEmpty ? kNotificationBrandApp : t;
    final details = await _detailsForChannelAndDelivery(
      ch,
      delivery,
      title: displayTitle,
      body: b,
      subtitle: NotificationMessageBuilder.pushSubtitle(null, channelKind),
    );
    final id = DateTime.now().millisecondsSinceEpoch.remainder(0x7FFFFFFF);
    await _showNotificationNow(
      id: id,
      title: displayTitle,
      body: b,
      details: details,
      payload: payload ?? '',
    );
  }
}

class _AgendaImminentEntry {
  const _AgendaImminentEntry({
    required this.when,
    required this.notificationId,
    required this.title,
    required this.body,
    required this.details,
    required this.payload,
    required this.dedupeKey,
  });

  final DateTime when;
  final int notificationId;
  final String title;
  final String body;
  final NotificationDetails details;
  final String payload;
  final String dedupeKey;
}

/// Modo de entrega efetivo (categoria + override do evento).
class _EffectiveDelivery {
  const _EffectiveDelivery(this.mode);
  final NotificationSoundMode mode;
}
