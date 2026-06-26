import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../models/agenda_alert_queue_item.dart';
import '../utils/agenda_alerts_archive_policy.dart';

/// Filtro por tipo na fila (Configurações > Pendentes e confirmadas).
enum AgendaQueueChannelFilter {
  audiencia,
  compromisso,
  escala,
}

/// Aba da fila: pendentes, notificados recentes (0–3 dias) ou arquivadas (3–7 dias).
enum AgendaQueueStatusFilter {
  pending,
  notifiedRecent,
  archived,
}

/// Leitura da fila de alertas (push/e-mail) — somente leitura no cliente.
class AgendaAlertsQueueService {
  AgendaAlertsQueueService._();

  static const String collectionName = 'agendaAlerts';

  static CollectionReference<Map<String, dynamic>> _coll(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection(collectionName);

  /// Itens visíveis na fila: pendentes (evento hoje+) e enviados (até 7 dias após notificação).
  static List<AgendaAlertQueueItem> onlyActiveQueue(
    List<AgendaAlertQueueItem> items, [
    DateTime? reference,
  ]) {
    final now = reference ?? DateTime.now();
    return items
        .where((e) => AgendaAlertsArchivePolicy.isVisibleInQueue(e, now))
        .toList();
  }

  /// Ordena por data do evento (menor → maior) e agrupa por dia civil.
  static List<({DateTime day, List<AgendaAlertQueueItem> items})> groupByEventDay(
    List<AgendaAlertQueueItem> items,
  ) {
    final sorted = List<AgendaAlertQueueItem>.from(items)
      ..sort((a, b) {
        final byEvent = a.eventAt.compareTo(b.eventAt);
        if (byEvent != 0) return byEvent;
        return a.notifyAt.compareTo(b.notifyAt);
      });

    final groups = <({DateTime day, List<AgendaAlertQueueItem> items})>[];
    DateTime? currentDay;
    List<AgendaAlertQueueItem>? bucket;

    for (final item in sorted) {
      final day = DateTime(
        item.eventAt.year,
        item.eventAt.month,
        item.eventAt.day,
      );
      if (currentDay == null ||
          day.year != currentDay.year ||
          day.month != currentDay.month ||
          day.day != currentDay.day) {
        if (bucket != null && currentDay != null) {
          groups.add((day: currentDay, items: bucket));
        }
        currentDay = day;
        bucket = [item];
      } else {
        bucket!.add(item);
      }
    }
    if (bucket != null && currentDay != null) {
      groups.add((day: currentDay, items: bucket));
    }
    return groups;
  }

  static String formatDayHeader(DateTime day, [DateTime? reference]) {
    final now = reference ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final d = DateTime(day.year, day.month, day.day);
    final weekday = DateFormat('EEEE', 'pt_BR').format(d);
    final cap = weekday.isEmpty
        ? weekday
        : '${weekday[0].toUpperCase()}${weekday.substring(1)}';
    final dateStr = DateFormat('dd/MM/yyyy', 'pt_BR').format(d);
    if (d == today) return 'Hoje · $dateStr · $cap';
    if (d == tomorrow) return 'Amanhã · $dateStr · $cap';
    return '$cap · $dateStr';
  }

  /// Fila completa (pendentes + confirmadas) — filtro no app por tipo e status.
  static Stream<List<AgendaAlertQueueItem>> watchQueue(String uid) {
    if (uid.isEmpty) return Stream.value([]);
    return _coll(uid)
        .where('status', whereIn: ['pending', 'sent'])
        .orderBy('notifyAt')
        .limit(350)
        .snapshots()
        .map(_mapDocs)
        .map(onlyActiveQueue);
  }

  static List<AgendaAlertQueueItem> filter({
    required List<AgendaAlertQueueItem> items,
    required AgendaQueueChannelFilter channel,
    required AgendaQueueStatusFilter statusFilter,
  }) {
    return items.where((e) {
      final kind = e.channelKind.toLowerCase();
      final channelOk = switch (channel) {
        AgendaQueueChannelFilter.audiencia => kind == 'audiencia',
        AgendaQueueChannelFilter.compromisso => kind == 'compromisso',
        AgendaQueueChannelFilter.escala => kind == 'escala',
      };
      if (!channelOk) return false;
      return switch (statusFilter) {
        AgendaQueueStatusFilter.pending => e.isPending,
        AgendaQueueStatusFilter.notifiedRecent =>
          e.isSent && AgendaAlertsArchivePolicy.isRecentlyNotified(e),
        AgendaQueueStatusFilter.archived =>
          e.isSent && AgendaAlertsArchivePolicy.isArchivedTabVisible(e),
      };
    }).toList();
  }

  static ({int pending, int notifiedRecent, int archived}) countsForChannel(
    List<AgendaAlertQueueItem> all,
    AgendaQueueChannelFilter channel,
  ) {
    final pending = filter(
      items: all,
      channel: channel,
      statusFilter: AgendaQueueStatusFilter.pending,
    ).length;
    final notifiedRecent = filter(
      items: all,
      channel: channel,
      statusFilter: AgendaQueueStatusFilter.notifiedRecent,
    ).length;
    final archived = filter(
      items: all,
      channel: channel,
      statusFilter: AgendaQueueStatusFilter.archived,
    ).length;
    return (
      pending: pending,
      notifiedRecent: notifiedRecent,
      archived: archived,
    );
  }

  static int countRecentlyNotifiedAll(List<AgendaAlertQueueItem> all) {
    return all
        .where(
          (e) => e.isSent && AgendaAlertsArchivePolicy.isRecentlyNotified(e),
        )
        .length;
  }

  static Stream<List<AgendaAlertQueueItem>> watchPending(String uid) {
    if (uid.isEmpty) return Stream.value([]);
    return _coll(uid)
        .where('status', isEqualTo: 'pending')
        .orderBy('notifyAt')
        .limit(250)
        .snapshots()
        .map(_mapDocs)
        .map(onlyActiveQueue);
  }

  static Stream<List<AgendaAlertQueueItem>> watchConfirmed(String uid) {
    if (uid.isEmpty) return Stream.value([]);
    return _coll(uid)
        .where('status', isEqualTo: 'sent')
        .limit(250)
        .snapshots()
        .map((snap) {
      final list = _mapDocs(snap);
      list.sort((a, b) {
        final sa = a.sentAt ?? a.notifyAt;
        final sb = b.sentAt ?? b.notifyAt;
        return sb.compareTo(sa);
      });
      return list;
    }).map(onlyActiveQueue);
  }

  static Stream<int> watchPendingDueCount(String uid) {
    return watchPending(uid).map((list) {
      final now = DateTime.now();
      return list.where((e) => !e.notifyAt.isAfter(now)).length;
    });
  }

  static List<AgendaAlertQueueItem> _mapDocs(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) {
    final out = <AgendaAlertQueueItem>[];
    for (final doc in snap.docs) {
      final item = AgendaAlertQueueItem.fromDoc(doc);
      if (item != null && !item.isCancelled) out.add(item);
    }
    return out;
  }

  static String leadLabel(int leadMin) {
    if (leadMin >= 1440) {
      return '${leadMin ~/ 1440} dia(s) antes';
    }
    if (leadMin >= 60) {
      return '${leadMin ~/ 60} hora(s) antes';
    }
    if (leadMin > 0) return '$leadMin min antes';
    return 'No horário';
  }

  static String channelLabel(String kind) => switch (kind) {
        'audiencia' => 'Audiência',
        'compromisso' => 'Compromisso',
        'escala' => 'Plantão / Escala',
        'financeiro' => 'Financeiro',
        _ => 'Agenda',
      };

  static String formatDateTime(DateTime dt) =>
      DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(dt);

  static String archivedRetentionHint() =>
      AgendaAlertsArchivePolicy.retentionSummary;
}
