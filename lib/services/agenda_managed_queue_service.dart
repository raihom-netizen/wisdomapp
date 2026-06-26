import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/agenda_alert_queue_item.dart';
import '../utils/agenda_notification_cutoff.dart';
import '../utils/agenda_notification_plan.dart';
import '../utils/agenda_reminder_end_of_day.dart';
import 'agenda_alerts_queue_service.dart';
import 'yearly_commitment_repeat_service.dart';

/// Fila gerenciável: mescla `agendaAlerts` (servidor) com plano local (reminders + scales).
/// Garante lista visível mesmo se a Cloud Function atrasar; edições nos módulos
/// refletem na hora via snapshots Firestore.
class AgendaManagedQueueService {
  AgendaManagedQueueService._();

  static const Duration _window = Duration(days: 60);
  static const int _kMaxDocsPerCollection = 600;

  /// Mesma chave do servidor: `{sourceType}_{sourceId}_{leadMin}`.
  static String alertDocId(String sourceType, String sourceId, int leadMin) {
    final safeId = sourceId.replaceAll(RegExp(r'[/\s]'), '_');
    return '${sourceType}_${safeId}_$leadMin';
  }

  static String _channelKindStr(AgendaNotificationChannelKind kind) =>
      switch (kind) {
        AgendaNotificationChannelKind.audiencia => 'audiencia',
        AgendaNotificationChannelKind.compromisso => 'compromisso',
        AgendaNotificationChannelKind.escala => 'escala',
        AgendaNotificationChannelKind.financeiro => 'financeiro',
      };

  static String _sourceTypeFor(AgendaNotificationChannelKind kind) =>
      kind == AgendaNotificationChannelKind.escala ? 'scale' : 'reminder';

  static AgendaAlertQueueItem _fromPlanEntry(AgendaNotificationPlanEntry e) {
    final sourceType = _sourceTypeFor(e.channelKind);
    final eventAt = e.notifyAt.add(Duration(minutes: e.leadMinutes));
    return AgendaAlertQueueItem(
      id: alertDocId(sourceType, e.docId, e.leadMinutes),
      status: 'pending',
      sourceType: sourceType,
      sourceId: e.docId,
      leadMin: e.leadMinutes,
      notifyAt: e.notifyAt,
      eventAt: eventAt,
      title: e.title,
      body: e.body,
      channelKind: _channelKindStr(e.channelKind),
    );
  }

  static List<AgendaAlertQueueItem> _merge(
    List<AgendaAlertQueueItem> server,
    List<AgendaAlertQueueItem> planned,
  ) {
    final map = <String, AgendaAlertQueueItem>{};
    // Plano local só preenche lacunas (servidor manda, sobretudo status «sent»).
    for (final s in server) {
      map[s.id] = s;
    }
    for (final p in planned) {
      map.putIfAbsent(p.id, () => p);
    }
    final merged = map.values.toList()
      ..sort((a, b) {
        final byEvent = a.eventAt.compareTo(b.eventAt);
        if (byEvent != 0) return byEvent;
        return a.notifyAt.compareTo(b.notifyAt);
      });
    return AgendaAlertsQueueService.onlyActiveQueue(merged);
  }

  static Future<List<AgendaAlertQueueItem>> _buildPlannedQueue(String uid) async {
    if (uid.isEmpty) return [];

    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endDate = DateTime(
      startOfToday.add(_window).year,
      startOfToday.add(_window).month,
      startOfToday.add(_window).day,
      23,
      59,
      59,
    );

    AgendaNotificationUserSettings settings =
        const AgendaNotificationUserSettings();
    try {
      final settingsSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('notifications')
          .get();
      settings = parseAgendaNotificationUserSettings(settingsSnap.data());
    } catch (_) {}

    String? userDisplayName;
    try {
      final userSnap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final n = (userSnap.data()?['name'] ?? '').toString().trim();
      if (n.isNotEmpty) userDisplayName = n;
    } catch (_) {}

    List<QueryDocumentSnapshot<Map<String, dynamic>>> reminders = [];
    List<QueryDocumentSnapshot<Map<String, dynamic>>> scales = [];

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('reminders')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .orderBy('date')
          .limit(_kMaxDocsPerCollection)
          .get();
      reminders = snap.docs.where((doc) {
        final d = doc.data();
        if (!YearlyCommitmentRepeatService.shouldShowInAgendaList(
          d,
          docId: doc.id,
        )) {
          return false;
        }
        return agendaReminderEligibleForNotifySchedule(d, now);
      }).toList();
    } catch (_) {}

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('scales')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .orderBy('date')
          .limit(_kMaxDocsPerCollection)
          .get();
      scales = snap.docs.toList();
    } catch (_) {}

    final plan = buildAgendaNotificationPlan(
      now: now,
      settings: settings,
      reminders: reminders,
      scales: scales,
      transactions: const [],
      forwardCutoff: agendaNotificationScheduleFloor(now),
      includeFinancial: false,
      userDisplayName: userDisplayName,
    );

  return plan.map(_fromPlanEntry).toList();
  }

  /// Stream unificado: servidor + plano local (atualiza ao editar agenda/escalas).
  static Stream<List<AgendaAlertQueueItem>> watchManagedQueue(String uid) {
    if (uid.isEmpty) return Stream.value([]);

    final controller = StreamController<List<AgendaAlertQueueItem>>.broadcast();
    List<AgendaAlertQueueItem> serverItems = [];
    List<AgendaAlertQueueItem> plannedItems = [];
    var rebuildPlannedScheduled = false;

    void emit() {
      if (controller.isClosed) return;
      controller.add(_merge(serverItems, plannedItems));
    }

    Future<void> rebuildPlanned() async {
      if (controller.isClosed) return;
      try {
        plannedItems = await _buildPlannedQueue(uid);
      } catch (_) {
        plannedItems = [];
      }
      emit();
    }

    void scheduleRebuildPlanned() {
      if (rebuildPlannedScheduled) return;
      rebuildPlannedScheduled = true;
      Future<void>.delayed(const Duration(milliseconds: 350), () async {
        rebuildPlannedScheduled = false;
        await rebuildPlanned();
      });
    }

    final startOfToday = DateTime.now();
    final today = DateTime(
      startOfToday.year,
      startOfToday.month,
      startOfToday.day,
    );
    final endDate = DateTime(
      today.add(_window).year,
      today.add(_window).month,
      today.add(_window).day,
      23,
      59,
      59,
    );

    final serverSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection(AgendaAlertsQueueService.collectionName)
        .where('status', whereIn: ['pending', 'sent'])
        .orderBy('notifyAt')
        .limit(500)
        .snapshots()
        .listen(
      (snap) {
        serverItems = AgendaAlertsQueueService.onlyActiveQueue(
          snap.docs
              .map(AgendaAlertQueueItem.fromDoc)
              .whereType<AgendaAlertQueueItem>()
              .toList(),
        );
        emit();
      },
      onError: (_) {
        serverItems = [];
        emit();
      },
    );

    final remindersSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('reminders')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(today))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
        .orderBy('date')
        .limit(_kMaxDocsPerCollection)
        .snapshots()
        .listen((_) => scheduleRebuildPlanned(), onError: (_) {});

    final scalesSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('scales')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(today))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
        .orderBy('date')
        .limit(_kMaxDocsPerCollection)
        .snapshots()
        .listen((_) => scheduleRebuildPlanned(), onError: (_) {});

    final settingsSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('notifications')
        .snapshots()
        .listen((_) => scheduleRebuildPlanned(), onError: (_) {});

    unawaited(rebuildPlanned());

    controller.onCancel = () async {
      await serverSub.cancel();
      await remindersSub.cancel();
      await scalesSub.cancel();
      await settingsSub.cancel();
    };

    return controller.stream;
  }
}
