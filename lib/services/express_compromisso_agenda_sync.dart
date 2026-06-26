import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/scale_entry.dart';
import '../utils/agenda_delivery_reset.dart';
import 'agenda_notification_reschedule_helper.dart';
import 'agenda_notifications_refresher.dart';
import 'agenda_reminder_delete_helper.dart';
import '../models/scale_entry.dart';
import 'agenda_scale_mirror_service.dart';
import 'produtividade_scale_mirror_service.dart';

/// Item de compromisso para geração automática em série (Escalas).
class GeracaoAutomaticaCompromissoItem {
  final DateTime date;
  final String startHHmm;
  final String endHHmm;
  final String title;
  final String colorHex;

  const GeracaoAutomaticaCompromissoItem({
    required this.date,
    required this.startHHmm,
    required this.endHHmm,
    required this.title,
    required this.colorHex,
  });
}

/// Integra **compromisso particular** do lançamento expresso (painel / Escalas)
/// com o módulo Agenda (`reminders`) + espelho no calendário (`scales`).
///
/// Fonte única para «em aberto» no painel e na Agenda; Escalas continua vendo
/// o item no calendário via espelho `agenda_{reminderId}`.
class ExpressCompromissoAgendaSync {
  ExpressCompromissoAgendaSync._();

  static const _agendaPrefix = 'agenda_';

  static String scaleDocId(String reminderId) => '$_agendaPrefix$reminderId';

  /// ID do doc em `reminders` a partir do espelho em `scales`.
  static String? reminderIdFromScaleDocId(String? scaleDocId) {
    if (scaleDocId == null || scaleDocId.isEmpty) return null;
    if (!scaleDocId.startsWith(_agendaPrefix)) return null;
    final id = scaleDocId.substring(_agendaPrefix.length);
    return id.isEmpty ? null : id;
  }

  /// Espelho Agenda, compromisso expresso ou doc `agenda_*` — exclusão deve sincronizar módulos.
  static bool scaleEntryLinksToAgenda(ScaleEntry e) {
    if (ProdutividadeScaleMirrorService.isProdutividadeFolgaEntry(e)) {
      return false;
    }
    if (e.isAgendaMirror) return true;
    final id = e.id ?? '';
    if (id.startsWith(_agendaPrefix)) return true;
    final src = (e.source ?? '').trim();
    if (src.startsWith(_agendaPrefix)) return true;
    final tipo = (e.agendaType ?? '').trim();
    if (tipo == 'audiencia' || tipo == 'compromisso') return true;
    if (e.isCompromisso) return true;
    return false;
  }

  /// Exclui da Escalas e, se vinculado, remove também na Agenda (+ anexos de audiência).
  static Future<void> deleteScaleWithAgendaSync({
    required String userDocId,
    required ScaleEntry entry,
  }) async {
    final scaleDocId = entry.id?.trim() ?? '';
    if (userDocId.isEmpty || scaleDocId.isEmpty) return;
    if (scaleEntryLinksToAgenda(entry)) {
      await deleteLinkedFromScaleDoc(
        userDocId: userDocId,
        scaleDocId: scaleDocId,
      );
      refreshNotifications(userDocId);
    } else {
      try {
        await _scales(userDocId, scaleDocId).delete();
      } catch (_) {}
      refreshNotifications(userDocId);
    }
  }

  static CollectionReference<Map<String, dynamic>> _reminders(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('reminders');

  static DocumentReference<Map<String, dynamic>> _scales(
    String uid,
    String scaleId,
  ) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('scales')
          .doc(scaleId);

  /// Grava/atualiza compromisso na Agenda e espelha em Escalas.
  ///
  /// Retorna o ID do documento em `reminders`.
  static Future<String> upsertFromExpress({
    required String userDocId,
    required String title,
    required DateTime date,
    required String startHHmm,
    required String endHHmm,
    required String colorHex,
    String notes = '',
    String? existingScaleDocId,
    List<int>? reminderLeads,
    String? notificationSoundId,
    String? notificationDeliveryMode,
  }) async {
    if (userDocId.isEmpty) return '';

    final linked = reminderIdFromScaleDocId(existingScaleDocId);
    final reminderRef = linked != null
        ? _reminders(userDocId).doc(linked)
        : _reminders(userDocId).doc();
    final reminderId = reminderRef.id;

    Map<String, dynamic>? beforeData;
    if (linked != null) {
      try {
        beforeData = (await reminderRef.get()).data();
      } catch (_) {}
    }

    final payload = <String, dynamic>{
      'type': 'compromisso',
      'agendaKind': 'compromisso_particular',
      'isPlantaoEscala': false,
      'title': title.trim().isEmpty ? 'Compromisso' : title.trim(),
      'notes': notes,
      'date': Timestamp.fromDate(
        DateTime(date.year, date.month, date.day),
      ),
      'time': startHHmm,
      'endTime': endHHmm,
      'colorHex': colorHex,
      'status': 'EM_ABERTO',
      'done': false,
      'source': 'lancamento_expresso',
      'lancamentoOrigem': 'lancamento_expresso',
      'updatedAt': FieldValue.serverTimestamp(),
    };
    payload['reminderLeads'] = FieldValue.delete();
    payload['notificationSoundId'] = FieldValue.delete();
    payload['notificationDeliveryMode'] = FieldValue.delete();
    if (linked == null) {
      payload['createdAt'] = FieldValue.serverTimestamp();
    }
    payload['agendaLoginDaySyncAt'] = FieldValue.serverTimestamp();

    if (beforeData != null &&
        AgendaDeliveryReset.reminderScheduleChanged(
          beforeData,
          date,
          startHHmm,
        )) {
      payload.addAll(AgendaDeliveryReset.reopenReminderAfterScheduleChange());
    } else if (beforeData != null) {
      final afterPlan = Map<String, dynamic>.from(beforeData)..addAll(payload);
      if (AgendaDeliveryReset.reminderNotifyPlanChanged(beforeData, afterPlan)) {
        payload.addAll(AgendaDeliveryReset.clearDeliveryFields());
        payload['status'] = 'EM_ABERTO';
        payload['done'] = false;
      }
    }

    await reminderRef.set(payload, SetOptions(merge: true));

    await AgendaScaleMirrorService.upsert(
      userDocId: userDocId,
      agendaId: reminderId,
      type: AgendaMirrorType.compromisso,
      label: payload['title'] as String,
      date: date,
      startHHmm: startHHmm,
      endHHmm: endHHmm,
      colorHex: colorHex,
      notes: notes,
      createdByLancamentoExpresso: true,
    );

    // Compromisso antigo só em `scales` (sem espelho agenda_*): remove duplicata.
    if (existingScaleDocId != null &&
        existingScaleDocId.isNotEmpty &&
        linked == null &&
        existingScaleDocId != scaleDocId(reminderId)) {
      try {
        await _scales(userDocId, existingScaleDocId).delete();
      } catch (_) {}
    }

    await AgendaNotificationRescheduleHelper.afterReminderSave(
      userDocId: userDocId,
      reminderRef: reminderRef,
      beforeData: beforeData,
      newDate: date,
      newTimeHHmm: startHHmm,
      afterPlanSnapshot: payload,
    );

    return reminderId;
  }

  /// Remove Agenda + espelho ao excluir da Escalas (ou limpar dia).
  static Future<void> deleteLinkedFromScaleDoc({
    required String userDocId,
    required String scaleDocId,
  }) async {
    if (userDocId.isEmpty || scaleDocId.isEmpty) return;

    final reminderId = reminderIdFromScaleDocId(scaleDocId);
    if (reminderId != null) {
      await _deleteReminderAndMirror(
        userDocId: userDocId,
        reminderId: reminderId,
      );
      return;
    }

    try {
      final snap = await _scales(userDocId, scaleDocId).get();
      final data = snap.data() ?? {};
      final linked = (data['linkedReminderId'] ?? '').toString();
      final agendaIdField = (data['agendaId'] ?? '').toString();
      final rid = linked.isNotEmpty
          ? linked
          : (agendaIdField.isNotEmpty ? agendaIdField : null);
      if (rid != null && rid.isNotEmpty) {
        await _deleteReminderAndMirror(
          userDocId: userDocId,
          reminderId: rid,
        );
        return;
      }
    } catch (_) {}

    try {
      await _scales(userDocId, scaleDocId).delete();
    } catch (_) {}
  }

  static Future<void> _deleteReminderAndMirror({
    required String userDocId,
    required String reminderId,
  }) async {
    var isAudiencia = false;
    try {
      final snap = await _reminders(userDocId).doc(reminderId).get();
      final type = (snap.data()?['type'] ?? 'compromisso').toString();
      isAudiencia = type == 'audiencia';
    } catch (_) {}
    if (isAudiencia) {
      await deleteAudienciaStorageForReminder(
        userDocId: userDocId,
        reminderDocId: reminderId,
      );
    }
    try {
      await _reminders(userDocId).doc(reminderId).delete();
    } catch (_) {}
    await AgendaScaleMirrorService.delete(
      userDocId: userDocId,
      agendaId: reminderId,
    );
  }

  static void refreshNotifications(String userDocId) {
    if (userDocId.isEmpty) return;
    AgendaNotificationsRefresher.refresh(uid: userDocId);
  }

  static String _normalizeColorHex(String colorHex) {
    var hex = colorHex.trim();
    if (hex.isEmpty) return kAgendaCompromissoDefaultColor;
    if (!hex.startsWith('#')) hex = '#$hex';
    return hex;
  }

  /// Geração automática (Escalas): grava em `reminders` + espelho `agenda_*` em `scales`
  /// para aparecer no Painel (em aberto), Agenda/Audiências e calendário de Escalas.
  static Future<int> upsertManyFromGeracaoAutomatica({
    required String userDocId,
    required String magicBatchId,
    required List<GeracaoAutomaticaCompromissoItem> items,
  }) async {
    if (userDocId.isEmpty || items.isEmpty || magicBatchId.trim().isEmpty) {
      return 0;
    }

    const batchLimit = 250;
    final generatedAt = FieldValue.serverTimestamp();
    var count = 0;

    for (var i = 0; i < items.length; i += batchLimit) {
      final end = (i + batchLimit) > items.length ? items.length : (i + batchLimit);
      final chunk = items.sublist(i, end);
      final batch = FirebaseFirestore.instance.batch();

      for (final item in chunk) {
        final reminderRef = _reminders(userDocId).doc();
        final reminderId = reminderRef.id;
        final title =
            item.title.trim().isEmpty ? 'Compromisso' : item.title.trim();
        final colorHex = _normalizeColorHex(item.colorHex);
        final day = DateTime(item.date.year, item.date.month, item.date.day);

        batch.set(reminderRef, {
          'type': 'compromisso',
          'title': title,
          'notes': '',
          'date': Timestamp.fromDate(day),
          'time': item.startHHmm,
          'endTime': item.endHHmm,
          'colorHex': colorHex,
          'status': 'EM_ABERTO',
          'done': false,
          'source': 'geracao_automatica',
          'lancamentoOrigem': 'geracao_automatica',
          'createdByMagic': true,
          'magicBatchId': magicBatchId,
          'magicGeneratedAt': generatedAt,
          'createdAt': generatedAt,
          'updatedAt': generatedAt,
          'agendaLoginDaySyncAt': generatedAt,
        });

        final mirrorRef = _scales(userDocId, scaleDocId(reminderId));
        final dateUtcNoon = DateTime.utc(day.year, day.month, day.day, 12, 0, 0);
        batch.set(mirrorRef, {
          'date': Timestamp.fromDate(dateUtcNoon),
          'start': item.startHHmm,
          'end': item.endHHmm,
          'label': title,
          'abbreviation': '',
          'colorHex': colorHex,
          'paid': false,
          'isCompromisso': true,
          'totalValue': 0,
          'dayRate': 0,
          'nightRate': 0,
          'hoursDay': 0,
          'hoursNight': 0,
          'employerType': 'private',
          'notes': '',
          'scaleNumber': '',
          'reminder': '',
          'reminderLeads': <int>[],
          'isAgendaMirror': true,
          'agendaId': reminderId,
          'agendaType': 'compromisso',
          'source': 'geracao_automatica',
          'lancamentoOrigem': 'geracao_automatica',
          'createdByLancamentoExpresso': false,
          'createdByMagic': true,
          'magicBatchId': magicBatchId,
          'magicGeneratedAt': generatedAt,
          'updatedAt': generatedAt,
        });
        count++;
      }
      await batch.commit();
    }

    refreshNotifications(userDocId);
    return count;
  }

  /// Remove compromissos gerados em lote (Agenda + espelhos Escalas) e docs em `scales`.
  static Future<int> deleteByMagicBatchIds({
    required String userDocId,
    required Set<String> batchIds,
  }) async {
    if (userDocId.isEmpty || batchIds.isEmpty) return 0;

    final uniqueRefs = <String, DocumentReference<Map<String, dynamic>>>{};

    void registrar(DocumentReference<Map<String, dynamic>> ref) {
      uniqueRefs[ref.path] = ref;
    }

    for (final batchId in batchIds) {
      if (batchId.trim().isEmpty) continue;

      try {
        final remindersSnap = await _reminders(userDocId)
            .where('magicBatchId', isEqualTo: batchId)
            .get();
        for (final doc in remindersSnap.docs) {
          registrar(doc.reference);
        }
      } catch (_) {}

      try {
        final scalesSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(userDocId)
            .collection('scales')
            .where('magicBatchId', isEqualTo: batchId)
            .get();
        for (final doc in scalesSnap.docs) {
          registrar(doc.reference);
          final rid = reminderIdFromScaleDocId(doc.id);
          if (rid != null) registrar(_reminders(userDocId).doc(rid));
        }
      } catch (_) {}
    }

    final refs = uniqueRefs.values.toList();
    if (refs.isEmpty) return 0;

    const batchLimit = 450;
    for (var i = 0; i < refs.length; i += batchLimit) {
      final batch = FirebaseFirestore.instance.batch();
      for (final ref in refs.skip(i).take(batchLimit)) {
        batch.delete(ref);
      }
      await batch.commit();
    }

    refreshNotifications(userDocId);
    return refs.length;
  }
}
