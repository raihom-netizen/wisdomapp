import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/agenda_delivery_reset.dart';
import '../utils/agenda_reminder_end_of_day.dart';
import 'agenda_alerts_queue_repair_service.dart';
import 'agenda_login_day_sync.dart';
import 'agenda_notifications_refresher.dart';
import 'yearly_commitment_repeat_service.dart';

/// Migra audiências, compromissos e plantões abertos para a fila `agendaAlerts`
/// (Configurações > Pendentes e confirmadas). Roda uma vez por versão no login.
class AgendaAlertsMigrationService {
  AgendaAlertsMigrationService._();

  /// v5: inclui hoje — ao criar/editar entra na fila no mesmo dia.
  static const int kMigrationVersion = 5;

  static const Duration _kWindow = Duration(days: 60);

  static Future<AgendaAlertsMigrationResult> runIfNeeded(
    String uid, {
    bool skipFollowUp = false,
  }) async {
    if (uid.isEmpty) {
      return const AgendaAlertsMigrationResult(skipped: true);
    }

    try {
      final userSnap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final userV = userSnap.data()?['agendaNotifUserMigratedV'];
      if (userV is num && userV.toInt() >= kMigrationVersion) {
        return const AgendaAlertsMigrationResult(skipped: true);
      }
    } catch (_) {}

    final now = DateTime.now();
    final startFrom = DateTime(now.year, now.month, now.day);
    final endDate = _windowEnd(startFrom);

    var remindersMigrated = 0;
    var scalesMigrated = 0;

    try {
      final remindersSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('reminders')
          .where('date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startFrom))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .orderBy('date')
          .limit(600)
          .get();

      remindersMigrated = await _migrateReminderDocs(remindersSnap.docs, now);

      final scalesSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('scales')
          .where('date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startFrom))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .orderBy('date')
          .limit(600)
          .get();

      scalesMigrated = await _migrateScaleDocs(scalesSnap.docs, now);
    } catch (_) {}

    if (remindersMigrated == 0 && scalesMigrated == 0) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'agendaNotifUserMigratedV': kMigrationVersion,
          'agendaNotifUserMigratedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {}
    }

    final queueRepair =
        await AgendaAlertsQueueRepairService.repairFuturePendingFromToday(uid);

    if (!skipFollowUp) {
      await AgendaLoginDaySync.runOnLogin(uid);
      await AgendaNotificationsRefresher.refresh(uid: uid);
    }

    return AgendaAlertsMigrationResult(
      remindersMigrated: remindersMigrated,
      scalesMigrated: scalesMigrated,
      queueRepair: queueRepair,
    );
  }

  /// Força migração de todos os abertos (botão na fila) — ignora versão no doc.
  static Future<AgendaAlertsMigrationResult> runFullRebuild(String uid) async {
    if (uid.isEmpty) {
      return const AgendaAlertsMigrationResult(skipped: true);
    }

    final now = DateTime.now();
    final startFrom = DateTime(now.year, now.month, now.day);
    final endDate = _windowEnd(startFrom);

    var remindersMigrated = 0;
    var scalesMigrated = 0;

    try {
      final remindersSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('reminders')
          .where('date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startFrom))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .orderBy('date')
          .limit(600)
          .get();

      remindersMigrated =
          await _touchReminderDocs(remindersSnap.docs, now, force: true);

      final scalesSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('scales')
          .where('date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startFrom))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .orderBy('date')
          .limit(600)
          .get();

      scalesMigrated = await _touchScaleDocs(scalesSnap.docs, now, force: true);
    } catch (_) {}

    final queueRepair =
        await AgendaAlertsQueueRepairService.repairFuturePendingFromToday(uid);

    await AgendaLoginDaySync.runOnLogin(uid);
    await AgendaNotificationsRefresher.refresh(uid: uid);

    return AgendaAlertsMigrationResult(
      remindersMigrated: remindersMigrated,
      scalesMigrated: scalesMigrated,
      forced: true,
      queueRepair: queueRepair,
    );
  }

  static Future<int> _migrateReminderDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    DateTime now,
  ) =>
      _touchReminderDocs(docs, now, force: false);

  static DateTime _windowEnd(DateTime startOfToday) => DateTime(
        startOfToday.add(_kWindow).year,
        startOfToday.add(_kWindow).month,
        startOfToday.add(_kWindow).day,
        23,
        59,
        59,
      );

  static Map<String, dynamic> _futureModelSyncPatch() => {
        ...AgendaDeliveryReset.clearDeliveryFields(),
        'agendaNotifMigratedV': kMigrationVersion,
        'agendaNotifMigratedAt': FieldValue.serverTimestamp(),
        'agendaLoginDaySyncAt': FieldValue.serverTimestamp(),
        'agendaQueueTouchedAt': FieldValue.serverTimestamp(),
        'agendaNotifResyncAt': FieldValue.serverTimestamp(),
      };

  static Future<int> _touchReminderDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    DateTime now, {
    required bool force,
  }) async {
    var count = 0;
    var batch = FirebaseFirestore.instance.batch();
    var ops = 0;

    for (final doc in docs) {
      final d = doc.data();
      if (!YearlyCommitmentRepeatService.shouldShowInAgendaList(d, docId: doc.id)) {
        continue;
      }
      if (!agendaReminderEligibleForNotifySchedule(d, now)) continue;
      if (!force) {
        final v = d['agendaNotifMigratedV'];
        if (v is num && v.toInt() >= kMigrationVersion) continue;
      }
      batch.update(doc.reference, _futureModelSyncPatch());
      count++;
      ops++;
      if (ops >= 400) {
        await batch.commit();
        batch = FirebaseFirestore.instance.batch();
        ops = 0;
      }
    }
    if (ops > 0) await batch.commit();
    return count;
  }

  static Future<int> _migrateScaleDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    DateTime now,
  ) =>
      _touchScaleDocs(docs, now, force: false);

  static Future<int> _touchScaleDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    DateTime now, {
    required bool force,
  }) async {
    var count = 0;
    var batch = FirebaseFirestore.instance.batch();
    var ops = 0;

    for (final doc in docs) {
      final d = doc.data();
      if (!agendaScaleFutureEventForNotify(d, now)) continue;
      if (!force) {
        final v = d['agendaNotifMigratedV'];
        if (v is num && v.toInt() >= kMigrationVersion) continue;
      }
      batch.update(
        doc.reference,
        {
          ..._futureModelSyncPatch(),
          'notificado': FieldValue.delete(),
        },
      );
      count++;
      ops++;
      if (ops >= 400) {
        await batch.commit();
        batch = FirebaseFirestore.instance.batch();
        ops = 0;
      }
    }
    if (ops > 0) await batch.commit();
    return count;
  }
}

class AgendaAlertsMigrationResult {
  const AgendaAlertsMigrationResult({
    this.remindersMigrated = 0,
    this.scalesMigrated = 0,
    this.skipped = false,
    this.forced = false,
    this.queueRepair,
  });

  final int remindersMigrated;
  final int scalesMigrated;
  final bool skipped;
  final bool forced;
  final AgendaAlertsQueueRepairResult? queueRepair;

  int get total => remindersMigrated + scalesMigrated;
  int get queueRepaired => queueRepair?.repaired ?? 0;
  bool get didWork => total > 0 || (queueRepair?.didWork ?? false);
}
