// Notificações na Web e PWA (Android/iPhone instalado) — Web Notifications API.
// Funciona quando o usuário instala o atalho no celular (PWA) e concede permissão.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import '../utils/agenda_notification_cutoff.dart';
import '../utils/agenda_delivery_channel_prefs.dart';
import '../utils/agenda_notification_plan.dart';
import '../utils/agenda_reminder_end_of_day.dart';
import '../utils/agenda_reminder_notify_times.dart';
import 'notification_message_builder.dart';
import 'local_notification_preferences.dart';

class ScaleNotificationsService {
  static final ScaleNotificationsService _instance = ScaleNotificationsService._();
  factory ScaleNotificationsService() => _instance;

  ScaleNotificationsService._();

  bool _initialized = false;
  Timer? _checkTimer;
  final List<_PendingReminder> _pendingReminders = [];

  bool get isSupported => true;

  /// Solicita permissão e inicia o timer que verifica lembretes a cada minuto.
  Future<void> init() async {
    if (_initialized) return;
    try {
      if (html.Notification.supported) {
        await html.Notification.requestPermission();
      }
      _startCheckTimer();
      _initialized = true;
    } catch (_) {}
  }

  void _startCheckTimer() {
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(const Duration(minutes: 1), (_) => _checkAndShowDue());
  }

  /// Dispara verificação imediata (ex.: após salvar audiência no módulo Agenda).
  void checkDueNow() => _checkAndShowDue();

  Future<void> beginRescheduleBatch() async {
    await cancelAllScaleReminders();
  }

  static const int _kMaxPendingWeb = 120;

  /// Mesma fila unificada do app nativo (config geral + por evento; hoje/amanhã).
  Future<void> scheduleAgendaBatch({
    required String uid,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> reminders,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> scales,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> transactions,
    DateTime? forwardCutoff,
    String? userDisplayName,
  }) async {
    if (!_initialized || uid.isEmpty) return;
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
        forwardCutoff: forwardCutoff ?? agendaNotificationScheduleFloor(now),
        includeFinancial: transactions.isNotEmpty,
        userDisplayName: userDisplayName,
      );

      var added = 0;
      for (final entry in plan) {
        if (added >= _kMaxPendingWeb) break;
        _pendingReminders.add(
          _PendingReminder(
            when: entry.notifyAt,
            title: entry.title,
            body: entry.body,
          ),
        );
        added++;
      }
      _checkAndShowDue();
    } catch (_) {}
  }

  void _checkAndShowDue() {
    final now = DateTime.now();
    final toRemove = <_PendingReminder>[];
    for (final r in _pendingReminders) {
      if (!now.isBefore(r.when)) {
        _showNotification(r.title, r.body);
        toRemove.add(r);
      }
    }
    for (final r in toRemove) {
      _pendingReminders.remove(r);
    }
  }

  void _showNotification(String title, String body) {
    try {
      if (!html.Notification.supported) return;
      if (html.Notification.permission != 'granted') return;
      html.Notification(title, body: body, icon: 'icons/Icon-192.png');
    } catch (_) {}
  }

  /// Agenda lembretes a partir das escalas (mesma lógica do app nativo).
  /// Na web, os lembretes são exibidos quando o app está aberto (timer a cada 1 min).
  Future<void> scheduleFromScales(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {String? uid}) async {
    if (!_initialized) return;
    try {
      // Padrão (admin): 60 min E 1 dia antes ao mesmo tempo.
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
              .map((e) => (e is num ? e.toInt() : int.tryParse(e.toString()) ?? 0))
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
        // Senão: mantém o padrão 1 dia + 60 min.
      }
      if (!reminderEnabled) return;

      final now = DateTime.now();
      for (final doc in docs) {
        final d = doc.data();
        // Espelhos da Agenda NÃO disparam aqui — já notificados via reminders.
        if (d['isAgendaMirror'] == true) continue;
        if (d['isProdutividadeFolgaMirror'] == true) continue;
        final isCompromisso = (d['isCompromisso'] ?? false) as bool;
        if (isCompromisso && !notifCompromissosAudiencias) continue;
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
        final minute = startParts.length > 1 ? (int.tryParse(startParts[1]) ?? 0) : 0;
        final shiftStart = DateTime(date.year, date.month, date.day, hour, minute);
        if (shiftStart.isBefore(now)) continue;

        final leads = _reminderLeadsForDoc(d, globalLeads);

        for (final when in agendaEffectiveNotifyAtList(
          eventAt: shiftStart,
          leadMinutes: leads,
          now: now,
        )) {
          final leadUsed = inferAgendaNotificationLeadMinutes(
            shiftStart,
            when,
            leads,
            now,
          );
          final message = NotificationMessageBuilder.buildScaleNotificationMessage(
            d,
            eventAt: shiftStart,
            leadMin: leadUsed,
          );
          _pendingReminders.add(_PendingReminder(
            when: when,
            title: message.title,
            body: message.body,
          ));
        }
      }
      _checkAndShowDue();
    } catch (_) {}
  }

  List<int> _reminderLeadsForDoc(Map<String, dynamic> d, List<int> globalLeads) {
    final parsed = globalLeads.where((m) => m > 0).toSet().toList()..sort();
    if (parsed.isNotEmpty) return parsed;
    return List<int>.from(LocalNotificationPreferences.kDefaultLeads);
  }

  Future<void> scheduleFromReminders(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {String? uid}) async {
    if (!_initialized || uid == null || uid.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(uid).collection('settings').doc('notifications').get();
      final data = snap.data();
      final userSettings = parseAgendaNotificationUserSettings(data);
      if (!userSettings.reminderEnabled) return;
      if (!userSettings.notifAudiencias && !userSettings.notifCompromissos) return;
      // Padrão (admin): 60 min E 1 dia antes ao mesmo tempo.
      List<int> globalLeads =
          List<int>.from(LocalNotificationPreferences.kDefaultLeads);
      final raw = data?['scaleReminderLeads'];
      if (raw is List && raw.isNotEmpty) {
        globalLeads = raw.map((e) => (e is num ? e.toInt() : int.tryParse(e.toString()) ?? 0)).where((m) => m > 0).toList();
        if (globalLeads.isEmpty) {
          globalLeads = List<int>.from(LocalNotificationPreferences.kDefaultLeads);
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

      final now = DateTime.now();
      for (final doc in docs) {
        final d = doc.data();
        final dateTs = d['date'];
        if (dateTs == null) continue;
        final date = (dateTs as Timestamp).toDate();
        final timeStr = (d['time'] ?? '09:00').toString();
        final parts = timeStr.split(':');
        final hour = int.tryParse(parts.first) ?? 9;
        final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
        final eventAt = DateTime(date.year, date.month, date.day, hour, minute);
        if (!agendaReminderEligibleForNotifySchedule(d, now)) continue;
        final isAudiencia =
            (d['type'] ?? 'compromisso').toString() == 'audiencia';
        final delivery = isAudiencia
            ? userSettings.deliveryAudiencia
            : userSettings.deliveryCompromisso;
        if (!agendaAllowsLocalOrPushDelivery(delivery)) continue;
        final leads = _reminderLeadsForDoc(d, globalLeads);
        for (final when in agendaEffectiveNotifyAtList(
          eventAt: eventAt,
          leadMinutes: leads,
          now: now,
        )) {
          final leadUsed = inferAgendaNotificationLeadMinutes(
            eventAt,
            when,
            leads,
            now,
          );
          final message = NotificationMessageBuilder.fromReminderDoc(
            d,
            userName: userDisplayName,
            eventAt: eventAt,
            leadMin: leadUsed,
          );
          _pendingReminders.add(
            _PendingReminder(
              when: when,
              title: message.title,
              body: message.body,
            ),
          );
        }
      }
      _checkAndShowDue();
    } catch (_) {}
  }

  Future<void> scheduleFinancialReminders(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {String? uid}) async {
    if (!_initialized || uid == null || uid.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(uid).collection('settings').doc('notifications').get();
      final data = snap.data();
      if (data?['notifFinanceiro'] == false) return;
      List<int> globalLeads = [1440];
      final raw = data?['scaleReminderLeads'];
      if (raw is List && raw.isNotEmpty) {
        globalLeads = raw.map((e) => (e is num ? e.toInt() : int.tryParse(e.toString()) ?? 0)).where((m) => m > 0).toList();
        if (globalLeads.isEmpty) globalLeads = [1440];
      }
      final now = DateTime.now();
      for (final doc in docs) {
        final d = doc.data();
        if ((d['type'] ?? 'expense').toString() == 'income') continue;
        if ((d['status'] ?? 'paid').toString() == 'paid') continue;
        final dateTs = d['date'];
        if (dateTs == null) continue;
        final dueDate = (dateTs as Timestamp).toDate();
        final dueAt = DateTime(dueDate.year, dueDate.month, dueDate.day, 9, 0);
        if (dueAt.isBefore(now)) continue;
        final desc = (d['description'] ?? d['category'] ?? 'Despesa').toString();
        final amount = (d['amount'] ?? 0).toDouble();
        final message = NotificationMessageBuilder.buildContaPagarNotification(desc: desc, valor: amount.toStringAsFixed(2));
        for (final when in agendaEffectiveNotifyAtList(
          eventAt: dueAt,
          leadMinutes: globalLeads,
          now: now,
        )) {
          _pendingReminders.add(
            _PendingReminder(
              when: when,
              title: message.title,
              body: message.body,
            ),
          );
        }
      }
      _checkAndShowDue();
    } catch (_) {}
  }

  Future<void> cancelAllScaleReminders() async {
    _pendingReminders.clear();
  }

  Future<void> updateChannelShowAsPopup(bool showAsPopup) async {}

  Future<void> refreshChannelsAfterSoundChange() async {}

  Future<void> showFcmPushNotification({
    required String title,
    required String body,
    String channelKind = 'escala',
    String? payload,
  }) async {}
}

class _PendingReminder {
  final DateTime when;
  final String title;
  final String body;
  _PendingReminder({required this.when, required this.title, required this.body});
}
