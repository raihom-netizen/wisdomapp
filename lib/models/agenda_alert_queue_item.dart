import 'package:cloud_firestore/cloud_firestore.dart';

/// Item da fila `users/{uid}/agendaAlerts` (push/e-mail no horário agendado).
class AgendaAlertQueueItem {
  const AgendaAlertQueueItem({
    required this.id,
    required this.status,
    required this.sourceType,
    required this.sourceId,
    required this.leadMin,
    required this.notifyAt,
    required this.eventAt,
    required this.title,
    required this.body,
    required this.channelKind,
    this.sentAt,
    this.cancelReason,
    this.pushEnabled = true,
    this.emailEnabled = true,
  });

  final String id;
  final String status;
  final String sourceType;
  final String sourceId;
  final int leadMin;
  final DateTime notifyAt;
  final DateTime eventAt;
  final String title;
  final String body;
  final String channelKind;
  final DateTime? sentAt;
  final String? cancelReason;
  final bool pushEnabled;
  final bool emailEnabled;

  bool get isPending => status == 'pending';
  bool get isSent => status == 'sent';
  bool get isCancelled =>
      status == 'cancelled' || status == 'skipped';

  static AgendaAlertQueueItem? fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data();
    final notifyTs = d['notifyAt'];
    final eventTs = d['eventAt'];
    if (notifyTs is! Timestamp || eventTs is! Timestamp) return null;
    return AgendaAlertQueueItem(
      id: doc.id,
      status: (d['status'] ?? 'pending').toString(),
      sourceType: (d['sourceType'] ?? '').toString(),
      sourceId: (d['sourceId'] ?? '').toString(),
      leadMin: (d['leadMin'] is num)
          ? (d['leadMin'] as num).toInt()
          : int.tryParse('${d['leadMin']}') ?? 0,
      notifyAt: notifyTs.toDate(),
      eventAt: eventTs.toDate(),
      title: (d['title'] ?? '').toString(),
      body: (d['body'] ?? '').toString(),
      channelKind: (d['channelKind'] ?? '').toString(),
      sentAt: (d['sentAt'] as Timestamp?)?.toDate(),
      cancelReason: (d['cancelReason'] as String?)?.toString(),
      pushEnabled: d['pushEnabled'] != false,
      emailEnabled: d['emailEnabled'] != false,
    );
  }
}
