import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/field_text_limits.dart';
import '../screens/audiencia_form_page.dart';
import '../screens/compromisso_form_page.dart';
import 'audiencia_oficio_upload_service.dart';
import '../utils/agenda_delivery_reset.dart';
import 'agenda_notification_reschedule_helper.dart';
import 'agenda_scale_mirror_service.dart';
import 'yearly_commitment_repeat_service.dart';

/// Persistência compartilhada entre Agenda e edição de espelhos em Escalas.
class AgendaReminderEditService {
  AgendaReminderEditService._();

  static Future<String> persistCompromissoEdit({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required CompromissoFormResult result,
    required String userDocId,
  }) async {
    final beforeEdit = Map<String, dynamic>.from(doc.data());
    final timeStrSave =
        '${result.time.hour.toString().padLeft(2, '0')}:${result.time.minute.toString().padLeft(2, '0')}';
    final endTimeStrSave =
        '${result.endTime.hour.toString().padLeft(2, '0')}:${result.endTime.minute.toString().padLeft(2, '0')}';
    final scheduleChanged = AgendaDeliveryReset.reminderScheduleChanged(
      beforeEdit,
      result.date,
      timeStrSave,
    );

    final wasYearly = beforeEdit['repeatYearly'] == true ||
        beforeEdit['isYearlyRepeatTemplate'] == true ||
        (beforeEdit['yearlyRepeatTemplateId'] ?? '').toString().trim().isNotEmpty;
    final templateId =
        YearlyCommitmentRepeatService.templateIdFromReminderData(
              beforeEdit,
              doc.id,
            ) ??
            doc.id;

    if (result.repeatYearly) {
      await YearlyCommitmentRepeatService.updateYearlySeries(
        userDocId: userDocId,
        templateId: templateId,
        title: result.title,
        notes: YearlyCommitmentRepeatService.mergeUserNotesWithYearlyLine(
          userNotes: result.notes,
          month: result.date.month,
          day: result.date.day,
        ),
        anchorCalendarDay: result.date,
        startHHmm: timeStrSave,
        endHHmm: endTimeStrSave,
        colorHex: result.colorHex,
        yearlyRepeatWeekdays: result.yearlyRepeatWeekdays,
      );
      return 'Compromisso anual atualizado — calendário limpo nas datas antigas, anos futuros recriados e notificações reprogramadas automaticamente.';
    }

    final isYearlyInstance =
        YearlyCommitmentRepeatService.isYearlyInstanceDocId(doc.id) ||
            YearlyCommitmentRepeatService.instanceYearFromData(
                  beforeEdit,
                  docId: doc.id,
                ) !=
                null;

    var detachedYearlyInstance = false;

    if (wasYearly && isYearlyInstance && !result.repeatYearly) {
      await YearlyCommitmentRepeatService.deleteYearlyInstanceOnly(
        userDocId: userDocId,
        instanceReminderDocId: doc.id,
        instanceData: beforeEdit,
      );
      detachedYearlyInstance = true;
    } else if (wasYearly) {
      await YearlyCommitmentRepeatService.deleteYearlySeries(
        userDocId: userDocId,
        templateId: templateId,
      );
    }

    final payload = <String, dynamic>{
      'title': result.title,
      'notes': result.notes,
      'date': Timestamp.fromDate(result.date),
      'time': timeStrSave,
      'endTime': endTimeStrSave,
      'colorHex': result.colorHex,
      'repeatYearly': false,
      'isYearlyRepeatTemplate': false,
      'yearlyRepeatTemplateId': FieldValue.delete(),
      'yearlyRepeatInstanceYear': FieldValue.delete(),
      'yearlyRepeatMonth': FieldValue.delete(),
      'yearlyRepeatDay': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
      'reminderLeads': FieldValue.delete(),
      'notificationSoundId': FieldValue.delete(),
      'notificationDeliveryMode': FieldValue.delete(),
    };
    final afterPlan = Map<String, dynamic>.from(beforeEdit)..addAll(payload);
    final deliveryReset = scheduleChanged ||
        AgendaDeliveryReset.reminderNotifyPlanChanged(beforeEdit, afterPlan);

    final targetRef = (wasYearly && !detachedYearlyInstance)
        ? FirebaseFirestore.instance
            .collection('users')
            .doc(userDocId)
            .collection('reminders')
            .doc()
        : (detachedYearlyInstance
            ? FirebaseFirestore.instance
                .collection('users')
                .doc(userDocId)
                .collection('reminders')
                .doc()
            : doc.reference);
    if (wasYearly || detachedYearlyInstance) {
      payload['type'] = 'compromisso';
      payload['status'] = 'EM_ABERTO';
      payload['done'] = false;
      payload['createdAt'] = FieldValue.serverTimestamp();
      await targetRef.set(payload);
    } else {
      await doc.reference.update(payload);
    }

    final agendaId = (wasYearly || detachedYearlyInstance) ? targetRef.id : doc.id;
    await AgendaScaleMirrorService.upsert(
      userDocId: userDocId,
      agendaId: agendaId,
      type: AgendaMirrorType.compromisso,
      label: result.title,
      date: result.date,
      startHHmm: timeStrSave,
      endHHmm: endTimeStrSave,
      colorHex: result.colorHex,
      notes: result.notes,
    );
    await AgendaNotificationRescheduleHelper.afterReminderSave(
      userDocId: userDocId,
      reminderRef: targetRef,
      beforeData: beforeEdit,
      newDate: result.date,
      newTimeHHmm: timeStrSave,
      afterPlanSnapshot: afterPlan,
    );
    return deliveryReset
        ? (detachedYearlyInstance
            ? 'Compromisso deste ano separado da série. Calendário e notificações reprogramados automaticamente.'
            : 'Compromisso atualizado. Notificações reprogramadas automaticamente para o novo dia/horário.')
        : (detachedYearlyInstance
            ? 'Compromisso deste ano separado da série.'
            : 'Compromisso atualizado.');
  }

  static Future<String> persistAudienciaEdit({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required AudienciaFormResult result,
    required String userDocId,
  }) async {
    final beforeEdit = Map<String, dynamic>.from(doc.data());
    final timeStrSave =
        '${result.time.hour.toString().padLeft(2, '0')}:${result.time.minute.toString().padLeft(2, '0')}';
    final endTimeStrSave =
        '${result.endTime.hour.toString().padLeft(2, '0')}:${result.endTime.minute.toString().padLeft(2, '0')}';
    final scheduleChanged = AgendaDeliveryReset.reminderScheduleChanged(
      beforeEdit,
      result.date,
      timeStrSave,
    );

    final sei = result.numeroSei.trim();
    final oco = result.numeroOcorrencia.trim();
    final relato = normalizeAudienciaRelatoForSave(result.resumoRelato);

    final payload = <String, dynamic>{
      'type': 'audiencia',
      'title': 'Audiência',
      'numeroSei': sei,
      'numeroOcorrencia': oco,
      'resumoRelato': relato,
      'localAudiencia': result.localAudiencia.trim(),
      'linkSalaAudiencia': result.linkSalaAudiencia.trim(),
      'date': Timestamp.fromDate(result.date),
      'time': timeStrSave,
      'endTime': endTimeStrSave,
      'colorHex': result.colorHex,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final afterPlan = Map<String, dynamic>.from(beforeEdit)..addAll(payload);
    final deliveryReset = scheduleChanged ||
        AgendaDeliveryReset.reminderNotifyPlanChanged(beforeEdit, afterPlan);

    await doc.reference.update(payload);

    await AgendaScaleMirrorService.upsert(
      userDocId: userDocId,
      agendaId: doc.id,
      type: AgendaMirrorType.audiencia,
      label: 'Audiência',
      date: result.date,
      startHHmm: timeStrSave,
      endHHmm: endTimeStrSave,
      colorHex: result.colorHex,
      notes: relato,
      numeroSei: sei,
      numeroOcorrencia: oco,
    );
    await AgendaNotificationRescheduleHelper.afterReminderSave(
      userDocId: userDocId,
      reminderRef: doc.reference,
      beforeData: beforeEdit,
      newDate: result.date,
      newTimeHHmm: timeStrSave,
      afterPlanSnapshot: afterPlan,
    );

    await AudienciaOficioUploadService.applyChange(
      userDocId: userDocId,
      reminderDocId: doc.id,
      removeOficio: result.removeOficio,
      bytes: result.oficioBytes,
      fileName: result.oficioFileName,
      mime: result.oficioMime,
      extension: result.oficioExtension,
    );

    return deliveryReset
        ? 'Audiência atualizada. Notificações reprogramadas automaticamente para o novo dia/horário.'
        : 'Audiência atualizada.';
  }
}
