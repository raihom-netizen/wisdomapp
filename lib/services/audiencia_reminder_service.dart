import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../constants/field_text_limits.dart';
import '../screens/audiencia_form_page.dart';
import 'agenda_notification_reschedule_helper.dart';
import 'agenda_reminder_edit_service.dart';
import 'agenda_scale_mirror_service.dart';
import 'audiencia_oficio_upload_service.dart';

/// Salvar / editar audiências (módulo Agenda WISDOMAPP).
class AudienciaReminderService {
  AudienciaReminderService._();

  static CollectionReference<Map<String, dynamic>> _reminders(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('reminders');

  static String _hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static Future<void> _applyOficio(AudienciaFormResult result, {
    required String userDocId,
    required String reminderDocId,
  }) {
    return AudienciaOficioUploadService.applyChange(
      userDocId: userDocId,
      reminderDocId: reminderDocId,
      removeOficio: result.removeOficio,
      bytes: result.oficioBytes,
      fileName: result.oficioFileName,
      mime: result.oficioMime,
      extension: result.oficioExtension,
    );
  }

  static Future<String> create({
    required String userDocId,
    required AudienciaFormResult result,
  }) async {
    final timeStr = _hhmm(result.time);
    final endTimeStr = _hhmm(result.endTime);
    final sei = result.numeroSei.trim();
    final oco = result.numeroOcorrencia.trim();
    final relato = normalizeAudienciaRelatoForSave(result.resumoRelato);

    final docRef = await _reminders(userDocId).add({
      'type': 'audiencia',
      'title': 'Audiência',
      'numeroSei': sei,
      'numeroOcorrencia': oco,
      'resumoRelato': relato,
      'localAudiencia': result.localAudiencia.trim(),
      'linkSalaAudiencia': result.linkSalaAudiencia.trim(),
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
      type: AgendaMirrorType.audiencia,
      label: 'Audiência',
      date: result.date,
      startHHmm: timeStr,
      endHHmm: endTimeStr,
      colorHex: result.colorHex,
      notes: relato,
      numeroSei: sei,
      numeroOcorrencia: oco,
    );

    unawaited(AgendaNotificationRescheduleHelper.afterReminderSave(
      userDocId: userDocId,
      reminderRef: docRef,
      newDate: result.date,
      newTimeHHmm: timeStr,
    ));

    await _applyOficio(result,
        userDocId: userDocId, reminderDocId: docRef.id);

    return docRef.id;
  }

  static Future<String> update({
    required String userDocId,
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required AudienciaFormResult result,
  }) {
    return AgendaReminderEditService.persistAudienciaEdit(
      doc: doc,
      result: result,
      userDocId: userDocId,
    );
  }
}
