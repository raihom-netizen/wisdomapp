import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../screens/compromisso_form_page.dart';
import 'agenda_notification_reschedule_helper.dart';
import 'agenda_reminder_delete_helper.dart';
import 'agenda_reminder_edit_service.dart';
import 'agenda_scale_mirror_service.dart';
import 'google_calendar_sync_service.dart';
import 'yearly_commitment_repeat_service.dart';

/// Salvar / editar / excluir compromissos particulares (módulo Agenda WISDOMAPP).
class CompromissoReminderService {
  CompromissoReminderService._();

  static CollectionReference<Map<String, dynamic>> _reminders(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('reminders');

  static Future<String?> create({
    required String userDocId,
    required CompromissoFormResult result,
  }) async {
    final timeStr =
        '${result.time.hour.toString().padLeft(2, '0')}:${result.time.minute.toString().padLeft(2, '0')}';
    final endTimeStr =
        '${result.endTime.hour.toString().padLeft(2, '0')}:${result.endTime.minute.toString().padLeft(2, '0')}';

    if (result.repeatYearly) {
      return YearlyCommitmentRepeatService.createWithYearlyRepeat(
        userDocId: userDocId,
        title: result.title,
        notes: result.notes,
        anchorCalendarDay: result.date,
        startHHmm: timeStr,
        endHHmm: endTimeStr,
        colorHex: result.colorHex,
        yearlyRepeatWeekdays: result.yearlyRepeatWeekdays,
      );
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

    unawaited(GoogleCalendarSyncService.syncReminderToGoogle(
      userDocId: userDocId,
      reminderDocId: docRef.id,
      title: result.title,
      notes: result.notes,
      date: result.date,
      timeHHmm: timeStr,
      endTimeHHmm: endTimeStr,
    ));

    return docRef.id;
  }

  static Future<String> update({
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

    unawaited(GoogleCalendarSyncService.syncReminderToGoogle(
      userDocId: userDocId,
      reminderDocId: doc.id,
      title: result.title,
      notes: result.notes,
      date: result.date,
      timeHHmm: timeStr,
      endTimeHHmm: endTimeStr,
    ));

    return msg;
  }

  static Future<void> deleteOne({
    required String userDocId,
    required String reminderDocId,
    String? googleEventId,
  }) async {
    await GoogleCalendarSyncService.deleteGoogleEventForReminder(
      userDocId: userDocId,
      reminderDocId: reminderDocId,
      googleEventId: googleEventId,
    );
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
