import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/agenda_notification_cutoff.dart';
import '../utils/agenda_reminder_end_of_day.dart';
import 'agenda_alerts_migration_service.dart';
import 'agenda_alerts_queue_service.dart';
import 'notification_message_builder.dart';

/// Varre `agendaAlerts` pendentes (de hoje em diante) e alinha título/corpo ao padrão v2.
class AgendaAlertsQueueRepairService {
  AgendaAlertsQueueRepairService._();

  /// Alinhado a [AGENDA_ALERT_PLAN_VERSION] no servidor (`functions/index.js`).
  static const int kPlanVersion = 2;

  /// Textos de slot na fila são gerados sem nome (nome entra só no disparo push/e-mail).
  static const String _kSlotUserName = '';

  /// Fila pendente com **evento ainda no futuro** (a partir de hoje, inclui mesmo dia).
  static Future<AgendaAlertsQueueRepairResult> repairFuturePendingFromTomorrow(
    String uid,
  ) =>
      repairPendingFromToday(uid, futureEventsOnly: true, fromTomorrow: false);

  /// Compatível — delega para [repairFuturePendingFromTomorrow].
  static Future<AgendaAlertsQueueRepairResult> repairFuturePendingFromToday(
    String uid,
  ) =>
      repairFuturePendingFromTomorrow(uid);

  static Future<AgendaAlertsQueueRepairResult> repairPendingFromToday(
    String uid, {
    bool futureEventsOnly = false,
    bool fromTomorrow = false,
  }) async {
    if (uid.isEmpty) {
      return const AgendaAlertsQueueRepairResult(skipped: true);
    }

    final now = DateTime.now();
    final startFloor = fromTomorrow
        ? agendaNotificationStartOfTomorrow(now)
        : DateTime(now.year, now.month, now.day);

    var scanned = 0;
    var repaired = 0;
    var cancelled = 0;
    var serverRebuildSources = 0;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection(AgendaAlertsQueueService.collectionName)
          .where('status', isEqualTo: 'pending')
          .orderBy('notifyAt')
          .limit(350)
          .get();

      final pendingFromToday = snap.docs.where((doc) {
        final data = doc.data();
        final notifyAt = (data['notifyAt'] as Timestamp?)?.toDate();
        final eventAt = (data['eventAt'] as Timestamp?)?.toDate();
        if (notifyAt == null || eventAt == null) return false;
        if (eventAt.isBefore(startFloor)) return false;
        if (futureEventsOnly && !eventAt.isAfter(now)) return false;
        return !notifyAt.isBefore(startFloor);
      }).toList();

      scanned = pendingFromToday.length;
      if (pendingFromToday.isEmpty) {
        return AgendaAlertsQueueRepairResult(scanned: 0);
      }

      final reminderCache = <String, Map<String, dynamic>?>{};
      final scaleCache = <String, Map<String, dynamic>?>{};
      final sourcesToRebuild = <String, DocumentReference>{};

      var batch = FirebaseFirestore.instance.batch();
      var ops = 0;

      Future<void> flush() async {
        if (ops == 0) return;
        await batch.commit();
        batch = FirebaseFirestore.instance.batch();
        ops = 0;
      }

      for (final alertDoc in pendingFromToday) {
        final a = alertDoc.data();
        final sourceType = (a['sourceType'] ?? '').toString();
        final sourceId = (a['sourceId'] ?? '').toString();
        final leadMin = (a['leadMin'] is num)
            ? (a['leadMin'] as num).toInt()
            : int.tryParse('${a['leadMin']}') ?? 0;
        if (sourceId.isEmpty || leadMin <= 0) continue;

        final notifyAt = (a['notifyAt'] as Timestamp?)?.toDate();
        final eventAt = (a['eventAt'] as Timestamp?)?.toDate();
        if (eventAt == null) continue;

        if (notifyAt != null && !notifyAt.isAfter(now)) {
          final unblocked = await _unblockOverduePendingIfFalseNotificado(
            uid: uid,
            sourceType: sourceType,
            sourceId: sourceId,
            leadMin: leadMin,
            reminderCache: reminderCache,
            scaleCache: scaleCache,
            batch: batch,
          );
          if (unblocked) {
            repaired++;
            ops++;
            if (ops >= 400) await flush();
            continue;
          }
        }
        if (futureEventsOnly && !eventAt.isAfter(now)) {
          batch.update(alertDoc.reference, {
            'status': 'cancelled',
            'cancelReason': 'event_passed',
            'updatedAt': FieldValue.serverTimestamp(),
          });
          cancelled++;
          ops++;
          if (ops >= 400) await flush();
          continue;
        }

        if (sourceType == 'reminder') {
          final src = await _loadReminder(uid, sourceId, reminderCache);
          if (src == null) {
            batch.update(alertDoc.reference, {
              'status': 'cancelled',
              'cancelReason': 'source_missing',
              'updatedAt': FieldValue.serverTimestamp(),
            });
            cancelled++;
            ops++;
          } else {
            final timeStr =
                (a['timeStr'] ?? src['time'] ?? '09:00').toString();
            final built = NotificationMessageBuilder.fromReminderDoc(
              src,
              userName: _kSlotUserName,
              eventAt: eventAt,
              leadMin: leadMin,
            );
            final needsText =
                _needsRepair(a, built.title, built.body, src, 'reminder');
            if (needsText) {
              batch.update(alertDoc.reference, {
                'title': built.title,
                'body': built.body,
                'planVersion': kPlanVersion,
                'channelKind': _channelFromReminder(src),
                'timeStr': timeStr,
                'updatedAt': FieldValue.serverTimestamp(),
              });
              repaired++;
              ops++;
            }
            if (futureEventsOnly &&
                agendaReminderFutureEventForNotify(src, now)) {
              sourcesToRebuild['reminder:$sourceId'] = FirebaseFirestore
                  .instance
                  .collection('users')
                  .doc(uid)
                  .collection('reminders')
                  .doc(sourceId);
            }
          }
        } else if (sourceType == 'scale') {
          final src = await _loadScale(uid, sourceId, scaleCache);
          if (src == null) {
            batch.update(alertDoc.reference, {
              'status': 'cancelled',
              'cancelReason': 'source_missing',
              'updatedAt': FieldValue.serverTimestamp(),
            });
            cancelled++;
            ops++;
          } else if (src['isAgendaMirror'] == true ||
              src['isProdutividadeFolgaMirror'] == true) {
            batch.update(alertDoc.reference, {
              'status': 'cancelled',
              'cancelReason': 'mirror_skip',
              'updatedAt': FieldValue.serverTimestamp(),
            });
            cancelled++;
            ops++;
          } else {
            final startStr =
                (a['startStr'] ?? src['start'] ?? '08:00').toString();
            final built = NotificationMessageBuilder.buildScaleNotificationMessage(
              src,
              userName: _kSlotUserName,
              eventAt: eventAt,
              leadMin: leadMin,
            );
            final needsText = _needsRepair(a, built.title, built.body, src, 'scale');
            if (needsText) {
              batch.update(alertDoc.reference, {
                'title': built.title,
                'body': built.body,
                'planVersion': kPlanVersion,
                'channelKind': _channelFromScale(src),
                'startStr': startStr,
                'updatedAt': FieldValue.serverTimestamp(),
              });
              repaired++;
              ops++;
            }
            if (futureEventsOnly && agendaScaleFutureEventForNotify(src, now)) {
              sourcesToRebuild['scale:$sourceId'] = FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .collection('scales')
                  .doc(sourceId);
            }
          }
        }

        if (ops >= 400) await flush();
      }

      await flush();

      for (final ref in sourcesToRebuild.values) {
        final bumped = await _bumpServerRebuild(ref);
        if (bumped) serverRebuildSources++;
      }
    } catch (_) {
      return AgendaAlertsQueueRepairResult(
        scanned: scanned,
        repaired: repaired,
        cancelled: cancelled,
        serverRebuildSources: serverRebuildSources,
        failed: true,
      );
    }

    return AgendaAlertsQueueRepairResult(
      scanned: scanned,
      repaired: repaired,
      cancelled: cancelled,
      serverRebuildSources: serverRebuildSources,
    );
  }

  /// Login antigo marcava `notificadoLeads` sem push — remove o lead para o cron reenviar.
  static Future<bool> _unblockOverduePendingIfFalseNotificado({
    required String uid,
    required String sourceType,
    required String sourceId,
    required int leadMin,
    required Map<String, Map<String, dynamic>?> reminderCache,
    required Map<String, Map<String, dynamic>?> scaleCache,
    required WriteBatch batch,
  }) async {
    DocumentReference<Map<String, dynamic>>? ref;
    Map<String, dynamic>? src;
    if (sourceType == 'reminder') {
      src = await _loadReminder(uid, sourceId, reminderCache);
      ref = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('reminders')
          .doc(sourceId);
    } else if (sourceType == 'scale') {
      src = await _loadScale(uid, sourceId, scaleCache);
      ref = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('scales')
          .doc(sourceId);
    }
    if (src == null || ref == null) return false;

    final raw = src['notificadoLeads'];
    if (raw is! List) return false;
    var hasLead = false;
    for (final e in raw) {
      final v = e is num ? e.toInt() : int.tryParse(e.toString());
      if (v == leadMin) {
        hasLead = true;
        break;
      }
    }
    if (!hasLead) return false;

    batch.update(ref, {
      'notificadoLeads': FieldValue.arrayRemove([leadMin]),
      'agendaQueueUnblockedAt': FieldValue.serverTimestamp(),
    });
    return true;
  }

  static Future<Map<String, dynamic>?> _loadReminder(
    String uid,
    String id,
    Map<String, Map<String, dynamic>?> cache,
  ) async {
    if (cache.containsKey(id)) return cache[id];
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('reminders')
        .doc(id)
        .get();
    final data = snap.exists ? snap.data() : null;
    cache[id] = data;
    return data;
  }

  static Future<Map<String, dynamic>?> _loadScale(
    String uid,
    String id,
    Map<String, Map<String, dynamic>?> cache,
  ) async {
    if (cache.containsKey(id)) return cache[id];
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('scales')
        .doc(id)
        .get();
    final data = snap.exists ? snap.data() : null;
    cache[id] = data;
    return data;
  }

  static String _channelFromReminder(Map<String, dynamic> d) {
    final type = (d['type'] ?? 'compromisso').toString().toLowerCase();
    return type == 'audiencia' ? 'audiencia' : 'compromisso';
  }

  static String _channelFromScale(Map<String, dynamic> d) {
    if (d['isCompromisso'] == true) return 'compromisso';
    return 'escala';
  }

  static bool _needsRepair(
    Map<String, dynamic> alert,
    String expectedTitle,
    String expectedBody,
    Map<String, dynamic> source,
    String sourceType,
  ) {
    final pv = alert['planVersion'];
    if (pv is! num || pv.toInt() < kPlanVersion) return true;

    final title = (alert['title'] ?? '').toString();
    final body = (alert['body'] ?? '').toString();
    if (title != expectedTitle || body != expectedBody) return true;

    if (body.contains('Controle Total') &&
        !body.contains(kNotificationBrandApp)) {
      return true;
    }

    if (sourceType == 'reminder') {
      final type = (source['type'] ?? '').toString().toLowerCase();
      if (type == 'audiencia') {
        final sei = (source['numeroSei'] ?? '').toString().trim();
        final oco = (source['numeroOcorrencia'] ?? '').toString().trim();
        if (sei.isNotEmpty && !body.contains('Processo (SEI)')) return true;
        if (oco.isNotEmpty && !body.contains('Ocorrência')) return true;
      }
    }

    return false;
  }

  /// Força o Cloud Function a reconstruir slots (purge + sync) quando a fila foi corrigida.
  static Future<bool> _bumpServerRebuild(DocumentReference ref) async {
    try {
      final snap = await ref.get();
      if (!snap.exists) return false;
      final data = snap.data() as Map<String, dynamic>?;
      if (data == null) return false;
      final current = (data['agendaNotifMigratedV'] is num)
          ? (data['agendaNotifMigratedV'] as num).toInt()
          : 0;
      final targetV = AgendaAlertsMigrationService.kMigrationVersion;
      if (current >= targetV) {
        await ref.update({'agendaNotifMigratedV': targetV - 1});
      }
      await ref.update({
        'agendaNotifMigratedV': targetV,
        'agendaNotifMigratedAt': FieldValue.serverTimestamp(),
        'agendaQueueRepairedAt': FieldValue.serverTimestamp(),
        'agendaNotifResyncAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}

class AgendaAlertsQueueRepairResult {
  const AgendaAlertsQueueRepairResult({
    this.scanned = 0,
    this.repaired = 0,
    this.cancelled = 0,
    this.serverRebuildSources = 0,
    this.skipped = false,
    this.failed = false,
  });

  final int scanned;
  final int repaired;
  final int cancelled;
  final int serverRebuildSources;
  final bool skipped;
  final bool failed;

  bool get didWork => repaired > 0 || cancelled > 0 || serverRebuildSources > 0;
}
