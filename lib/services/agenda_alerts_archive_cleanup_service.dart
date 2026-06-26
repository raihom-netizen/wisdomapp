import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/agenda_alerts_archive_policy.dart';
import 'agenda_alerts_queue_service.dart';

/// Remove da fila Firestore alertas **sent** com mais de 7 dias desde o envio
/// (aba Arquivadas a partir de 3 dias — regra de UI no app).
class AgendaAlertsArchiveCleanupService {
  AgendaAlertsArchiveCleanupService._();

  static DateTime? _lastRunAt;
  static String? _lastUid;
  static const Duration _kMinInterval = Duration(hours: 18);

  static Future<int> purgeExpiredSentIfNeeded(String uid) async {
    if (uid.isEmpty) return 0;
    final now = DateTime.now();
    if (_lastUid == uid &&
        _lastRunAt != null &&
        now.difference(_lastRunAt!) < _kMinInterval) {
      return 0;
    }
    _lastUid = uid;
    _lastRunAt = now;

    var deleted = 0;
    try {
      deleted += await _purgeBySentAt(uid, now);
      deleted += await _purgeLegacySentWithoutSentAt(uid, now);
    } catch (_) {}
    return deleted;
  }

  static Future<int> _purgeBySentAt(String uid, DateTime now) async {
    final cutoff = AgendaAlertsArchivePolicy.archivedVisibleSince(now);
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection(AgendaAlertsQueueService.collectionName)
        .where('status', isEqualTo: 'sent')
        .where('sentAt', isLessThan: Timestamp.fromDate(cutoff))
        .limit(250)
        .get();

    if (snap.docs.isEmpty) return 0;
    var batch = FirebaseFirestore.instance.batch();
    var ops = 0;
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
      ops++;
      if (ops >= 400) {
        await batch.commit();
        batch = FirebaseFirestore.instance.batch();
        ops = 0;
      }
    }
    if (ops > 0) await batch.commit();
    return snap.docs.length;
  }

  /// Docs antigos sem `sentAt` — usa `notifyAt` como referência.
  static Future<int> _purgeLegacySentWithoutSentAt(
    String uid,
    DateTime now,
  ) async {
    final cutoff = AgendaAlertsArchivePolicy.archivedVisibleSince(now);
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection(AgendaAlertsQueueService.collectionName)
        .where('status', isEqualTo: 'sent')
        .where('notifyAt', isLessThan: Timestamp.fromDate(cutoff))
        .limit(150)
        .get();

    var deleted = 0;
    var batch = FirebaseFirestore.instance.batch();
    var ops = 0;
    for (final doc in snap.docs) {
      final d = doc.data();
      if (d['sentAt'] != null) continue;
      batch.delete(doc.reference);
      deleted++;
      ops++;
      if (ops >= 400) {
        await batch.commit();
        batch = FirebaseFirestore.instance.batch();
        ops = 0;
      }
    }
    if (ops > 0) await batch.commit();
    return deleted;
  }
}
