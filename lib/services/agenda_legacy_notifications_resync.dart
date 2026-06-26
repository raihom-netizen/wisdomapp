import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/agenda_reminder_end_of_day.dart';
import 'agenda_notifications_refresher.dart';

/// Ressincroniza **audiências e compromissos** cadastrados antes da correção de
/// notificações: limpa flags «já notificado» no Firestore (uma vez por doc) e
/// reagenda lembretes locais + permite push/e-mail no próximo ciclo do servidor.
class AgendaLegacyNotificationsResync {
  AgendaLegacyNotificationsResync._();

  /// Marca no doc após reset (v3 = corrige corte 15h + replaneja alertas).
  static const int kResyncVersion = 3;

  /// Busca reminders dos últimos 2 dias civis (cobre audiência «em aberto» 24h).
  static const Duration _kLookback = Duration(days: 2);

  static Future<void> runForUser(
    String uid, {
    bool skipLocalRefresh = false,
  }) async {
    if (uid.isEmpty) return;

    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final queryFrom = startOfToday.subtract(_kLookback);

    try {
      final remindersRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('reminders');

      final snap = await remindersRef
          .where(
            'date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(queryFrom),
          )
          .get();

      var batch = FirebaseFirestore.instance.batch();
      var ops = 0;

      for (final doc in snap.docs) {
        final d = doc.data();
        if (!agendaReminderEligibleForNotifySchedule(d, now)) continue;
        final v = d['agendaNotifResyncV'];
        if (v is num && v.toInt() >= kResyncVersion) continue;

        batch.update(doc.reference, {
          'notificadoLeads': FieldValue.delete(),
          'emailNotificadoLeads': FieldValue.delete(),
          'notificado': FieldValue.delete(),
          'notificadoEm': FieldValue.delete(),
          'emailNotificadoEm': FieldValue.delete(),
          'agendaNotifResyncV': kResyncVersion,
          'agendaNotifResyncAt': FieldValue.serverTimestamp(),
        });
        ops++;
        if (ops >= 400) {
          await batch.commit();
          batch = FirebaseFirestore.instance.batch();
          ops = 0;
        }
      }
      if (ops > 0) await batch.commit();
    } catch (_) {
      // Melhor-esforço — o refresh local segue mesmo se o batch falhar.
    }

    if (!skipLocalRefresh) {
      await AgendaNotificationsRefresher.refresh(uid: uid);
    }
  }
}
