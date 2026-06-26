import 'package:cloud_firestore/cloud_firestore.dart';

/// Zera flags de entrega (push/e-mail) quando data/horário ou antecedências mudam.
class AgendaDeliveryReset {
  AgendaDeliveryReset._();

  static DateTime? _reminderDateTime(Map<String, dynamic> data) {
    final date = (data['date'] as Timestamp?)?.toDate();
    if (date == null) return null;
    final timeStr = (data['time'] ?? '').toString().trim();
    if (timeStr.isEmpty) {
      return DateTime(date.year, date.month, date.day);
    }
    final parts = timeStr.split(':');
    if (parts.length < 2) return DateTime(date.year, date.month, date.day);
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return DateTime(date.year, date.month, date.day, h, m);
  }

  static DateTime? _scaleDateTime(Map<String, dynamic> data) {
    final date = (data['date'] as Timestamp?)?.toDate();
    if (date == null) return null;
    final startStr = (data['start'] ?? '').toString().trim();
    if (startStr.isEmpty) {
      return DateTime(date.year, date.month, date.day);
    }
    final parts = startStr.split(':');
    if (parts.length < 2) return DateTime(date.year, date.month, date.day);
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return DateTime(date.year, date.month, date.day, h, m);
  }

  static bool reminderScheduleChanged(
    Map<String, dynamic> before,
    DateTime newDate,
    String newTimeHHmm,
  ) {
    final old = _reminderDateTime(before);
    final parts = newTimeHHmm.split(':');
    final h = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    final neu = DateTime(newDate.year, newDate.month, newDate.day, h, m);
    if (old == null) return true;
    return old != neu;
  }

  static bool scaleScheduleChanged(
    Map<String, dynamic> before,
    DateTime newDate,
    String newStartHHmm,
  ) {
    final old = _scaleDateTime(before);
    final parts = newStartHHmm.split(':');
    final h = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    final neu = DateTime(newDate.year, newDate.month, newDate.day, h, m);
    if (old == null) return true;
    return old != neu;
  }

  static bool scaleNotifyPlanChanged(
    Map<String, dynamic> before,
    Map<String, dynamic> after,
  ) {
    final bLeads = _normalizeLeads(before['reminderLeads']);
    final aLeads = _normalizeLeads(after['reminderLeads']);
    if (bLeads != aLeads) return true;
    final bSound = (before['notificationSoundId'] ?? '').toString();
    final aSound = (after['notificationSoundId'] ?? '').toString();
    if (bSound != aSound) return true;
    final bMode = (before['notificationDeliveryMode'] ?? '').toString();
    final aMode = (after['notificationDeliveryMode'] ?? '').toString();
    return bMode != aMode;
  }

  static String _contentStr(dynamic v) {
    if (v == null) return '';
    if (v is bool) return v ? '1' : '0';
    return v.toString().trim();
  }

  static bool reminderContentChanged(
    Map<String, dynamic> before,
    Map<String, dynamic> after,
  ) {
    const keys = [
      'title',
      'type',
      'notes',
      'localAudiencia',
      'linkSalaAudiencia',
      'numeroSei',
      'numeroOcorrencia',
      'status',
    ];
    for (final k in keys) {
      if (_contentStr(before[k]) != _contentStr(after[k])) return true;
    }
    return false;
  }

  static bool scaleContentChanged(
    Map<String, dynamic> before,
    Map<String, dynamic> after,
  ) {
    const keys = [
      'label',
      'abbreviation',
      'scaleLocationName',
      'notes',
      'scaleNumber',
      'isCompromisso',
      'end',
    ];
    for (final k in keys) {
      if (_contentStr(before[k]) != _contentStr(after[k])) return true;
    }
    return false;
  }

  static bool reminderNotifyPlanChanged(
    Map<String, dynamic> before,
    Map<String, dynamic> after,
  ) {
    final bLeads = _normalizeLeads(before['reminderLeads']);
    final aLeads = _normalizeLeads(after['reminderLeads']);
    if (bLeads != aLeads) return true;
    final bSound = (before['notificationSoundId'] ?? '').toString();
    final aSound = (after['notificationSoundId'] ?? '').toString();
    if (bSound != aSound) return true;
    final bMode = (before['notificationDeliveryMode'] ?? '').toString();
    final aMode = (after['notificationDeliveryMode'] ?? '').toString();
    return bMode != aMode;
  }

  static String _normalizeLeads(dynamic raw) {
    if (raw is! List) return '';
    final parsed = raw
        .map((e) => e is num ? e.toInt() : int.tryParse(e.toString()) ?? 0)
        .where((m) => m > 0)
        .toList()
      ..sort();
    return parsed.join(',');
  }

  /// Campos removidos no Firestore para permitir novo push/e-mail.
  static Map<String, dynamic> clearDeliveryFields({bool includeScaleNotificado = false}) {
    final m = <String, dynamic>{
      'notificadoLeads': FieldValue.delete(),
      'emailNotificadoLeads': FieldValue.delete(),
      'notificadoEm': FieldValue.delete(),
      'emailNotificadoEm': FieldValue.delete(),
      'agendaNotifRescheduledAt': FieldValue.serverTimestamp(),
    };
    if (includeScaleNotificado) {
      m['notificado'] = FieldValue.delete();
    }
    return m;
  }

  static Map<String, dynamic> reopenReminderAfterScheduleChange() {
    return {
      'done': false,
      'status': 'EM_ABERTO',
      ...clearDeliveryFields(),
    };
  }
}
