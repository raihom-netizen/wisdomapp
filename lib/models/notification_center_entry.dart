import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../models/agenda_alert_queue_item.dart';
import '../utils/agenda_alerts_archive_policy.dart';

/// Tipo visual na central (escalas, compromissos, audiências, financeiro).
enum NotificationCenterKind {
  audiencia,
  compromisso,
  escala,
  financeiro,
  outros,
}

/// Origem do item na central.
enum NotificationCenterSource {
  agendaAlert,
  financePending,
  pushInbox,
}

/// Item unificado da central de notificações (leve — só leitura + dismiss local).
class NotificationCenterEntry {
  const NotificationCenterEntry({
    required this.id,
    required this.kind,
    required this.source,
    required this.title,
    required this.body,
    this.eventAt,
    this.notifiedAt,
    this.isPending = false,
    this.leadMin,
    this.linkLocalizacao = '',
    this.contatoWhatsApp = '',
  });

  /// Chave estável para dismiss local (`agenda:…`, `finance:…`, `push:…`).
  final String id;
  final NotificationCenterKind kind;
  final NotificationCenterSource source;
  final String title;
  final String body;
  final DateTime? eventAt;
  final DateTime? notifiedAt;
  final bool isPending;
  final int? leadMin;
  final String linkLocalizacao;
  final String contatoWhatsApp;

  static NotificationCenterKind kindFromChannel(String? raw) {
    switch ((raw ?? '').toLowerCase().trim()) {
      case 'audiencia':
        return NotificationCenterKind.audiencia;
      case 'compromisso':
        return NotificationCenterKind.compromisso;
      case 'escala':
      case 'folga':
        return NotificationCenterKind.escala;
      case 'financeiro':
        return NotificationCenterKind.financeiro;
      default:
        return NotificationCenterKind.outros;
    }
  }

  static NotificationCenterEntry? fromAgendaAlert(AgendaAlertQueueItem item) {
    if (item.isCancelled) return null;
    if (item.isPending) {
      return NotificationCenterEntry(
        id: 'agenda:${item.id}',
        kind: kindFromChannel(item.channelKind),
        source: NotificationCenterSource.agendaAlert,
        title: item.title,
        body: item.body,
        eventAt: item.eventAt,
        notifiedAt: null,
        isPending: true,
        leadMin: item.leadMin,
        linkLocalizacao: item.linkLocalizacao,
        contatoWhatsApp: item.contatoWhatsApp,
      );
    }
    if (!item.isSent) return null;
    if (!AgendaAlertsArchivePolicy.isRecentlyNotified(item)) return null;
    final at = AgendaAlertsArchivePolicy.notifiedAt(item);
    return NotificationCenterEntry(
      id: 'agenda:${item.id}',
      kind: kindFromChannel(item.channelKind),
      source: NotificationCenterSource.agendaAlert,
      title: item.title,
      body: item.body,
      eventAt: item.eventAt,
      notifiedAt: at,
      isPending: false,
      leadMin: item.leadMin,
      linkLocalizacao: item.linkLocalizacao,
      contatoWhatsApp: item.contatoWhatsApp,
    );
  }

  static NotificationCenterEntry? fromFinanceDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data();
    final status = (d['status'] ?? '').toString();
    if (status != 'pending') return null;
    final type = (d['type'] ?? 'expense').toString();
    if (type != 'expense') return null;
    final desc = (d['description'] ?? d['title'] ?? 'Conta a pagar').toString();
    final amount = d['amount'];
    String amountStr = '';
    if (amount is num) {
      amountStr = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
          .format(amount.toDouble());
    }
    final dateTs = d['date'];
    DateTime? due;
    if (dateTs is Timestamp) due = dateTs.toDate();
    final body = amountStr.isEmpty ? 'Pendente de pagamento' : amountStr;
    return NotificationCenterEntry(
      id: 'finance:${doc.id}',
      kind: NotificationCenterKind.financeiro,
      source: NotificationCenterSource.financePending,
      title: desc.trim().isEmpty ? 'Conta a pagar' : desc.trim(),
      body: body,
      eventAt: due,
      notifiedAt: null,
      isPending: true,
    );
  }

  static NotificationCenterEntry fromPushInboxMap(Map<String, dynamic> m) {
    final kind = kindFromChannel(m['kind']?.toString());
    final notifiedRaw = m['notifiedAt']?.toString();
    DateTime? notifiedAt;
    if (notifiedRaw != null && notifiedRaw.isNotEmpty) {
      notifiedAt = DateTime.tryParse(notifiedRaw);
    }
    return NotificationCenterEntry(
      id: (m['id'] ?? '').toString(),
      kind: kind,
      source: NotificationCenterSource.pushInbox,
      title: (m['title'] ?? '').toString(),
      body: (m['body'] ?? '').toString(),
      eventAt: null,
      notifiedAt: notifiedAt ?? DateTime.now(),
      isPending: false,
      linkLocalizacao: (m['linkLocalizacao'] ?? '').toString().trim(),
      contatoWhatsApp: (m['contatoWhatsApp'] ?? '').toString().trim(),
    );
  }

  Map<String, dynamic> toPushInboxMap() => {
        'id': id,
        'kind': kind.name,
        'title': title,
        'body': body,
        if (notifiedAt != null) 'notifiedAt': notifiedAt!.toIso8601String(),
        if (linkLocalizacao.isNotEmpty) 'linkLocalizacao': linkLocalizacao,
        if (contatoWhatsApp.isNotEmpty) 'contatoWhatsApp': contatoWhatsApp,
      };
}
