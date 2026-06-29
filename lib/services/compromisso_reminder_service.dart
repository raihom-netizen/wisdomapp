import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../screens/compromisso_form_page.dart';
import 'agenda_notification_reschedule_helper.dart';
import 'agenda_notifications_refresher.dart';
import 'agenda_reminder_delete_helper.dart';
import 'agenda_reminder_edit_service.dart';
import 'agenda_scale_mirror_service.dart';
import 'apple_calendar_sync_service.dart';
import 'google_calendar_sync_service.dart';
import 'yearly_commitment_repeat_service.dart';

/// Salvar / editar / excluir compromissos particulares (módulo Agenda WISDOMAPP).
class CompromissoReminderService {
  CompromissoReminderService._();

  static CollectionReference<Map<String, dynamic>> _reminders(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('reminders');

  static Future<({String docId, bool googleSynced, int created})> create({
    required String userDocId,
    required CompromissoFormResult result,
  }) async {
    final days = result.targetDates;
    if (days.length > 1) {
      return createMany(userDocId: userDocId, result: result, dates: days);
    }

    final timeStr =
        '${result.time.hour.toString().padLeft(2, '0')}:${result.time.minute.toString().padLeft(2, '0')}';
    final endTimeStr =
        '${result.endTime.hour.toString().padLeft(2, '0')}:${result.endTime.minute.toString().padLeft(2, '0')}';

    if (result.repeatYearly) {
      final id = await YearlyCommitmentRepeatService.createWithYearlyRepeat(
        userDocId: userDocId,
        title: result.title,
        notes: result.notes,
        anchorCalendarDay: result.date,
        startHHmm: timeStr,
        endHHmm: endTimeStr,
        colorHex: result.colorHex,
        yearlyRepeatWeekdays: result.yearlyRepeatWeekdays,
      );
      return (docId: id, googleSynced: false, created: 1);
    }

    final docRef = await _reminders(userDocId).add({
      'type': 'compromisso',
      'title': result.title,
      'notes': result.notes,
      'date': Timestamp.fromDate(result.date),
      'time': timeStr,
      'endTime': endTimeStr,
      'colorHex': result.colorHex,
      'status': 'EM_ABERTO',
      'done': false,
      'createdAt': FieldValue.serverTimestamp(),
      'agendaLoginDaySyncAt': FieldValue.serverTimestamp(),
    });

    await AgendaScaleMirrorService.upsert(
      userDocId: userDocId,
      agendaId: docRef.id,
      type: AgendaMirrorType.compromisso,
      label: result.title,
      date: result.date,
      startHHmm: timeStr,
      endHHmm: endTimeStr,
      colorHex: result.colorHex,
      notes: result.notes,
    );

    unawaited(AgendaNotificationRescheduleHelper.afterReminderSave(
      userDocId: userDocId,
      reminderRef: docRef,
      newDate: result.date,
      newTimeHHmm: timeStr,
    ));

    var googleSynced = false;
    if (await GoogleCalendarSyncService.isEnabled(userDocId)) {
      await GoogleCalendarSyncService.warmUpIfEnabled(userDocId);
      googleSynced = await GoogleCalendarSyncService.syncReminderToGoogle(
        userDocId: userDocId,
        reminderDocId: docRef.id,
        title: result.title,
        notes: result.notes,
        date: result.date,
        timeHHmm: timeStr,
        endTimeHHmm: endTimeStr,
      );
    }
    if (await AppleCalendarSyncService.isEnabled(userDocId)) {
      unawaited(
        AppleCalendarSyncService.syncReminder(
          userDocId: userDocId,
          reminderDocId: docRef.id,
          title: result.title,
          notes: result.notes,
          date: result.date,
          timeHHmm: timeStr,
          endTimeHHmm: endTimeStr,
        ),
      );
    }

    return (docId: docRef.id, googleSynced: googleSynced, created: 1);
  }

  /// Vários dias com o mesmo título/horário (não usa repetição anual).
  static Future<({String docId, bool googleSynced, int created})> createMany({
    required String userDocId,
    required CompromissoFormResult result,
    required List<DateTime> dates,
  }) async {
    if (userDocId.isEmpty || dates.isEmpty) {
      return (docId: '', googleSynced: false, created: 0);
    }

    final timeStr =
        '${result.time.hour.toString().padLeft(2, '0')}:${result.time.minute.toString().padLeft(2, '0')}';
    final endTimeStr =
        '${result.endTime.hour.toString().padLeft(2, '0')}:${result.endTime.minute.toString().padLeft(2, '0')}';

    const batchLimit = 400;
    final gcalEnabled = await GoogleCalendarSyncService.isEnabled(userDocId);
    if (gcalEnabled) {
      await GoogleCalendarSyncService.warmUpIfEnabled(userDocId);
    }

    final createdRefs = <({DocumentReference<Map<String, dynamic>> ref, DateTime day})>[];
    for (var i = 0; i < dates.length; i += batchLimit) {
      final slice = dates.skip(i).take(batchLimit);
      final batch = FirebaseFirestore.instance.batch();
      for (final rawDay in slice) {
        final day = DateTime(rawDay.year, rawDay.month, rawDay.day);
        final ref = _reminders(userDocId).doc();
        batch.set(ref, {
          'type': 'compromisso',
          'title': result.title,
          'notes': result.notes,
          'date': Timestamp.fromDate(day),
          'time': timeStr,
          'endTime': endTimeStr,
          'colorHex': result.colorHex,
          'status': 'EM_ABERTO',
          'done': false,
          'createdAt': FieldValue.serverTimestamp(),
          'agendaLoginDaySyncAt': FieldValue.serverTimestamp(),
          'batchGroupTitle': result.title,
        });
        createdRefs.add((ref: ref, day: day));
      }
      await batch.commit();
    }

    var synced = 0;
    String? firstId;
    for (var i = 0; i < createdRefs.length; i += 40) {
      final chunk = createdRefs.skip(i).take(40);
      await Future.wait(chunk.map((e) async {
        firstId ??= e.ref.id;
        await AgendaScaleMirrorService.upsert(
          userDocId: userDocId,
          agendaId: e.ref.id,
          type: AgendaMirrorType.compromisso,
          label: result.title,
          date: e.day,
          startHHmm: timeStr,
          endHHmm: endTimeStr,
          colorHex: result.colorHex,
          notes: result.notes,
        );
        unawaited(AgendaNotificationRescheduleHelper.afterReminderSave(
          userDocId: userDocId,
          reminderRef: e.ref,
          newDate: e.day,
          newTimeHHmm: timeStr,
        ));
        if (gcalEnabled) {
          final ok = await GoogleCalendarSyncService.syncReminderToGoogle(
            userDocId: userDocId,
            reminderDocId: e.ref.id,
            title: result.title,
            notes: result.notes,
            date: e.day,
            timeHHmm: timeStr,
            endTimeHHmm: endTimeStr,
          );
          if (ok) synced++;
        }
      }));
    }

    unawaited(AgendaNotificationsRefresher.refresh(uid: userDocId));

    return (
      docId: firstId ?? '',
      googleSynced: synced > 0 && synced == createdRefs.length,
      created: createdRefs.length,
    );
  }

  /// Salva edição de evento que existe só no Google (ou já vinculado por [googleEventId]).
  static Future<void> upsertFromGoogleEvent({
    required String userDocId,
    required String googleEventId,
    required CompromissoFormResult result,
  }) async {
    final timeStr =
        '${result.time.hour.toString().padLeft(2, '0')}:${result.time.minute.toString().padLeft(2, '0')}';
    final endTimeStr =
        '${result.endTime.hour.toString().padLeft(2, '0')}:${result.endTime.minute.toString().padLeft(2, '0')}';

    final linked = await _reminders(userDocId)
        .where('googleEventId', isEqualTo: googleEventId)
        .limit(1)
        .get();

    if (linked.docs.isNotEmpty) {
      await update(
        userDocId: userDocId,
        doc: linked.docs.first,
        result: result,
      );
      return;
    }

    final updated = await GoogleCalendarSyncService.updateGoogleEventById(
      userDocId: userDocId,
      eventId: googleEventId,
      title: result.title,
      notes: result.notes,
      date: result.date,
      timeHHmm: timeStr,
      endTimeHHmm: endTimeStr,
    );
    if (!updated) {
      throw Exception('Não foi possível atualizar no Google Calendar.');
    }

    final docRef = await _reminders(userDocId).add({
      'type': 'compromisso',
      'title': result.title,
      'notes': result.notes,
      'date': Timestamp.fromDate(result.date),
      'time': timeStr,
      'endTime': endTimeStr,
      'colorHex': result.colorHex,
      'status': 'EM_ABERTO',
      'done': false,
      'googleEventId': googleEventId,
      'googleSyncedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'agendaLoginDaySyncAt': FieldValue.serverTimestamp(),
    });

    await AgendaScaleMirrorService.upsert(
      userDocId: userDocId,
      agendaId: docRef.id,
      type: AgendaMirrorType.compromisso,
      label: result.title,
      date: result.date,
      startHHmm: timeStr,
      endHHmm: endTimeStr,
      colorHex: result.colorHex,
      notes: result.notes,
    );

    unawaited(AgendaNotificationRescheduleHelper.afterReminderSave(
      userDocId: userDocId,
      reminderRef: docRef,
      newDate: result.date,
      newTimeHHmm: timeStr,
    ));
  }

  /// Exclui evento Google (e reminder local vinculado, se existir).
  static Future<bool> deleteGoogleOnlyEvent({
    required String userDocId,
    required String googleEventId,
    String? recurringEventId,
    bool tryDeleteEntireSeries = true,
  }) async {
    final linked = await _reminders(userDocId)
        .where('googleEventId', isEqualTo: googleEventId)
        .limit(1)
        .get();

    if (linked.docs.isNotEmpty) {
      await deleteOne(
        userDocId: userDocId,
        reminderDocId: linked.docs.first.id,
        googleEventId: googleEventId,
        recurringEventId: recurringEventId,
        tryDeleteEntireSeries: tryDeleteEntireSeries,
      );
      return true;
    }

    return GoogleCalendarSyncService.removeGoogleEventFromAgenda(
      userDocId: userDocId,
      eventId: googleEventId,
      recurringEventId: recurringEventId,
      tryDeleteEntireSeries: tryDeleteEntireSeries,
    );
  }

  static Future<({String message, bool googleSynced})> update({
    required String userDocId,
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required CompromissoFormResult result,
  }) async {
    final msg = await AgendaReminderEditService.persistCompromissoEdit(
      doc: doc,
      result: result,
      userDocId: userDocId,
    );

    final timeStr =
        '${result.time.hour.toString().padLeft(2, '0')}:${result.time.minute.toString().padLeft(2, '0')}';
    final endTimeStr =
        '${result.endTime.hour.toString().padLeft(2, '0')}:${result.endTime.minute.toString().padLeft(2, '0')}';

    var googleSynced = false;
    if (await GoogleCalendarSyncService.isEnabled(userDocId)) {
      await GoogleCalendarSyncService.warmUpIfEnabled(userDocId);
      googleSynced = await GoogleCalendarSyncService.syncReminderToGoogle(
        userDocId: userDocId,
        reminderDocId: doc.id,
        title: result.title,
        notes: result.notes,
        date: result.date,
        timeHHmm: timeStr,
        endTimeHHmm: endTimeStr,
      );
    }

    return (message: msg, googleSynced: googleSynced);
  }

  static Future<void> deleteOne({
    required String userDocId,
    required String reminderDocId,
    String? googleEventId,
    String? recurringEventId,
    bool tryDeleteEntireSeries = true,
  }) async {
    var eventId = (googleEventId ?? '').trim();
    if (eventId.isEmpty) {
      final snap = await _reminders(userDocId).doc(reminderDocId).get();
      eventId = (snap.data()?['googleEventId'] ?? '').toString().trim();
    }
    if (eventId.isNotEmpty) {
      await GoogleCalendarSyncService.removeGoogleEventFromAgenda(
        userDocId: userDocId,
        eventId: eventId,
        recurringEventId: recurringEventId,
        tryDeleteEntireSeries: tryDeleteEntireSeries,
      );
    }
    await deleteAgendaReminderCore(
      userDocId: userDocId,
      reminderDocId: reminderDocId,
      isAudiencia: false,
    );
  }

  static Future<int> clearDay({
    required BuildContext context,
    required String userDocId,
    required DateTime day,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    bool skipConfirm = false,
  }) async {
    if (docs.isEmpty) return 0;
    if (!skipConfirm) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Limpar dia?'),
          content: Text(
            'Remover todos os compromissos particulares do dia '
            '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Limpar'),
            ),
          ],
        ),
      );
      if (confirm != true) return 0;
    }

    var n = 0;
    for (final doc in docs) {
      final data = doc.data();
      await GoogleCalendarSyncService.deleteGoogleEventForReminder(
        userDocId: userDocId,
        reminderDocId: doc.id,
        googleEventId: (data['googleEventId'] ?? '').toString(),
      );
      final ok = await deleteAgendaReminderCore(
        userDocId: userDocId,
        reminderDocId: doc.id,
        isAudiencia: false,
      );
      if (ok) n++;
    }
    return n;
  }

  /// Limpeza em massa — compromissos particulares (Firestore em batch + espelhos).
  static Future<int> clearCompromissosBulk({
    required String userDocId,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  }) async {
    if (userDocId.isEmpty || docs.isEmpty) return 0;

    const batchLimit = 450;
    var removed = 0;
    final googleTasks = <Future<void>>[];

    for (var i = 0; i < docs.length; i += batchLimit) {
      final slice = docs.skip(i).take(batchLimit).toList();
      final batch = FirebaseFirestore.instance.batch();
      final mirrorDeletes = <Future<void>>[];
      final yearlyDeletes = <Future<void>>[];

      for (final doc in slice) {
        final data = doc.data();
        if (!isCompromissoDoc(data)) continue;

        if (YearlyCommitmentRepeatService.isYearlyRepeatEntry(data)) {
          yearlyDeletes.add(
            YearlyCommitmentRepeatService.deleteYearlyInstanceOnly(
              userDocId: userDocId,
              instanceReminderDocId: doc.id,
              instanceData: data,
            ),
          );
          removed++;
          continue;
        }

        final gId = (data['googleEventId'] ?? '').toString().trim();
        if (gId.isNotEmpty) {
          googleTasks.add(
            GoogleCalendarSyncService.deleteGoogleEventForReminder(
              userDocId: userDocId,
              reminderDocId: doc.id,
              googleEventId: gId,
            ),
          );
        }

        batch.delete(doc.reference);
        mirrorDeletes.add(
          AgendaScaleMirrorService.delete(
            userDocId: userDocId,
            agendaId: doc.id,
          ),
        );
        removed++;
      }

      if (mirrorDeletes.isNotEmpty) {
        await batch.commit();
        await Future.wait(mirrorDeletes);
      }
      if (yearlyDeletes.isNotEmpty) {
        await Future.wait(yearlyDeletes);
      }
    }

    if (googleTasks.isNotEmpty) {
      unawaited(Future.wait(googleTasks));
    }
    unawaited(AgendaNotificationsRefresher.refresh(uid: userDocId));
    return removed;
  }

  /// Busca compromissos particulares num intervalo (query indexada type+date).
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> fetchCompromissosInRange({
    required String userDocId,
    required DateTime start,
    required DateTime end,
  }) async {
    if (userDocId.isEmpty) return const [];
    final endEod = DateTime(end.year, end.month, end.day, 23, 59, 59);
    final snap = await _reminders(userDocId)
        .where('type', isEqualTo: 'compromisso')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endEod))
        .orderBy('date')
        .get();
    return snap.docs
        .where((d) => YearlyCommitmentRepeatService.shouldShowInAgendaList(
              d.data(),
              docId: d.id,
            ))
        .toList(growable: false);
  }

  static bool isCompromissoDoc(Map<String, dynamic> data) {
    final t = (data['type'] ?? 'compromisso').toString().toLowerCase();
    return t == 'compromisso';
  }

  static DateTime? dateFromDoc(Map<String, dynamic> data) {
    final raw = data['date'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }

  static bool hasActiveLicense(UserProfile profile) => profile.hasActiveLicense;
}
