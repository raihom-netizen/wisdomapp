import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/agenda_notification_plan.dart';
import '../utils/agenda_reminder_end_of_day.dart';
import 'agenda_notifications_refresher.dart';
import 'scale_notifications_service.dart';
import 'yearly_commitment_repeat_service.dart';

/// Ao **entrar** (login / abrir o app logado): toca docs de hoje para o servidor
/// replanejar `agendaAlerts` e disparar push/e-mail vencidos (app pode estar fechado).
class AgendaLoginDaySync {
  AgendaLoginDaySync._();

  static String? _lastUid;
  static DateTime? _lastRunAt;
  static const Duration _kMinInterval = Duration(seconds: 45);
  /// Plantões/compromissos dos próximos dias — garante fila no servidor antes do aviso.
  static const Duration _kForwardSyncWindow = Duration(days: 7);

  static Future<void> runOnLogin(
    String uid, {
    bool skipLocalRefresh = false,
  }) async {
    if (uid.isEmpty) return;
    final now = DateTime.now();
    if (_lastUid == uid &&
        _lastRunAt != null &&
        now.difference(_lastRunAt!) < _kMinInterval) {
      return;
    }
    _lastUid = uid;
    _lastRunAt = now;

    final dayStart = DateTime(now.year, now.month, now.day);
    final forwardEnd = DateTime(
      dayStart.add(_kForwardSyncWindow).year,
      dayStart.add(_kForwardSyncWindow).month,
      dayStart.add(_kForwardSyncWindow).day,
      23,
      59,
      59,
    );

    AgendaNotificationUserSettings settings;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('notifications')
          .get();
      settings = parseAgendaNotificationUserSettings(snap.data());
    } catch (_) {
      settings = const AgendaNotificationUserSettings();
    }

    if (!settings.reminderEnabled) {
      if (!skipLocalRefresh) {
        await AgendaNotificationsRefresher.refresh(uid: uid);
      }
      ScaleNotificationsService().checkDueNow();
      return;
    }

    try {
      // Não marcar `notificadoLeads` no login — isso bloqueava push com app fechado
      // (servidor ignorava alertas pendentes na fila). Push/e-mail = cron + onWrite.
      await _touchTodayOpenDocsForServerSync(
        uid: uid,
        now: now,
        dayStart: dayStart,
        dayEnd: forwardEnd,
        settings: settings,
      );
    } catch (_) {}

    if (!skipLocalRefresh) {
      await AgendaNotificationsRefresher.refresh(uid: uid);
    }
    ScaleNotificationsService().checkDueNow();
  }

  /// Toque leve nos docs de hoje ainda abertos → Cloud Function replaneja
  /// `agendaAlerts` e dispara o que já venceu (push/e-mail).
  static Future<void> _touchTodayOpenDocsForServerSync({
    required String uid,
    required DateTime now,
    required DateTime dayStart,
    required DateTime dayEnd,
    required AgendaNotificationUserSettings settings,
  }) async {
    var batch = FirebaseFirestore.instance.batch();
    var ops = 0;
    final ts = FieldValue.serverTimestamp();

    Future<void> flush() async {
      if (ops == 0) return;
      await batch.commit();
      batch = FirebaseFirestore.instance.batch();
      ops = 0;
    }

    if (settings.notifAudiencias || settings.notifCompromissos) {
      final remindersSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('reminders')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(dayEnd))
          .get();

      for (final doc in remindersSnap.docs) {
        final d = doc.data();
        final isAud = (d['type'] ?? 'compromisso').toString() == 'audiencia';
        if (isAud && !settings.notifAudiencias) continue;
        if (!isAud && !settings.notifCompromissos) continue;
        if (!YearlyCommitmentRepeatService.shouldShowInAgendaList(d, docId: doc.id)) {
          continue;
        }
        if (!agendaReminderEligibleForNotifySchedule(d, now)) continue;
        final eventAt = agendaReminderEventStartDateTime(d);
        if (eventAt == null || !eventAt.isAfter(now)) continue;
        batch.update(doc.reference, {'agendaLoginDaySyncAt': ts});
        ops++;
        if (ops >= 400) await flush();
      }
    }

    if (settings.notifEscalas || settings.notifCompromissos) {
      final scalesSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('scales')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(dayEnd))
          .get();

      for (final doc in scalesSnap.docs) {
        final d = doc.data();
        if (d['isAgendaMirror'] == true) continue;
        if (d['isProdutividadeFolgaMirror'] == true) continue;
        final isCompromisso = d['isCompromisso'] == true;
        if (isCompromisso && !settings.notifCompromissos) continue;
        if (!isCompromisso && !settings.notifEscalas) continue;
        final eventAt = _scaleEventAt(d);
        if (eventAt == null || !eventAt.isAfter(now)) continue;
        batch.update(doc.reference, {'agendaLoginDaySyncAt': ts});
        ops++;
        if (ops >= 400) await flush();
      }
    }

    await flush();
  }

  static DateTime? _scaleEventAt(Map<String, dynamic> d) {
    final date = (d['date'] as Timestamp?)?.toDate();
    final startStr = d['start'] as String?;
    if (date == null || startStr == null) return null;
    final parts = startStr.split(':');
    final hour = int.tryParse(parts.first) ?? 8;
    final minute =
        parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }
}
