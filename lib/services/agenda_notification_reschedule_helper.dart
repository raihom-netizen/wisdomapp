import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/agenda_delivery_reset.dart';
import 'agenda_alerts_migration_service.dart';
import 'agenda_notifications_refresher.dart';

/// Reprogramação automática de push/e-mail — só quando data/hora ou antecedências mudam.
/// Conteúdo (SEI, observação, título) não recria a fila no servidor (cron mantém pending).
class AgendaNotificationRescheduleHelper {
  AgendaNotificationRescheduleHelper._();

  static Map<String, dynamic> _queueTouchFields() {
    return {
      'agendaLoginDaySyncAt': FieldValue.serverTimestamp(),
      'agendaQueueTouchedAt': FieldValue.serverTimestamp(),
      'agendaNotifResyncAt': FieldValue.serverTimestamp(),
      'agendaNotifMigratedV': AgendaAlertsMigrationService.kMigrationVersion,
      'agendaNotifMigratedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Após salvar **audiência/compromisso** (`reminders`).
  static Future<void> afterReminderSave({
    required String userDocId,
    required DocumentReference<Map<String, dynamic>> reminderRef,
    Map<String, dynamic>? beforeData,
    DateTime? newDate,
    String? newTimeHHmm,
    Map<String, dynamic>? afterPlanSnapshot,
  }) async {
    if (userDocId.isEmpty) return;

    var reprogrammed = beforeData == null;
    final patch = <String, dynamic>{};

    if (beforeData == null) {
      patch.addAll(_queueTouchFields());
      patch.addAll(AgendaDeliveryReset.reopenReminderAfterScheduleChange());
      reprogrammed = true;
    } else {
      var scheduleChanged = false;
      if (newDate != null && newTimeHHmm != null) {
        scheduleChanged = AgendaDeliveryReset.reminderScheduleChanged(
          beforeData,
          newDate,
          newTimeHHmm,
        );
      }
      final notifyChanged = afterPlanSnapshot != null &&
          AgendaDeliveryReset.reminderNotifyPlanChanged(
            beforeData,
            afterPlanSnapshot,
          );
      if (scheduleChanged || notifyChanged) {
        patch.addAll(_queueTouchFields());
        patch.addAll(AgendaDeliveryReset.reopenReminderAfterScheduleChange());
        reprogrammed = true;
      }
    }

    if (!reprogrammed) return;

    try {
      await reminderRef.set(patch, SetOptions(merge: true));
    } catch (_) {}

    unawaited(AgendaNotificationsRefresher.refresh(uid: userDocId));
  }

  /// Após salvar **plantão/compromisso na escala** (`scales`, não espelho agenda_*).
  static Future<void> afterScaleSave({
    required String userDocId,
    required DocumentReference<Map<String, dynamic>> scaleRef,
    Map<String, dynamic>? beforeData,
    DateTime? newDate,
    String? newStartHHmm,
    Map<String, dynamic>? afterPlanSnapshot,
  }) async {
    if (userDocId.isEmpty) return;
    final id = scaleRef.id;
    if (id.startsWith('agenda_')) return;

    var reprogrammed = beforeData == null;
    final patch = <String, dynamic>{};

    if (beforeData == null) {
      patch.addAll(_queueTouchFields());
      patch.addAll(
        AgendaDeliveryReset.clearDeliveryFields(includeScaleNotificado: true),
      );
      reprogrammed = true;
    } else {
      var scheduleChanged = false;
      if (newDate != null && newStartHHmm != null) {
        scheduleChanged = AgendaDeliveryReset.scaleScheduleChanged(
          beforeData,
          newDate,
          newStartHHmm,
        );
      }
      final notifyChanged = afterPlanSnapshot != null &&
          AgendaDeliveryReset.scaleNotifyPlanChanged(
            beforeData,
            afterPlanSnapshot,
          );
      if (scheduleChanged || notifyChanged) {
        patch.addAll(_queueTouchFields());
        patch.addAll(
          AgendaDeliveryReset.clearDeliveryFields(includeScaleNotificado: true),
        );
        reprogrammed = true;
      }
    }

    if (!reprogrammed) return;

    try {
      await scaleRef.set(patch, SetOptions(merge: true));
    } catch (_) {}

    unawaited(AgendaNotificationsRefresher.refresh(uid: userDocId));
  }

  /// Compatível com chamadas antigas — preferir [afterReminderSave] / [afterScaleSave].
  static Future<void> afterItemChanged({
    required String userDocId,
    DocumentReference<Map<String, dynamic>>? reminderRef,
    DocumentReference<Map<String, dynamic>>? scaleRef,
    bool queueRebuild = false,
    Map<String, dynamic>? beforeData,
    DateTime? eventDate,
    String? eventTimeHHmm,
    Map<String, dynamic>? afterPlanSnapshot,
    bool isScale = false,
  }) async {
    if (reminderRef != null) {
      await afterReminderSave(
        userDocId: userDocId,
        reminderRef: reminderRef,
        beforeData: beforeData,
        newDate: eventDate,
        newTimeHHmm: eventTimeHHmm,
        afterPlanSnapshot: afterPlanSnapshot,
      );
      return;
    }
    if (scaleRef != null) {
      await afterScaleSave(
        userDocId: userDocId,
        scaleRef: scaleRef,
        beforeData: beforeData,
        newDate: eventDate,
        newStartHHmm: eventTimeHHmm,
        afterPlanSnapshot: afterPlanSnapshot,
      );
    } else if (queueRebuild && userDocId.isNotEmpty) {
      unawaited(AgendaNotificationsRefresher.refresh(uid: userDocId));
    }
  }
}
